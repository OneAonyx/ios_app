import Foundation

/// Bewegung und Sport außerhalb des Gyms. Gym-Einheiten kommen als `.gym` aus dem Training dazu.
public enum ActivityKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case walking, running, cycling, swimming, hiking, ballSports, racketSports
    case yoga, stretching, homeWorkout, climbing, dancing, martialArts, other
    case gym

    public var id: String { rawValue }

    /// Was man von Hand einträgt (Gym-Einheiten kommen aus dem Training).
    public static var loggable: [ActivityKind] { allCases.filter { $0 != .gym } }

    public var title: String {
        switch self {
        case .walking: "Spazieren, Gehen"
        case .running: "Laufen"
        case .cycling: "Radfahren"
        case .swimming: "Schwimmen"
        case .hiking: "Wandern"
        case .ballSports: "Ballsport"
        case .racketSports: "Tennis, Badminton …"
        case .yoga: "Yoga"
        case .stretching: "Dehnen, Mobility"
        case .homeWorkout: "Training zuhause"
        case .climbing: "Klettern, Bouldern"
        case .dancing: "Tanzen"
        case .martialArts: "Kampfsport"
        case .other: "Sonstiges"
        case .gym: "Krafttraining (Gym)"
        }
    }

    /// Kurz für Tabellen: „Laufen“, „Gym“.
    public var shortTitle: String {
        switch self {
        case .walking: "Gehen"
        case .racketSports: "Tennis u. Ä."
        case .stretching: "Dehnen"
        case .homeWorkout: "Training zuhause"
        case .climbing: "Klettern"
        case .gym: "Gym"
        default: title
        }
    }

    public var symbol: String {
        switch self {
        case .walking: "figure.walk"
        case .running: "figure.run"
        case .cycling: "figure.outdoor.cycle"
        case .swimming: "figure.pool.swim"
        case .hiking: "figure.hiking"
        case .ballSports: "figure.soccer"
        case .racketSports: "figure.tennis"
        case .yoga: "figure.yoga"
        case .stretching: "figure.flexibility"
        case .homeWorkout: "figure.strengthtraining.functional"
        case .climbing: "figure.climbing"
        case .dancing: "figure.dance"
        case .martialArts: "figure.martial.arts"
        case .other: "figure.mixed.cardio"
        case .gym: "dumbbell.fill"
        }
    }

    public var defaultIntensity: ActivityIntensity {
        switch self {
        case .walking, .yoga, .stretching: .light
        case .running, .ballSports, .martialArts, .climbing: .vigorous
        default: .moderate
        }
    }

    /// Typische Dauer für den ersten Vorschlag.
    public var defaultMinutes: Int {
        switch self {
        case .walking: 30
        case .stretching: 15
        case .hiking: 120
        case .ballSports: 90
        default: 45
        }
    }
}

/// Anstrengung nach Gefühl (wie in den WHO-Empfehlungen).
public enum ActivityIntensity: Int, Codable, Sendable, CaseIterable, Identifiable, Comparable {
    case light = 1
    case moderate = 2
    case vigorous = 3

    public var id: Int { rawValue }

    public static func < (lhs: ActivityIntensity, rhs: ActivityIntensity) -> Bool { lhs.rawValue < rhs.rawValue }

    public var title: String {
        switch self {
        case .light: "leicht"
        case .moderate: "mittel"
        case .vigorous: "intensiv"
        }
    }

    public var detail: String {
        switch self {
        case .light: "Unterhaltung locker möglich"
        case .moderate: "leicht außer Atem, Sprechen geht noch"
        case .vigorous: "stark außer Atem, kaum Sprechen"
        }
    }
}

public struct ActivityFact: Sendable, Hashable, Identifiable {
    public var id: String
    public var date: Date
    public var kind: ActivityKind
    public var minutes: Int
    public var intensity: ActivityIntensity
    public var note: String

    public init(id: String = UUID().uuidString, date: Date, kind: ActivityKind, minutes: Int, intensity: ActivityIntensity, note: String = "") {
        self.id = id
        self.date = date
        self.kind = kind
        self.minutes = max(0, minutes)
        self.intensity = intensity
        self.note = note
    }

    /// Anstrengend genug, um als möglicher Auslöser zu zählen (Gym oder mindestens mittel ab 20 Min.).
    public var isStrenuous: Bool {
        kind == .gym || (intensity >= .moderate && minutes >= 20)
    }

    /// Minuten für das WHO-Ziel: mittel zählt einfach, intensiv doppelt, leicht nicht.
    public var weightedMinutes: Int {
        switch intensity {
        case .light: 0
        case .moderate: minutes
        case .vigorous: minutes * 2
        }
    }

    /// „Laufen 30 Min., intensiv“
    public var summary: String {
        "\(kind.shortTitle) \(DurationText.short(minutes)), \(intensity.title)"
    }
}

public struct ActivityWeek: Sendable, Hashable, Identifiable {
    public var weekStart: Date
    public var minutes: Int
    public var weightedMinutes: Int
    public var sessions: Int
    public var activeDays: Int
    public var id: Date { weekStart }
}

public struct ActivityKindLine: Sendable, Hashable, Identifiable {
    public var kind: ActivityKind
    public var sessions: Int
    public var minutes: Int
    public var id: String { kind.rawValue }
}

public enum ActivityStats {
    /// WHO: mindestens 150 Minuten mittlere (oder 75 intensive) Bewegung pro Woche.
    public static let weeklyTarget = 150

    public static func weeks(_ facts: [ActivityFact], from: Date, to: Date, calendar: Calendar) -> [ActivityWeek] {
        var result: [ActivityWeek] = []
        var start = AgendaBuilder.startOfWeek(containing: from, calendar: calendar)
        while start < to {
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 86_400)
            let week = facts.filter { $0.date >= start && $0.date < end }
            result.append(ActivityWeek(
                weekStart: start,
                minutes: week.reduce(0) { $0 + $1.minutes },
                weightedMinutes: week.reduce(0) { $0 + $1.weightedMinutes },
                sessions: week.count,
                activeDays: Set(week.map { calendar.startOfDay(for: $0.date) }).count
            ))
            start = end
        }
        return result
    }

    public static func byKind(_ facts: [ActivityFact]) -> [ActivityKindLine] {
        Dictionary(grouping: facts, by: \.kind)
            .map { kind, items in ActivityKindLine(kind: kind, sessions: items.count, minutes: items.reduce(0) { $0 + $1.minutes }) }
            .sorted { $0.minutes == $1.minutes ? $0.kind.title < $1.kind.title : $0.minutes > $1.minutes }
    }

    /// „Sport oder Training“ als Umstand für die Muster: von Beginn bis 6 Stunden nach dem Ende.
    public static func dayFactors(_ facts: [ActivityFact]) -> [DayFactor] {
        facts.filter(\.isStrenuous).map { fact in
            DayFactor(
                key: "activity", name: "Sport oder Training",
                start: fact.date, end: fact.date.addingTimeInterval(Double(fact.minutes + 6 * 60) * 60)
            )
        }
    }
}
