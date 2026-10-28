import EventKit
import Foundation
import SwiftData
import TagwerkCore

/// Tag planen: Morgen-Briefing, Tag abschließen, Woche planen.
@MainActor
public enum PlanningActions {
    /// Uhrzeit des Morgen-Briefings (Minute des Tages), −1 = aus.
    public static var briefingMinute: Int {
        UserDefaults.standard.object(forKey: SettingsKeys.briefingMinute) as? Int ?? MorningBriefing.standardMinute
    }

    /// Briefing für heute (falls die Uhrzeit noch kommt) und morgen.
    public static func reminderCandidates(now: Date = .now, calendar: Calendar, in context: ModelContext) -> [ReminderCandidate] {
        let minute = briefingMinute
        guard minute >= 0 else { return [] }
        let name = UserDefaults.standard.string(forKey: SettingsKeys.userName) ?? ""
        let today = calendar.startOfDay(for: now)
        return [0, 1].compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return MorningBriefing.candidate(briefingFacts(for: day, calendar: calendar, in: context), minuteOfDay: minute, name: name, now: now, calendar: calendar)
        }
    }

    /// Was am Tag ansteht.
    public static func briefingFacts(for day: Date, calendar: Calendar, in context: ModelContext) -> BriefingFacts {
        let start = calendar.startOfDay(for: day)
        let end = calendar.endOfDayDate(for: start)
        let noon = start.addingTimeInterval(12 * 3_600)

        let openTasks = (try? context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isDone }))) ?? []
        let focus = openTasks.filter { $0.facts.isFocus(on: start, calendar: calendar) }
        let due = openTasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return dueDate < end && !task.facts.isFocus(on: start, calendar: calendar)
        }

        let doses = MedicationActions.fetchAll(in: context)
            .filter { $0.isActive && $0.schedule.isScheduled }
            .flatMap { $0.entries(on: start, now: noon, calendar: calendar) }
            .map(\.dose.date)
            .sorted()

        var training: String?
        if let plan = TrainingActions.activePlan(in: context),
           plan.preferredWeekdays.contains(calendar.component(.weekday, from: start)) {
            training = plan.nextDay?.name
        }

        let birthdays = LifeActions.birthdays(in: context)
            .filter { BirthdayLogic.daysUntil($0.fact, now: start, calendar: calendar) == 0 }
            .map(\.name)

        let stored = UserDefaults.standard.string(forKey: SettingsKeys.weekFocus) ?? ""
        return BriefingFacts(
            day: start,
            events: events(from: start, to: end),
            focus: focus.map(\.title),
            dueTasks: due.count,
            doses: doses.count,
            firstDose: doses.first,
            training: training,
            birthdays: birthdays,
            weekFocus: WeekFocus.current(stored, now: start, calendar: calendar)
        )
    }

    /// Termine aus Apple Kalender (nur mit Zugriff, ausgeblendete Kalender bleiben draußen).
    static func events(from start: Date, to end: Date) -> [BriefingFacts.Event] {
        let defaults = UserDefaults.standard
        let show = defaults.object(forKey: SettingsKeys.showCalendarEvents) as? Bool ?? true
        guard show, EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let hidden = Set((defaults.string(forKey: SettingsKeys.hiddenCalendarIDs) ?? "").split(separator: "\n").map(String.init))
        let store = EKEventStore()
        let calendars = store.calendars(for: .event).filter { !hidden.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate).map { event in
            BriefingFacts.Event(start: event.startDate, title: event.title ?? "Termin", isAllDay: event.isAllDay)
        }
    }

    // MARK: Tag abschließen

    /// Offene Aufgaben, die heute fällig oder überfällig sind.
    public static func openToday(now: Date = .now, calendar: Calendar, in context: ModelContext) -> [TaskItem] {
        let end = calendar.endOfDayDate(for: now)
        let open = (try? context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isDone }, sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
        return open.filter { task in
            if let due = task.dueDate, due < end { return true }
            return task.facts.isFocus(on: now, calendar: calendar)
        }
    }

    /// Alle offenen Aufgaben von heute auf morgen schieben.
    @discardableResult
    public static func moveAllToTomorrow(now: Date = .now, calendar: Calendar, in context: ModelContext) -> Int {
        let tasks = openToday(now: now, calendar: calendar, in: context)
        for task in tasks {
            TaskActions.moveToTomorrow(task, in: context, now: now, calendar: calendar)
        }
        return tasks.count
    }
}
