import Foundation

/// Wiederholung einer Aufgabe (später auch für Routinen und Fristen).
///
/// - `fixed`: Der nächste Termin richtet sich nach dem Fälligkeitsdatum
///   („jeden Montag“), egal wann erledigt wurde.
/// - `afterCompletion`: Der nächste Termin zählt ab dem Erledigungstag
///   („3 Tage nach Erledigung“, z. B. Bettwäsche wechseln).
public struct RecurrenceRule: Codable, Sendable, Hashable {
    public enum Frequency: String, Codable, Sendable, CaseIterable {
        case daily
        case weekly
        case monthly
        case yearly
    }

    public enum Mode: String, Codable, Sendable, CaseIterable {
        case fixed
        case afterCompletion
    }

    public var frequency: Frequency
    /// Abstand in Einheiten der Frequenz, mindestens 1.
    public var interval: Int
    /// Für `weekly`: Wochentage als `Calendar`-Wochentag (1 = So … 7 = Sa).
    /// Leer = derselbe Wochentag wie das Fälligkeitsdatum.
    public var weekdays: [Int]
    /// Für `monthly`: fester Tag im Monat (1–31). Verhindert, dass aus dem 31. nach
    /// einem kurzen Monat dauerhaft der 28. wird. `nil` = Tag des Fälligkeitsdatums.
    public var monthDay: Int?
    public var mode: Mode
    /// Letzter möglicher Tag (einschließlich).
    public var endDate: Date?

    public init(
        frequency: Frequency,
        interval: Int = 1,
        weekdays: [Int] = [],
        monthDay: Int? = nil,
        mode: Mode = .fixed,
        endDate: Date? = nil
    ) {
        self.frequency = frequency
        self.interval = max(1, interval)
        self.weekdays = Array(Set(weekdays.filter { (1...7).contains($0) })).sorted {
            GermanCalendar.mondayIndex(ofWeekday: $0) < GermanCalendar.mondayIndex(ofWeekday: $1)
        }
        self.monthDay = monthDay.map { min(max($0, 1), 31) }
        self.mode = mode
        self.endDate = endDate
    }

    // MARK: - Vorlagen

    public static let daily = RecurrenceRule(frequency: .daily)
    public static let weekly = RecurrenceRule(frequency: .weekly)
    public static let workdays = RecurrenceRule(frequency: .weekly, weekdays: [2, 3, 4, 5, 6])
    public static let biweekly = RecurrenceRule(frequency: .weekly, interval: 2)
    public static let monthly = RecurrenceRule(frequency: .monthly)
    public static let yearly = RecurrenceRule(frequency: .yearly)

    public var isWorkdays: Bool {
        frequency == .weekly && interval == 1 && weekdays == [2, 3, 4, 5, 6]
    }

    // MARK: - Nächster Termin

    /// Nächster Termin nach `current` (Fälligkeit der gerade erledigten Instanz).
    /// Die Uhrzeit von `current` bleibt erhalten, auch über Sommer-/Winterzeit hinweg.
    /// `nil`, wenn das Enddatum überschritten ist.
    public func nextOccurrence(after current: Date, completedAt: Date? = nil, calendar: Calendar) -> Date? {
        let next: Date?
        switch mode {
        case .fixed:
            next = nextFixed(after: current, calendar: calendar)
        case .afterCompletion:
            let base = calendar.combining(day: completedAt ?? current, timeOf: current)
            next = adding(interval, of: frequency, to: base, calendar: calendar)
        }
        guard let next else { return nil }
        if let endDate, calendar.startOfDay(for: next) > calendar.startOfDay(for: endDate) {
            return nil
        }
        return next
    }

    /// Die nächsten `count` Termine ab `start` (einschließlich `start`), z. B. für eine Vorschau.
    public func occurrences(startingAt start: Date, count: Int, calendar: Calendar) -> [Date] {
        var dates: [Date] = []
        var current = start
        while dates.count < count {
            dates.append(current)
            guard let next = nextOccurrence(after: current, calendar: calendar) else { break }
            current = next
        }
        return dates
    }

    private func nextFixed(after current: Date, calendar: Calendar) -> Date? {
        switch frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: interval, to: current)
        case .weekly:
            guard !weekdays.isEmpty else {
                return calendar.date(byAdding: .day, value: 7 * interval, to: current)
            }
            let currentIndex = GermanCalendar.mondayIndex(ofWeekday: calendar.component(.weekday, from: current))
            let indices = weekdays.map(GermanCalendar.mondayIndex(ofWeekday:)).sorted()
            let days: Int
            if let later = indices.first(where: { $0 > currentIndex }) {
                days = later - currentIndex
            } else {
                days = 7 * interval - currentIndex + indices[0]
            }
            return calendar.date(byAdding: .day, value: days, to: current)
        case .monthly:
            return addingMonths(interval, to: current, calendar: calendar)
        case .yearly:
            return calendar.date(byAdding: .year, value: interval, to: current)
        }
    }

    private func adding(_ amount: Int, of frequency: Frequency, to date: Date, calendar: Calendar) -> Date? {
        switch frequency {
        case .daily: calendar.date(byAdding: .day, value: amount, to: date)
        case .weekly: calendar.date(byAdding: .day, value: 7 * amount, to: date)
        case .monthly: addingMonths(amount, to: date, calendar: calendar)
        case .yearly: calendar.date(byAdding: .year, value: amount, to: date)
        }
    }

    /// Monate addieren und dabei den gewünschten Tag im Monat beibehalten
    /// (31. → 30./28. in kurzen Monaten, danach wieder 31.).
    private func addingMonths(_ months: Int, to date: Date, calendar: Calendar) -> Date? {
        let day = monthDay ?? calendar.component(.day, from: date)
        var components = calendar.dateComponents([.year, .month], from: date)
        components.month = (components.month ?? 1) + months
        components.day = 1
        guard let firstOfMonth = calendar.date(from: components),
              let daysInMonth = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count
        else { return nil }
        components.day = min(day, daysInMonth)
        guard let target = calendar.date(from: components) else { return nil }
        return calendar.combining(day: target, timeOf: date)
    }

    // MARK: - Beschreibung

    /// Deutsche Kurzbeschreibung, z. B. „Wöchentlich am Mo, Mi“ oder „3 Tage nach Erledigung“.
    public func summary(calendar: Calendar) -> String {
        var text: String
        switch mode {
        case .afterCompletion:
            text = "\(interval) \(unitName(plural: interval != 1)) nach Erledigung"
        case .fixed:
            switch frequency {
            case .daily:
                text = interval == 1 ? "Täglich" : "Alle \(interval) Tage"
            case .weekly:
                if isWorkdays {
                    text = "Werktags"
                } else {
                    text = interval == 1 ? "Wöchentlich" : "Alle \(interval) Wochen"
                    if !weekdays.isEmpty {
                        let names = weekdays.map { GermanCalendar.shortWeekdays[$0 - 1] }
                        text += " am " + names.joined(separator: ", ")
                    }
                }
            case .monthly:
                text = interval == 1 ? "Monatlich" : "Alle \(interval) Monate"
                if let monthDay {
                    text += " am \(monthDay)."
                }
            case .yearly:
                text = interval == 1 ? "Jährlich" : "Alle \(interval) Jahre"
            }
        }
        if let endDate {
            let parts = calendar.dateComponents([.day, .month, .year], from: endDate)
            text += String(format: " bis %02d.%02d.%04d", parts.day ?? 1, parts.month ?? 1, parts.year ?? 0)
        }
        return text
    }

    private func unitName(plural: Bool) -> String {
        switch frequency {
        case .daily: plural ? "Tage" : "Tag"
        case .weekly: plural ? "Wochen" : "Woche"
        case .monthly: plural ? "Monate" : "Monat"
        case .yearly: plural ? "Jahre" : "Jahr"
        }
    }
}
