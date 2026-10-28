import Foundation

// MARK: - Körperkarte

/// Ansicht der Körperkarte.
public enum BodyMapSide: String, Codable, Sendable, CaseIterable, Identifiable {
    case front, back

    public var id: String { rawValue }

    public var title: String {
        self == .front ? "Vorne" : "Hinten"
    }
}

/// Punkt auf der Körperkarte, 0…1 in Breite und Höhe der Figur.
public struct BodyPoint: Sendable, Hashable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }
}

/// Körperregion für Schmerzen. „Links“ und „rechts“ aus Sicht der Person.
public enum BodyRegion: String, Codable, Sendable, CaseIterable, Identifiable {
    case head, jaw, neck
    case shoulderLeft, shoulderRight
    case upperArmLeft, upperArmRight
    case elbowLeft, elbowRight
    case wristLeft, wristRight
    case chest, upperAbdomen, lowerAbdomen
    case upperBack, lowerBack
    case hipLeft, hipRight
    case thighLeft, thighRight
    case kneeLeft, kneeRight
    case calfLeft, calfRight
    case footLeft, footRight

    public var id: String { rawValue }

    /// Teil ohne Seite, z. B. „Schulter“.
    public var part: String {
        switch self {
        case .head: "Kopf"
        case .jaw: "Kiefer"
        case .neck: "Nacken"
        case .shoulderLeft, .shoulderRight: "Schulter"
        case .upperArmLeft, .upperArmRight: "Oberarm"
        case .elbowLeft, .elbowRight: "Ellbogen"
        case .wristLeft, .wristRight: "Hand/Handgelenk"
        case .chest: "Brust"
        case .upperAbdomen: "Oberbauch"
        case .lowerAbdomen: "Unterbauch"
        case .upperBack: "Oberer Rücken"
        case .lowerBack: "Unterer Rücken"
        case .hipLeft, .hipRight: "Hüfte/Leiste"
        case .thighLeft, .thighRight: "Oberschenkel"
        case .kneeLeft, .kneeRight: "Knie"
        case .calfLeft, .calfRight: "Wade"
        case .footLeft, .footRight: "Fuß/Sprunggelenk"
        }
    }

    /// `nil` bei Regionen in der Körpermitte.
    public var isLeft: Bool? {
        switch self {
        case .shoulderLeft, .upperArmLeft, .elbowLeft, .wristLeft, .hipLeft, .thighLeft, .kneeLeft, .calfLeft, .footLeft: true
        case .shoulderRight, .upperArmRight, .elbowRight, .wristRight, .hipRight, .thighRight, .kneeRight, .calfRight, .footRight: false
        default: nil
        }
    }

    /// „Schulter rechts“, „Unterer Rücken“
    public var title: String {
        switch isLeft {
        case true?: "\(part) links"
        case false?: "\(part) rechts"
        case nil: part
        }
    }

    /// Wo die Region auf der Karte liegt. In der Vorderansicht ist links die rechte Körperseite.
    public var positions: [BodyMapSide: BodyPoint] {
        func pair(_ offset: Double) -> (front: Double, back: Double) {
            // Vorne: linke Körperseite rechts im Bild. Hinten: linke Seite links im Bild.
            let left = isLeft == true
            return (left ? 0.5 + offset : 0.5 - offset, left ? 0.5 - offset : 0.5 + offset)
        }
        switch self {
        case .head: return [.front: BodyPoint(0.5, 0.07), .back: BodyPoint(0.5, 0.07)]
        case .jaw: return [.front: BodyPoint(0.5, 0.125)]
        case .neck: return [.back: BodyPoint(0.5, 0.155)]
        case .chest: return [.front: BodyPoint(0.5, 0.28)]
        case .upperAbdomen: return [.front: BodyPoint(0.5, 0.38)]
        case .lowerAbdomen: return [.front: BodyPoint(0.5, 0.46)]
        case .upperBack: return [.back: BodyPoint(0.5, 0.28)]
        case .lowerBack: return [.back: BodyPoint(0.5, 0.42)]
        default:
            let (y, offset): (Double, Double) = switch self {
            case .shoulderLeft, .shoulderRight: (0.205, 0.2)
            case .upperArmLeft, .upperArmRight: (0.31, 0.26)
            case .elbowLeft, .elbowRight: (0.4, 0.29)
            case .wristLeft, .wristRight: (0.52, 0.33)
            case .hipLeft, .hipRight: (0.52, 0.12)
            case .thighLeft, .thighRight: (0.63, 0.1)
            case .kneeLeft, .kneeRight: (0.74, 0.1)
            case .calfLeft, .calfRight: (0.84, 0.1)
            default: (0.95, 0.1)
            }
            let x = pair(offset)
            switch self {
            case .calfLeft, .calfRight:
                return [.back: BodyPoint(x.back, y)]
            case .shoulderLeft, .shoulderRight, .elbowLeft, .elbowRight:
                return [.front: BodyPoint(x.front, y), .back: BodyPoint(x.back, y)]
            default:
                return [.front: BodyPoint(x.front, y)]
            }
        }
    }

    public static func regions(on view: BodyMapSide) -> [BodyRegion] {
        allCases.filter { $0.positions[view] != nil }
    }
}

// MARK: - Merkmale

/// Wie sich der Schmerz anfühlt.
public enum PainQuality: String, Codable, Sendable, CaseIterable, Identifiable {
    case stabbing, dull, pulling, burning, throbbing, cramping, pressing, radiating

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .stabbing: "stechend"
        case .dull: "dumpf"
        case .pulling: "ziehend"
        case .burning: "brennend"
        case .throbbing: "pochend"
        case .cramping: "krampfartig"
        case .pressing: "drückend"
        case .radiating: "ausstrahlend"
        }
    }
}

/// Möglicher Auslöser aus eigener Sicht.
public enum PainTrigger: String, Codable, Sendable, CaseIterable, Identifiable {
    case training, strain, sitting, sleep, food, stress, unknown

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .training: "nach Training/Sport"
        case .strain: "Heben, Tragen"
        case .sitting: "langes Sitzen, Haltung"
        case .sleep: "nach dem Schlafen"
        case .food: "nach dem Essen"
        case .stress: "Stress"
        case .unknown: "unklar"
        }
    }
}

/// Was geholfen hat.
public enum PainRelief: String, Codable, Sendable, CaseIterable, Identifiable {
    case medication, rest, heat, cold, movement, nothing

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .medication: "Schmerzmittel"
        case .rest: "Ruhe"
        case .heat: "Wärme"
        case .cold: "Kälte"
        case .movement: "Bewegung, Dehnen"
        case .nothing: "nichts"
        }
    }
}

/// Numerische Schmerzskala 0–10 (NRS), wie in Praxis und Klinik.
public enum PainScale {
    public static let range = 0...10

    public static func label(_ value: Int) -> String {
        switch value {
        case ...0: "kein Schmerz"
        case 1...3: "leicht"
        case 4...6: "mittel"
        case 7...9: "stark"
        default: "unerträglich"
        }
    }

    /// 0 = grün … 3 = rot, für die Farbe der Anzeige.
    public static func level(_ value: Int) -> Int {
        switch value {
        case ...0: 0
        case 1...3: 1
        case 4...6: 2
        default: 3
        }
    }
}

// MARK: - Eintrag und Auswertung

public struct PainFact: Sendable, Hashable, Identifiable {
    public var id: String
    public var date: Date
    public var regions: [BodyRegion]
    public var intensity: Int
    public var qualities: [PainQuality]
    public var durationMinutes: Int?
    public var triggers: [PainTrigger]
    public var reliefs: [PainRelief]
    public var note: String

    public init(
        id: String = UUID().uuidString, date: Date, regions: [BodyRegion], intensity: Int, qualities: [PainQuality] = [],
        durationMinutes: Int? = nil, triggers: [PainTrigger] = [], reliefs: [PainRelief] = [], note: String = ""
    ) {
        self.id = id
        self.date = date
        self.regions = regions
        self.intensity = min(max(intensity, PainScale.range.lowerBound), PainScale.range.upperBound)
        self.qualities = qualities
        self.durationMinutes = durationMinutes
        self.triggers = triggers
        self.reliefs = reliefs
        self.note = note
    }

    /// „Unterer Rücken, Knie rechts“
    public var regionText: String {
        regions.isEmpty ? "ohne Ort" : regions.map(\.title).joined(separator: ", ")
    }

    /// „Unterer Rücken 6/10, stechend, 2 Std.“
    public var summary: String {
        var parts = ["\(regionText) \(intensity)/10"]
        if !qualities.isEmpty { parts.append(qualities.map(\.title).joined(separator: ", ")) }
        if let durationMinutes { parts.append(DurationText.short(durationMinutes)) }
        return parts.joined(separator: ", ")
    }
}

/// „45 Min.“, „2 Std.“, „1,5 Std.“, „ganzer Tag“
public enum DurationText {
    public static func short(_ minutes: Int) -> String {
        if minutes >= 24 * 60 { return "ganzer Tag" }
        if minutes >= 60 {
            let hours = Double(minutes) / 60
            return "\(WeightFormat.number((hours * 2).rounded() / 2)) Std."
        }
        return "\(minutes) Min."
    }
}

public struct PainRegionLine: Sendable, Hashable, Identifiable {
    public var region: BodyRegion
    public var count: Int
    public var averageIntensity: Double
    public var maxIntensity: Int
    public var id: String { region.rawValue }
}

public struct PainWeek: Sendable, Hashable, Identifiable {
    public var weekStart: Date
    public var count: Int
    public var averageIntensity: Double?
    public var maxIntensity: Int?
    public var id: Date { weekStart }
}

/// Schmerzen über einen Zeitraum.
public struct PainSummary: Sendable, Hashable {
    public var count: Int
    public var days: Int
    public var averageIntensity: Double?
    public var maxIntensity: Int?
    public var regions: [PainRegionLine]
    public var weeks: [PainWeek]
    public var qualities: [(PainQuality, Int)]
    public var triggers: [(PainTrigger, Int)]
    public var reliefs: [(PainRelief, Int)]
    /// Einträge am Tag eines Trainings oder am Tag danach.
    public var afterActivity: Int

    public static func == (lhs: PainSummary, rhs: PainSummary) -> Bool {
        lhs.count == rhs.count && lhs.regions == rhs.regions && lhs.weeks == rhs.weeks && lhs.afterActivity == rhs.afterActivity
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(count)
        hasher.combine(regions)
    }

    public static func compute(
        _ facts: [PainFact], activities: [ActivityFact] = [], from: Date, to: Date, calendar: Calendar
    ) -> PainSummary {
        let inRange = facts.filter { $0.date >= from && $0.date < to }
        let intensities = inRange.map(\.intensity)
        var byRegion: [BodyRegion: [Int]] = [:]
        for fact in inRange {
            for region in fact.regions { byRegion[region, default: []].append(fact.intensity) }
        }
        let regions = byRegion.map { region, values in
            PainRegionLine(
                region: region, count: values.count,
                averageIntensity: Double(values.reduce(0, +)) / Double(values.count), maxIntensity: values.max() ?? 0
            )
        }
        .sorted { $0.count == $1.count ? $0.averageIntensity > $1.averageIntensity : $0.count > $1.count }

        var weeks: [PainWeek] = []
        var start = AgendaBuilder.startOfWeek(containing: from, calendar: calendar)
        while start < to {
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 86_400)
            let week = inRange.filter { $0.date >= start && $0.date < end }.map(\.intensity)
            weeks.append(PainWeek(
                weekStart: start, count: week.count,
                averageIntensity: week.isEmpty ? nil : Double(week.reduce(0, +)) / Double(week.count), maxIntensity: week.max()
            ))
            start = end
        }

        func counted<T: Hashable & CaseIterable>(_ values: [T]) -> [(T, Int)] {
            let counts = Dictionary(grouping: values, by: { $0 }).mapValues(\.count)
            return T.allCases.compactMap { value in counts[value].map { (value, $0) } }.sorted { $0.1 > $1.1 }
        }

        let activeDays = Set(activities.filter { $0.isStrenuous }.map { calendar.startOfDay(for: $0.date) })
        let afterActivity = inRange.filter { fact in
            let day = calendar.startOfDay(for: fact.date)
            let dayBefore = calendar.date(byAdding: .day, value: -1, to: day) ?? day
            return activeDays.contains(day) || activeDays.contains(dayBefore)
        }.count

        return PainSummary(
            count: inRange.count,
            days: Set(inRange.map { calendar.startOfDay(for: $0.date) }).count,
            averageIntensity: intensities.isEmpty ? nil : Double(intensities.reduce(0, +)) / Double(intensities.count),
            maxIntensity: intensities.max(),
            regions: regions,
            weeks: weeks,
            qualities: counted(inRange.flatMap(\.qualities)),
            triggers: counted(inRange.flatMap(\.triggers)),
            reliefs: counted(inRange.flatMap(\.reliefs)),
            afterActivity: afterActivity
        )
    }

    public static let empty = PainSummary(
        count: 0, days: 0, averageIntensity: nil, maxIntensity: nil, regions: [], weeks: [], qualities: [], triggers: [], reliefs: [], afterActivity: 0
    )
}
