import SwiftData
import TagwerkCore
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
        let categoryID = response.notification.request.content.categoryIdentifier
        let actionID = response.actionIdentifier
        let taskID = response.notification.request.content.userInfo[NotificationIDs.taskIDKey] as? String

        if categoryID == NotificationIDs.Category.task, let taskID {
            await MainActor.run {
                Self.handleTaskAction(actionID, taskID: taskID)
            }
            return
        }

        let record = NotificationActionRecord(actionIdentifier: actionID)
        SystemCheckStore.recordNotificationAction(record)
        await MainActor.run {
            AppModel.shared.systemCheck.handleNotificationAction(record)
        }
    }

    @MainActor
    private static func handleTaskAction(_ actionID: String, taskID: String) {
        let model = AppModel.shared
        guard let task = TaskActions.fetchTask(stableID: taskID, in: model.context) else { return }
        switch actionID {
        case NotificationIDs.Action.complete:
            TaskActions.complete(task, in: model.context, calendar: AppModel.calendar)
        case NotificationIDs.Action.tomorrow:
            TaskActions.moveToTomorrow(task, in: model.context, calendar: AppModel.calendar)
        case UNNotificationDefaultActionIdentifier:
            model.selectedTab = .today
            model.editingTask = task
        default:
            break
        }
        model.tasksChanged()
    }
}
