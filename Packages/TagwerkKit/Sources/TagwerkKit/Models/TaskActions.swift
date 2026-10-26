import Foundation
import SwiftData
import TagwerkCore

/// Alle Änderungen an Aufgaben an einer Stelle, damit App, Mitteilungen und
/// Siri-Aktionen dieselben Regeln nutzen.
@MainActor
public enum TaskActions {
    // MARK: Anlegen

    /// Legt eine Aufgabe aus der Schnellerfassung an. Eine Liste aus „#Name“ wird
    /// gesucht (ohne Groß-/Kleinschreibung) und bei Bedarf neu angelegt.
    @discardableResult
    public static func create(
        from entry: QuickEntry,
        presetList: TaskList?,
        defaultReminderOffset: Int?,
        in context: ModelContext,
        now: Date = .now
    ) -> TaskItem {
        let list = entry.listName.map { findOrCreateList(named: $0, in: context) } ?? presetList
        let task = TaskItem(
            title: entry.title,
            dueDate: entry.dueDate,
            hasDueTime: entry.hasTime,
            priority: entry.priority,
            list: list,
            sortIndex: nextSortIndex(in: context),
            createdAt: now
        )
        task.recurrence = entry.recurrence
        if entry.hasTime, let offset = defaultReminderOffset, offset >= 0 {
            task.reminderOffsets = [offset]
        }
        context.insert(task)
        save(context)
        return task
    }

    public static func findOrCreateList(named name: String, in context: ModelContext) -> TaskList {
        let lists = (try? context.fetch(FetchDescriptor<TaskList>())) ?? []
        if let existing = lists.first(where: { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            return existing
        }
        let list = TaskList(name: name, sortIndex: Double(lists.count))
        context.insert(list)
        return list
    }

    public static func nextSortIndex(in context: ModelContext) -> Double {
        var descriptor = FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.sortIndex, order: .reverse)])
        descriptor.fetchLimit = 1
        let highest = (try? context.fetch(descriptor))?.first?.sortIndex ?? 0
        return highest + 1
    }

    // MARK: Erledigen

    public static func toggleCompletion(_ task: TaskItem, in context: ModelContext, now: Date = .now, calendar: Calendar) {
        if task.isDone {
            reopen(task, in: context)
        } else {
            complete(task, in: context, now: now, calendar: calendar)
        }
    }

    /// Markiert als erledigt. Bei Wiederholungen entsteht eine neue Aufgabe für den
    /// nächsten Termin; die erledigte bleibt als Verlauf erhalten.
    @discardableResult
    public static func complete(_ task: TaskItem, in context: ModelContext, now: Date = .now, calendar: Calendar) -> TaskItem? {
        guard !task.isDone else { return nil }
        task.isDone = true
        task.completedAt = now

        var follower: TaskItem?
        if let rule = task.recurrence {
            let base = task.dueDate ?? calendar.startOfDay(for: now)
            if let nextDate = rule.nextOccurrence(after: base, completedAt: now, calendar: calendar) {
                let next = TaskItem(
                    title: task.title,
                    notes: task.notes,
                    dueDate: nextDate,
                    hasDueTime: task.hasDueTime,
                    priority: task.priority,
                    list: task.list,
                    sortIndex: task.sortIndex,
                    createdAt: now
                )
                next.recurrenceData = task.recurrenceData
                next.reminderOffsets = task.reminderOffsets
                next.tags = task.tags
                next.isFlagged = task.isFlagged
                next.kindRaw = task.kindRaw
                next.estimateMinutes = task.estimateMinutes
                context.insert(next)
                for subtask in task.sortedSubtasks {
                    let copy = Subtask(title: subtask.title, sortIndex: subtask.sortIndex)
                    context.insert(copy)
                    copy.task = next
                }
                task.nextOccurrenceID = next.stableID
                follower = next
            }
        }
        save(context)
        return follower
    }

    /// Öffnet wieder. Eine noch unberührte Folgeaufgabe der Wiederholung wird entfernt.
    public static func reopen(_ task: TaskItem, in context: ModelContext) {
        task.isDone = false
        task.completedAt = nil
        if let nextID = task.nextOccurrenceID, let next = fetchTask(stableID: nextID, in: context), !next.isDone {
            context.delete(next)
        }
        task.nextOccurrenceID = nil
        save(context)
    }

    // MARK: Verschieben, Fokus, Löschen

    /// Verschiebt auf einen anderen Tag, die Uhrzeit bleibt.
    public static func move(_ task: TaskItem, toDay day: Date, in context: ModelContext, calendar: Calendar) {
        let start = calendar.startOfDay(for: day)
        if task.hasDueTime, let due = task.dueDate {
            let time = calendar.dateComponents([.hour, .minute], from: due)
            task.dueDate = calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: start)
        } else {
            task.dueDate = start
        }
        save(context)
    }

    public static func moveToTomorrow(_ task: TaskItem, in context: ModelContext, now: Date = .now, calendar: Calendar) {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        move(task, toDay: tomorrow, in: context, calendar: calendar)
    }

    public static func moveToNextWeek(_ task: TaskItem, in context: ModelContext, now: Date = .now, calendar: Calendar) {
        let monday = AgendaBuilder.startOfWeek(containing: now, calendar: calendar)
        let nextMonday = calendar.date(byAdding: .day, value: 7, to: monday) ?? now
        move(task, toDay: nextMonday, in: context, calendar: calendar)
    }

    /// Setzt oder entfernt den Fokus für heute. Gibt `false` zurück, wenn schon drei im Fokus sind.
    @discardableResult
    public static func toggleFocus(_ task: TaskItem, allTasks: [TaskItem], in context: ModelContext, now: Date = .now, calendar: Calendar) -> Bool {
        if task.facts.isFocus(on: now, calendar: calendar) {
            task.focusDate = nil
            save(context)
            return true
        }
        let current = allTasks.filter { !$0.isDone && $0.facts.isFocus(on: now, calendar: calendar) }.count
        guard FocusRules.canAddFocus(currentCount: current) else { return false }
        task.focusDate = calendar.startOfDay(for: now)
        save(context)
        return true
    }

    public static func delete(_ task: TaskItem, in context: ModelContext) {
        context.delete(task)
        save(context)
    }

    public static func addSubtask(titled title: String, to task: TaskItem, in context: ModelContext) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let index = (task.sortedSubtasks.last?.sortIndex ?? 0) + 1
        let subtask = Subtask(title: trimmed, sortIndex: index)
        context.insert(subtask)
        subtask.task = task
        save(context)
    }

    // MARK: Hilfen

    public static func fetchTask(stableID: String, in context: ModelContext) -> TaskItem? {
        let id = stableID
        var descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.stableID == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    public static func save(_ context: ModelContext) {
        try? context.save()
    }
}
