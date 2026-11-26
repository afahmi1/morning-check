import AppIntents
import Foundation

struct MorningCheckFromAlert: AppIntent {
    static let title: LocalizedStringResource = "Check In from Apple Sleep Alert"
    static let description = IntentDescription("Asks for a morning rating. Optionally stages a Sleep Score parsed from the text you pass in. The score stays hidden until you rate and isn't saved as confirmed until you review it.")
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
