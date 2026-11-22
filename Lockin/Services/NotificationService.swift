import Foundation
import UserNotifications

enum NotificationService {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func post(title: String, body: String, identifier: String = UUID().uuidString) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func xboxNudge(gamertag: String, titleName: String, minutes: Int) {
        let game = titleName.isEmpty ? "Xbox" : titleName
        post(
            title: "Xbox during a study block",
            body: "\(gamertag) is on \(game). You have been on for about \(minutes) minutes. Turn it off and study.",
            identifier: "lockin.xbox.\(Int(Date().timeIntervalSince1970))"
        )
    }
}
