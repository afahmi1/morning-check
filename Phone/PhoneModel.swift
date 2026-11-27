import Combine
import Foundation
import MorningCheckCore
import UIKit
import UserNotifications
import WatchConnectivity

struct PhoneDisk: Codable {
    var diary = Diary()
    var lastPromptDay: String?
    var discardedThrough: Date?
}

enum PromptMode: String, CaseIterable, Identifiable {
    case off, sleepData, appleAlert
    var id: Self { self }
    var title: String {
        switch self {
        case .off: "Manual only"
        case .sleepData: "When Watch sleep data arrives"
        case .appleAlert: "Apple Sleep Score alert experiment"
        }
    }
}

@MainActor
final class PhoneModel: NSObject, ObservableObject {
    static let shared = PhoneModel()
    @Published private(set) var disk = PhoneDisk()
    @Published private(set) var mode: PromptMode
    @Published private(set) var appearance: DayBreakAppearance
    @Published private(set) var promptStatus = ""
    @Published private(set) var storageError: String?
    @Published private(set) var showCheckIn = 0

    private let file: LocalFile<PhoneDisk>?
    private let appearanceDefaults: UserDefaults?
    private let signal = SleepSignal()
    private var started = false
    private var busyDays = Set<String>()
    private var evaluated = false
    private var mayWrite = true

    override private init() {
        #if DEBUG
        let isolated = ProcessInfo.processInfo.arguments.contains("-isolated-ui-test")
        let testDefaults = ProcessInfo.processInfo.environment["DAYBREAK_TEST_APPEARANCE_SUITE"]
            .flatMap(UserDefaults.init(suiteName:))
        #else
        let isolated = false
        let testDefaults: UserDefaults? = nil
        #endif
        file = isolated ? nil : LocalFile(name: "phone.json")
        appearanceDefaults = isolated ? testDefaults : .standard
        appearance = DayBreakAppearance.load(from: appearanceDefaults)
        mode = isolated ? .off : PromptMode(rawValue: UserDefaults.standard.string(forKey: "morningPromptMode") ?? "") ?? .off
        super.init()
    }

    func start() {
        guard !started else { return }
        started = true
        do { disk = try file?.load() ?? PhoneDisk() }
        catch { mayWrite = false; storageError = "The log couldn’t open. Existing data was not overwritten." }
        #if DEBUG
        if file == nil, ProcessInfo.processInfo.arguments.contains("-appearance-review-fixture") {
            let examples: [(Restedness, Int?)] = [(.slightly, 100), (.notAtAll, 94), (.somewhat, 52), (.veryWell, 72), (.well, nil)]
            var fixture = PhoneDisk()
            for (offset, sample) in examples.enumerated() {
                let date = Date(timeIntervalSince1970: 1_784_640_000 + Double(offset * 86_400))
                let rating = Rating(sample.0, at: date, source: .phone)
                fixture.diary.record(rating)
                if let value = sample.1, let score = Score(value, source: .manual) {
                    fixture.diary.confirm(score, on: rating.wakeDay)
                }
            }
            disk = fixture
        }
        #endif
        guard file != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        PromptStyle.register()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
        if mode == .sleepData { observe() }
    }

    func changeAppearance(to next: DayBreakAppearance) {
        guard next != appearance else { return }
        appearance = next
        next.save(to: appearanceDefaults)
        syncAppearance()
    }

    func syncAppearance() {
        guard file != nil, WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        var context = session.applicationContext
        context[PeerKey.appearance] = appearance.payload
        // This is the latest state, not an event. WatchConnectivity queues it for an offline Watch.
        // If unavailable, retry on activation, Watch state change or next foreground.
        try? session.updateApplicationContext(context)
    }

    func changePromptMode(to next: PromptMode) async {
        guard file != nil else { return }
        do {
            if next != .off {
                guard try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) else {
                    promptStatus = "Notifications are off. You can still rate from the Watch app."; return
                }
                if next == .sleepData {
                    guard signal.isAvailable else { promptStatus = "Health data is unavailable on this device."; return }
                    try await signal.authorize()
                }
            }
            if next != .sleepData { signal.stop() }
            if next == .off {
                UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                UNUserNotificationCenter.current().removeAllDeliveredNotifications()
            }
            mode = next
            UserDefaults.standard.set(next.rawValue, forKey: "morningPromptMode")
            switch next {
            case .off: promptStatus = "Automatic prompts off."
            case .appleAlert: promptStatus = "Waiting for the Shortcuts automation. The Watch alert may not be visible to it."
            case .sleepData:
                observe()
                do {
                    try await signal.enableDelivery()
                    promptStatus = "Background delivery requested. Timing and Health access still need a device check."
                } catch {
                    promptStatus = "Background delivery unavailable. DayBreak can check for new sleep data while open."
                }
                await evaluateSleep()
            }
        } catch { promptStatus = "Couldn’t enable that trigger. Check permissions or keep ratings manual." }
    }

    private func observe() {
        signal.start { [weak self] in await self?.evaluateSleep() }
    }

    func evaluateSleep() async {
        guard mode == .sleepData, !evaluated else { return }
        let now = Date.now
        let day = WakeDay.key(now)
        guard disk.diary[day]?.rating == nil, disk.lastPromptDay != day else { return }
        evaluated = true
        defer { evaluated = false }
        do {
            guard let end = try await signal.recentNightEnd(now: now), mode == .sleepData,
                  WakeDay.key(end) == day else { return }
            _ = try await notify(on: day)
        } catch {
            // A locked or restricted Health store is not a reason to guess a wake-up.
        }
    }

    func acceptAlertText(_ text: String?, at deliveryDate: Date?) async -> String {
        start()
        guard mode == .appleAlert else { return "Enable Apple alert experiment in DayBreak first." }
        let now = Date.now
        let at = deliveryDate ?? now
        let age = now.timeIntervalSince(at)
        let day = WakeDay.key(at)
        guard (-300...7200).contains(age), day == WakeDay.key(now) else { return "Alert outside the check-in window." }
        var staged = false
        if let text, let number = ScoreText.candidate(text), let score = Score(number, source: .notification) {
            var next = disk
            if next.diary.stage(score, on: day) { staged = save(next) }
        }
        do {
            let sent = try await notify(on: day)
            if sent { return staged ? "Prompt sent. Score hidden until after you rate." : "Prompt sent. No score was captured." }
            return staged ? "Score staged. No duplicate prompt sent." : "No duplicate prompt sent."
        } catch { return "Couldn’t send the check-in notification." }
    }

    func sendTestReminder() async {
        guard file != nil else { return }
        do {
            guard try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) else {
                promptStatus = "Allow notifications to run the routing test."; return
            }
            let content = UNMutableNotificationContent()
            content.title = "DayBreak test"
            content.body = "Notification routing test. Nothing will be logged."
            content.sound = .default
            let request = UNNotificationRequest(identifier: "morning-check-test", content: content,
                                                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 12, repeats: false))
            try await UNUserNotificationCenter.current().add(request)
            promptStatus = "Test set for 12 seconds. Lock your iPhone and keep the Watch unlocked."
        } catch { promptStatus = "Couldn’t schedule the test." }
    }

    private func notify(on day: String) async throws -> Bool {
        guard mayWrite, mode != .off, disk.diary[day]?.rating == nil, disk.lastPromptDay != day,
              busyDays.insert(day).inserted else { return false }
        defer { busyDays.remove(day) }
        let content = UNMutableNotificationContent()
        content.title = "DayBreak"
        content.body = "How rested do you feel?"
        content.categoryIdentifier = PromptStyle.category
        content.sound = .default
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional,
              mode != .off, disk.diary[day]?.rating == nil else { return false }
        try await center.add(UNNotificationRequest(identifier: "morning-\(day)", content: content, trigger: nil))
        var next = disk
        next.lastPromptDay = day
        _ = save(next)
        if disk.diary[day]?.rating != nil || mode == .off { cancelPrompt(on: day) }
        return true
    }

    @discardableResult
    func recordPhoneRating(_ value: Restedness) -> Bool {
        receive(Rating(value, source: .phone))
    }

    @discardableResult
    private func receive(_ rating: Rating) -> Bool {
        guard rating.isConsistent, rating.reportedAt <= Date.now.addingTimeInterval(24 * 3600) else { return false }
        if let cutoff = disk.discardedThrough, rating.reportedAt <= cutoff { return true }
        var next = disk
        guard next.diary.record(rating) else { return mayWrite }
        if save(next) { cancelPrompt(on: rating.wakeDay); return true }
        return false
    }

    @discardableResult
    func confirmScore(_ score: Score, day: String) -> Bool {
        var next = disk
        guard next.diary.confirm(score, on: day) else { return false }
        return save(next)
    }

    func clearScore(day: String) {
        var next = disk
        next.diary.clearScores(on: day)
        _ = save(next)
    }

    func eraseDiary() {
        let next = PhoneDisk(diary: Diary(), lastPromptDay: WakeDay.key(.now), discardedThrough: .now)
        guard save(next) else { return }
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    private func cancelPrompt(on day: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["morning-\(day)"])
        center.removeDeliveredNotifications(withIdentifiers: ["morning-\(day)"])
    }

    private func save(_ next: PhoneDisk) -> Bool {
        guard mayWrite else { return false }
        do {
            try file?.save(next)
            disk = next
            storageError = nil
            return true
        } catch {
            storageError = "Couldn’t save locally. Please try again."
            return false
        }
    }

    nonisolated private static func rating(in payload: [String: Any]) -> Rating? {
        guard let content = payload[PeerKey.rating] as? Data, content.count <= 4096,
              let rating = try? JSONDecoder().decode(Rating.self, from: content), rating.source == .watch else { return nil }
        return rating
    }
}

extension PhoneModel: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                             willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                             didReceive response: UNNotificationResponse) async {
        await MainActor.run { showCheckIn += 1 }
    }
}

extension PhoneModel: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated { Task { @MainActor in syncAppearance() } }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in syncAppearance() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        guard let rating = Self.rating(in: message) else { replyHandler([:]); return }
        Task { @MainActor in
            replyHandler(receive(rating) ? [PeerKey.ack: rating.id.uuidString] : [:])
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let rating = Self.rating(in: userInfo) else { return }
        Task { @MainActor in
            guard receive(rating), WCSession.default.activationState == .activated else { return }
            #if !targetEnvironment(simulator)
            WCSession.default.transferUserInfo([PeerKey.ack: rating.id.uuidString])
            #endif
        }
    }
}
