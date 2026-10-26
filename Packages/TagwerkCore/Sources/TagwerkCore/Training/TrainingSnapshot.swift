import Foundation

/// Training im gemeinsamen Speicher für Widget, Kontrollzentrum und Siri.
public struct TrainingWidgetSnapshot: Codable, Sendable, Equatable {
    public var writtenAt: Date
    public var planName: String
    /// Nächste Einheit, z. B. „Pull“ / „B“.
    public var nextDayName: String
    public var nextDayShort: String
    public var exerciseCount: Int
    public var estimatedMinutes: Int
    /// „Woche 2 von 6“
    public var weekLabel: String
    public var isDeload: Bool
    public var lastTrainingAt: Date?
    /// Läuft gerade eine Einheit?
    public var activeSessionStart: Date?
    public var activeDayName: String?

    public init(
        writtenAt: Date, planName: String, nextDayName: String, nextDayShort: String,
        exerciseCount: Int, estimatedMinutes: Int, weekLabel: String, isDeload: Bool,
        lastTrainingAt: Date?, activeSessionStart: Date? = nil, activeDayName: String? = nil
    ) {
        self.writtenAt = writtenAt
        self.planName = planName
        self.nextDayName = nextDayName
        self.nextDayShort = nextDayShort
        self.exerciseCount = exerciseCount
        self.estimatedMinutes = estimatedMinutes
        self.weekLabel = weekLabel
        self.isDeload = isDeload
        self.lastTrainingAt = lastTrainingAt
        self.activeSessionStart = activeSessionStart
        self.activeDayName = activeDayName
    }

    public static let empty = TrainingWidgetSnapshot(
        writtenAt: .distantPast, planName: "", nextDayName: "", nextDayShort: "",
        exerciseCount: 0, estimatedMinutes: 0, weekLabel: "", isDeload: false, lastTrainingAt: nil
    )

    public var hasPlan: Bool { !nextDayName.isEmpty }

    /// Ganze Tage seit dem letzten Training (0 = heute).
    public func daysSinceLast(now: Date, calendar: Calendar) -> Int? {
        guard let lastTrainingAt else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: lastTrainingAt), to: calendar.startOfDay(for: now)).day
    }

    /// „heute trainiert“, „gestern“, „vor 3 Tagen“, „noch kein Training“.
    public func lastTrainingLabel(now: Date, calendar: Calendar) -> String {
        switch daysSinceLast(now: now, calendar: calendar) {
        case nil: "noch kein Training"
        case 0: "heute trainiert"
        case 1: "zuletzt gestern"
        case let days?: "zuletzt vor \(days) Tagen"
        }
    }

    /// Antwort für Siri.
    public func sentence(now: Date, calendar: Calendar) -> String {
        guard hasPlan else { return "Es ist noch kein Trainingsplan angelegt." }
        if let activeDayName { return "Du trainierst gerade: \(activeDayName)." }
        let deload = isDeload ? " (Deload)" : ""
        let last: String
        switch daysSinceLast(now: now, calendar: calendar) {
        case nil: last = "Bisher noch kein Training."
        case 0: last = "Heute hast du schon trainiert."
        case 1: last = "Zuletzt trainiert: gestern."
        case let days?: last = "Zuletzt trainiert: vor \(days) Tagen."
        }
        return "Als Nächstes: \(nextDayShort) \(nextDayName)\(deload), \(exerciseCount) Übungen, etwa \(estimatedMinutes) Minuten. \(last)"
    }

    public func encoded() throws -> Data {
        try SharedCoding.encoder.encode(self)
    }

    public static func decode(_ data: Data?) -> TrainingWidgetSnapshot? {
        guard let data else { return nil }
        return try? SharedCoding.decoder.decode(TrainingWidgetSnapshot.self, from: data)
    }
}

public enum WorkoutEstimate {
    /// Ungefähre Dauer in Minuten: je Satz 1 Min. Arbeit plus Pause, je Übung 1 Min. Umbau,
    /// dazu 5 Min. Aufwärmen, auf 5 Minuten gerundet.
    public static func minutes(_ items: [(sets: Int, restSeconds: Int)]) -> Int {
        let seconds = items.reduce(0) { $0 + $1.sets * ($1.restSeconds + 60) + 60 } + 5 * 60
        return Int((Double(seconds) / 60 / 5).rounded()) * 5
    }
}
