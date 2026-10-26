import Foundation

/// Eine mögliche Mitteilung. iOS erlaubt nur 64 geplante Mitteilungen gleichzeitig,
/// deshalb plant Tagwerk rollierend und mit Vorrang (Medikamente vor Aufgaben).
public struct ReminderCandidate: Sendable, Equatable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case task
        case medication

        /// Höherer Wert = wichtiger.
        public var rank: Int {
            switch self {
            case .medication: 10
            case .task: 0
            }
        }
    }

    public var id: String
    public var kind: Kind
    public var fireDate: Date
    public var title: String
    public var body: String
    /// z. B. Aufgaben- oder Medikamenten-ID für die Aktionsknöpfe.
    public var referenceID: String

    public init(id: String, kind: Kind, fireDate: Date, title: String, body: String, referenceID: String) {
        self.id = id
        self.kind = kind
        self.fireDate = fireDate
        self.title = title
        self.body = body
        self.referenceID = referenceID
    }
}

public enum ReminderPlanner {
    /// Höchstens 60 eigene Mitteilungen (4 Plätze Reserve, z. B. für Tests).
    public static let defaultLimit = 60

    /// Wählt die Mitteilungen der nächsten `horizon` Sekunden aus: wichtigere zuerst,
    /// innerhalb gleicher Wichtigkeit die früheren. Ergebnis nach Zeit sortiert.
    public static func plan(
        _ candidates: [ReminderCandidate],
        now: Date,
        horizon: TimeInterval = 72 * 3_600,
        limit: Int = defaultLimit
    ) -> [ReminderCandidate] {
        let windowEnd = now.addingTimeInterval(horizon)
        return candidates
            .filter { $0.fireDate > now && $0.fireDate <= windowEnd }
            .sorted { lhs, rhs in
                if lhs.kind.rank != rhs.kind.rank { return lhs.kind.rank > rhs.kind.rank }
                if lhs.fireDate != rhs.fireDate { return lhs.fireDate < rhs.fireDate }
                return lhs.id < rhs.id
            }
            .prefix(max(0, limit))
            .sorted { $0.fireDate < $1.fireDate }
    }
}

/// Erinnerungen für Aufgaben.
public enum TaskReminders {
    /// Uhrzeit für Erinnerungen an ganztägige Aufgaben.
    public static let allDayReminderHour = 9

    /// Auswahl im Editor: Minuten vor der Fälligkeit.
    public static let presets: [(minutes: Int, label: String)] = [
        (0, "Zur Fälligkeit"),
        (5, "5 Min. vorher"),
        (15, "15 Min. vorher"),
        (30, "30 Min. vorher"),
        (60, "1 Std. vorher"),
        (1_440, "1 Tag vorher"),
    ]

    public static func label(forOffset minutes: Int) -> String {
        presets.first { $0.minutes == minutes }?.label ?? "\(minutes) Min. vorher"
    }

    public static func candidates(
        taskID: String,
        title: String,
        dueDate: Date,
        hasDueTime: Bool,
        offsets: [Int],
        calendar: Calendar
    ) -> [ReminderCandidate] {
        let anchor = hasDueTime
            ? dueDate
            : (calendar.date(bySettingHour: allDayReminderHour, minute: 0, second: 0, of: dueDate) ?? dueDate)
        let time = GermanCalendar.time(dueDate, calendar: calendar)
        return Set(offsets).sorted().map { offset in
            let body: String
            switch (offset >= 1_440, hasDueTime) {
            case (true, true): body = "Morgen um \(time) fällig"
            case (true, false): body = "Morgen fällig"
            case (false, true): body = "Fällig um \(time)"
            case (false, false): body = "Heute fällig"
            }
            return ReminderCandidate(
                id: "task.\(taskID).\(offset)",
                kind: .task,
                fireDate: anchor.addingTimeInterval(TimeInterval(-offset * 60)),
                title: title,
                body: body,
                referenceID: taskID
            )
        }
    }
}
