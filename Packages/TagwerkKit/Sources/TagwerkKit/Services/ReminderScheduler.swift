import Foundation
import SwiftData
import TagwerkCore
import UserNotifications

/// Plant Erinnerungen für Aufgaben und Medikamente als lokale Mitteilungen.
///
/// iOS erlaubt nur 64 geplante Mitteilungen. Orbit plant deshalb rollierend die
/// nächsten 72 Stunden, Medikamente zuerst, und ersetzt bei jeder Änderung die eigenen
/// Mitteilungen (Präfixe in `NotificationIDs.Prefix.managed`). „In 10 Min“ bleibt stehen.
@MainActor
public enum ReminderScheduler {
    /// Wie weit Medikamente vorausgeplant werden.
    public static let horizon: TimeInterval = 72 * 3_600

    /// - Parameter alarmsActive: Wecker (AlarmKit) sind erlaubt. Dann übernimmt bei
    ///   Medikamenten mit „Wecker“ der Wecker die eigentliche Erinnerung.
    public static func reschedule(context: ModelContext, now: Date = .now, calendar: Calendar, alarmsActive: Bool) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let candidates = taskCandidates(context: context, calendar: calendar)
            + medicationCandidates(context: context, now: now, calendar: calendar, alarmsActive: alarmsActive)
            + TrainingActions.reminderCandidates(now: now, calendar: calendar, in: context)
            + InsightsActions.reminderCandidates(now: now, calendar: calendar)
            + LifeActions.reminderCandidates(now: now, calendar: calendar, in: context)
        let planned = ReminderPlanner.plan(candidates, now: now, horizon: horizon)
        let plannedIDs = Set(planned.map(\.id))

        let pending = await center.pendingNotificationRequests()
        let managed = pending.map(\.identifier).filter { id in
            NotificationIDs.Prefix.managed.contains { id.hasPrefix($0) }
        }
        let obsolete = Set(managed).subtracting(plannedIDs)
        if !obsolete.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(obsolete))
        }

        for candidate in planned {
            let content = UNMutableNotificationContent()
            content.title = candidate.title
            content.body = candidate.body
            content.sound = .default
            switch candidate.kind {
            case .task:
                content.categoryIdentifier = NotificationIDs.Category.task
                content.threadIdentifier = "tagwerk.tasks"
                content.userInfo = [NotificationIDs.taskIDKey: candidate.referenceID]
            case .medication, .medicationFollowUp:
                content.categoryIdentifier = NotificationIDs.Category.medication
                content.threadIdentifier = "tagwerk.medication"
                content.userInfo = [
                    NotificationIDs.doseIDKey: candidate.referenceID,
                    NotificationIDs.medicationIDKey: DoseID.parse(candidate.referenceID)?.medicationID ?? "",
                ]
            case .refill:
                content.threadIdentifier = "tagwerk.medication"
                content.userInfo = [NotificationIDs.medicationIDKey: candidate.referenceID]
            case .training:
                content.threadIdentifier = "tagwerk.training"
                content.userInfo = [NotificationIDs.trainingKey: candidate.referenceID]
            case .review:
                content.threadIdentifier = "tagwerk.review"
                content.userInfo = [NotificationIDs.reviewKey: candidate.referenceID]
            case .habit:
                content.threadIdentifier = "tagwerk.habits"
                content.userInfo = [NotificationIDs.habitKey: candidate.referenceID]
            case .lifeDeadline, .birthday:
                content.threadIdentifier = "tagwerk.life"
                content.userInfo = [NotificationIDs.lifeKey: candidate.referenceID]
            }

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: candidate.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: candidate.id, content: content, trigger: trigger)
            // Gleiche ID ersetzt eine bestehende Mitteilung (z. B. nach Titeländerung).
            try? await center.add(request)
        }
    }

    static func taskCandidates(context: ModelContext, calendar: Calendar) -> [ReminderCandidate] {
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isDone })
        let openTasks = (try? context.fetch(descriptor)) ?? []
        return openTasks.flatMap { task -> [ReminderCandidate] in
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
    }

    static func medicationCandidates(context: ModelContext, now: Date, calendar: Calendar, alarmsActive: Bool) -> [ReminderCandidate] {
        var result: [ReminderCandidate] = []
        for medication in MedicationActions.fetchAll(in: context) where medication.isActive {
            if medication.reminderStyle != .none, medication.schedule.isScheduled {
                // Ab 12 Std. zurück, damit auch überfällige noch eine Nachfrage bekommen können.
                let open = medication.entries(from: now.addingTimeInterval(-DoseTiming.missedAfter), to: now.addingTimeInterval(horizon), now: now, calendar: calendar)
                    .filter(\.isOpen)
                    .map(\.dose)
                let usesAlarm = medication.reminderStyle == .alarm && alarmsActive
                result += MedicationReminders.candidates(
                    doses: open,
                    name: medication.displayName,
                    detail: { medication.detail(for: $0.amount) },
                    includeMain: !usesAlarm,
                    includeFollowUp: true,
                    calendar: calendar
                )
            }
            if let forecast = medication.forecast(now: now, calendar: calendar),
               let stockText = medication.stockText,
               let refill = MedicationReminders.refillCandidate(
                   medicationID: medication.stableID,
                   name: medication.displayName,
                   stockText: stockText,
                   forecast: forecast,
                   now: now,
                   calendar: calendar
               ) {
                result.append(refill)
            }
        }
        return result
    }
}
