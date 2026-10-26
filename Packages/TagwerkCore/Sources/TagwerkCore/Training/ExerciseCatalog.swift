import Foundation

/// Muskelgruppen für Volumen und Bibliothek.
public enum MuscleGroup: String, Codable, Sendable, CaseIterable, Identifiable, Comparable {
    case chest, lats, upperBack, frontDelts, sideDelts, rearDelts
    case biceps, triceps, forearms, traps
    case abs, obliques, lowerBack
    case glutes, quads, hamstrings, calves, adductors

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .chest: "Brust"
        case .lats: "Latissimus"
        case .upperBack: "Oberer Rücken"
        case .frontDelts: "Vordere Schulter"
        case .sideDelts: "Seitliche Schulter"
        case .rearDelts: "Hintere Schulter"
        case .biceps: "Bizeps"
        case .triceps: "Trizeps"
        case .forearms: "Unterarme"
        case .traps: "Nacken"
        case .abs: "Bauch"
        case .obliques: "Seitlicher Bauch"
        case .lowerBack: "Unterer Rücken"
        case .glutes: "Gesäß"
        case .quads: "Oberschenkel vorne"
        case .hamstrings: "Oberschenkel hinten"
        case .calves: "Waden"
        case .adductors: "Adduktoren"
        }
    }

    /// Wöchentliche Arbeitssätze für Muskelaufbau (Richtwert bei ca. 1 Jahr Erfahrung).
    /// Untergrenze 0 = optional, kein „zu wenig“.
    public var weeklyTarget: ClosedRange<Int> {
        switch self {
        // Nebenmuskeln zählen halb (z. B. Bizeps bei Klimmzügen), daher großzügige Obergrenzen.
        case .chest, .lats: 10...20
        case .upperBack: 8...18
        case .sideDelts: 8...20
        case .rearDelts: 6...16
        case .biceps, .triceps: 8...20
        case .frontDelts: 0...14
        case .forearms, .obliques, .lowerBack, .adductors: 0...8
        case .traps, .hamstrings, .calves: 0...10
        case .abs, .glutes, .quads: 0...12
        }
    }

    /// Reihenfolge in Listen (Oberkörper zuerst).
    public var sortOrder: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    public static func < (lhs: MuscleGroup, rhs: MuscleGroup) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

public enum Equipment: String, Codable, Sendable, CaseIterable, Identifiable {
    case barbell, dumbbell, cable, machine, smith, ezBar, bodyweight, band, kettlebell, other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .barbell: "Langhantel"
        case .dumbbell: "Kurzhantel"
        case .cable: "Kabel"
        case .machine: "Maschine"
        case .smith: "Multipresse"
        case .ezBar: "SZ-Stange"
        case .bodyweight: "Körpergewicht"
        case .band: "Band"
        case .kettlebell: "Kettlebell"
        case .other: "Sonstiges"
        }
    }

    /// Leichtestes sinnvolles Gewicht (z. B. leere Stange) für Aufwärmsätze.
    public var minimumLoad: Double {
        switch self {
        case .barbell: 20
        case .ezBar: 10
        case .smith: 15
        default: 0
        }
    }

    public var defaultIncrement: Double {
        switch self {
        case .barbell, .ezBar, .smith, .cable, .bodyweight, .band, .other: 2.5
        case .dumbbell: 2
        case .machine: 5
        case .kettlebell: 4
        }
    }
}

public enum Mechanic: String, Codable, Sendable {
    /// Grundübung (mehrere Gelenke).
    case compound
    /// Isolationsübung.
    case isolation

    public var title: String {
        self == .compound ? "Grundübung" : "Isolation"
    }
}

/// Eine Übung aus der Bibliothek (mitgeliefert oder selbst angelegt).
public struct ExerciseInfo: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var aliases: [String]
    public var primary: [MuscleGroup]
    public var secondary: [MuscleGroup]
    public var equipment: Equipment
    public var mechanic: Mechanic
    /// Steigerungsschritt in kg.
    public var increment: Double
    /// Standardpause in Sekunden.
    public var rest: Int
    public var unilateral: Bool
    /// Gewicht ist Unterstützung (assistierte Maschine): weniger ist schwerer.
    public var assisted: Bool
    public var cues: [String]
    /// Selbst angelegt statt mitgeliefert.
    public var isCustom: Bool

    public init(
        id: String,
        name: String,
        aliases: [String] = [],
        primary: [MuscleGroup],
        secondary: [MuscleGroup] = [],
        equipment: Equipment,
        mechanic: Mechanic,
        increment: Double? = nil,
        rest: Int = 90,
        unilateral: Bool = false,
        assisted: Bool = false,
        cues: [String] = [],
        isCustom: Bool = false
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.primary = primary
        self.secondary = secondary
        self.equipment = equipment
        self.mechanic = mechanic
        self.increment = increment ?? equipment.defaultIncrement
        self.rest = rest
        self.unilateral = unilateral
        self.assisted = assisted
        self.cues = cues
        self.isCustom = isCustom
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, aliases, primary, secondary, equipment, mechanic, increment, rest, unilateral, assisted, cues, isCustom
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        primary = try c.decode([MuscleGroup].self, forKey: .primary)
        secondary = try c.decodeIfPresent([MuscleGroup].self, forKey: .secondary) ?? []
        equipment = try c.decodeIfPresent(Equipment.self, forKey: .equipment) ?? .other
        mechanic = try c.decodeIfPresent(Mechanic.self, forKey: .mechanic) ?? .isolation
        increment = try c.decodeIfPresent(Double.self, forKey: .increment) ?? equipment.defaultIncrement
        rest = try c.decodeIfPresent(Int.self, forKey: .rest) ?? 90
        unilateral = try c.decodeIfPresent(Bool.self, forKey: .unilateral) ?? false
        assisted = try c.decodeIfPresent(Bool.self, forKey: .assisted) ?? false
        cues = try c.decodeIfPresent([String].self, forKey: .cues) ?? []
        isCustom = try c.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
    }

    public var isCompound: Bool { mechanic == .compound }

    /// „Brust · Trizeps“
    public var muscleSummary: String {
        primary.map(\.title).joined(separator: " · ")
    }
}

/// Die Übungsbibliothek: mitgelieferte und eigene Übungen.
public struct ExerciseCatalog: Sendable {
    public private(set) var exercises: [ExerciseInfo]
    private var byID: [String: ExerciseInfo]

    public init(exercises: [ExerciseInfo]) {
        self.exercises = exercises
        var map: [String: ExerciseInfo] = [:]
        for exercise in exercises where map[exercise.id] == nil {
            map[exercise.id] = exercise
        }
        byID = map
    }

    public func exercise(id: String) -> ExerciseInfo? {
        byID[id]
    }

    /// Name zur Anzeige, auch für unbekannte IDs.
    public func name(for id: String) -> String {
        byID[id]?.name ?? id
    }

    /// Eigene Übungen ergänzen (gleiche ID ersetzt die mitgelieferte nicht).
    public func adding(_ custom: [ExerciseInfo]) -> ExerciseCatalog {
        ExerciseCatalog(exercises: exercises + custom.filter { byID[$0.id] == nil })
    }

    /// Suche in Name und Alternativnamen, ohne Groß-/Kleinschreibung und Akzente.
    public func search(_ query: String) -> [ExerciseInfo] {
        let needle = NameMatcher.normalize(query)
        guard !needle.isEmpty else { return sorted }
        return sorted.filter { exercise in
            ([exercise.name] + exercise.aliases).contains { NameMatcher.normalize($0).contains(needle) }
        }
    }

    /// Nach Name sortiert.
    public var sorted: [ExerciseInfo] {
        exercises.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    /// Nach erster Hauptmuskelgruppe gruppiert.
    public var grouped: [(muscle: MuscleGroup, exercises: [ExerciseInfo])] {
        let groups = Dictionary(grouping: sorted) { $0.primary.first ?? .abs }
        return groups.keys.sorted().map { ($0, groups[$0] ?? []) }
    }

    /// Alternativen zum Tauschen: gleiche erste Hauptmuskelgruppe, zuerst gleicher Typ
    /// (Grundübung/Isolation), dann nach Überschneidung der Muskeln.
    public func alternatives(to id: String, limit: Int = 12) -> [ExerciseInfo] {
        guard let base = byID[id], let main = base.primary.first else { return [] }
        let baseMuscles = Set(base.primary + base.secondary)
        return exercises
            .filter { $0.id != id && $0.primary.contains(main) }
            .sorted { lhs, rhs in
                let lm = lhs.mechanic == base.mechanic, rm = rhs.mechanic == base.mechanic
                if lm != rm { return lm }
                let lo = baseMuscles.intersection(lhs.primary + lhs.secondary).count
                let ro = baseMuscles.intersection(rhs.primary + rhs.secondary).count
                if lo != ro { return lo > ro }
                return lhs.name.localizedCompare(rhs.name) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Fehler im Inhalt (doppelte IDs, leere Muskelgruppen, unsinnige Werte).
    public func validationIssues() -> [String] {
        var issues: [String] = []
        var seen = Set<String>()
        for exercise in exercises {
            if !seen.insert(exercise.id).inserted { issues.append("Doppelte ID: \(exercise.id)") }
            if exercise.name.trimmingCharacters(in: .whitespaces).isEmpty { issues.append("Ohne Namen: \(exercise.id)") }
            if exercise.primary.isEmpty { issues.append("Keine Hauptmuskeln: \(exercise.id)") }
            if exercise.increment <= 0 || exercise.increment > 20 { issues.append("Steigerung unplausibel: \(exercise.id)") }
            if exercise.rest < 30 || exercise.rest > 300 { issues.append("Pause unplausibel: \(exercise.id)") }
            if !Set(exercise.primary).isDisjoint(with: exercise.secondary) { issues.append("Muskel doppelt: \(exercise.id)") }
        }
        var names = Set<String>()
        for exercise in exercises where !names.insert(NameMatcher.normalize(exercise.name)).inserted {
            issues.append("Doppelter Name: \(exercise.name)")
        }
        return issues
    }

    // MARK: Mitgelieferte Inhalte

    private struct CatalogFile: Decodable {
        var version: Int
        var exercises: [ExerciseInfo]
    }

    public static func decode(_ data: Data) throws -> ExerciseCatalog {
        ExerciseCatalog(exercises: try JSONDecoder().decode(CatalogFile.self, from: data).exercises)
    }

    /// Die mitgelieferte Bibliothek (`Resources/exercises.de.json`).
    public static func bundled() -> ExerciseCatalog {
        guard let url = Bundle.module.url(forResource: "exercises.de", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? decode(data)
        else { return ExerciseCatalog(exercises: []) }
        return catalog
    }
}
