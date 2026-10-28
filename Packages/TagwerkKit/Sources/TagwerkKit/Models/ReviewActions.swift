import Foundation
import SwiftData
import TagwerkCore

/// Monats- und Jahresrückblick: Kennzahlen aus allen Bereichen.
@MainActor
public enum ReviewActions {
    /// Rückblick für den Zeitraum mit Vergleich zum Zeitraum davor.
    /// Gezählt wird erst ab dem ersten Eintrag, sonst stünde im Jahresrückblick „an 8 von 301 Tagen“,
    /// obwohl Orbit erst seit ein paar Wochen genutzt wird.
    public static func review(_ period: ReviewPeriod, start: Date, now: Date = .now, calendar: Calendar, in context: ModelContext) -> PeriodReview {
        let end = period.shifted(start, by: 1, calendar: calendar)
        let previousStart = period.shifted(start, by: -1, calendar: calendar)
        let first = firstRecordDay(calendar: calendar, in: context) ?? previousStart
        let current = metrics(from: max(start, first), to: end, now: now, calendar: calendar, in: context)
        let previous = metrics(from: max(previousStart, first), to: start, now: now, calendar: calendar, in: context)
        var review = PeriodReview.make(period: period, start: start, current: current, previous: previous, calendar: calendar)
        review.since = first > start && first < end ? first : nil
        return review
    }

    /// Erster Tag mit eigenen Einträgen. Importe aus Health und Körperwerte zählen nicht,
    /// weil sie weiter zurückreichen können als die Nutzung von Orbit.
    public static func firstRecordDay(calendar: Calendar, in context: ModelContext) -> Date? {
        func first<T: PersistentModel>(_ type: T.Type, _ key: KeyPath<T, Date>) -> Date? {
            var descriptor = FetchDescriptor<T>(sortBy: [SortDescriptor(key)])
            descriptor.fetchLimit = 1
            return (try? context.fetch(descriptor))?.first?[keyPath: key]
        }
        let dates: [Date?] = [
            first(TaskItem.self, \.createdAt),
            first(DoseLog.self, \.createdAt),
            first(WorkoutSession.self, \.startedAt),
            first(MealEntry.self, \.date),
            first(SymptomEntry.self, \.date),
            first(DailyCheckIn.self, \.day),
            first(PainEntry.self, \.date),
            first(ActivityEntry.self, \.date),
        ]
        return dates.compactMap { $0 }.min().map { calendar.startOfDay(for: $0) }
    }

    /// Kennzahlen von `start` bis `end` (exklusiv), beim laufenden Zeitraum nur bis heute.
    public static func metrics(from start: Date, to end: Date, now: Date = .now, calendar: Calendar, in context: ModelContext) -> PeriodMetrics {
        let until = min(end, calendar.endOfDayDate(for: now))
        guard until > start else { return PeriodMetrics(days: 0) }
        let days = max(1, calendar.dateComponents([.day], from: start, to: until).day ?? 1)

        let sessions = TrainingActions.sessions(from: start, to: until, in: context).filter { $0.endedAt != nil }
        let workingSets = sessions.reduce(0) { $0 + $1.doneSets.filter { $0.kind != .warmup }.count }
        let activityMinutes = DiaryActions.activityFacts(from: start, to: until, in: context).reduce(0) { $0 + $1.minutes }

        let dayFacts = DiaryActions.dayFacts(from: start, to: until, now: now, calendar: calendar, in: context)
        let symptomDays = dayFacts.filter { $0.symptoms > 0 }.count
        let diaryComplete = dayFacts.filter { DiaryCheck.items($0).allSatisfy(\.isDone) }.count

        let pains = DiaryActions.pains(from: start, to: until, in: context)
        let painByDay = Dictionary(grouping: pains) { calendar.startOfDay(for: $0.date) }.mapValues { $0.map(\.intensity).max() ?? 0 }
        let averagePain = painByDay.isEmpty ? nil : Double(painByDay.values.reduce(0, +)) / Double(painByDay.count)

        var adherence = AdherenceSummary()
        for medication in MedicationActions.fetchAll(in: context) where medication.schedule.isScheduled {
            let summary = Adherence.summarize(medication.entries(from: max(start, medication.startDate), to: until, now: now, calendar: calendar))
            adherence.taken += summary.taken
            adherence.skipped += summary.skipped
            adherence.missed += summary.missed
        }
        let resolved = adherence.taken + adherence.skipped + adherence.missed

        let checkIns = InsightsActions.checkIns(from: start, to: until, in: context).map(\.fact)
        let sleep = checkIns.compactMap(\.sleepHours)
        let moods = checkIns.compactMap(\.mood)
        let steps = HealthActions.facts(from: start, to: until, in: context).compactMap(\.steps).filter { $0 > 0 }

        let weights = TrainingActions.metrics(.weight, in: context)
        let inRange = weights.filter { $0.date >= start && $0.date < until }
        let weightStart = weights.last { $0.date < start }?.value ?? inRange.first?.value

        let past = Date.distantPast
        let tasksDone = (try? context.fetchCount(FetchDescriptor<TaskItem>(predicate: #Predicate { task in
            task.isDone && (task.completedAt ?? past) >= start && (task.completedAt ?? past) < until
        }))) ?? 0

        return PeriodMetrics(
            days: days,
            workouts: sessions.count,
            workingSets: workingSets,
            activityMinutes: activityMinutes,
            symptomDays: symptomDays,
            painDays: painByDay.count,
            averagePain: averagePain,
            adherence: resolved > 0 ? Double(adherence.taken) / Double(resolved) : nil,
            averageSleepHours: sleep.isEmpty ? nil : sleep.reduce(0, +) / Double(sleep.count),
            averageMood: moods.isEmpty ? nil : Double(moods.reduce(0, +)) / Double(moods.count),
            averageSteps: steps.isEmpty ? nil : steps.reduce(0, +) / steps.count,
            weightStart: inRange.isEmpty ? nil : weightStart,
            weightEnd: inRange.last?.value,
            diaryCompleteDays: diaryComplete,
            tasksDone: tasksDone
        )
    }

    /// Einheiten je Monat eines Jahres (für das Diagramm im Jahresrückblick).
    public static func workoutsPerMonth(year start: Date, calendar: Calendar, in context: ModelContext) -> [(month: Date, count: Int)] {
        (0..<12).compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: offset, to: start),
                  let next = calendar.date(byAdding: .month, value: 1, to: month) else { return nil }
            let count = TrainingActions.sessions(from: month, to: next, in: context).filter { $0.endedAt != nil }.count
            return (month, count)
        }
    }
}
