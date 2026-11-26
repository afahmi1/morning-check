import Foundation
import MorningCheckCore
import SwiftUI
import WatchConnectivity

struct WatchDisk: Codable {
    var diary = Diary()
    var acknowledged = Set<UUID>()
}

@MainActor
final class WatchModel: NSObject, ObservableObject {
    static let shared = WatchModel()
    @Published private(set) var disk = WatchDisk()
    @Published private(set) var error: String?
    private let file = LocalFile<WatchDisk>(name: "watch.json")
    private var canWrite = true
    private var started = false
    private var inFlight = Set<UUID>()

    var today: Rating? { disk.diary[WakeDay.key(.now)]?.rating }

    func start() {
        guard !started else { return }
        started = true
        do { disk = try file.load() ?? WatchDisk() }
        catch { canWrite = false; self.error = "Could not open your Watch log. Nothing was overwritten." }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func record(_ value: Restedness) {
        let rating = Rating(value, source: .watch)
        var next = disk
        guard next.diary.record(rating), persist(next) else { return }
        sendPending()
    }

    func eraseLocal() {
        if WCSession.isSupported() { WCSession.default.outstandingUserInfoTransfers.forEach { $0.cancel() } }
        _ = persist(WatchDisk())
    }

    func sendPending() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        for rating in disk.diary.rows.reversed().compactMap(\.rating) where !disk.acknowledged.contains(rating.id) {
            guard !inFlight.contains(rating.id), let data = try? JSONEncoder().encode(rating) else { continue }
            if session.isReachable {
                inFlight.insert(rating.id)
                session.sendMessage([PeerKey.rating: data]) { reply in
                    let ack = reply[PeerKey.ack] as? String
                    Task { @MainActor in
                        self.inFlight.remove(rating.id)
                        if ack == rating.id.uuidString { self.acknowledge(rating.id) }
                        else { self.enqueue(data) }
                    }
                } errorHandler: { _ in
                    Task { @MainActor in
                        self.inFlight.remove(rating.id)
                        if self.disk.diary[rating.wakeDay]?.rating?.id == rating.id { self.enqueue(data) }
                    }
                }
            } else { enqueue(data) }
        }
    }

    private func enqueue(_ data: Data) {
        #if !targetEnvironment(simulator)
        let session = WCSession.default
        guard session.activationState == .activated,
              let rating = try? JSONDecoder().decode(Rating.self, from: data),
              disk.diary[rating.wakeDay]?.rating?.id == rating.id,
              !disk.acknowledged.contains(rating.id),
              !session.outstandingUserInfoTransfers.contains(where: {
                  guard let payload = $0.userInfo[PeerKey.rating] as? Data else { return false }
                  return (try? JSONDecoder().decode(Rating.self, from: payload))?.id == rating.id
              }) else { return }
        session.transferUserInfo([PeerKey.rating: data])
        #endif
    }

    private func acknowledge(_ id: UUID) {
        guard disk.diary.rows.contains(where: { $0.rating?.id == id }), !disk.acknowledged.contains(id) else { return }
        var next = disk
        next.acknowledged.insert(id)
        _ = persist(next)
    }

    private func persist(_ next: WatchDisk) -> Bool {
        guard canWrite else { return false }
        do { try file.save(next); disk = next; error = nil; return true }
        catch { self.error = "Could not save on Watch. Try again."; return false }
    }
}

extension WatchModel: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated { Task { @MainActor in sendPending() } }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable { Task { @MainActor in sendPending() } }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let raw = userInfo[PeerKey.ack] as? String, let id = UUID(uuidString: raw) else { return }
        Task { @MainActor in acknowledge(id) }
    }
}
