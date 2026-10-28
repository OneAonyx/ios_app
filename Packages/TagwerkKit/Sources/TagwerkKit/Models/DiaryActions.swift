import Foundation
import SwiftData
import TagwerkCore

/// Arzt-Tagebuch: Schmerzen, Bewegung, Tages-Vermerke, Vollständigkeit.
@MainActor
public enum DiaryActions {
    // MARK: Schmerzen

    public static func pains(from start: Date, to end: Date, in context: ModelContext) -> [PainEntry] {
        let descriptor = FetchDescriptor<PainEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    public static func allPains(in context: ModelContext) -> [PainEntry] {
        (try? context.fetch(FetchDescriptor<PainEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
    }

    @discardableResult
    public static func addPain(_ fact: PainFact, in context: ModelContext) -> PainEntry {
        let entry = PainEntry(date: fact.date, regions: fact.regions, intensity: fact.intensity)
        apply(fact, to: entry)
        context.insert(entry)
        save(context)
        return entry
    }

    public static func apply(_ fact: PainFact, to entry: PainEntry) {
        entry.date = fact.date
        entry.regions = fact.regions
        entry.intensity = fact.intensity
        entry.qualities = fact.qualities
        entry.durationMinutes = fact.durationMinutes
        entry.triggers = fact.triggers
        entry.reliefs = fact.reliefs
        entry.note = fact.note
    }

    public static func delete(_ entry: PainEntry, in context: ModelContext) {
        context.delete(entry)
        save(context)
    }

    // MARK: Bewegung

    public static func activities(from start: Date, to end: Date, in context: ModelContext) -> [ActivityEntry] {
        let descriptor = FetchDescriptor<ActivityEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    @discardableResult
    public static func addActivity(_ fact: ActivityFact, in context: ModelContext) -> ActivityEntry {
        let entry = ActivityEntry(date: fact.date, kind: fact.kind, minutes: fact.minutes, intensity: fact.intensity)
        entry.note = fact.note
        context.insert(entry)
        save(context)
        return entry
    }

    public static func delete(_ entry: ActivityEntry, in context: ModelContext) {
        context.delete(entry)
        save(context)
    }

    /// Bewegung von Hand plus beendete Gym-Einheiten (Krafttraining, mittel).
    public static func activityFacts(from start: Date, to end: Date, in context: ModelContext) -> [ActivityFact] {
        let manual = activities(from: start, to: end, in: context).map(\.fact)
        let gym = TrainingActions.sessions(from: start, to: end, in: context).compactMap { session -> ActivityFact? in
            guard let ended = session.endedAt else { return nil }
            let minutes = max(1, Int(ended.timeIntervalSince(session.startedAt) / 60))
            return ActivityFact(
                id: "gym-\(session.stableID)", date: session.startedAt, kind: .gym, minutes: minutes,
                intensity: .moderate, note: session.dayName
            )
        }
        return (manual + gym).sorted { $0.date < $1.date }
    }

    // MARK: Tages-Vermerke

    public static func diaryDay(on day: Date, calendar: Calendar, in context: ModelContext) -> DiaryDay? {
        let start = calendar.startOfDay(for: day)
        let end = calendar.endOfDayDate(for: start)
        var descriptor = FetchDescriptor<DiaryDay>(predicate: #Predicate { $0.day >= start && $0.day < end })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private static func diaryDayCreating(on day: Date, calendar: Calendar, in context: ModelContext) -> DiaryDay {
        if let existing = diaryDay(on: day, calendar: calendar, in: context) { return existing }
        let created = DiaryDay(day: calendar.startOfDay(for: day))
        context.insert(created)
        return created
    }

    /// „Heute keine Beschwerden“ setzen oder zurücknehmen.
    public static func setSymptomFree(_ value: Bool, on day: Date = .now, calendar: Calendar, in context: ModelContext) {
        let record = diaryDayCreating(on: day, calendar: calendar, in: context)
        record.symptomFree = value
        record.updatedAt = .now
        save(context)
    }

    /// „Heute keine Bewegung“ setzen oder zurücknehmen.
    public static func setRestDay(_ value: Bool, on day: Date = .now, calendar: Calendar, in context: ModelContext) {
        let record = diaryDayCreating(on: day, calendar: calendar, in: context)
        record.restDay = value
        record.updatedAt = .now
        save(context)
    }

    // MARK: Vollständigkeit

    /// Was an jedem Tag im Zeitraum erfasst ist.
    public static func dayFacts(from start: Date, to end: Date, now: Date = .now, calendar: Calendar, in context: ModelContext) -> [DiaryDayFacts] {
        let first = calendar.startOfDay(for: start)
        let meals = Dictionary(grouping: NutritionActions.meals(from: first, to: end, in: context)) { calendar.startOfDay(for: $0.date) }
        let symptoms = Dictionary(grouping: NutritionActions.symptoms(from: first, to: end, in: context)) { calendar.startOfDay(for: $0.date) }
        let pains = Dictionary(grouping: pains(from: first, to: end, in: context)) { calendar.startOfDay(for: $0.date) }
        let manual = Dictionary(grouping: activities(from: first, to: end, in: context)) { calendar.startOfDay(for: $0.date) }
        let gym = Dictionary(grouping: TrainingActions.sessions(from: first, to: end, in: context)) { calendar.startOfDay(for: $0.startedAt) }
        let checkIns = Set(InsightsActions.checkIns(from: first, to: end, in: context).map { calendar.startOfDay(for: $0.day) })
        let records = (try? context.fetch(FetchDescriptor<DiaryDay>(predicate: #Predicate { $0.day >= first && $0.day < end }))) ?? []
        let flags = Dictionary(records.map { (calendar.startOfDay(for: $0.day), $0) }, uniquingKeysWith: { lhs, _ in lhs })
        let medications = MedicationActions.fetchAll(in: context).filter { $0.schedule.isScheduled }

        var result: [DiaryDayFacts] = []
        var day = first
        while day < end {
            let doses = medications.flatMap { $0.entries(on: day, now: now, calendar: calendar) }
            result.append(DiaryDayFacts(
                day: day,
                meals: meals[day]?.count ?? 0,
                symptoms: symptoms[day]?.count ?? 0,
                pains: pains[day]?.count ?? 0,
                symptomFree: flags[day]?.symptomFree ?? false,
                activities: manual[day]?.count ?? 0,
                gymSessions: gym[day]?.filter { $0.endedAt != nil }.count ?? 0,
                restDay: flags[day]?.restDay ?? false,
                dosesDue: doses.count,
                dosesResolved: doses.filter(\.isResolved).count,
                checkIn: checkIns.contains(day)
            ))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    public static func today(now: Date = .now, calendar: Calendar, in context: ModelContext) -> DiaryDayFacts {
        let start = calendar.startOfDay(for: now)
        return dayFacts(from: start, to: calendar.endOfDayDate(for: start), now: now, calendar: calendar, in: context).first ?? DiaryDayFacts(day: start)
    }

    // MARK: Bericht

    /// Mahlzeiten, Einnahmen und Check-ins für die Tag-für-Tag-Tabelle.
    public static func reportInput(from start: Date, to end: Date, questions: String, now: Date = .now, calendar: Calendar, in context: ModelContext) -> DiaryReportInput {
        let meals = NutritionActions.meals(from: start, to: end, in: context).map { meal in
            var text = meal.sortedItems.map(\.name).joined(separator: ", ")
            if text.isEmpty { text = meal.type.title }
            if meal.freshness != .fresh { text += " (\(meal.freshness.title))" }
            return DiaryEvent(date: meal.date, text: text)
        }
        var medications: [DiaryEvent] = []
        for medication in MedicationActions.fetchAll(in: context) {
            for log in medication.logs ?? [] {
                guard let date = log.takenAt ?? log.scheduledAt, date >= start, date < end else { continue }
                let text = log.status == .taken ? medication.displayName : "ausgelassen: \(medication.displayName)"
                medications.append(DiaryEvent(date: date, text: text))
            }
        }
        return DiaryReportInput(
            pains: pains(from: start, to: end, in: context).map(\.fact),
            activities: activityFacts(from: start, to: end, in: context),
            days: dayFacts(from: start, to: end, now: now, calendar: calendar, in: context),
            meals: meals,
            medications: medications,
            checkIns: InsightsActions.checkIns(from: start, to: end, in: context).map(\.fact),
            questions: questions
        )
    }

    // MARK: Erinnerung

    /// Standard 20:30 Uhr, `-1` = aus.
    public static var reminderMinute: Int {
        UserDefaults.standard.object(forKey: SettingsKeys.diaryReminderMinute) as? Int ?? (20 * 60 + 30)
    }

    public static func reminderCandidates(now: Date, calendar: Calendar, in context: ModelContext) -> [ReminderCandidate] {
        let minute = reminderMinute
        guard minute >= 0 else { return [] }
        var result: [ReminderCandidate] = []
        let todayFacts = today(now: now, calendar: calendar, in: context)
        if let candidate = DiaryCheck.reminder(todayFacts, minuteOfDay: minute, now: now, calendar: calendar) {
            result.append(candidate)
        }
        // Morgen und übermorgen ist noch nichts eingetragen: Erinnerung vorsorglich planen.
        for offset in 1...2 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { continue }
            let empty = DiaryDayFacts(day: day)
            if let candidate = DiaryCheck.reminder(empty, minuteOfDay: minute, now: day, calendar: calendar) {
                result.append(candidate)
            }
        }
        return result
    }

    public static func save(_ context: ModelContext) {
        try? context.save()
    }
}
