import Foundation

/// Die für Filter und Sortierung relevanten Eigenschaften einer Aufgabe.
/// Die SwiftData-Klasse liefert diese Werte, die Logik hier bleibt testbar.
public struct TaskFacts: Sendable, Equatable {
    public var dueDate: Date?
    public var hasDueTime: Bool
    public var isDone: Bool
    public var completedAt: Date?
    public var priority: Int
    public var isFlagged: Bool
    /// Tag, für den die Aufgabe im „Fokus“ steht.
    public var focusDate: Date?
    public var listID: String?
    public var sortIndex: Double
    public var createdAt: Date

    public init(
        dueDate: Date? = nil,
        hasDueTime: Bool = false,
        isDone: Bool = false,
        completedAt: Date? = nil,
        priority: Int = 0,
        isFlagged: Bool = false,
        focusDate: Date? = nil,
        listID: String? = nil,
        sortIndex: Double = 0,
        createdAt: Date = Date(timeIntervalSince1970: 0)
    ) {
        self.dueDate = dueDate
        self.hasDueTime = hasDueTime
        self.isDone = isDone
        self.completedAt = completedAt
        self.priority = priority
        self.isFlagged = isFlagged
        self.focusDate = focusDate
        self.listID = listID
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }

    public func isOverdue(now: Date, calendar: Calendar) -> Bool {
        guard !isDone, let dueDate else { return false }
        return DueFormatter.isOverdue(due: dueDate, hasTime: hasDueTime, now: now, calendar: calendar)
    }

    public func isDueToday(now: Date, calendar: Calendar) -> Bool {
        guard let dueDate else { return false }
        return calendar.isDate(dueDate, inSameDayAs: now)
    }

    public func isFocus(on day: Date, calendar: Calendar) -> Bool {
        guard let focusDate else { return false }
        return calendar.isDate(focusDate, inSameDayAs: day)
    }

    public func wasCompleted(on day: Date, calendar: Calendar) -> Bool {
        guard isDone, let completedAt else { return false }
        return calendar.isDate(completedAt, inSameDayAs: day)
    }
}

/// Feste Listen im Planer.
public enum SmartList: String, CaseIterable, Sendable, Identifiable, Hashable {
    case today
    case planned
    case inbox
    case flagged
    case all
    case done

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .today: "Heute"
        case .planned: "Geplant"
        case .inbox: "Eingang"
        case .flagged: "Markiert"
        case .all: "Alle offenen"
        case .done: "Erledigt"
        }
    }

    public var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .planned: "calendar"
        case .inbox: "tray"
        case .flagged: "flag"
        case .all: "tray.full"
        case .done: "checkmark.circle"
        }
    }

    /// „Heute“ enthält Überfälliges, heute Fälliges und den Fokus des Tages.
    /// „Eingang“ sind offene Aufgaben ohne Datum und ohne Liste.
    public func includes(_ task: TaskFacts, now: Date, calendar: Calendar) -> Bool {
        switch self {
        case .today:
            guard !task.isDone else { return false }
            if task.isFocus(on: now, calendar: calendar) { return true }
            guard let due = task.dueDate else { return false }
            return calendar.startOfDay(for: due) <= calendar.startOfDay(for: now)
        case .planned:
            return !task.isDone && task.dueDate != nil
        case .inbox:
            return !task.isDone && task.dueDate == nil && task.listID == nil
        case .flagged:
            return !task.isDone && task.isFlagged
        case .all:
            return !task.isDone
        case .done:
            return task.isDone
        }
    }
}

/// Sortierung von Aufgaben.
public enum TaskOrdering {
    /// Offene Aufgaben: überfällig zuerst, dann nach Datum (ganztägig vor Uhrzeit),
    /// ohne Datum ans Ende, dann Priorität, eigene Reihenfolge, Erstellung.
    /// Erledigte Aufgaben: zuletzt erledigte zuerst.
    public static func areInIncreasingOrder(_ a: TaskFacts, _ b: TaskFacts, now: Date, calendar: Calendar) -> Bool {
        if a.isDone != b.isDone {
            return !a.isDone
        }
        if a.isDone {
            return (a.completedAt ?? .distantPast) > (b.completedAt ?? .distantPast)
        }
        let aOverdue = a.isOverdue(now: now, calendar: calendar)
        let bOverdue = b.isOverdue(now: now, calendar: calendar)
        if aOverdue != bOverdue {
            return aOverdue
        }
        switch (a.dueDate, b.dueDate) {
        case let (aDue?, bDue?):
            let aDay = calendar.startOfDay(for: aDue)
            let bDay = calendar.startOfDay(for: bDue)
            if aDay != bDay { return aDay < bDay }
            if a.hasDueTime != b.hasDueTime { return !a.hasDueTime }
            if a.hasDueTime, aDue != bDue { return aDue < bDue }
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            break
        }
        if a.priority != b.priority {
            return a.priority > b.priority
        }
        if a.sortIndex != b.sortIndex {
            return a.sortIndex < b.sortIndex
        }
        return a.createdAt < b.createdAt
    }

    public static func sorted<T>(_ items: [T], facts: (T) -> TaskFacts, now: Date, calendar: Calendar) -> [T] {
        items
            .map { (item: $0, facts: facts($0)) }
            .sorted { areInIncreasingOrder($0.facts, $1.facts, now: now, calendar: calendar) }
            .map(\.item)
    }
}

/// Fortschritt des Tages für die Ringe auf „Heute“.
public struct TodayProgress: Sendable, Equatable {
    public var done: Int
    public var open: Int

    public var total: Int { done + open }

    /// 0…1, bei 0 Aufgaben 0.
    public var fraction: Double {
        total == 0 ? 0 : Double(done) / Double(total)
    }

    public init(done: Int, open: Int) {
        self.done = done
        self.open = open
    }

    /// Offen: alles aus „Heute“. Erledigt: heute erledigte Aufgaben, die heute
    /// oder früher fällig waren oder im Fokus standen.
    public static func compute(_ tasks: [TaskFacts], now: Date, calendar: Calendar) -> TodayProgress {
        let open = tasks.filter { SmartList.today.includes($0, now: now, calendar: calendar) }.count
        let done = tasks.filter { task in
            guard task.wasCompleted(on: now, calendar: calendar) else { return false }
            if task.isFocus(on: now, calendar: calendar) { return true }
            guard let due = task.dueDate else { return false }
            return calendar.startOfDay(for: due) <= calendar.startOfDay(for: now)
        }.count
        return TodayProgress(done: done, open: open)
    }
}

/// Regeln für „Fokus 3“: höchstens drei Hauptaufgaben pro Tag.
public enum FocusRules {
    public static let maximum = 3

    public static func canAddFocus(currentCount: Int) -> Bool {
        currentCount < maximum
    }
}
