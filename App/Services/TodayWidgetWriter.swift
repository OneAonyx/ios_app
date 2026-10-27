import Foundation
import SwiftData
import TagwerkCore
import TagwerkKit

/// Baut den Stand für die Widgets „Heute“ und „Aufgaben“ aus Aufgaben, Einnahmen,
/// Terminen, Routinen und Geburtstagen.
@MainActor
enum TodayWidgetWriter {
    static func write(app: AppModel, now: Date = .now) {
        guard !AppInfo.isUITesting else { return }
        TodaySnapshotStore.write(makeSnapshot(app: app, now: now))
    }

    static func makeSnapshot(app: AppModel, now: Date) -> TodayWidgetSnapshot {
        let context = app.context
        let calendar = AppModel.calendar
        let defaults = UserDefaults.standard
        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        let medications = MedicationActions.fetchAll(in: context)
        let plans = (try? context.fetch(FetchDescriptor<WorkoutPlan>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))) ?? []
        let filter = FocusFilterStore.read()

        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
        let showEvents = defaults.object(forKey: SettingsKeys.showCalendarEvents) as? Bool ?? true
        let training: (WorkoutPlan?, [WorkoutSession]) = filter.hideTraining ? (nil, []) : (plans.last(where: \.isActive) ?? plans.last, sessions)
        let source = AgendaSource(
            tasks: tasks,
            medications: medications,
            training: training,
            calendarService: app.calendarService,
            showEvents: showEvents,
            hiddenCalendarIDsText: defaults.string(forKey: SettingsKeys.hiddenCalendarIDs) ?? ""
        )
        let nextUp = AgendaBuilder.nextUp(in: source.items(from: start, to: end, now: now), now: now, calendar: calendar)

        let visible = tasks.filter { filter.listID == nil || $0.facts.listID == filter.listID }
        let progress = TodayProgress.compute(visible.map(\.facts), now: now, calendar: calendar)
        let today = TaskOrdering.sorted(
            visible.filter { SmartList.today.includes($0.facts, now: now, calendar: calendar) },
            facts: \.facts, now: now, calendar: calendar
        )
        let focus = today.filter { $0.facts.isFocus(on: now, calendar: calendar) }
        let lines = (focus + today.filter { !$0.facts.isFocus(on: now, calendar: calendar) }).prefix(6).map { task in
            TodayWidgetSnapshot.TaskLine(
                id: task.stableID,
                title: task.title,
                detail: detail(for: task.facts, now: now, calendar: calendar),
                priority: task.facts.priority,
                isFocus: task.facts.isFocus(on: now, calendar: calendar)
            )
        }

        let doses = DayDoses(medications: medications.filter { $0.schedule.isScheduled }, day: now, now: now, calendar: calendar)
        let habits = LifeActions.dueToday(now: now, calendar: calendar, in: context)
        let habitsDone = habits.filter { LifeActions.isDone($0, on: now, calendar: calendar, in: context) }.count
        let birthday = LifeActions.upcomingBirthdays(within: 7, now: now, calendar: calendar, in: context).first.map { birthday in
            let fact = birthday.fact
            return "\(BirthdayLogic.headline(fact, now: now, calendar: calendar)) · \(BirthdayLogic.whenText(fact, now: now, calendar: calendar))"
        }

        return TodayWidgetSnapshot(
            writtenAt: now,
            nextUpTitle: nextUp?.title,
            nextUpTime: nextUp?.start,
            nextUpSymbol: nextUp.map { symbol(for: $0.kind) },
            tasksOpen: progress.open,
            tasksDone: progress.done,
            dosesDone: doses.done,
            dosesTotal: doses.total,
            habitsDone: habitsDone,
            habitsTotal: habits.count,
            tasks: Array(lines),
            upcoming: birthday
        )
    }

    private static func detail(for facts: TaskFacts, now: Date, calendar: Calendar) -> String {
        guard let due = facts.dueDate else { return "" }
        if facts.isOverdue(now: now, calendar: calendar) { return "überfällig" }
        return DueFormatter.label(due: due, hasTime: facts.hasDueTime, now: now, calendar: calendar)
    }

    static func symbol(for kind: AgendaItem.Kind) -> String {
        switch kind {
        case .event: "calendar"
        case .task: "checklist"
        case .medication: "pills.fill"
        case .training: "dumbbell.fill"
        case .birthday: "gift.fill"
        case .deadline: "doc.badge.clock"
        }
    }
}
