import Foundation
import SwiftData
import TagwerkCore

/// Training-Coach: Plan-Check mit Vorschlägen und Wochenlücken je Muskel.
@MainActor
public enum CoachActions {
    static let dismissedKey = "tagwerk.coach.dismissed"
    /// Zurückgestellte Vorschläge kommen nach vier Wochen wieder, falls noch aktuell.
    static let dismissDays = 28.0

    /// Vorschläge für den aktiven Plan, ohne zurückgestellte. Wichtigste zuerst.
    public static func suggestions(now: Date = .now, calendar: Calendar, limit: Int = 6, in context: ModelContext) -> [CoachSuggestion] {
        guard let plan = TrainingActions.activePlan(in: context) else { return [] }
        let catalog = TrainingActions.catalog(in: context)
        let items = plan.rotationDays.flatMap { day in
            day.sortedExercises.map { exercise in
                CoachPlanItem(id: exercise.stableID, exerciseID: exercise.exerciseID, dayName: day.name, sets: exercise.sets, repMin: exercise.repMin, repMax: exercise.repMax)
            }
        }
        var trends: [String: ExerciseTrend] = [:]
        for id in Set(items.map(\.exerciseID)) {
            trends[id] = ProgressActions.trend(for: id, catalog: catalog, now: now, in: context)
        }
        let weekly = averageWeeklySets(weeks: 2, now: now, catalog: catalog, calendar: calendar, in: context)
        let dismissed = dismissedIDs(now: now)
        return Array(
            PlanCoach.suggestions(items: items, trends: trends, weeklySets: weekly, catalog: catalog, limit: 30)
                .filter { !dismissed.contains($0.id) }
                .prefix(limit)
        )
    }

    /// Durchschnitt der Arbeitssätze je Muskel in den letzten vollen Wochen mit Training.
    /// Leer, wenn es dort kein Training gab (dann keine Volumen-Vorschläge).
    public static func averageWeeklySets(weeks: Int, now: Date, catalog: ExerciseCatalog, calendar: Calendar, in context: ModelContext) -> [MuscleGroup: Double] {
        let thisMonday = AgendaBuilder.startOfWeek(containing: now, calendar: calendar)
        var totals: [MuscleGroup: Double] = [:]
        var trainedWeeks = 0
        for offset in 1...max(weeks, 1) {
            guard let monday = calendar.date(byAdding: .day, value: -7 * offset, to: thisMonday) else { continue }
            let volume = TrainingActions.weeklyVolume(containing: monday, catalog: catalog, calendar: calendar, in: context)
            guard volume.contains(where: { $0.sets > 0 }) else { continue }
            trainedWeeks += 1
            for item in volume { totals[item.muscle, default: 0] += item.sets }
        }
        guard trainedWeeks > 0 else { return [:] }
        return totals.mapValues { $0 / Double(trainedWeeks) }
    }

    /// Übernimmt einen Vorschlag in den Plan.
    @discardableResult
    public static func apply(_ suggestion: CoachSuggestion, in context: ModelContext) -> Bool {
        let id = suggestion.planItemID
        var descriptor = FetchDescriptor<PlanExercise>(predicate: #Predicate { $0.stableID == id })
        descriptor.fetchLimit = 1
        guard let item = (try? context.fetch(descriptor))?.first else { return false }
        switch suggestion.change {
        case .addSet: item.sets = min(item.sets + 1, 8)
        case .removeSet: item.sets = max(item.sets - 1, 1)
        case .repRange(let min, let max):
            item.repMin = min
            item.repMax = max
        case .swap(let target): item.exerciseID = target
        }
        TrainingActions.save(context)
        return true
    }

    /// „Später“: Vorschlag vier Wochen lang nicht mehr zeigen.
    public static func dismiss(_ suggestion: CoachSuggestion, now: Date = .now) {
        var stored = storedDismissals()
        stored[suggestion.id] = now.timeIntervalSince1970
        UserDefaults.standard.set(stored, forKey: dismissedKey)
    }

    static func dismissedIDs(now: Date) -> Set<String> {
        let cutoff = now.addingTimeInterval(-dismissDays * 86_400).timeIntervalSince1970
        return Set(storedDismissals().filter { $0.value >= cutoff }.keys)
    }

    private static func storedDismissals() -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: dismissedKey) as? [String: Double] ?? [:]
    }

    /// Wochenlücken vor der nächsten Einheit. Anfang der Woche nur die Muskeln der nächsten Einheit,
    /// ab Freitag auch die übrigen (höchstens drei), damit es nicht nach Warnliste aussieht.
    public static func weeklyGapText(now: Date = .now, calendar: Calendar, in context: ModelContext) -> String? {
        guard let plan = TrainingActions.activePlan(in: context), let day = plan.nextDay else { return nil }
        let catalog = TrainingActions.catalog(in: context)
        let thisWeek = TrainingActions.weeklyVolume(containing: now, catalog: catalog, calendar: calendar, in: context)
        let next = day.sortedExercises.filter { !$0.isOptional }.map(\.exerciseID)
        let gaps = PlanCoach.weeklyGaps(thisWeek: thisWeek, nextSession: next, catalog: catalog)
        // Wochentag: 1 = Sonntag … 6 = Freitag, 7 = Samstag.
        let weekday = calendar.component(.weekday, from: now)
        let lateInWeek = weekday == 1 || weekday >= 6
        let shown = gaps.filter(\.inNextSession) + (lateInWeek ? Array(gaps.filter { !$0.inNextSession }.prefix(3)) : [])
        return PlanCoach.gapText(shown)
    }
}
