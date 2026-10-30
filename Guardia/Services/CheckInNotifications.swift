import UserNotifications

@MainActor
final class CheckInNotifications {
    private let center = UNUserNotificationCenter.current()
    private let identifier = "guardia.check-in"
    func requestPermission() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert])
    }
    func post() async throws {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "Guardia check-in"
        content.body = "Open Guardia to review a route check-in."
        // Do not expose destination, coordinates or contacts on the lock screen.
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }
    func clear() {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
