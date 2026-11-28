import Combine
import Foundation
import MorningCheckCore
import UIKit
import UserNotifications
import WatchConnectivity

struct PhoneDisk: Codable {
    var diary = Diary()
    var lastPromptDay: String?
    var pendingPromptDay: String?
    var discardedThrough: Date?
}

extension PromptMode {
    var title: String {
        switch self {
        case .off: "Manual only"
        case .sleepData: "When Watch sleep data arrives"
        case .appleAlert: "Apple Sleep Score alert experiment"
        case .either: "Watch sleep or iPhone alert"
        }
    }
}

extension PromptOutcome {
    var description: String {
        switch self {
        case .off: "That prompt source is off in DayBreak."
        case .stale: "Outside today’s check-in window."
        case .alreadyRated: "You’ve already rated this morning."
        case .alreadyQueued: "A check-in was already queued for today."
        case .logUnavailable: "DayBreak couldn’t access its local log."
        case .logErased: "The iPhone log was erased today. No reminder will be sent for this date."
        case .submissionUncertain: "DayBreak can’t tell if iOS accepted an earlier request. It won’t retry today to avoid a duplicate."
        case .healthLocked: "Couldn't read Health while locked. DayBreak rechecks when it can run after unlock."
        case .healthUnavailable: "Health data is unavailable on this device."
        case .sleepNotReady: "No recent qualifying Watch sleep was readable."
        case .healthReadFailed: "Couldn't read Watch sleep. Check DayBreak’s Sleep access in Health."
        case .notificationsOff: "iOS hasn't allowed DayBreak notifications."
        case .queued: "iOS accepted the check-in request. That doesn’t confirm a banner appeared."
        case .queueFailed: "iOS couldn't queue the check-in. Try the notification test."
        }
    }
}

enum StageReadState: Equatable {
    case reading, missing, unavailable(PromptOutcome), saveFailed
}

@MainActor
final class PhoneModel: NSObject, ObservableObject {
    static let shared = PhoneModel()
    @Published private(set) var disk = PhoneDisk()
    @Published private(set) var mode: PromptMode
    @Published private(set) var appearance: DayBreakAppearance
    @Published private(set) var promptStatus = ""
    @Published private(set) var promptChecks = PromptChecks()
    @Published private(set) var promptChecksUnavailable = false
    @Published private(set) var storageError: String?
    @Published private(set) var showCheckIn = 0
    @Published private(set) var wakeStagesEnabled: Bool
    @Published private(set) var automaticAlertScores: Bool
    @Published private(set) var scoreImportMessage = "No alert import checked yet."
    @Published private(set) var lastScoreImportCheck: Date?
    @Published private(set) var stageAccessInProgress = false
    @Published private(set) var stageAccessMessage: String?
    @Published private(set) var stageReads: [String: StageReadState] = [:]

    private let file: LocalFile<PhoneDisk>?
    private let stageTestFixture: Bool
    private let appearanceDefaults: UserDefaults?
    private let promptCheckFile = LocalFile<PromptChecks>(name: "prompt-checks.json")
    private let signal = SleepSignal()
    private let promptQueue = PromptSubmissionQueue()
    private var promptCheckJournal = PromptCheckJournal()
    private var started = false
    private var changingMode = false
    private var queuedInSession: String?
    private var sendingPromptDays = Set<String>()
    private var evaluatingSleep = false
    private var recheckSleep = false
    private var mayWrite = true
    private var stageConfiguration = UUID()
    private var readingStageDays = Set<String>()
    private var retryStageDays = Set<String>()

    override private init() {
        #if DEBUG
        let isolated = ProcessInfo.processInfo.arguments.contains("-isolated-ui-test")
        let testDefaults = ProcessInfo.processInfo.environment["DAYBREAK_TEST_APPEARANCE_SUITE"]
            .flatMap(UserDefaults.init(suiteName:))
        let useStageFixture = isolated && ProcessInfo.processInfo.arguments.contains("-wake-stage-test-fixture")
        #else
        let isolated = false
        let testDefaults: UserDefaults? = nil
        let useStageFixture = false
        #endif
        file = isolated ? nil : LocalFile(name: "phone.json")
        appearanceDefaults = isolated ? testDefaults : .standard
        appearance = DayBreakAppearance.load(from: appearanceDefaults)
        mode = isolated ? .off : PromptMode(rawValue: UserDefaults.standard.string(forKey: "morningPromptMode") ?? "") ?? .off
        stageTestFixture = useStageFixture
        wakeStagesEnabled = isolated ? useStageFixture : UserDefaults.standard.bool(forKey: "logWakeStage")
        automaticAlertScores = !isolated && UserDefaults.standard.bool(forKey: "automaticAlertScores")
        if !isolated {
            scoreImportMessage = UserDefaults.standard.string(forKey: "lastAlertImportOutcome") ?? "No alert import checked yet."
            lastScoreImportCheck = UserDefaults.standard.object(forKey: "lastAlertImportCheck") as? Date
        }
        super.init()
    }

    func start() {
        guard !started else { return }
        started = true
        loadDiary()
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
        #if DEBUG
        if file == nil, ProcessInfo.processInfo.arguments.contains("-automatic-alert-score-test-fixture") {
            // Synthetic domain-boundary fixture in the isolated in-memory diary only.
            automaticAlertScores = true
            if let score = Score(100, source: .automaticNotification) {
                _ = disk.diary.importAutomatically(score, on: WakeDay.key(.now))
            }
        }
        #endif
        guard file != nil else { return }
        syncPromptChecks()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        PromptStyle.register()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
        updateSleepObserver()
    }

    private func loadDiary() {
        guard let file else { return }
        do {
            disk = try file.load() ?? PhoneDisk()
            mayWrite = true
            storageError = nil
        } catch {
            mayWrite = false
            storageError = "The log couldn’t open. Existing data was not overwritten."
        }
    }

    func refreshHealthData() async {
        if !mayWrite { loadDiary() }
        if promptChecksUnavailable { syncPromptChecks() }
        await evaluateSleep()
        await refreshRecentWakeStages()
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
        guard file != nil, !changingMode else { return }
        changingMode = true
        defer { changingMode = false }
        do {
            if next != .off {
                guard try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) else {
                    promptStatus = "Notifications are off. You can still rate from the Watch app."; return
                }
                if next.accepts(.watchSleep) {
                    guard signal.isAvailable else { promptStatus = "Health data is unavailable on this device."; return }
                    try await signal.authorize()
                }
            }
            if next == .off {
                UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                UNUserNotificationCenter.current().removeAllDeliveredNotifications()
            }
            mode = next
            UserDefaults.standard.set(next.rawValue, forKey: "morningPromptMode")
            updateSleepObserver()
            if !next.accepts(.watchSleep) { try? await signal.disableDelivery() }
            switch next {
            case .off: promptStatus = "Automatic prompts off."
            case .appleAlert: promptStatus = "Waiting for the iPhone Shortcuts automation."
            case .sleepData, .either:
                do {
                    try await signal.enableDelivery()
                    promptStatus = next == .either
                        ? "The iPhone alert also needs a Shortcuts automation."
                        : "Watch sleep is checked when Health makes it available."
                } catch {
                    promptStatus = "Couldn't register for background sleep updates. Try reselecting this mode."
                }
                await evaluateSleep()
            }
        } catch { promptStatus = "Couldn’t enable that trigger. Check permissions or keep ratings manual." }
    }

    private func updateSleepObserver() {
        guard mode.accepts(.watchSleep) || wakeStagesEnabled else { signal.stop(); return }
        signal.start { [weak self] failure in
            guard let self else { return }
            if let failure {
                let day = WakeDay.key(.now)
                guard self.blocked(.watchSleep, day: day) == nil else { return }
                self.recordCheck(failure, for: .watchSleep)
            } else {
                await self.evaluateSleep()
                await self.refreshRecentWakeStages()
            }
        }
    }

    func evaluateSleep() async {
        guard file != nil, mode.accepts(.watchSleep) else { return }
        if evaluatingSleep { recheckSleep = true; return }
        evaluatingSleep = true
        defer { evaluatingSleep = false }
        repeat {
            recheckSleep = false
            let now = Date.now
            let day = WakeDay.key(now)
            if let reason = blocked(.watchSleep, day: day, now: now) {
                if reason == .submissionUncertain || reason == .logUnavailable { recordCheck(reason, for: .watchSleep) }
                return
            }
            let eraseCutoff = disk.discardedThrough
            let reading = await signal.readRecentNight(now: now)
            // A stale result must not discard a new unlock or observer event.
            guard eraseCutoff == disk.discardedThrough, blocked(.watchSleep, day: day) == nil else { continue }
            let outcome: PromptOutcome
            switch reading {
            case .session(let end) where WakeDay.key(end) == day:
                outcome = await notify(on: day, from: .watchSleep, signalAt: end, eraseCutoff: eraseCutoff)
            case .session: outcome = .sleepNotReady
            case .notReady(let reason): outcome = reason
            }
            if eraseCutoff == disk.discardedThrough { recordCheck(outcome, for: .watchSleep) }
        } while recheckSleep
    }

    func acceptAlertText(_ text: String?, at deliveryDate: Date?, title: String? = nil, sourceApp: String? = nil) async -> String {
        start()
        if !mayWrite { loadDiary() }
        let now = Date.now
        // Explicit Shortcuts input can stage a score without opt-in to alert prompts.
        let scoreStatus: String?
        if automaticAlertScores {
            scoreStatus = importAutomaticScore(text, title: title, sourceApp: sourceApp, at: deliveryDate, now: now)
        } else {
            scoreStatus = stageAlertScore(text, at: deliveryDate, now: now)
        }
        guard mode.accepts(.appleAlert) else {
            return scoreStatus ?? "No score text was passed. Select an iPhone alert prompt option to use this action for reminders."
        }
        let capture = scoreStatus ?? "No score text was passed by Shortcuts."
        let signalAt = deliveryDate ?? now
        guard let day = PromptPolicy.eligibleDay(for: .appleAlert, signalAt: signalAt, now: now) else {
            recordCheck(.stale, for: .appleAlert)
            return "\(PromptOutcome.stale.description) \(capture)"
        }
        let eraseCutoff = disk.discardedThrough
        let outcome = await notify(on: day, from: .appleAlert, signalAt: signalAt, eraseCutoff: eraseCutoff)
        guard eraseCutoff == disk.discardedThrough else { return outcome.description }
        recordCheck(outcome, for: .appleAlert)
        return "\(outcome.description) \(capture)"
    }

    func changeAutomaticAlertScores(to enabled: Bool) {
        automaticAlertScores = enabled
        if file != nil { UserDefaults.standard.set(enabled, forKey: "automaticAlertScores") }
    }

    private func importAutomaticScore(_ text: String?, title: String?, sourceApp: String?, at deliveryDate: Date?, now: Date) -> String {
        let message: String
        switch AutomaticScoreInput.evaluate(text: text, title: title, sourceApp: sourceApp, receivedAt: deliveryDate, now: now) {
        case .sourceMismatch: message = "No score saved: the automation must pass the Health app and a recognized Sleep Score title."
        case .missingTimestamp: message = "No score saved: the alert’s original date was not supplied."
        case .stale: message = "No score saved: the alert is not recent and from today."
        case .noScore: message = "No score saved: no single supported score matched the alert title."
        case .score(let score, let day):
            guard file != nil, mayWrite else { return recordScoreImport("No score saved: the local log is unavailable.", at: now) }
            if let cutoff = disk.discardedThrough, let deliveryDate, deliveryDate <= cutoff {
                return recordScoreImport("No score saved: the alert predates the log erase.", at: now)
            }
            var next = disk
            guard next.diary.importAutomatically(score, on: day) else {
                return recordScoreImport("No score replaced: this morning already has a score, candidate, or removed-score marker.", at: now)
            }
            message = save(next) ? "Score copied automatically from Health alert. No confirmation needed."
                : "Couldn’t save the automatic score locally."
        }
        return recordScoreImport(message, at: now)
    }

    private func recordScoreImport(_ message: String, at time: Date) -> String {
        // Only fixed technical outcomes and check time; never score values or alert text.
        scoreImportMessage = message
        lastScoreImportCheck = time
        if file != nil {
            UserDefaults.standard.set(message, forKey: "lastAlertImportOutcome")
            UserDefaults.standard.set(time, forKey: "lastAlertImportCheck")
        }
        return message
    }

    private func stageAlertScore(_ text: String?, at deliveryDate: Date?, now: Date) -> String? {
        switch AlertScoreInput.evaluate(text: text, receivedAt: deliveryDate, now: now) {
        case .noText: return nil
        case .noTimestamp: return "No score was saved: Shortcuts didn’t pass the alert’s original receipt time."
        case .stale: return "No score was saved: the alert is outside today’s import window."
        case .noUnambiguousScore: return "No score was saved: the alert didn’t contain one clear Sleep Score."
        case .candidate(let score, let day):
            guard file != nil, mayWrite else { return "No score was saved: the local log is unavailable." }
            if let cutoff = disk.discardedThrough, let deliveryDate, deliveryDate <= cutoff {
                return "No score was saved: the alert predates the log erase."
            }
            if disk.diary[day]?.score != nil { return "A confirmed score is already saved for that day." }
            var next = disk
            guard next.diary.stage(score, on: day) else { return "A score is already waiting for review for that day." }
            return save(next) ? "Score candidate ready to review after rating." : "Couldn’t save the score candidate locally."
        }
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

    private func blocked(_ source: PromptSource, day: String, now: Date = .now) -> PromptOutcome? {
        PromptPolicy.blocked(source, mode: mode, day: day, currentDay: WakeDay.key(now),
                             alreadyRated: disk.diary[day]?.rating != nil,
                             lastQueuedDay: queuedInSession == day ? day : disk.lastPromptDay, storageAvailable: mayWrite,
                             unresolvedDay: sendingPromptDays.contains(day) ? nil : disk.pendingPromptDay,
                             erasedToday: disk.discardedThrough.map { WakeDay.key($0) } == day)
    }

    private func recordCheck(_ outcome: PromptOutcome, for source: PromptSource) {
        guard file != nil, mode.accepts(source) || outcome == .queued, outcome != .off else { return }
        promptCheckJournal.record(outcome, for: source, at: .now)
        syncPromptChecks()
    }

    private func syncPromptChecks() {
        guard file != nil else { return }
        let checkFile = promptCheckFile
        do {
            try promptCheckJournal.sync(load: checkFile.load, save: checkFile.save)
            promptChecksUnavailable = false
        } catch {
            promptChecksUnavailable = true
        }
        promptChecks = promptCheckJournal.checks
    }

    private func notify(on day: String, from source: PromptSource, signalAt: Date, eraseCutoff: Date?) async -> PromptOutcome {
        let revalidate: @MainActor @Sendable () -> PromptOutcome? = {
            let now = Date.now
            guard eraseCutoff == self.disk.discardedThrough,
                  PromptPolicy.eligibleDay(for: source, signalAt: signalAt, now: now) == day else { return .stale }
            return self.blocked(source, day: day, now: now)
        }
        return await promptQueue.attempt(on: day, revalidate: revalidate) {
            await self.submitPrompt(on: day, eraseCutoff: eraseCutoff, revalidate: revalidate)
        }
    }

    private func submitPrompt(on day: String, eraseCutoff: Date?, revalidate: @MainActor @Sendable () -> PromptOutcome?) async -> PromptOutcome {
        let content = UNMutableNotificationContent()
        content.title = "DayBreak"
        content.body = "How rested do you feel?"
        content.categoryIdentifier = PromptStyle.category
        content.sound = .default
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if let reason = revalidate() { return reason }
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return .notificationsOff }
        return await PromptTransaction.submit(revalidate: revalidate, reserve: {
            var next = disk
            next.pendingPromptDay = day
            guard save(next) else { return false }
            // Other enabled routes can wait on this in-process request instead of treating it as interrupted.
            sendingPromptDays.insert(day)
            return true
        }, send: {
            try await center.add(UNNotificationRequest(identifier: "morning-\(day)", content: content, trigger: nil))
        }, finalize: { accepted in
            let cancel = accepted && revalidate() != nil
            defer {
                sendingPromptDays.remove(day)
                // An immediate banner might already have appeared before we can remove it.
                if cancel { cancelPrompt(on: day) }
            }
            guard eraseCutoff == disk.discardedThrough, disk.pendingPromptDay == day else { return }
            var next = disk
            next.pendingPromptDay = nil
            if accepted, day == WakeDay.key(.now) {
                queuedInSession = day
                next.lastPromptDay = day
            }
            // On a failed write, the durable reservation still blocks a duplicate after relaunch.
            _ = save(next)
        })
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
        guard save(next) else { return false }
        cancelPrompt(on: rating.wakeDay)
        if wakeStagesEnabled { Task { await self.refreshWakeStage(on: rating.wakeDay) } }
        return true
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
        let next = PhoneDisk(diary: Diary(), discardedThrough: .now)
        guard save(next) else { return }
        queuedInSession = nil
        stageReads.removeAll()
        retryStageDays.removeAll()
        promptCheckJournal.clear()
        syncPromptChecks()
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

extension PhoneModel {
    func changeWakeStageLogging(to enabled: Bool) async {
        guard file != nil, enabled != wakeStagesEnabled, !stageAccessInProgress else { return }
        stageAccessMessage = nil
        stageAccessInProgress = true
        defer { stageAccessInProgress = false }
        if enabled {
            guard signal.isAvailable else { stageAccessMessage = "Health data is unavailable on this device."; return }
            do { try await signal.authorize() }
            catch { stageAccessMessage = "Couldn’t request access. Check DayBreak’s Sleep access in Health."; return }
        }
        stageConfiguration = UUID()
        stageReads.removeAll()
        retryStageDays.removeAll()
        wakeStagesEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "logWakeStage")
        updateSleepObserver()
        if enabled { Task { await refreshRecentWakeStages() } }
    }

    private func refreshRecentWakeStages() async {
        guard wakeStagesEnabled, mayWrite else { return }
        let cutoff = Date.now.addingTimeInterval(-7 * 24 * 3600)
        let days = disk.diary.rows.filter { $0.rating.map { $0.reportedAt >= cutoff } ?? false }.map(\.id)
        for day in days { await refreshWakeStage(on: day) }
    }

    func refreshWakeStage(on day: String) async {
        guard wakeStagesEnabled, mayWrite, disk.diary[day]?.rating != nil else { return }
        if !readingStageDays.insert(day).inserted { retryStageDays.insert(day); return }
        defer {
            readingStageDays.remove(day)
            retryStageDays.remove(day)
            if stageReads[day] == .reading { stageReads[day] = nil }
        }
        repeat {
            retryStageDays.remove(day)
            guard wakeStagesEnabled, mayWrite, let rating = disk.diary[day]?.rating else { return }
            stageReads[day] = .reading
            let configuration = stageConfiguration
            let cutoff = disk.discardedThrough
            let reading = await readWakeStage(for: rating)
            guard wakeStagesEnabled, stageConfiguration == configuration, disk.discardedThrough == cutoff,
                  disk.diary[day]?.rating == rating else { continue }
            switch reading {
            case .unavailable(let reason): stageReads[day] = .unavailable(reason)
            case .result(nil): stageReads[day] = .missing
            case .result(.some(let stage)):
                var next = disk
                if next.diary.attach(stage, to: rating), !save(next) { stageReads[day] = .saveFailed }
                else { stageReads[day] = nil }
            }
        } while retryStageDays.contains(day)
    }

    private func readWakeStage(for rating: Rating) async -> SleepSignal.StageReading {
        #if DEBUG
        if stageTestFixture {
            // Hypothetical interval for the isolated, in-memory UI test; do not touch HealthKit.
            let end = rating.reportedAt
            let interval = SleepInterval(start: end.addingTimeInterval(-8 * 3600), end: end, stage: .rem)
            return .result(SleepWindow.wakeStage(in: [interval], for: rating))
        }
        #endif
        return await signal.readWakeStage(for: rating)
    }
}

extension PhoneModel: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                             willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
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
