import Foundation

/// Morgens: Schlaf und Energie. Abends: Stimmung und Stress.
public enum CheckInKind: String, Codable, Sendable, CaseIterable {
    case morning, evening

    public var title: String {
        switch self {
        case .morning: "Guten Morgen"
        case .evening: "Wie war dein Tag?"
        }
    }

    /// Welcher Check-in gerade passt: morgens bis 12 Uhr, abends ab 17 Uhr, sonst keiner.
    public static func current(now: Date, calendar: Calendar) -> CheckInKind? {
        switch calendar.component(.hour, from: now) {
        case 4..<12: .morning
        case 17..<24: .evening
        default: nil
        }
    }
}

/// Eine Skala von 1 bis 5 mit Beschriftung.
public enum CheckInScale: String, Codable, Sendable, CaseIterable, Identifiable {
    case sleep, energy, mood, stress

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sleep: "Schlaf"
        case .energy: "Energie"
        case .mood: "Stimmung"
        case .stress: "Stress"
        }
    }

    public var question: String {
        switch self {
        case .sleep: "Wie hast du geschlafen?"
        case .energy: "Wie fit fühlst du dich?"
        case .mood: "Wie geht es dir?"
        case .stress: "Wie gestresst warst du?"
        }
    }

    public var symbol: String {
        switch self {
        case .sleep: "bed.double.fill"
        case .energy: "bolt.fill"
        case .mood: "face.smiling"
        case .stress: "waveform.path"
        }
    }

    /// Bei Stress ist ein niedriger Wert gut, sonst ein hoher.
    public var higherIsBetter: Bool { self != .stress }

    /// Kurzes Zeichen je Wert (Emoji), links schlecht bzw. entspannt.
    public func emoji(_ value: Int) -> String {
        let index = min(max(value, 1), 5) - 1
        switch self {
        case .sleep: return ["😫", "🥱", "😐", "🙂", "😴"][index]
        case .energy: return ["🪫", "😮‍💨", "😐", "🙂", "⚡️"][index]
        case .mood: return ["😣", "😕", "😐", "🙂", "😄"][index]
        case .stress: return ["😌", "🙂", "😐", "😬", "🤯"][index]
        }
    }

    public func label(_ value: Int) -> String {
        let index = min(max(value, 1), 5) - 1
        switch self {
        case .sleep: return ["sehr schlecht", "schlecht", "geht so", "gut", "sehr gut"][index]
        case .energy: return ["erschöpft", "müde", "normal", "fit", "voller Energie"][index]
        case .mood: return ["sehr schlecht", "eher schlecht", "neutral", "gut", "sehr gut"][index]
        case .stress: return ["entspannt", "etwas", "mittel", "hoch", "sehr hoch"][index]
        }
    }

    /// Welche Skalen zu welchem Check-in gehören.
    public static func scales(for kind: CheckInKind) -> [CheckInScale] {
        switch kind {
        case .morning: [.sleep, .energy]
        case .evening: [.mood, .stress]
        }
    }
}

/// Werte eines Tages. Fehlende Werte sind `nil`.
public struct CheckInFact: Sendable, Hashable {
    public var day: Date
    public var sleep: Int?
    public var sleepHours: Double?
    public var energy: Int?
    public var mood: Int?
    public var stress: Int?
    public var note: String

    public init(day: Date, sleep: Int? = nil, sleepHours: Double? = nil, energy: Int? = nil, mood: Int? = nil, stress: Int? = nil, note: String = "") {
        self.day = day
        self.sleep = sleep
        self.sleepHours = sleepHours
        self.energy = energy
        self.mood = mood
        self.stress = stress
        self.note = note
    }

    public func value(_ scale: CheckInScale) -> Int? {
        switch scale {
        case .sleep: sleep
        case .energy: energy
        case .mood: mood
        case .stress: stress
        }
    }

    public func isComplete(_ kind: CheckInKind) -> Bool {
        CheckInScale.scales(for: kind).allSatisfy { value($0) != nil }
    }

    /// Umstände des Tages für die Muster-Auswertung: schlecht geschlafen, viel Stress.
    public func factors(calendar: Calendar) -> [DayFactor] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        var result: [DayFactor] = []
        if let sleep, sleep <= 2 {
            result.append(DayFactor(key: "factor.sleep", name: "Schlecht geschlafen", start: start, end: end))
        }
        if let stress, stress >= 4 {
            result.append(DayFactor(key: "factor.stress", name: "Viel Stress", start: start, end: end))
        }
        return result
    }
}

/// Ein Umstand, der für einen Zeitraum gilt (z. B. ein Tag mit wenig Schlaf).
public struct DayFactor: Sendable, Hashable {
    public var key: String
    public var name: String
    public var start: Date
    public var end: Date

    public init(key: String, name: String, start: Date, end: Date) {
        self.key = key
        self.name = name
        self.start = start
        self.end = end
    }

    public func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }
}

/// Durchschnitte über mehrere Tage.
public struct CheckInAverages: Sendable, Hashable {
    public var sleep: Double?
    public var energy: Double?
    public var mood: Double?
    public var stress: Double?
    public var days: Int

    public static func compute(_ facts: [CheckInFact]) -> CheckInAverages {
        func average(_ values: [Int]) -> Double? {
            values.isEmpty ? nil : Double(values.reduce(0, +)) / Double(values.count)
        }
        return CheckInAverages(
            sleep: average(facts.compactMap(\.sleep)),
            energy: average(facts.compactMap(\.energy)),
            mood: average(facts.compactMap(\.mood)),
            stress: average(facts.compactMap(\.stress)),
            days: facts.count
        )
    }

    public func value(_ scale: CheckInScale) -> Double? {
        switch scale {
        case .sleep: sleep
        case .energy: energy
        case .mood: mood
        case .stress: stress
        }
    }

    /// „3,8“
    public static func format(_ value: Double?) -> String {
        guard let value else { return "–" }
        return WeightFormat.number((value * 10).rounded() / 10)
    }
}
