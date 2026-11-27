import AppIntents
import Foundation

struct MorningCheckFromAlert: AppIntent {
    static let title: LocalizedStringResource = "Check In from Apple Sleep Alert"
    static let description = IntentDescription("Requests a morning check-in if iPhone alert prompts are enabled. If you pass the original alert text and receipt time, it can also prepare a score for review after rating. It does not read Apple's Sleep Score from Health.")
    static let openAppWhenRun = false

    @Parameter(title: "Sleep Score notification text") var notificationText: String?
    @Parameter(title: "Notification received at") var receivedAt: Date?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await PhoneModel.shared.acceptAlertText(notificationText, at: receivedAt)
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
