import Foundation
import SwiftData
import TagwerkCore

/// Routinen, Gewohnheiten, Verträge und Fristen, Geburtstage, Tagebuch, Haushalt.
@MainActor
public enum LifeActions {
    // MARK: Routinen und Gewohnheiten

    public static func habits(includeArchived: Bool = false, in context: ModelContext) -> [Habit] {
        let all = (try? context.fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.createdAt)]))) ?? []
        return includeArchived ? all : all.filter { !$0.isArchived }
    }

    public static func habit(stableID: String, in context: ModelContext) -> Habit? {
        var descriptor = FetchDescriptor<Habit>(predicate: #Predicate { $0.stableID == stableID })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    @discardableResult
    public static func createHabit(
        name: String, kind: HabitKind, symbol: String = "checkmark.circle", colorName: String = "orange",
        period: HabitPeriod = .anytime, schedule: HabitSchedule = .daily, target: Double = 1, unit: String = "",
        steps: [String] = [], reminderMinute: Int = -1, now: Date = .now, in context: ModelContext
    ) -> Habit {
        let habit = Habit(name: name, kind: kind, createdAt: now)
        habit.symbol = symbol
        habit.colorName = colorName
        habit.period = period
        habit.schedule = schedule
        habit.target = max(target, 0.01)
        habit.unit = unit
        habit.steps = steps.map { RoutineStep(title: $0) }
        habit.reminderMinute = reminderMinute
        habit.sortIndex = (habits(includeArchived: true, in: context).map(\.sortIndex).max() ?? 0) + 1
        context.insert(habit)
        save(context)
        return habit
    }

    @discardableResult
    public static func createHabit(from template: LifeTemplates.HabitTemplate, now: Date = .now, in context: ModelContext) -> Habit {
        let reminder: Int = switch template.period {
        case .morning: 7 * 60 + 30
        case .evening: 21 * 60
        case .anytime: -1
        }
        return createHabit(
            name: template.name, kind: template.kind, symbol: template.symbol,
            colorName: template.kind == .routine ? "indigo" : "orange", period: template.period, schedule: template.schedule,
            target: template.target, unit: template.unit, steps: template.steps, reminderMinute: reminder, now: now, in: context
        )
    }

    public static func delete(_ habit: Habit, in context: ModelContext) {
        let id = habit.stableID
        for log in (try? context.fetch(FetchDescriptor<HabitLog>(predicate: #Predicate { $0.habitID == id }))) ?? [] {
            context.delete(log)
        }
        context.delete(habit)
        save(context)
    }

    public static func logs(for habit: Habit, in context: ModelContext) -> [HabitLog] {
        let id = habit.stableID
        return (try? context.fetch(FetchDescriptor<HabitLog>(predicate: #Predicate { $0.habitID == id }, sortBy: [SortDescriptor(\.day)]))) ?? []
    }

    public static func log(for habit: Habit, on day: Date, calendar: Calendar, in context: ModelContext) -> HabitLog? {
        let id = habit.stableID
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        var descriptor = FetchDescriptor<HabitLog>(predicate: #Predicate { $0.habitID == id && $0.day >= start && $0.day < end })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    static func logEntry(for habit: Habit, on day: Date, calendar: Calendar, in context: ModelContext) -> HabitLog {
        if let existing = log(for: habit, on: day, calendar: calendar, in: context) { return existing }
        let created = HabitLog(habitID: habit.stableID, day: calendar.startOfDay(for: day))
        context.insert(created)
        return created
    }

    /// Schritt einer Routine abhaken oder zurücknehmen.
    public static func toggleStep(_ stepID: String, of habit: Habit, on day: Date = .now, calendar: Calendar, in context: ModelContext) {
        let entry = logEntry(for: habit, on: day, calendar: calendar, in: context)
        if entry.doneSteps.contains(stepID) {
            entry.doneSteps.removeAll { $0 == stepID }
        } else {
            entry.doneSteps.append(stepID)
        }
        entry.updatedAt = .now
        save(context)
    }

    /// Wert einer Gewohnheit ändern (z. B. +1 oder +10 Min.), nie unter 0.
    public static func add(_ delta: Double, to habit: Habit, on day: Date = .now, calendar: Calendar, in context: ModelContext) {
        let entry = logEntry(for: habit, on: day, calendar: calendar, in: context)
        entry.value = max(0, entry.value + delta)
        entry.updatedAt = .now
        save(context)
    }

    /// Ganz erledigt bzw. wieder offen.
    public static func toggleDone(_ habit: Habit, on day: Date = .now, calendar: Calendar, in context: ModelContext) {
        let entry = logEntry(for: habit, on: day, calendar: calendar, in: context)
        if habit.fact.isComplete(entry.habitDay) {
            entry.value = 0
            entry.doneSteps = []
        } else {
            entry.value = habit.target
            entry.doneSteps = habit.steps.map(\.id)
        }
        entry.updatedAt = .now
        save(context)
    }

    public static func days(for habit: Habit, in context: ModelContext) -> [Date: HabitDay] {
        Dictionary(logs(for: habit, in: context).map { ($0.day, $0.habitDay) }, uniquingKeysWith: { lhs, rhs in
            HabitDay(day: lhs.day, value: lhs.value + rhs.value, doneSteps: lhs.doneSteps.union(rhs.doneSteps))
        })
    }

    public static func stats(for habit: Habit, now: Date = .now, calendar: Calendar, in context: ModelContext) -> HabitStats {
        HabitProgress.stats(habit.fact, days: days(for: habit, in: context), today: now, calendar: calendar)
    }

    public static func isDone(_ habit: Habit, on day: Date = .now, calendar: Calendar, in context: ModelContext) -> Bool {
        habit.fact.isComplete(log(for: habit, on: day, calendar: calendar, in: context)?.habitDay)
    }

    /// Heute fällige, nicht archivierte Routinen und Gewohnheiten.
    public static func dueToday(now: Date = .now, calendar: Calendar, in context: ModelContext) -> [Habit] {
        habits(in: context).filter { $0.schedule.isDue(on: now, calendar: calendar) }
    }

    // MARK: Verträge und Fristen

    public static func contracts(in context: ModelContext) -> [Contract] {
        (try? context.fetch(FetchDescriptor<Contract>(sortBy: [SortDescriptor(\.name)]))) ?? []
    }

    public static func contract(stableID: String, in context: ModelContext) -> Contract? {
        var descriptor = FetchDescriptor<Contract>(predicate: #Predicate { $0.stableID == stableID })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    @discardableResult
    public static func createContract(from template: LifeTemplates.ContractTemplate, now: Date = .now, in context: ModelContext) -> Contract {
        let contract = Contract(name: template.name, kind: template.kind, createdAt: now)
        contract.billing = template.billing
        contract.notice = template.notice
        contract.reminderDaysBefore = template.reminderDaysBefore
        context.insert(contract)
        save(context)
        return contract
    }

    public static func delete(_ contract: Contract, in context: ModelContext) {
        context.delete(contract)
        save(context)
    }

    /// Einträge, deren Frist bald ansteht oder abgelaufen ist, nach Datum.
    public static func attention(now: Date = .now, calendar: Calendar, in context: ModelContext) -> [Contract] {
        contracts(in: context)
            .filter { ContractLogic.status($0.fact, now: now, calendar: calendar).needsAttention }
            .sorted {
                (ContractLogic.deadline($0.fact, now: now, calendar: calendar) ?? $0.endDate ?? .distantFuture)
                    < (ContractLogic.deadline($1.fact, now: now, calendar: calendar) ?? $1.endDate ?? .distantFuture)
            }
    }

    // MARK: Geburtstage

    public static func birthdays(in context: ModelContext) -> [Birthday] {
        (try? context.fetch(FetchDescriptor<Birthday>(sortBy: [SortDescriptor(\.name)]))) ?? []
    }

    public static func upcomingBirthdays(within days: Int = 30, now: Date = .now, calendar: Calendar, in context: ModelContext) -> [Birthday] {
        birthdays(in: context)
            .filter { BirthdayLogic.daysUntil($0.fact, now: now, calendar: calendar) <= days }
            .sorted { BirthdayLogic.daysUntil($0.fact, now: now, calendar: calendar) < BirthdayLogic.daysUntil($1.fact, now: now, calendar: calendar) }
    }

    @discardableResult
    public static func addBirthday(name: String, day: Int, month: Int, year: Int?, reminderDaysBefore: Int = 3, in context: ModelContext) -> Birthday {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        // Doppelte (gleicher Name, gleicher Tag) nicht noch einmal anlegen.
        if let existing = birthdays(in: context).first(where: { $0.name == trimmed && $0.day == day && $0.month == month }) {
            return existing
        }
        let birthday = Birthday(name: trimmed, day: day, month: month, year: year)
        birthday.reminderDaysBefore = reminderDaysBefore
        context.insert(birthday)
        save(context)
        return birthday
    }

    public static func delete(_ birthday: Birthday, in context: ModelContext) {
        context.delete(birthday)
        save(context)
    }

    // MARK: Tagebuch

    public static func journal(on day: Date, calendar: Calendar, in context: ModelContext) -> JournalEntry? {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        var descriptor = FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.day >= start && $0.day < end })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    public static func journalEntries(in context: ModelContext) -> [JournalEntry] {
        (try? context.fetch(FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\.day, order: .reverse)]))) ?? []
    }

    /// Antwort und Notiz speichern. Leere Einträge werden entfernt.
    public static func saveJournal(answer: String, text: String, on day: Date = .now, calendar: Calendar, in context: ModelContext) {
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = journal(on: day, calendar: calendar, in: context)
        if trimmedAnswer.isEmpty, trimmedText.isEmpty {
            if let existing { context.delete(existing) }
            save(context)
            return
        }
        let entry = existing ?? {
            let created = JournalEntry(day: calendar.startOfDay(for: day), prompt: JournalPrompts.prompt(for: day, calendar: calendar))
            context.insert(created)
            return created
        }()
        entry.answer = trimmedAnswer
        entry.text = trimmedText
        entry.updatedAt = .now
        save(context)
    }

    /// „Top 3 für morgen“: legt Aufgaben für morgen an und setzt sie in den Fokus.
    @discardableResult
    public static func planTomorrow(_ titles: [String], now: Date = .now, calendar: Calendar, in context: ModelContext) -> [TaskItem] {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let cleaned = titles.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(FocusRules.maximum)
        let created = cleaned.map { title -> TaskItem in
            let task = TaskItem(title: title, dueDate: tomorrow)
            task.focusDate = tomorrow
            context.insert(task)
            return task
        }
        save(context)
        return Array(created)
    }

    // MARK: Haushalt

    /// Wiederkehrende Haushaltsaufgabe aus einer Vorlage, ab heute fällig.
    @discardableResult
    public static func addChore(_ chore: LifeTemplates.Chore, now: Date = .now, calendar: Calendar, in context: ModelContext) -> TaskItem {
        let lists = (try? context.fetch(FetchDescriptor<TaskList>())) ?? []
        let home = lists.first { $0.name.localizedCaseInsensitiveContains("haushalt") }
        let task = TaskItem(title: chore.title, dueDate: calendar.startOfDay(for: now), list: home)
        task.recurrence = chore.recurrence
        context.insert(task)
        save(context)
        return task
    }

    // MARK: Agenda und Erinnerungen

    public static func agendaItems(from start: Date, to end: Date, now: Date = .now, calendar: Calendar, in context: ModelContext) -> [AgendaItem] {
        let birthdayItems = birthdays(in: context).compactMap {
            BirthdayLogic.agendaItem(id: $0.stableID, fact: $0.fact, from: start, to: end, calendar: calendar)
        }
        let deadlineItems = contracts(in: context).compactMap {
            ContractLogic.agendaItem(id: $0.stableID, fact: $0.fact, from: start, to: end, now: now, calendar: calendar)
        }
        return birthdayItems + deadlineItems
    }

    public static func reminderCandidates(now: Date, calendar: Calendar, in context: ModelContext) -> [ReminderCandidate] {
        let habitItems = habits(in: context).flatMap { habit in
            HabitProgress.reminderCandidates(
                habitID: habit.stableID, name: habit.name, kind: habit.kind, schedule: habit.schedule,
                minuteOfDay: habit.reminderMinute, completedToday: isDone(habit, on: now, calendar: calendar, in: context),
                now: now, calendar: calendar
            )
        }
        let contractItems = contracts(in: context).flatMap {
            ContractLogic.reminderCandidates(id: $0.stableID, fact: $0.fact, now: now, calendar: calendar)
        }
        let birthdayItems = birthdays(in: context).flatMap {
            BirthdayLogic.reminderCandidates(id: $0.stableID, fact: $0.fact, now: now, calendar: calendar)
        }
        return habitItems + contractItems + birthdayItems
    }

    public static func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            print("Orbit: Speichern fehlgeschlagen: \(error)")
        }
    }
}
