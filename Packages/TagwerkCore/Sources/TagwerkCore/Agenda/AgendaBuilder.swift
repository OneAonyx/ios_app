import Foundation

/// Ein Eintrag in Agenda oder Wochenansicht: Kalendertermin, Aufgabe oder Einnahme.
/// Später kommen Trainings dazu.
public struct AgendaItem: Sendable, Equatable, Identifiable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case event
        case task
        case medication
    }

    public var id: String
    public var kind: Kind
    public var title: String
    public var start: Date
    /// Ende bei Terminen. Aufgaben haben keins.
    public var end: Date?
    public var isAllDay: Bool
    public var isDone: Bool
    /// Wird vom `AgendaBuilder` gesetzt.
    public var isOverdue: Bool
    /// Farbe als Hex-Wert (z. B. Kalenderfarbe), `nil` = Standardfarbe.
    public var colorHex: String?
    /// Zusatzinfo, z. B. Kalender- oder Listenname.
    public var subtitle: String?

    public init(
        id: String,
        kind: Kind,
        title: String,
        start: Date,
        end: Date? = nil,
        isAllDay: Bool,
        isDone: Bool = false,
        isOverdue: Bool = false,
        colorHex: String? = nil,
        subtitle: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.isDone = isDone
        self.isOverdue = isOverdue
        self.colorHex = colorHex
        self.subtitle = subtitle
    }
}

public struct AgendaDay: Sendable, Equatable, Identifiable {
    public var date: Date
    public var allDay: [AgendaItem]
    public var timed: [AgendaItem]

    public var id: Date { date }
    public var isEmpty: Bool { allDay.isEmpty && timed.isEmpty }
    public var count: Int { allDay.count + timed.count }

    public init(date: Date, allDay: [AgendaItem] = [], timed: [AgendaItem] = []) {
        self.date = date
        self.allDay = allDay
        self.timed = timed
    }
}

/// Verteilt Termine und Aufgaben auf Tage.
public enum AgendaBuilder {
    /// - Parameters:
    ///   - startDay: erster Tag (wird auf Mitternacht gesetzt)
    ///   - days: Anzahl Tage
    ///   - includeOverdue: offene, überfällige Aufgaben erscheinen am ersten Tag, falls dieser heute ist
    public static func build(
        items: [AgendaItem],
        from startDay: Date,
        days: Int,
        now: Date,
        calendar: Calendar,
        includeOverdue: Bool = true
    ) -> [AgendaDay] {
        let firstDay = calendar.startOfDay(for: startDay)
        let today = calendar.startOfDay(for: now)

        return (0..<max(0, days)).compactMap { offset -> AgendaDay? in
            guard let dayStart = calendar.date(byAdding: .day, value: offset, to: firstDay),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
            else { return nil }

            var allDay: [AgendaItem] = []
            var timed: [AgendaItem] = []

            for var item in items {
                let isOverdueTask = item.kind == .task && !item.isDone
                    && DueFormatter.isOverdue(due: item.start, hasTime: !item.isAllDay, now: now, calendar: calendar)
                item.isOverdue = isOverdueTask

                let lastMoment = item.end.map { max($0, item.start) } ?? item.start
                var belongsHere = item.start < dayEnd && lastMoment >= dayStart
                // Ein Termin, der genau um Mitternacht endet, gehört nicht mehr zum neuen Tag.
                if let end = item.end, end == dayStart, item.start < dayStart {
                    belongsHere = false
                }
                // Überfällige Aufgaben aus der Vergangenheit sammeln sich auf „heute“.
                if includeOverdue, isOverdueTask, dayStart == today, calendar.startOfDay(for: item.start) < today {
                    belongsHere = true
                }
                // Erledigte Aufgaben aus vergangenen Tagen nicht mehr zeigen.
                if item.kind == .task, item.isDone, dayStart < today {
                    belongsHere = false
                }
                guard belongsHere else { continue }

                let startsToday = calendar.isDate(item.start, inSameDayAs: dayStart)
                if item.isAllDay || !startsToday {
                    allDay.append(item)
                } else {
                    timed.append(item)
                }
            }

            allDay.sort { lhs, rhs in
                if lhs.isOverdue != rhs.isOverdue { return lhs.isOverdue }
                if lhs.kind != rhs.kind { return lhs.kind == .event }
                return lhs.title.localizedCompare(rhs.title) == .orderedAscending
            }
            timed.sort { lhs, rhs in
                if lhs.start != rhs.start { return lhs.start < rhs.start }
                return lhs.title.localizedCompare(rhs.title) == .orderedAscending
            }
            return AgendaDay(date: dayStart, allDay: allDay, timed: timed)
        }
    }

    /// Montag der Woche, in der `date` liegt.
    public static func startOfWeek(containing date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let index = GermanCalendar.mondayIndex(ofWeekday: calendar.component(.weekday, from: day))
        return calendar.date(byAdding: .day, value: -index, to: day) ?? day
    }

    /// Nächster Eintrag mit Uhrzeit, der noch nicht vorbei ist (für „Als Nächstes“).
    public static func nextUp(in items: [AgendaItem], now: Date, calendar: Calendar) -> AgendaItem? {
        items
            .filter { !$0.isAllDay && !$0.isDone && calendar.isDate($0.start, inSameDayAs: now) }
            .filter { ($0.end ?? $0.start) >= now }
            .min { $0.start < $1.start }
    }
}
