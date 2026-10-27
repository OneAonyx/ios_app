import Foundation

/// Ein Geburtstag ohne Datenbank. Das Jahr ist optional.
public struct BirthdayFact: Sendable, Hashable {
    public var name: String
    public var day: Int
    public var month: Int
    public var year: Int?
    public var reminderDaysBefore: Int

    public init(name: String, day: Int, month: Int, year: Int? = nil, reminderDaysBefore: Int = 3) {
        self.name = name
        self.day = min(max(day, 1), 31)
        self.month = min(max(month, 1), 12)
        self.year = year
        self.reminderDaysBefore = max(0, reminderDaysBefore)
    }
}

public enum BirthdayLogic {
    /// Nächster Geburtstag ab heute (heute zählt). Der 29. Februar fällt in anderen Jahren auf den 28.
    public static func nextOccurrence(_ fact: BirthdayFact, now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        let year = calendar.component(.year, from: today)
        for candidateYear in year...(year + 1) {
            if let date = date(fact, in: candidateYear, calendar: calendar), date >= today {
                return date
            }
        }
        return today
    }

    static func date(_ fact: BirthdayFact, in year: Int, calendar: Calendar) -> Date? {
        var components = DateComponents(year: year, month: fact.month, day: fact.day)
        if let candidate = calendar.date(from: components), calendar.component(.month, from: candidate) == fact.month {
            return calendar.startOfDay(for: candidate)
        }
        // Tag gibt es in diesem Jahr nicht (29. Februar): letzter Tag des Monats.
        components.day = 1
        guard let first = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: first)
        else { return nil }
        components.day = range.upperBound - 1
        return calendar.date(from: components).map { calendar.startOfDay(for: $0) }
    }

    public static func daysUntil(_ fact: BirthdayFact, now: Date, calendar: Calendar) -> Int {
        let next = nextOccurrence(fact, now: now, calendar: calendar)
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: next).day ?? 0
    }

    /// Alter am nächsten Geburtstag, `nil` ohne Jahr.
    public static func turningAge(_ fact: BirthdayFact, now: Date, calendar: Calendar) -> Int? {
        guard let year = fact.year else { return nil }
        let next = nextOccurrence(fact, now: now, calendar: calendar)
        let age = calendar.component(.year, from: next) - year
        return age > 0 ? age : nil
    }

    /// „heute“, „morgen“, „in 5 Tagen“, „am 12. Nov.“
    public static func whenText(_ fact: BirthdayFact, now: Date, calendar: Calendar) -> String {
        let days = daysUntil(fact, now: now, calendar: calendar)
        switch days {
        case 0: return "heute"
        case 1: return "morgen"
        case 2...30: return "in \(days) Tagen"
        default: return "am " + WeeklyReview.dayMonth(nextOccurrence(fact, now: now, calendar: calendar), calendar: calendar)
        }
    }

    /// „Lena wird 30“, „Lena hat Geburtstag“
    public static func headline(_ fact: BirthdayFact, now: Date, calendar: Calendar) -> String {
        if let age = turningAge(fact, now: now, calendar: calendar) {
            return "\(fact.name) wird \(age)"
        }
        return "\(fact.name) hat Geburtstag"
    }

    /// „12. Nov.“ bzw. „12. Nov. 1994“
    public static func dateText(_ fact: BirthdayFact) -> String {
        let base = "\(fact.day). \(GermanCalendar.shortMonths[fact.month - 1])"
        return fact.year.map { "\(base) \($0)" } ?? base
    }

    /// Nach dem nächsten Termin sortiert.
    public static func upcoming(_ facts: [BirthdayFact], now: Date, calendar: Calendar) -> [BirthdayFact] {
        facts.sorted { daysUntil($0, now: now, calendar: calendar) < daysUntil($1, now: now, calendar: calendar) }
    }

    /// Eintrag für Agenda und Woche, wenn der Geburtstag im Zeitraum liegt.
    public static func agendaItem(id: String, fact: BirthdayFact, from start: Date, to end: Date, calendar: Calendar) -> AgendaItem? {
        let next = nextOccurrence(fact, now: start, calendar: calendar)
        guard next >= calendar.startOfDay(for: start), next < end else { return nil }
        return AgendaItem(
            id: "bday-\(id)", kind: .birthday, title: headline(fact, now: start, calendar: calendar),
            start: next, isAllDay: true, subtitle: "Geburtstag"
        )
    }

    /// Erinnerung X Tage vorher (9 Uhr) und am Tag selbst (8 Uhr).
    public static func reminderCandidates(id: String, fact: BirthdayFact, now: Date, calendar: Calendar) -> [ReminderCandidate] {
        let next = nextOccurrence(fact, now: now, calendar: calendar)
        var result: [ReminderCandidate] = []
        var plans: [(Date, Int, String)] = []
        if fact.reminderDaysBefore > 0, let early = calendar.date(byAdding: .day, value: -fact.reminderDaysBefore, to: next) {
            let when = fact.reminderDaysBefore == 1 ? "morgen" : "in \(fact.reminderDaysBefore) Tagen"
            plans.append((early, 9, "\(headline(fact, now: now, calendar: calendar)) \(when)"))
        }
        plans.append((next, 8, "Heute: " + headline(fact, now: now, calendar: calendar)))
        for (day, hour, title) in plans {
            guard let fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day), fire > now else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            result.append(ReminderCandidate(
                id: String(format: "%@%@.%04d%02d%02d", NotificationIDs.Prefix.birthday, id, parts.year ?? 0, parts.month ?? 0, parts.day ?? 0),
                kind: .birthday,
                fireDate: fire,
                title: title,
                body: "Geburtstag am \(WeeklyReview.dayMonth(next, calendar: calendar)).",
                referenceID: id
            ))
        }
        return result
    }
}

/// Fragen für das Tagebuch, eine je Tag im Wechsel.
public enum JournalPrompts {
    public static let all = [
        "Was lief heute gut?",
        "Wofür bist du heute dankbar?",
        "Was hat dir heute Energie gegeben?",
        "Was hast du heute gelernt?",
        "Worauf bist du heute stolz?",
        "Was nimmst du dir für morgen vor?",
        "Was hat dich heute zum Lächeln gebracht?",
    ]

    public static func prompt(for day: Date, calendar: Calendar) -> String {
        let index = (calendar.ordinality(of: .day, in: .year, for: day) ?? 1) % all.count
        return all[index]
    }
}
