import Foundation

/// Eine Erinnerung aus Apple Erinnerungen (unabhängig von EventKit, damit testbar).
public struct ExternalReminder: Sendable, Equatable {
    public enum Frequency: String, Sendable {
        case daily, weekly, monthly, yearly
    }

    public var id: String
    public var title: String
    public var notes: String
    public var listName: String
    /// Fälligkeit wie in Erinnerungen: Tag, optional mit Uhrzeit.
    public var due: DateComponents?
    /// Priorität wie in EventKit: 0 keine, 1–4 hoch, 5 mittel, 6–9 niedrig.
    public var priority: Int
    public var isCompleted: Bool
    public var completedAt: Date?
    public var frequency: Frequency?
    public var interval: Int
    /// Wochentage 1 = Sonntag … 7 = Samstag.
    public var weekdays: [Int]

    public init(
        id: String, title: String, notes: String = "", listName: String, due: DateComponents? = nil, priority: Int = 0,
        isCompleted: Bool = false, completedAt: Date? = nil, frequency: Frequency? = nil, interval: Int = 1, weekdays: [Int] = []
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.listName = listName
        self.due = due
        self.priority = priority
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.frequency = frequency
        self.interval = interval
        self.weekdays = weekdays
    }
}

/// Was aus einer Erinnerung als Aufgabe angelegt wird.
public struct ImportedTask: Sendable, Equatable {
    public var stableID: String
    public var title: String
    public var notes: String
    public var listName: String
    public var dueDate: Date?
    public var hasDueTime: Bool
    public var priority: Int
    public var isDone: Bool
    public var completedAt: Date?
    public var recurrence: RecurrenceRule?
}

/// Einmaliger Import aus Apple Erinnerungen. Erneutes Importieren legt nichts doppelt an.
public enum ReminderImport {
    public static func stableID(for reminderID: String) -> String { "reminder-\(reminderID)" }

    /// EventKit 1–4 → hoch (3), 5 → mittel (2), 6–9 → niedrig (1), 0 → keine.
    public static func priority(_ value: Int) -> Int {
        switch value {
        case 1...4: 3
        case 5: 2
        case 6...9: 1
        default: 0
        }
    }

    /// Datum und ob eine Uhrzeit gesetzt ist.
    public static func dueDate(_ components: DateComponents?, calendar: Calendar) -> (date: Date, hasTime: Bool)? {
        guard let components, let year = components.year, let month = components.month, let day = components.day else { return nil }
        var parts = DateComponents(year: year, month: month, day: day)
        let hasTime = components.hour != nil
        if hasTime {
            parts.hour = components.hour
            parts.minute = components.minute ?? 0
        }
        guard let date = calendar.date(from: parts) else { return nil }
        return (date, hasTime)
    }

    public static func recurrence(_ reminder: ExternalReminder) -> RecurrenceRule? {
        guard let frequency = reminder.frequency else { return nil }
        let mapped: RecurrenceRule.Frequency = switch frequency {
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        case .yearly: .yearly
        }
        return RecurrenceRule(frequency: mapped, interval: reminder.interval, weekdays: frequency == .weekly ? reminder.weekdays : [])
    }

    /// Aufgaben, die neu angelegt werden: ohne schon importierte, Erledigte nur auf Wunsch.
    public static func plan(_ reminders: [ExternalReminder], existingIDs: Set<String>, includeCompleted: Bool, calendar: Calendar) -> [ImportedTask] {
        reminders.compactMap { reminder in
            let id = stableID(for: reminder.id)
            let title = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !existingIDs.contains(id), !title.isEmpty, includeCompleted || !reminder.isCompleted else { return nil }
            let due = dueDate(reminder.due, calendar: calendar)
            return ImportedTask(
                stableID: id,
                title: title,
                notes: reminder.notes.trimmingCharacters(in: .whitespacesAndNewlines),
                listName: reminder.listName,
                dueDate: due?.date,
                hasDueTime: due?.hasTime ?? false,
                priority: priority(reminder.priority),
                isDone: reminder.isCompleted,
                completedAt: reminder.isCompleted ? reminder.completedAt : nil,
                recurrence: recurrence(reminder)
            )
        }
    }

    /// „23 neue Aufgaben aus 2 Listen, 4 schon vorhanden“
    public static func summary(imported: Int, lists: Int, skipped: Int) -> String {
        var text = imported == 1 ? "1 neue Aufgabe" : "\(imported) neue Aufgaben"
        text += lists == 1 ? " aus 1 Liste" : " aus \(lists) Listen"
        if skipped > 0 { text += ", \(skipped) schon vorhanden oder erledigt" }
        return text
    }
}
