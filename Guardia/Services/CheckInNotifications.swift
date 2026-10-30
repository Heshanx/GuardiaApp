import UserNotifications
import Foundation

@MainActor
final class CheckInNotifications {
    private let center = UNUserNotificationCenter.current()
    private let identifier = "guardia.check-in"
    func requestPermission() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert])
    }
    func post() async throws {
        if let enabled = UserDefaults.standard.object(forKey: "routeCheckInsEnabled") as? Bool, !enabled { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "Guardia check-in"
        content.body = "Open Guardia to review a route check-in."
        
        // prevent exposing contacts to the lockscreen
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }
    func clear() {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
