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
        // Gym-Ankunft: Überwachung sofort wieder aufnehmen, auch bei einem Start im Hintergrund.
        GymArrival.shared.startIfEnabled()
        return true
    }

    /// Mitteilungen auch zeigen, während die App offen ist. „Pause vorbei“ nicht: Das zeigt
    /// der Trainingsbildschirm selbst.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        if notification.request.identifier.hasPrefix(NotificationIDs.Prefix.restTimer) {
            return []
        }
        return [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let content = response.notification.request.content
        let categoryID = content.categoryIdentifier
        let actionID = response.actionIdentifier
        let taskID = content.userInfo[NotificationIDs.taskIDKey] as? String
        let doseID = content.userInfo[NotificationIDs.doseIDKey] as? String
        let medicationID = content.userInfo[NotificationIDs.medicationIDKey] as? String

        if categoryID == NotificationIDs.Category.task, let taskID {
            await MainActor.run {
                Self.handleTaskAction(actionID, taskID: taskID)
            }
            return
        }

        if categoryID == NotificationIDs.Category.medication, let doseID {
            await Self.handleMedicationAction(actionID, doseID: doseID, title: content.title, body: content.body)
            return
        }

        if content.userInfo[NotificationIDs.trainingKey] != nil || response.notification.request.identifier.hasPrefix(NotificationIDs.Prefix.restTimer) {
            await MainActor.run {
                AppModel.shared.openTraining()
            }
            return
        }

        if content.userInfo[NotificationIDs.habitKey] != nil || content.userInfo[NotificationIDs.lifeKey] != nil {
            await MainActor.run {
                AppModel.shared.openLife()
            }
            return
        }

        if let reference = content.userInfo[NotificationIDs.reviewKey] as? String {
            // Wochenrückblick: referenceID ist der Wochenbeginn in Sekunden seit 1970.
            let weekStart = Double(reference).map { Date(timeIntervalSince1970: $0) }
            await MainActor.run {
                AppModel.shared.openReview(weekStart: weekStart)
            }
            return
        }

        if medicationID != nil {
            // Nachfüll-Hinweis angetippt.
            await MainActor.run {
                AppModel.shared.openMedications()
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
    private static func handleMedicationAction(_ actionID: String, doseID: String, title: String, body: String) async {
        switch actionID {
        case NotificationIDs.Action.taken:
            await DoseActionCenter.submit(PendingDoseAction(doseID: doseID, kind: .taken, at: .now, source: "notification"))
        case NotificationIDs.Action.skip:
            await DoseActionCenter.submit(PendingDoseAction(doseID: doseID, kind: .skipped, at: .now, source: "notification"))
        case NotificationIDs.Action.snooze10:
            await MedicationNotifications.snooze(doseID: doseID, title: title, body: body, minutes: 10)
        case UNNotificationDefaultActionIdentifier:
            AppModel.shared.openMedications()
        default:
            break
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
