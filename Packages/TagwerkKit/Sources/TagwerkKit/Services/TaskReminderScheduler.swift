import Foundation
import SwiftData
import TagwerkCore
import UserNotifications

/// Plant Erinnerungen für Aufgaben als lokale Mitteilungen.
///
/// iOS erlaubt nur 64 geplante Mitteilungen. Tagwerk plant deshalb rollierend die
/// nächsten 72 Stunden und ersetzt die eigenen Aufgaben-Mitteilungen bei jeder Änderung.
@MainActor
public enum TaskReminderScheduler {
    public static let identifierPrefix = "task."

    public static func reschedule(context: ModelContext, now: Date = .now, calendar: Calendar) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isDone })
        let openTasks = (try? context.fetch(descriptor)) ?? []
        let candidates = openTasks.flatMap { task -> [ReminderCandidate] in
            guard let due = task.dueDate, !task.reminderOffsets.isEmpty else { return [] }
            return TaskReminders.candidates(
                taskID: task.stableID,
                title: task.title,
                dueDate: due,
                hasDueTime: task.hasDueTime,
                offsets: task.reminderOffsets,
                calendar: calendar
            )
        }
        let planned = ReminderPlanner.plan(candidates, now: now)
        let plannedIDs = Set(planned.map(\.id))

        let pending = await center.pendingNotificationRequests()
        let pendingTaskIDs = Set(pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) })
        let obsolete = pendingTaskIDs.subtracting(plannedIDs)
        if !obsolete.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(obsolete))
        }

        for candidate in planned {
            let content = UNMutableNotificationContent()
            content.title = candidate.title
            content.body = candidate.body
            content.sound = .default
            content.categoryIdentifier = NotificationIDs.Category.task
            content.threadIdentifier = "tagwerk.tasks"
            content.userInfo = [NotificationIDs.taskIDKey: candidate.referenceID]

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: candidate.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: candidate.id, content: content, trigger: trigger)
            // Gleiche ID ersetzt eine bestehende Mitteilung (z. B. nach Titeländerung).
            try? await center.add(request)
        }
    }
}
