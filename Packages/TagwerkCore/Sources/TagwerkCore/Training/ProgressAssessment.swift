import Foundation

/// Wie schnell es vorangeht.
public enum ProgressPace: String, Sendable, Hashable, CaseIterable {
    case tooFast
    case good
    case slow
    case stalled
    case declining
    case notEnoughData

    public var title: String {
        switch self {
        case .tooFast: "sehr schnell"
        case .good: "gutes Tempo"
        case .slow: "langsam"
        case .stalled: "Stillstand"
        case .declining: "rückläufig"
        case .notEnoughData: "noch zu wenig Daten"
        }
    }

    public var symbol: String {
        switch self {
        case .tooFast: "hare.fill"
        case .good: "checkmark.circle.fill"
        case .slow: "tortoise.fill"
        case .stalled: "pause.circle.fill"
        case .declining: "arrow.down.right.circle.fill"
        case .notEnoughData: "hourglass"
        }
    }

    /// Reihenfolge in Listen: Handlungsbedarf zuerst.
    public var sortRank: Int {
        switch self {
        case .declining: 0
        case .stalled: 1
        case .tooFast: 2
        case .slow: 3
        case .good: 4
        case .notEnoughData: 5
        }
    }
}

/// Kraftverlauf einer Übung (geschätztes Maximalgewicht, e1RM).
public struct ExerciseTrend: Sendable, Hashable, Identifiable {
    public var exerciseID: String
    public var sessions: Int
    public var weeks: Double
    public var first: Double
    public var last: Double
    /// Veränderung in Prozent pro Woche.
    public var percentPerWeek: Double
    public var pace: ProgressPace
    public var message: String

    public var id: String { exerciseID }

    /// „+1,2 % pro Woche“
    public var rateText: String {
        let rounded = (percentPerWeek * 10).rounded() / 10
        let sign = rounded > 0 ? "+" : (rounded < 0 ? "−" : "±")
        return "\(sign)\(WeightFormat.number(abs(rounded))) % pro Woche"
    }
}

/// Verlauf des Körpergewichts beim Muskelaufbau.
public struct BodyweightTrend: Sendable, Hashable {
    public var weeks: Double
    public var first: Double
    public var last: Double
    /// Prozent des Körpergewichts pro Woche.
    public var percentPerWeek: Double
    public var kilogramsPerWeek: Double
    public var pace: ProgressPace
    public var message: String

    /// „+0,3 kg pro Woche“
    public var rateText: String {
        let rounded = (kilogramsPerWeek * 100).rounded() / 100
        let sign = rounded > 0 ? "+" : (rounded < 0 ? "−" : "±")
        return "\(sign)\(WeightFormat.number(abs(rounded))) kg pro Woche"
    }
}

public enum ProgressAssessment {
    /// Kraftverlauf der letzten `weeks` Wochen. Braucht mindestens 3 Einheiten über 2 Wochen.
    public static func exercise(
        _ exerciseID: String, history: [ExercisePerformance], isCompound: Bool, now: Date, weeks: Int = 8
    ) -> ExerciseTrend {
        let from = now.addingTimeInterval(-Double(weeks) * 7 * 86_400)
        let points = history
            .filter { $0.date >= from && $0.date <= now }
            .compactMap { performance in performance.bestEstimatedOneRepMax.map { (performance.date, $0) } }
            .sorted { $0.0 < $1.0 }
        guard points.count >= 3, let firstDate = points.first?.0, let lastDate = points.last?.0,
              lastDate.timeIntervalSince(firstDate) >= 13 * 86_400
        else {
            return ExerciseTrend(
                exerciseID: exerciseID, sessions: points.count, weeks: 0, first: points.first?.1 ?? 0, last: points.last?.1 ?? 0,
                percentPerWeek: 0, pace: .notEnoughData,
                message: "Für eine Einschätzung braucht es mindestens 3 Einheiten über 2 Wochen."
            )
        }
        let slopePerDay = slope(points.map { ($0.0.timeIntervalSince(firstDate) / 86_400, $0.1) })
        let mean = points.map { $0.1 }.reduce(0, +) / Double(points.count)
        let percent = mean > 0 ? slopePerDay * 7 / mean * 100 : 0
        let span = lastDate.timeIntervalSince(firstDate) / (7 * 86_400)
        let pace = exercisePace(percent, isCompound: isCompound)
        return ExerciseTrend(
            exerciseID: exerciseID, sessions: points.count, weeks: span, first: points.first?.1 ?? 0, last: points.last?.1 ?? 0,
            percentPerWeek: percent, pace: pace, message: exerciseMessage(pace, isCompound: isCompound, weeks: span)
        )
    }

    /// Schwellen in Prozent pro Woche. Isolationsübungen dürfen schwanken, Grundübungen sind träger.
    static func exercisePace(_ percent: Double, isCompound: Bool) -> ProgressPace {
        let fast = isCompound ? 2.5 : 3.5
        let good = isCompound ? 0.5 : 0.4
        switch percent {
        case fast...: return .tooFast
        case good..<fast: return .good
        case 0.1..<good: return .slow
        case -0.5..<0.1: return .stalled
        default: return .declining
        }
    }

    static func exerciseMessage(_ pace: ProgressPace, isCompound: Bool, weeks: Double) -> String {
        let weekText = weeks >= 2 ? "seit etwa \(Int(weeks.rounded())) Wochen" : "zuletzt"
        switch pace {
        case .tooFast:
            return "Sehr schneller Anstieg. Normal, wenn die Übung neu ist oder das Startgewicht niedrig war. Sonst auf saubere Technik, volle Bewegung und ehrliche RIR achten."
        case .good:
            return "Passt: stetige Steigerung im Bereich, den man nach etwa einem Jahr Training erwarten kann. Weiter so."
        case .slow:
            return "Geht langsam voran. Erst Wiederholungen bis zum oberen Ende sammeln, dann steigern. Schlaf, Eiweiß und Kalorien prüfen."
        case .stalled:
            return "Kein Fortschritt \(weekText). Kleinere Steigerung wählen, Wiederholungsbereich wechseln oder die Übung im nächsten Zyklus tauschen."
        case .declining:
            return "Kraft sinkt \(weekText). Erholung prüfen (Schlaf, Stress, Essen). Ein Deload hilft oft."
        case .notEnoughData:
            return "Für eine Einschätzung braucht es mindestens 3 Einheiten über 2 Wochen."
        }
    }

    /// Körpergewicht der letzten `weeks` Wochen. Beim Muskelaufbau gelten etwa 0,1–0,5 % pro Woche als gut.
    public static func bodyweight(_ points: [(date: Date, value: Double)], now: Date, weeks: Int = 6) -> BodyweightTrend? {
        let from = now.addingTimeInterval(-Double(weeks) * 7 * 86_400)
        let recent = points.filter { $0.date >= from && $0.date <= now && $0.value > 0 }.sorted { $0.date < $1.date }
        guard recent.count >= 3, let firstDate = recent.first?.date, let lastDate = recent.last?.date,
              lastDate.timeIntervalSince(firstDate) >= 13 * 86_400
        else { return nil }
        let perDay = slope(recent.map { ($0.date.timeIntervalSince(firstDate) / 86_400, $0.value) })
        let mean = recent.map { $0.value }.reduce(0, +) / Double(recent.count)
        let kilograms = perDay * 7
        let percent = mean > 0 ? kilograms / mean * 100 : 0
        let pace: ProgressPace
        let message: String
        switch percent {
        case 0.5...:
            pace = .tooFast
            message = "Du nimmst schneller zu als nötig. Über 0,5 % pro Woche ist es meist viel Fett. Etwa 200–300 kcal weniger."
        case 0.1..<0.5:
            pace = .good
            message = "Gutes Aufbautempo: langsam zunehmen, damit es vor allem Muskeln werden."
        case -0.1..<0.1:
            pace = .slow
            message = "Gewicht bleibt gleich. Für Muskelaufbau leicht mehr essen (etwa 200–300 kcal am Tag)."
        default:
            pace = .declining
            message = "Gewicht sinkt. Gewollt? Für Muskelaufbau ist das zu wenig Energie."
        }
        return BodyweightTrend(
            weeks: lastDate.timeIntervalSince(firstDate) / (7 * 86_400), first: recent.first?.value ?? 0, last: recent.last?.value ?? 0,
            percentPerWeek: percent, kilogramsPerWeek: kilograms, pace: pace, message: message
        )
    }

    /// Steigung einer Ausgleichsgeraden.
    static func slope(_ points: [(Double, Double)]) -> Double {
        let count = Double(points.count)
        guard count >= 2 else { return 0 }
        let meanX = points.map { $0.0 }.reduce(0, +) / count
        let meanY = points.map { $0.1 }.reduce(0, +) / count
        let numerator = points.reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        let denominator = points.reduce(0) { $0 + ($1.0 - meanX) * ($1.0 - meanX) }
        return denominator > 0 ? numerator / denominator : 0
    }

    /// „5 gut, 2 langsam, 1 Stillstand“
    public static func summary(_ trends: [ExerciseTrend]) -> String {
        let counted = Dictionary(grouping: trends.filter { $0.pace != .notEnoughData }, by: \.pace)
        let order: [ProgressPace] = [.good, .tooFast, .slow, .stalled, .declining]
        let parts = order.compactMap { pace -> String? in
            guard let count = counted[pace]?.count, count > 0 else { return nil }
            return "\(count) \(pace.title)"
        }
        return parts.isEmpty ? "Noch zu wenig Daten" : parts.joined(separator: ", ")
    }
}

/// Pose eines Fortschrittsfotos. Gleiche Pose, gleiches Licht, gleiche Uhrzeit machen Fotos vergleichbar.
public enum PhotoPose: String, Codable, Sendable, CaseIterable, Identifiable {
    case front
    case side
    case back

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .front: "Vorne"
        case .side: "Seite"
        case .back: "Hinten"
        }
    }
}
