import ActivityKit
import Foundation
import Observation
import SwiftData
import TagwerkCore
import TagwerkKit
import UserNotifications

/// Steuert eine laufende Einheit: Pausen-Timer, Live Activity (Dynamic Island,
/// Sperrbildschirm) und die Mitteilung „Pause vorbei“.
@MainActor
@Observable
final class WorkoutRunner {
    /// Ende der laufenden Pause.
    private(set) var restEndsAt: Date?
    /// Gesamtlänge der laufenden Pause (für den Fortschrittsbalken).
    private(set) var restDuration: TimeInterval = 0
    /// Übung, die nach der Pause dran ist (zum automatischen Weiterblättern).
    var focusSlot: Int?

    @ObservationIgnored private var activity: Activity<WorkoutActivityAttributes>?
    @ObservationIgnored private let restNotificationID = NotificationIDs.Prefix.restTimer + "current"

    var isResting: Bool {
        guard let restEndsAt else { return false }
        return restEndsAt > .now
    }

    // MARK: Pause

    func startRest(seconds: Int, session: WorkoutSession, catalog: ExerciseCatalog) {
        guard seconds > 0 else {
            skipRest(session: session, catalog: catalog)
            return
        }
        restDuration = TimeInterval(seconds)
        restEndsAt = Date.now.addingTimeInterval(restDuration)
        scheduleRestNotification(session: session, catalog: catalog)
        updateActivity(session: session, catalog: catalog)
    }

    func addRest(_ seconds: Int = 30, session: WorkoutSession, catalog: ExerciseCatalog) {
        let base = max(restEndsAt ?? .now, .now)
        restEndsAt = base.addingTimeInterval(TimeInterval(seconds))
        restDuration += TimeInterval(seconds)
        scheduleRestNotification(session: session, catalog: catalog)
        updateActivity(session: session, catalog: catalog)
    }

    func skipRest(session: WorkoutSession?, catalog: ExerciseCatalog) {
        restEndsAt = nil
        restDuration = 0
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [restNotificationID])
        if let session {
            updateActivity(session: session, catalog: catalog)
        }
    }

    private func scheduleRestNotification(session: WorkoutSession, catalog: ExerciseCatalog) {
        guard let restEndsAt, !AppInfo.isUITesting else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [restNotificationID])
        let content = UNMutableNotificationContent()
        content.title = "Pause vorbei"
        content.body = nextSetText(session: session, catalog: catalog) ?? "Weiter geht's."
        content.sound = .default
        content.threadIdentifier = "tagwerk.training"
        content.interruptionLevel = .active
        let interval = max(1, restEndsAt.timeIntervalSinceNow)
        let request = UNNotificationRequest(
            identifier: restNotificationID,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        center.add(request)
    }

    // MARK: Live Activity

    /// Startet oder aktualisiert die Live Activity der Einheit.
    func updateActivity(session: WorkoutSession, catalog: ExerciseCatalog) {
        guard !AppInfo.isUITesting else { return }
        let state = contentState(session: session, catalog: catalog)
        let content = ActivityContent(state: state, staleDate: state.restEndsAt)
        if let activity {
            Task { await activity.update(content) }
            return
        }
        if let existing = Activity<WorkoutActivityAttributes>.activities.first {
            activity = existing
            Task { await existing.update(content) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        activity = try? Activity.request(attributes: WorkoutActivityAttributes(title: session.title), content: content)
    }

    func endActivity() {
        restEndsAt = nil
        restDuration = 0
        focusSlot = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [restNotificationID])
        let activities = Activity<WorkoutActivityAttributes>.activities
        activity = nil
        Task {
            for item in activities {
                await item.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private func contentState(session: WorkoutSession, catalog: ExerciseCatalog) -> WorkoutActivityAttributes.ContentState {
        let working = (session.sets ?? []).filter { $0.kind != .warmup }
        let next = TrainingActions.nextPendingSet(in: session)
        let name = next.map { catalog.name(for: $0.exerciseID) } ?? "Alle Sätze erledigt"
        return WorkoutActivityAttributes.ContentState(
            sessionStart: session.startedAt,
            exerciseName: name,
            detail: next.map { setDescription($0, in: session, catalog: catalog) } ?? "Einheit beenden",
            restEndsAt: isResting ? restEndsAt : nil,
            restSeconds: Int(restDuration),
            doneSets: working.filter(\.isDone).count,
            totalSets: working.count
        )
    }

    /// „Satz 2 von 4 · 80 kg × 8“
    func setDescription(_ set: SetLog, in session: WorkoutSession, catalog: ExerciseCatalog) -> String {
        let exercise = TrainingActions.info(for: set.exerciseID, catalog: catalog)
        let slotSets = session.sets(inSlot: set.slot).filter { $0.kind == set.kind }
        let position = (slotSets.firstIndex { $0.stableID == set.stableID } ?? 0) + 1
        let prefix = set.kind == .warmup ? "Aufwärmen \(position)" : (set.kind == .drop ? "Drop-Satz" : "Satz \(position) von \(slotSets.count)")
        let weight = WeightFormat.label(set.weight, equipment: exercise.equipment, assisted: exercise.assisted)
        return "\(prefix) · \(weight) × \(set.reps)"
    }

    func nextSetText(session: WorkoutSession, catalog: ExerciseCatalog) -> String? {
        guard let next = TrainingActions.nextPendingSet(in: session) else { return nil }
        return "Als Nächstes: \(catalog.name(for: next.exerciseID)) – \(setDescription(next, in: session, catalog: catalog))"
    }
}
