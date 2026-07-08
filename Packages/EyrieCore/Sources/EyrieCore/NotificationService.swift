import Foundation
import UserNotifications

/// Thin wrapper around UNUserNotificationCenter shared by all modules.
public final class NotificationService: Sendable {
    public static let shared = NotificationService()

    private init() {}

    /// Requests authorization on first use; returns whether notifications are allowed.
    @discardableResult
    public func ensureAuthorized() async -> Bool {
        // UNUserNotificationCenter traps in processes without a bundle
        // identifier (e.g. swift test runners); treat those as unauthorized.
        guard Bundle.main.bundleIdentifier != nil else { return false }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .authorized, .provisional:
            return true
        default:
            return false
        }
    }

    public func send(title: String, body: String, sound: Bool = true) async {
        guard await ensureAuthorized() else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
