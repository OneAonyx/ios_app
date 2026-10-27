import Foundation

/// Gewohnheit (Zielwert je Tag, z. B. „10 Min. dehnen“) oder Routine (abhakbare Schritte).
public enum HabitKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case habit
    case routine

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .habit: "Gewohnheit"
        case .routine: "Routine"
        }
    }
}

/// Tageszeit, zu der eine Routine oder Gewohnheit gehört.
public enum HabitPeriod: String, Codable, Sendable, CaseIterable, Identifiable {
    case morning
    case evening
    case anytime

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .morning: "Morgens"
        case .evening: "Abends"
        case .anytime: "Jederzeit"
        }
    }

    public var symbol: String {
        switch self {
        case .morning: "sunrise.fill"
        case .evening: "moon.stars.fill"
        case .anytime: "clock"
        }
    }

    /// Passt die Tageszeit gerade? Morgens bis 12 Uhr, abends ab 17 Uhr.
    public func isCurrent(now: Date, calendar: Calendar) -> Bool {
        let hour = calendar.component(.hour, from: now)
        switch self {
        case .morning: return hour >= 4 && hour < 12
        case .evening: return hour >= 17
        case .anytime: return true
        }
    }
}

/// Wann eine Gewohnheit fällig ist.
public struct HabitSchedule: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case daily
        /// Bestimmte Wochentage (1 = Sonntag … 7 = Samstag, wie `Calendar`).
        case weekdays
        /// Flexibel: so oft pro Woche, egal an welchen Tagen.
        case timesPerWeek
    }

    public var kind: Kind
    public var weekdays: [Int]
    public var timesPerWeek: Int

    public init(kind: Kind = .daily, weekdays: [Int] = [], timesPerWeek: Int = 3) {
        self.kind = kind
        self.weekdays = weekdays.filter { (1...7).contains($0) }.sorted()
        self.timesPerWeek = min(max(timesPerWeek, 1), 7)
    }

    public static let daily = HabitSchedule()

    public static func weekdays(_ days: [Int]) -> HabitSchedule {
        HabitSchedule(kind: .weekdays, weekdays: days)
    }

    public static func times(_ count: Int) -> HabitSchedule {
        HabitSchedule(kind: .timesPerWeek, timesPerWeek: count)
    }

    /// Steht die Gewohnheit an diesem Tag an? Bei „x pro Woche“ jeden Tag (frei wählbar).
    public func isDue(on day: Date, calendar: Calendar) -> Bool {
        switch kind {
        case .daily, .timesPerWeek: return true
        case .weekdays:
            return weekdays.isEmpty || weekdays.contains(calendar.component(.weekday, from: day))
        }
    }

    /// „Täglich“, „Mo, Mi, Fr“, „3× pro Woche“
    public var summary: String {
        switch kind {
        case .daily: return "Täglich"
        case .timesPerWeek: return "\(timesPerWeek)× pro Woche"
        case .weekdays:
            if weekdays.isEmpty || weekdays.count == 7 { return "Täglich" }
            if weekdays == [2, 3, 4, 5, 6] { return "Werktags" }
            if weekdays == [1, 7] { return "Am Wochenende" }
            // Montag zuerst.
            let ordered = weekdays.sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }
            return ordered.map { GermanCalendar.shortWeekdays[$0 - 1] }.joined(separator: ", ")
        }
    }

    public func encoded() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }

    public static func decode(_ data: Data?) -> HabitSchedule? {
        guard let data, !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(HabitSchedule.self, from: data)
    }
}

/// Ein Schritt einer Routine.
public struct RoutineStep: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String

    public init(id: String = UUID().uuidString, title: String) {
        self.id = id
        self.title = title
    }

    public static func encode(_ steps: [RoutineStep]) -> Data {
        (try? JSONEncoder().encode(steps)) ?? Data()
    }

    public static func decode(_ data: Data?) -> [RoutineStep] {
        guard let data, !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([RoutineStep].self, from: data)) ?? []
    }
}

/// Was an einem Tag erledigt wurde.
public struct HabitDay: Sendable, Hashable {
    public var day: Date
    public var value: Double
    public var doneSteps: Set<String>

    public init(day: Date, value: Double = 0, doneSteps: Set<String> = []) {
        self.day = day
        self.value = value
        self.doneSteps = doneSteps
    }
}

/// Eine Gewohnheit oder Routine ohne Datenbank.
public struct HabitFact: Sendable, Hashable {
    public var kind: HabitKind
    public var schedule: HabitSchedule
    /// Zielwert je Tag (Gewohnheit), z. B. 1 (einmal) oder 20 (Minuten).
    public var target: Double
    public var steps: [RoutineStep]
    public var createdAt: Date

    public init(kind: HabitKind, schedule: HabitSchedule = .daily, target: Double = 1, steps: [RoutineStep] = [], createdAt: Date) {
        self.kind = kind
        self.schedule = schedule
        self.target = max(target, 0.01)
        self.steps = steps
        self.createdAt = createdAt
    }

    /// Anteil 0…1 an einem Tag.
    public func fraction(_ day: HabitDay?) -> Double {
        guard let day else { return 0 }
        switch kind {
        case .habit:
            return min(day.value / target, 1)
        case .routine:
            guard !steps.isEmpty else { return day.value > 0 ? 1 : 0 }
            let done = steps.filter { day.doneSteps.contains($0.id) }.count
            return Double(done) / Double(steps.count)
        }
    }

    public func isComplete(_ day: HabitDay?) -> Bool {
        fraction(day) >= 1
    }
}

/// Serien und Quote.
public struct HabitStats: Sendable, Hashable {
    /// Tage in Folge (bei „x pro Woche“: Wochen in Folge).
    public var current: Int
    public var best: Int
    /// Erfüllte fällige Tage der letzten 30 Tage (0…1), `nil` ohne fällige Tage.
    public var rate: Double?
    /// Diese Woche erledigt (nur „x pro Woche“ sinnvoll, sonst Tage).
    public var thisWeek: Int
    public var weekTarget: Int
    /// Einheit der Serie: „Tage“ oder „Wochen“.
    public var unitIsWeeks: Bool

    /// „5 Tage in Folge“, „2 Wochen in Folge“
    public var streakText: String? {
        guard current > 0 else { return nil }
        if unitIsWeeks { return current == 1 ? "1 Woche geschafft" : "\(current) Wochen in Folge" }
        return current == 1 ? "1 Tag" : "\(current) Tage in Folge"
    }
}

public enum HabitProgress {
    /// Serien, Quote und Wochenstand. `days` je Tagesbeginn.
    public static func stats(_ fact: HabitFact, days: [Date: HabitDay], today: Date, calendar: Calendar) -> HabitStats {
        let start = calendar.startOfDay(for: fact.createdAt)
        let todayStart = calendar.startOfDay(for: today)
        func complete(_ day: Date) -> Bool { fact.isComplete(days[day]) }
        let weekStart = AgendaBuilder.startOfWeek(containing: today, calendar: calendar)

        if fact.schedule.kind == .timesPerWeek {
            let needed = fact.schedule.timesPerWeek
            func count(weekFrom monday: Date) -> Int {
                (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }.filter { $0 <= todayStart && complete($0) }.count
            }
            let thisWeek = count(weekFrom: weekStart)
            // Laufende Woche zählt erst, wenn sie geschafft ist.
            var current = thisWeek >= needed ? 1 : 0
            var monday = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
            while monday >= AgendaBuilder.startOfWeek(containing: start, calendar: calendar), count(weekFrom: monday) >= needed {
                current += 1
                monday = calendar.date(byAdding: .day, value: -7, to: monday) ?? monday
            }
            var best = 0
            var run = 0
            var week = AgendaBuilder.startOfWeek(containing: start, calendar: calendar)
            while week <= weekStart {
                if count(weekFrom: week) >= needed {
                    run += 1
                    best = max(best, run)
                } else if week < weekStart {
                    run = 0
                }
                week = calendar.date(byAdding: .day, value: 7, to: week) ?? weekStart.addingTimeInterval(1)
            }
            let rate = rateOfLastDays(30, fact: fact, complete: complete, start: start, today: todayStart, calendar: calendar)
            return HabitStats(current: current, best: max(best, current), rate: rate, thisWeek: thisWeek, weekTarget: needed, unitIsWeeks: true)
        }

        // Täglich oder bestimmte Wochentage: heute zählt mit, bricht aber die Serie nicht, solange der Tag läuft.
        var current = 0
        var day = todayStart
        if fact.schedule.isDue(on: day, calendar: calendar), !complete(day) {
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        while day >= start {
            if fact.schedule.isDue(on: day, calendar: calendar) {
                guard complete(day) else { break }
                current += 1
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }

        var best = 0
        var run = 0
        var cursor = start
        while cursor <= todayStart {
            if fact.schedule.isDue(on: cursor, calendar: calendar) {
                if complete(cursor) {
                    run += 1
                    best = max(best, run)
                } else if cursor < todayStart {
                    run = 0
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        let weekDays = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
        let due = weekDays.filter { fact.schedule.isDue(on: $0, calendar: calendar) && $0 >= start }
        let doneThisWeek = due.filter { $0 <= todayStart && complete($0) }.count
        let rate = rateOfLastDays(30, fact: fact, complete: complete, start: start, today: todayStart, calendar: calendar)
        return HabitStats(current: current, best: max(best, current), rate: rate, thisWeek: doneThisWeek, weekTarget: due.count, unitIsWeeks: false)
    }

    /// Erfüllte fällige Tage (heute nur, wenn schon erledigt). Bei „x pro Woche“: Tage mit Eintrag / (x/7 je Tag).
    static func rateOfLastDays(_ count: Int, fact: HabitFact, complete: (Date) -> Bool, start: Date, today: Date, calendar: Calendar) -> Double? {
        let first = max(start, calendar.date(byAdding: .day, value: -(count - 1), to: today) ?? today)
        var dueDays = 0
        var done = 0
        var day = first
        while day <= today {
            let isToday = day == today
            if fact.schedule.isDue(on: day, calendar: calendar) {
                if complete(day) {
                    done += 1
                    dueDays += 1
                } else if !isToday {
                    dueDays += 1
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        if fact.schedule.kind == .timesPerWeek {
            let span = max(1, (calendar.dateComponents([.day], from: first, to: today).day ?? 0) + 1)
            let expected = Double(span) * Double(fact.schedule.timesPerWeek) / 7
            return expected > 0 ? min(Double(done) / expected, 1) : nil
        }
        return dueDays > 0 ? Double(done) / Double(dueDays) : nil
    }

    /// Erinnerungen an den nächsten fälligen Tagen (heute nur, wenn noch offen und die Uhrzeit noch kommt).
    public static func reminderCandidates(
        habitID: String, name: String, kind: HabitKind, schedule: HabitSchedule, minuteOfDay: Int,
        completedToday: Bool, now: Date, days: Int = 3, calendar: Calendar
    ) -> [ReminderCandidate] {
        guard minuteOfDay >= 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        return (0..<days).compactMap { offset -> ReminderCandidate? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  schedule.isDue(on: day, calendar: calendar),
                  !(offset == 0 && completedToday),
                  let fire = calendar.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: day),
                  fire > now
            else { return nil }
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            return ReminderCandidate(
                id: String(format: "%@%@.%04d%02d%02d", NotificationIDs.Prefix.habit, habitID, parts.year ?? 0, parts.month ?? 0, parts.day ?? 0),
                kind: .habit,
                fireDate: fire,
                title: name,
                body: kind == .routine ? "Zeit für deine Routine." : "Schon erledigt? Tippe zum Abhaken.",
                referenceID: habitID
            )
        }
    }
}
