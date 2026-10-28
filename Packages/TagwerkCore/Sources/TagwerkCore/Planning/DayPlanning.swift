import Foundation

/// Was der Tag bringt, für das Morgen-Briefing.
public struct BriefingFacts: Sendable, Equatable {
    public struct Event: Sendable, Equatable {
        public var start: Date
        public var title: String
        public var isAllDay: Bool

        public init(start: Date, title: String, isAllDay: Bool = false) {
            self.start = start
            self.title = title
            self.isAllDay = isAllDay
        }
    }

    public var day: Date
    public var events: [Event]
    public var focus: [String]
    /// Fällige Aufgaben ohne die Fokus-Aufgaben.
    public var dueTasks: Int
    public var doses: Int
    public var firstDose: Date?
    /// „Push“, wenn heute ein Trainingstag ist.
    public var training: String?
    public var birthdays: [String]
    public var weekFocus: String?

    public init(
        day: Date, events: [Event] = [], focus: [String] = [], dueTasks: Int = 0, doses: Int = 0, firstDose: Date? = nil,
        training: String? = nil, birthdays: [String] = [], weekFocus: String? = nil
    ) {
        self.day = day
        self.events = events
        self.focus = focus
        self.dueTasks = dueTasks
        self.doses = doses
        self.firstDose = firstDose
        self.training = training
        self.birthdays = birthdays
        self.weekFocus = weekFocus
    }

    public var isEmpty: Bool {
        events.isEmpty && focus.isEmpty && dueTasks == 0 && doses == 0 && training == nil && birthdays.isEmpty
    }
}

/// Morgen-Briefing: eine Mitteilung, die den Tag in zwei Zeilen zusammenfasst.
public enum MorningBriefing {
    public static let standardMinute = 7 * 60 + 15

    /// „Guten Morgen, Anna“
    public static func title(name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Guten Morgen" : "Guten Morgen, \(trimmed)"
    }

    /// „2 Termine, zuerst 09:00 Zahnarzt · Fokus: Steuer, Rezept · 3 Aufgaben · 2 Einnahmen ab 08:00 · Training: Push · Geburtstag: Lena“
    public static func body(_ facts: BriefingFacts, calendar: Calendar) -> String {
        var parts: [String] = []
        let timed = facts.events.filter { !$0.isAllDay }.sorted { $0.start < $1.start }
        if let first = timed.first {
            let count = facts.events.count
            parts.append("\(count == 1 ? "1 Termin" : "\(count) Termine"), \(count == 1 ? "" : "zuerst ")\(GermanCalendar.time(first.start, calendar: calendar)) \(first.title)")
        } else if let allDay = facts.events.first {
            parts.append(facts.events.count == 1 ? allDay.title : "\(facts.events.count) Termine")
        }
        if !facts.focus.isEmpty {
            parts.append("Fokus: \(facts.focus.prefix(3).joined(separator: ", "))")
        }
        if facts.dueTasks > 0 {
            parts.append(facts.dueTasks == 1 ? (facts.focus.isEmpty ? "1 Aufgabe" : "1 weitere Aufgabe") : "\(facts.dueTasks) \(facts.focus.isEmpty ? "Aufgaben" : "weitere Aufgaben")")
        }
        if facts.doses > 0 {
            let start = facts.firstDose.map { " ab \(GermanCalendar.time($0, calendar: calendar))" } ?? ""
            parts.append(facts.doses == 1 ? "1 Einnahme\(start)" : "\(facts.doses) Einnahmen\(start)")
        }
        if let training = facts.training {
            parts.append("Training: \(training)")
        }
        if !facts.birthdays.isEmpty {
            parts.append("Geburtstag: \(facts.birthdays.joined(separator: ", "))")
        }
        var text = parts.isEmpty ? "Heute steht nichts Festes an." : parts.joined(separator: " · ")
        if let focus = facts.weekFocus, !focus.isEmpty {
            text += "\nWoche: \(focus)"
        }
        return text
    }

    /// Mitteilung für den Tag, `nil` wenn die Uhrzeit schon vorbei ist oder der Tag leer.
    public static func candidate(_ facts: BriefingFacts, minuteOfDay: Int, name: String, now: Date, calendar: Calendar) -> ReminderCandidate? {
        guard minuteOfDay >= 0, !facts.isEmpty else { return nil }
        let day = calendar.startOfDay(for: facts.day)
        guard let fire = calendar.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: day), fire > now else { return nil }
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        let key = String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        return ReminderCandidate(
            id: NotificationIDs.Prefix.briefing + key, kind: .briefing, fireDate: fire,
            title: title(name: name), body: body(facts, calendar: calendar), referenceID: key
        )
    }
}

/// Fokus der Woche: ein Satz, der eine Woche lang oben auf „Heute“ steht.
public enum WeekFocus {
    /// „2026-W44“ (ISO-Woche, Montag als Wochenbeginn).
    public static func key(for date: Date, calendar: Calendar) -> String {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        let c = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
    }

    /// Gespeichert als „2026-W44|Text“; gilt nur in derselben Woche.
    public static func current(_ stored: String, now: Date, calendar: Calendar) -> String? {
        let parts = stored.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0] == key(for: now, calendar: calendar) else { return nil }
        let text = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    public static func store(_ text: String, now: Date, calendar: Calendar) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : "\(key(for: now, calendar: calendar))|\(trimmed)"
    }
}
