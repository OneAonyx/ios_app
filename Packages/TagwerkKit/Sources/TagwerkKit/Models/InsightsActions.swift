import Foundation
import SwiftData
import TagwerkCore

/// Check-ins, Wochenrückblick, Arztbericht und Claude-Verlauf.
@MainActor
public enum InsightsActions {
    // MARK: Check-ins

    public static func checkIn(on day: Date, calendar: Calendar, in context: ModelContext) -> DailyCheckIn? {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        var descriptor = FetchDescriptor<DailyCheckIn>(predicate: #Predicate { $0.day >= start && $0.day < end })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// Wert setzen (legt den Check-in des Tages bei Bedarf an).
    public static func set(_ scale: CheckInScale, _ value: Int?, on day: Date = .now, calendar: Calendar, in context: ModelContext) {
        let entry = checkIn(on: day, calendar: calendar, in: context) ?? {
            let created = DailyCheckIn(day: calendar.startOfDay(for: day))
            context.insert(created)
            return created
        }()
        entry.set(scale, value)
        save(context)
    }

    public static func setNote(_ note: String, on day: Date = .now, calendar: Calendar, in context: ModelContext) {
        let entry = checkIn(on: day, calendar: calendar, in: context) ?? {
            let created = DailyCheckIn(day: calendar.startOfDay(for: day))
            context.insert(created)
            return created
        }()
        entry.note = note
        entry.updatedAt = .now
        save(context)
    }

    public static func checkIns(from start: Date, to end: Date, in context: ModelContext) -> [DailyCheckIn] {
        let descriptor = FetchDescriptor<DailyCheckIn>(predicate: #Predicate { $0.day >= start && $0.day < end }, sortBy: [SortDescriptor(\.day)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Wenig Schlaf und viel Stress als Umstände für die Muster-Auswertung.
    public static func dayFactors(from start: Date, to end: Date, calendar: Calendar, in context: ModelContext) -> [DayFactor] {
        checkIns(from: calendar.startOfDay(for: start), to: end, in: context).flatMap { $0.fact.factors(calendar: calendar) }
    }

    // MARK: Erinnerung

    public static var reviewReminderEnabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKeys.weeklyReviewReminder) as? Bool ?? true
    }

    public static func reminderCandidates(now: Date, calendar: Calendar) -> [ReminderCandidate] {
        guard reviewReminderEnabled, let candidate = ReviewReminders.candidate(now: now, calendar: calendar) else { return [] }
        return [candidate]
    }

    // MARK: Wochenrückblick

    public static func weeklyReview(weekStart: Date, now: Date = .now, calendar: Calendar, in context: ModelContext) -> WeeklyReview {
        WeeklyReview.make(reviewInput(weekStart: weekStart, now: now, calendar: calendar, in: context), calendar: calendar)
    }

    public static func reviewInput(weekStart: Date, now: Date = .now, calendar: Calendar, in context: ModelContext) -> WeeklyReviewInput {
        let start = calendar.startOfDay(for: weekStart)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 86_400)
        let until = min(end, now)

        // Aufgaben
        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        let completed = tasks.filter { task in
            guard task.isDone, let done = task.completedAt else { return false }
            return done >= start && done < end
        }.count
        let overdue = tasks.filter { task in
            guard !task.isDone, let due = task.dueDate else { return false }
            return due < calendar.startOfDay(for: until)
        }.count

        // Medikamente
        var adherence = AdherenceSummary()
        let medications = MedicationActions.fetchAll(in: context).filter { $0.isActive && $0.schedule.isScheduled }
        for medication in medications {
            let summary = Adherence.summarize(medication.entries(from: start, to: until, now: now, calendar: calendar))
            adherence.taken += summary.taken
            adherence.skipped += summary.skipped
            adherence.missed += summary.missed
            adherence.open += summary.open
        }

        // Training
        let sessions = TrainingActions.sessions(from: start, to: end, in: context).filter { !$0.isActive }
        let workouts = sessions.map { session in
            WorkoutFact(
                date: session.startedAt,
                title: session.title,
                workingSets: session.doneSets.filter { $0.kind != .warmup }.count,
                volume: session.volume
            )
        }
        let plan = TrainingActions.activePlan(in: context)
        let records = weekRecords(start: start, end: end, sessions: sessions, in: context)

        // Ernährung
        var days: [NutritionDay] = []
        var day = start
        while day < until {
            let value = NutritionActions.day(day, calendar: calendar, in: context)
            if !value.meals.isEmpty || value.waterML > 0 { days.append(value) }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? until
        }

        // Gewicht
        let weights = TrainingActions.metrics(.weight, in: context)
        let before = weights.last { $0.date < start }?.value
        let after = weights.last { $0.date >= start && $0.date < end }?.value

        return WeeklyReviewInput(
            weekStart: start,
            tasksCompleted: completed,
            tasksOverdue: overdue,
            medication: adherence.expected > 0 ? adherence : nil,
            workouts: workouts,
            plannedWorkouts: plan.map { $0.preferredWeekdays.count }.flatMap { $0 > 0 ? $0 : nil },
            records: records,
            nutritionDays: days,
            symptoms: NutritionActions.symptoms(from: start, to: end, in: context).map(\.fact),
            checkIns: checkIns(from: start, to: end, in: context).map(\.fact),
            weightBefore: before,
            weightAfter: after
        )
    }

    /// Neue Höchstgewichte der Woche gegenüber allen Einheiten davor.
    static func weekRecords(start: Date, end: Date, sessions: [WorkoutSession], in context: ModelContext) -> [String] {
        let catalog = TrainingActions.catalog(in: context)
        let earlier = TrainingActions.finishedSessions(in: context, limit: 300).filter { $0.startedAt < start }
        var previousBest: [String: Double] = [:]
        for session in earlier {
            for set in session.doneSets where set.kind == .working && set.weight > 0 {
                previousBest[set.exerciseID] = max(previousBest[set.exerciseID] ?? 0, set.weight)
            }
        }
        var weekBest: [String: Double] = [:]
        for session in sessions {
            for set in session.doneSets where set.kind == .working && set.weight > 0 {
                weekBest[set.exerciseID] = max(weekBest[set.exerciseID] ?? 0, set.weight)
            }
        }
        return weekBest
            .compactMap { id, best -> (String, Double)? in
                guard let before = previousBest[id], best > before else { return nil }
                return (id, best)
            }
            .sorted { $0.1 > $1.1 }
            .map { "Neues Höchstgewicht: \(catalog.name(for: $0.0)) \(WeightFormat.number($0.1)) kg" }
    }

    // MARK: Arztbericht

    public static func doctorReport(from: Date, to: Date, name: String, now: Date = .now, calendar: Calendar, in context: ModelContext) -> DoctorReport {
        let start = calendar.startOfDay(for: from)
        let end = min(to, now)

        let medications = MedicationActions.fetchAll(in: context).compactMap { medication -> DoctorReport.MedicationLine? in
            let extras = medication.extraIntakes(from: start, to: end).count
            let adherence = medication.schedule.isScheduled
                ? Adherence.summarize(medication.entries(from: max(start, medication.startDate), to: end, now: now, calendar: calendar))
                : nil
            let hadActivity = medication.isActive || extras > 0 || (adherence?.taken ?? 0) > 0
            guard hadActivity else { return nil }
            return DoctorReport.MedicationLine(
                name: medication.displayName,
                schedule: medication.schedule.summary,
                hint: medication.timing.hint,
                adherence: adherence,
                extraIntakes: extras,
                isActive: medication.isActive
            )
        }

        let symptoms = NutritionActions.symptoms(from: start, to: end, in: context).map {
            DoctorReport.SymptomLogRow(date: $0.date, type: $0.type, severity: $0.severity, durationMinutes: $0.durationMinutes, note: $0.note)
        }

        let catalog = NutritionActions.catalog(in: context)
        let meals = NutritionActions.meals(from: start, to: end, in: context)
        let facts = NutritionActions.facts(meals, catalog: catalog, in: context)
        let factors = dayFactors(from: start, to: end, calendar: calendar, in: context)
        let report = TriggerAnalysis.analyze(
            meals: facts,
            symptoms: NutritionActions.symptoms(from: start, to: end.addingTimeInterval(86_400), in: context).map(\.fact),
            dayFactors: factors
        )
        let byDay = Dictionary(grouping: facts) { calendar.startOfDay(for: $0.date) }
        let loads = byDay.values.map { HistamineLoad.compute($0) }

        let tolerances = NutritionActions.tolerances(in: context)
        let avoided = tolerances.filter { $0.value == .avoid }.keys.map { catalog.name(for: $0) }
        let caution = tolerances.filter { $0.value == .caution }.keys.map { catalog.name(for: $0) }

        let weights = TrainingActions.metrics(.weight, in: context).map { DoctorReport.WeightPoint(date: $0.date, value: $0.value) }

        return DoctorReport.make(
            from: start,
            to: end,
            createdAt: now,
            name: name,
            medications: medications,
            symptoms: symptoms,
            findings: report.hasEnoughData ? report.findings : [],
            mealCount: meals.count,
            avoidedFoods: avoided,
            cautionFoods: caution,
            loads: loads,
            weights: weights,
            checkIns: checkIns(from: start, to: end, in: context).map(\.fact),
            calendar: calendar
        )
    }

    /// „Kopfschmerz 4×, Hautrötung 2×“ für Claude.
    public static func symptomSummary(from start: Date, to end: Date, in context: ModelContext) -> [String] {
        let symptoms = NutritionActions.symptoms(from: start, to: end, in: context)
        return Dictionary(grouping: symptoms, by: \.type)
            .sorted { $0.value.count > $1.value.count }
            .map { "\($0.key.title) \($0.value.count)×" }
    }

    // MARK: Claude-Verlauf

    @discardableResult
    public static func createExchange(_ prompt: ClaudePrompt, title: String, in context: ModelContext) -> ClaudeExchange {
        let exchange = ClaudeExchange(task: prompt.task, ref: prompt.ref, title: title, prompt: prompt.text)
        context.insert(exchange)
        save(context)
        return exchange
    }

    public static func markSent(_ exchange: ClaudeExchange, in context: ModelContext) {
        exchange.status = .sent
        save(context)
    }

    public static func attach(_ response: String, to exchange: ClaudeExchange, now: Date = .now, in context: ModelContext) {
        exchange.response = response
        exchange.answeredAt = now
        exchange.status = .answered
        save(context)
    }

    public static func setStatus(_ status: ClaudeExchangeStatus, of exchange: ClaudeExchange, in context: ModelContext) {
        exchange.status = status
        save(context)
    }

    public static func delete(_ exchange: ClaudeExchange, in context: ModelContext) {
        context.delete(exchange)
        save(context)
    }

    public static func exchanges(in context: ModelContext) -> [ClaudeExchange] {
        (try? context.fetch(FetchDescriptor<ClaudeExchange>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
    }

    /// Die zuletzt abgeschickte Anfrage, die noch auf Antwort wartet.
    public static func waitingExchange(in context: ModelContext) -> ClaudeExchange? {
        let sent = ClaudeExchangeStatus.sent.rawValue
        var descriptor = FetchDescriptor<ClaudeExchange>(
            predicate: #Predicate { $0.statusRaw == sent },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    public static func exchange(ref: String, in context: ModelContext) -> ClaudeExchange? {
        var descriptor = FetchDescriptor<ClaudeExchange>(predicate: #Predicate { $0.ref == ref })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    public static func exchange(stableID: String, in context: ModelContext) -> ClaudeExchange? {
        var descriptor = FetchDescriptor<ClaudeExchange>(predicate: #Predicate { $0.stableID == stableID })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    public static func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            print("Orbit: Speichern fehlgeschlagen: \(error)")
        }
    }
}
