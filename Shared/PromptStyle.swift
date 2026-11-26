import Foundation
import UserNotifications

enum PromptStyle {
    static let category = "MORNING_CHECK"
    static let rateAction = "RATE_MORNING"

    static func register() {
        let rate = UNNotificationAction(identifier: rateAction, title: "Rate", options: [.foreground])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: category, actions: [rate], intentIdentifiers: [])
        ])
    }
}
