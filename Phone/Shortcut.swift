import AppIntents
import Foundation

struct MorningCheckFromAlert: AppIntent {
    static let title: LocalizedStringResource = "Check In from Apple Sleep Alert"
    static let description = IntentDescription("Requests a check-in if alert prompts are enabled. With automatic alert scores enabled, pass Notification Body, Date, Title and App to copy a matching score without confirmation. It does not read the score from HealthKit.")
    static let openAppWhenRun = false

    @Parameter(title: "Sleep Score notification text") var notificationText: String?
    @Parameter(title: "Notification received at") var receivedAt: Date?
    @Parameter(title: "Notification title") var notificationTitle: String?
    @Parameter(title: "Notification app") var notificationApp: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await PhoneModel.shared.acceptAlertText(notificationText, at: receivedAt,
                                                             title: notificationTitle, sourceApp: notificationApp)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct MorningCheckShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: MorningCheckFromAlert(),
                    phrases: ["Check in from a sleep alert with \(.applicationName)"],
                    shortTitle: "DayBreak Check-In", systemImageName: "sun.horizon")
    }
}
