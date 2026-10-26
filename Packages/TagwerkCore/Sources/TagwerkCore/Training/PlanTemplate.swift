import Foundation

/// Eine Übung in einer Plan-Vorlage.
public struct ExerciseTemplate: Codable, Sendable, Hashable {
    /// ID aus der Bibliothek. Bei importierten Plänen evtl. erst nach dem Zuordnen gesetzt.
    public var exercise: String
    /// Name aus einem Import (z. B. von Claude), solange keine ID feststeht.
    public var name: String?
    public var sets: Int
    public var repMin: Int
    public var repMax: Int
    public var rir: Int
    public var restSec: Int
    /// Gleiche Buchstaben = Supersatz.
    public var superset: String?
    public var note: String?
    /// Kann ohne schlechtes Gewissen wegfallen.
    public var optional: Bool

    public init(
        exercise: String, name: String? = nil, sets: Int, repMin: Int, repMax: Int, rir: Int, restSec: Int,
        superset: String? = nil, note: String? = nil, optional: Bool = false
    ) {
        self.exercise = exercise
        self.name = name
        self.sets = sets
        self.repMin = repMin
        self.repMax = repMax
        self.rir = rir
        self.restSec = restSec
        self.superset = superset
        self.note = note
        self.optional = optional
    }

    private enum CodingKeys: String, CodingKey {
        case exercise, id, name, sets, repMin, repMax, reps, rir, restSec, rest, superset, note, optional
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        exercise = try c.decodeIfPresent(String.self, forKey: .exercise) ?? c.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name)
        sets = min(max(try c.decodeIfPresent(Int.self, forKey: .sets) ?? 3, 1), 10)
        var low = try c.decodeIfPresent(Int.self, forKey: .repMin)
        var high = try c.decodeIfPresent(Int.self, forKey: .repMax)
        // „reps“: 10 oder „8-12“ als Ersatz.
        if low == nil || high == nil {
            if let reps = try? c.decode(Int.self, forKey: .reps) {
                low = low ?? reps
                high = high ?? reps
            } else if let text = try? c.decode(String.self, forKey: .reps) {
                let numbers = text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
                low = low ?? numbers.first
                high = high ?? numbers.last
            }
        }
        repMin = min(max(low ?? 8, 1), 50)
        repMax = max(repMin, min(high ?? max(low ?? 12, 12), 50))
        rir = min(max(try c.decodeIfPresent(Int.self, forKey: .rir) ?? 2, 0), 5)
        restSec = min(max(try c.decodeIfPresent(Int.self, forKey: .restSec) ?? c.decodeIfPresent(Int.self, forKey: .rest) ?? 90, 15), 600)
        superset = try c.decodeIfPresent(String.self, forKey: .superset)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        optional = try c.decodeIfPresent(Bool.self, forKey: .optional) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(exercise, forKey: .exercise)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encode(sets, forKey: .sets)
        try c.encode(repMin, forKey: .repMin)
        try c.encode(repMax, forKey: .repMax)
        try c.encode(rir, forKey: .rir)
        try c.encode(restSec, forKey: .restSec)
        try c.encodeIfPresent(superset, forKey: .superset)
        try c.encodeIfPresent(note, forKey: .note)
        if optional { try c.encode(true, forKey: .optional) }
    }

    /// „4 × 6–8 · RIR 2“
    public var prescription: String {
        let reps = repMin == repMax ? "\(repMin)" : "\(repMin)–\(repMax)"
        return "\(sets) × \(reps) · RIR \(rir)"
    }
}

/// Ein Trainingstag in einer Vorlage.
public struct DayTemplate: Codable, Sendable, Hashable {
    public var name: String
    public var shortName: String?
    public var focus: String?
    public var exercises: [ExerciseTemplate]

    public init(name: String, shortName: String? = nil, focus: String? = nil, exercises: [ExerciseTemplate]) {
        self.name = name
        self.shortName = shortName
        self.focus = focus
        self.exercises = exercises
    }
}

/// Ein Trainingsplan als JSON („orbit.plan.v1“, ältere Anfragen: „tagwerk.plan.v1“).
public struct PlanTemplate: Codable, Sendable, Hashable {
    public static let format = "orbit.plan.v1"
    public static let acceptedFormats = ["orbit.plan.v1", "tagwerk.plan.v1"]

    public var format: String?
    public var id: String?
    public var name: String
    public var summary: String?
    /// Länge des Zyklus in Wochen inklusive Deload-Woche.
    public var mesoWeeks: Int
    public var days: [DayTemplate]
    /// Zusätze, die man an einen Tag hängen kann (z. B. „Beine & Rumpf“).
    public var modules: [DayTemplate]

    public init(format: String? = PlanTemplate.format, id: String? = nil, name: String, summary: String? = nil, mesoWeeks: Int = 6, days: [DayTemplate], modules: [DayTemplate] = []) {
        self.format = format
        self.id = id
        self.name = name
        self.summary = summary
        self.mesoWeeks = mesoWeeks
        self.days = days
        self.modules = modules
    }

    private enum CodingKeys: String, CodingKey {
        case format, id, name, summary, mesoWeeks, deloadWeek, days, modules
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(String.self, forKey: .format)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Trainingsplan"
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        // Älteres Format: „mesoWeeks“ ohne Deload plus „deloadWeek“.
        let weeks = try c.decodeIfPresent(Int.self, forKey: .mesoWeeks)
        let deload = try c.decodeIfPresent(Int.self, forKey: .deloadWeek)
        mesoWeeks = min(max(deload ?? weeks ?? 6, 3), 12)
        days = try c.decode([DayTemplate].self, forKey: .days)
        modules = try c.decodeIfPresent([DayTemplate].self, forKey: .modules) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(format, forKey: .format)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(summary, forKey: .summary)
        try c.encode(mesoWeeks, forKey: .mesoWeeks)
        try c.encode(days, forKey: .days)
        if !modules.isEmpty { try c.encode(modules, forKey: .modules) }
    }

    /// Unbekannte Übungs-IDs und leere Tage.
    public func validationIssues(catalog: ExerciseCatalog) -> [String] {
        var issues: [String] = []
        if days.isEmpty { issues.append("Der Plan hat keine Trainingstage.") }
        for day in days + modules {
            if day.exercises.isEmpty { issues.append("„\(day.name)“ hat keine Übungen.") }
            for item in day.exercises where catalog.exercise(id: item.exercise) == nil {
                issues.append("Unbekannte Übung in „\(day.name)“: \(item.name ?? item.exercise)")
            }
        }
        return issues
    }

    // MARK: Mitgeliefert

    public static func decode(_ data: Data) throws -> PlanTemplate {
        try JSONDecoder().decode(PlanTemplate.self, from: data)
    }

    /// Dein Startplan „Oberkörper 4er – Hypertrophie“.
    public static func bundledUpperFourDay() -> PlanTemplate? {
        guard let url = Bundle.module.url(forResource: "plan-upper-4day", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? decode(data)
    }
}

/// Unscharfer Vergleich von Übungsnamen (für Importe, z. B. aus Claude).
public enum NameMatcher {
    /// Kleinbuchstaben, ohne Akzente, Umlaute ausgeschrieben, nur Buchstaben/Ziffern/Leerzeichen.
    public static func normalize(_ text: String) -> String {
        var value = text.lowercased()
        for (umlaut, plain) in [("ä", "ae"), ("ö", "oe"), ("ü", "ue"), ("ß", "ss")] {
            value = value.replacingOccurrences(of: umlaut, with: plain)
        }
        value = value.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "de_DE"))
        let mapped = value.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    static func tokens(_ text: String) -> Set<String> {
        Set(normalize(text).split(separator: " ").map(String.init).filter { $0.count > 1 })
    }

    /// Ähnlichkeit 0…1 aus Wort-Überschneidung und Buchstaben-Abstand.
    public static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let a = normalize(lhs), b = normalize(rhs)
        if a.isEmpty || b.isEmpty { return 0 }
        if a == b { return 1 }
        let ta = tokens(a), tb = tokens(b)
        let jaccard = ta.isEmpty || tb.isEmpty ? 0 : Double(ta.intersection(tb).count) / Double(ta.union(tb).count)
        let distance = Double(levenshtein(Array(a), Array(b)))
        let ratio = 1 - distance / Double(max(a.count, b.count))
        let containment = (a.contains(b) || b.contains(a)) ? 0.85 : 0
        return max(jaccard, ratio, containment)
    }

    /// Beste Übung zu einem Namen, `nil` unter der Schwelle.
    public static func bestMatch(for name: String, in catalog: ExerciseCatalog, threshold: Double = 0.72) -> (exercise: ExerciseInfo, score: Double)? {
        var best: (ExerciseInfo, Double)?
        for exercise in catalog.exercises {
            let score = ([exercise.name] + exercise.aliases).map { similarity(name, $0) }.max() ?? 0
            if score > (best?.1 ?? 0) {
                best = (exercise, score)
            }
        }
        guard let best, best.1 >= threshold else { return nil }
        return (best.0, best.1)
    }

    static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}

/// Ergebnis eines Plan-Imports.
public struct ImportedPlan: Sendable {
    public struct Match: Sendable, Hashable {
        public var given: String
        public var exerciseID: String
        public var exerciseName: String
        public var score: Double
    }

    public var template: PlanTemplate
    /// Zugeordnete Übungen (für die Vorschau).
    public var matches: [Match]
    /// Namen, für die es keine passende Übung gab. Sie werden als eigene Übungen angelegt.
    public var unmatched: [String]
}

public enum PlanImportError: Error, Equatable, LocalizedError {
    case noPlanFound
    case wrongFormat(String)
    case noDays

    public var errorDescription: String? {
        switch self {
        case .noPlanFound: "Im Text wurde kein Trainingsplan im JSON-Format gefunden."
        case .wrongFormat(let format): "Das Format „\(format)“ ist kein Trainingsplan."
        case .noDays: "Der Plan enthält keine Trainingstage."
        }
    }
}

/// Liest einen Plan aus Text (z. B. Claude-Antwort mit Codeblock) und ordnet die Übungen zu.
public enum PlanImporter {
    public static func parse(_ text: String) throws -> PlanTemplate {
        let candidates = ClaudeResponseExtractor.jsonCandidates(in: text)
            + ClaudeResponseExtractor.jsonCandidates(in: ClaudeResponseExtractor.normalizingQuotes(text))
        var foreignFormat: String?
        for candidate in candidates {
            guard let template = try? JSONDecoder().decode(PlanTemplate.self, from: Data(candidate.utf8)) else { continue }
            if let format = template.format, !PlanTemplate.acceptedFormats.contains(format) {
                foreignFormat = format
                continue
            }
            guard !template.days.isEmpty else { throw PlanImportError.noDays }
            return template
        }
        if let foreignFormat { throw PlanImportError.wrongFormat(foreignFormat) }
        throw PlanImportError.noPlanFound
    }

    /// Ordnet Namen den Bibliotheks-IDs zu. Unbekannte bekommen die ID „custom-<name>“.
    public static func resolve(_ template: PlanTemplate, catalog: ExerciseCatalog) -> ImportedPlan {
        var matches: [ImportedPlan.Match] = []
        var unmatched: [String] = []
        func map(_ day: DayTemplate) -> DayTemplate {
            var copy = day
            copy.exercises = day.exercises.map { item in
                var item = item
                if catalog.exercise(id: item.exercise) != nil { return item }
                let given = item.name ?? item.exercise
                if let best = NameMatcher.bestMatch(for: given, in: catalog) {
                    item.exercise = best.exercise.id
                    matches.append(.init(given: given, exerciseID: best.exercise.id, exerciseName: best.exercise.name, score: best.score))
                } else {
                    item.exercise = customID(for: given)
                    item.name = given
                    if !unmatched.contains(given) { unmatched.append(given) }
                }
                return item
            }
            return copy
        }
        var resolved = template
        resolved.days = template.days.map(map)
        resolved.modules = template.modules.map(map)
        return ImportedPlan(template: resolved, matches: matches, unmatched: unmatched)
    }

    /// Stabile ID für eine eigene Übung aus ihrem Namen.
    public static func customID(for name: String) -> String {
        "custom-" + NameMatcher.normalize(name).replacingOccurrences(of: " ", with: "-")
    }
}
