import TagwerkKit
import UIKit
import UserNotifications

/// Registriert die Mitteilungs-Kategorien und nimmt Antworten auf Mitteilungen entgegen,
/// auch wenn die App dafür im Hintergrund gestartet wird.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationSetup.registerCategories()
        return true
    }

    /// Mitteilungen auch zeigen, während die App offen ist.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let record = NotificationActionRecord(actionIdentifier: response.actionIdentifier)
        SystemCheckStore.recordNotificationAction(record)
        await MainActor.run {
            AppModel.shared.systemCheck.handleNotificationAction(record)
        }
    }
}
