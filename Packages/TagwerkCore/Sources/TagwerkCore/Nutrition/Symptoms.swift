import Foundation

// MARK: - Symptome

public enum SymptomType: String, Codable, Sendable, CaseIterable, Identifiable {
    case headache, flush, itching, hives, bloating, abdominalPain, diarrhea, nausea
    case palpitations, stuffyNose, runnyNose, fatigue, dizziness, other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .headache: "Kopfschmerz"
        case .flush: "Hautrötung"
        case .itching: "Juckreiz"
        case .hives: "Quaddeln"
        case .bloating: "Blähungen"
        case .abdominalPain: "Bauchschmerz"
        case .diarrhea: "Durchfall"
        case .nausea: "Übelkeit"
        case .palpitations: "Herzrasen"
        case .stuffyNose: "Verstopfte Nase"
        case .runnyNose: "Laufende Nase"
        case .fatigue: "Müdigkeit"
        case .dizziness: "Schwindel"
        case .other: "Sonstiges"
        }
    }

    public var symbol: String {
        switch self {
        case .headache: "brain.head.profile"
        case .flush: "flame"
        case .itching: "hand.raised.fingers.spread"
        case .hives: "circle.dotted"
        case .bloating: "wind"
        case .abdominalPain: "bolt.heart"
        case .diarrhea: "toilet"
        case .nausea: "face.dashed"
        case .palpitations: "heart.circle"
        case .stuffyNose: "nose"
        case .runnyNose: "drop"
        case .fatigue: "zzz"
        case .dizziness: "tornado"
        case .other: "ellipsis.circle"
        }
    }

    /// Wörter für die Schnellerfassung („kopfschmerz 3“).
    public var keywords: [String] {
        switch self {
        case .headache: ["kopfschmerz", "kopfschmerzen", "kopfweh", "migraene"]
        case .flush: ["hautroetung", "roetung", "flush", "rot im gesicht"]
        case .itching: ["juckreiz", "jucken", "juckt"]
        case .hives: ["quaddeln", "nesselsucht", "ausschlag"]
        case .bloating: ["blaehungen", "blaehbauch", "aufgeblaeht"]
        case .abdominalPain: ["bauchschmerz", "bauchschmerzen", "bauchweh", "magenschmerzen", "kraempfe"]
        case .diarrhea: ["durchfall"]
        case .nausea: ["uebelkeit", "uebel"]
        case .palpitations: ["herzrasen", "herzklopfen"]
        case .stuffyNose: ["verstopfte nase", "nase zu"]
        case .runnyNose: ["laufende nase", "schnupfen", "niesen"]
        case .fatigue: ["muedigkeit", "muede", "erschoepft"]
        case .dizziness: ["schwindel", "schwindelig"]
        case .other: []
        }
    }
}

/// Stärke 1–5.
public enum SymptomSeverity {
    public static let range = 1...5

    public static func title(_ value: Int) -> String {
        switch value {
        case ...1: "sehr leicht"
        case 2: "leicht"
        case 3: "mittel"
        case 4: "stark"
        default: "sehr stark"
        }
    }
}

public struct SymptomFact: Sendable, Hashable {
    public var date: Date
    public var type: SymptomType
    public var severity: Int

    public init(date: Date, type: SymptomType, severity: Int) {
        self.date = date
        self.type = type
        self.severity = severity
    }
}

/// Erkennt „kopfschmerz 3“ oder „übelkeit“ als Symptom (für die Schnellerfassung und Siri).
public enum SymptomParser {
    public static func parse(_ text: String) -> (type: SymptomType, severity: Int)? {
        let normalized = NameMatcher.normalize(text)
        guard !normalized.isEmpty else { return nil }
        var tokens = normalized.split(separator: " ").map(String.init)
        var severity = 3
        if let last = tokens.last, let value = Int(last), SymptomSeverity.range.contains(value) {
            severity = value
            tokens.removeLast()
        }
        let phrase = tokens.joined(separator: " ")
        guard !phrase.isEmpty, tokens.count <= 3 else { return nil }
        for type in SymptomType.allCases where type.keywords.contains(phrase) {
            return (type, severity)
        }
        return nil
    }
}

// MARK: - Auslöser-Analyse

/// Ein auffälliges Muster: Lebensmittel oder Umstand, nach dem öfter Beschwerden kamen.
public struct TriggerFinding: Sendable, Hashable, Identifiable {
    public var key: String
    public var name: String
    public var isFactor: Bool
    /// Wie oft gegessen (Mahlzeiten).
    public var occurrences: Int
    /// Danach Beschwerden innerhalb von 15 Min. bis 3 Std.
    public var followedSoon: Int
    /// Gewichteter Anteil mit Beschwerden (0…1, nahe Beschwerden zählen voll, spätere weniger).
    public var rate: Double
    /// Verhältnis zur Grundrate aller Mahlzeiten (2 = doppelt so oft wie sonst).
    public var lift: Double

    public var id: String { key }

    /// „5 von 6 Mal Beschwerden innerhalb von 3 Std.“
    public var sentence: String {
        "\(followedSoon) von \(occurrences) Mal Beschwerden innerhalb von 3 Std."
    }

    /// „etwa 2,5× so oft wie sonst“
    public var comparison: String {
        "etwa \(WeightFormat.number((lift * 10).rounded() / 10))× so oft wie nach anderen Mahlzeiten"
    }
}

public struct TriggerReport: Sendable, Hashable {
    public var findings: [TriggerFinding]
    public var mealCount: Int
    public var symptomCount: Int
    /// Anteil aller Mahlzeiten mit Beschwerden danach.
    public var baseline: Double

    public var hasEnoughData: Bool {
        mealCount >= TriggerAnalysis.minimumMeals && symptomCount >= TriggerAnalysis.minimumSymptoms
    }

    /// Was noch fehlt, bis die Auswertung aussagekräftig wird.
    public var missingDataText: String? {
        guard !hasEnoughData else { return nil }
        var parts: [String] = []
        let meals = TriggerAnalysis.minimumMeals - mealCount
        let symptoms = TriggerAnalysis.minimumSymptoms - symptomCount
        if meals > 0 { parts.append("\(meals) Mahlzeiten") }
        if symptoms > 0 { parts.append(symptoms == 1 ? "1 Symptom" : "\(symptoms) Symptome") }
        return "Noch \(parts.joined(separator: " und ")) eintragen, dann zeigt Orbit erste Muster."
    }
}

/// Sucht Lebensmittel, nach denen auffällig oft Beschwerden kamen. Ohne KI: zählt nur,
/// wie oft innerhalb von 24 Stunden danach Symptome eingetragen wurden, und vergleicht
/// mit der Grundrate. Ergebnis ist ein Hinweis, keine Diagnose.
public enum TriggerAnalysis {
    public static let minimumMeals = 10
    public static let minimumSymptoms = 3
    /// Ein Lebensmittel erscheint erst ab so vielen Mahlzeiten.
    public static let minimumOccurrences = 3

    /// Gewicht eines Symptoms nach `minutes` Minuten: 15 Min.–3 Std. voll, bis 8 Std. halb,
    /// bis 24 Std. wenig, davor (unter 15 Min.) kaum.
    public static func weight(minutesAfterMeal minutes: Double) -> Double {
        switch minutes {
        case ..<0: 0
        case ..<15: 0.3
        case ..<180: 1
        case ..<480: 0.5
        case ..<1440: 0.2
        default: 0
        }
    }

    public static func analyze(
        meals: [MealFact],
        symptoms: [SymptomFact],
        only type: SymptomType? = nil,
        minimumSeverity: Int = 1
    ) -> TriggerReport {
        let relevant = symptoms.filter { (type == nil || $0.type == type) && $0.severity >= minimumSeverity }
        guard !meals.isEmpty else {
            return TriggerReport(findings: [], mealCount: 0, symptomCount: relevant.count, baseline: 0)
        }
        // Für jede Mahlzeit: stärkstes Gewicht eines folgenden Symptoms und ob es „bald“ kam.
        var mealWeights: [String: (weight: Double, soon: Bool)] = [:]
        for meal in meals {
            var best = 0.0
            var soon = false
            for symptom in relevant {
                let minutes = symptom.date.timeIntervalSince(meal.date) / 60
                let value = weight(minutesAfterMeal: minutes)
                best = max(best, value)
                if minutes >= 15 && minutes < 180 { soon = true }
            }
            mealWeights[meal.id] = (best, soon)
        }
        let baseline = mealWeights.values.reduce(0) { $0 + $1.weight } / Double(meals.count)

        struct Tally { var name: String; var isFactor: Bool; var count = 0; var soon = 0; var weight = 0.0 }
        var tallies: [String: Tally] = [:]
        func add(_ key: String, name: String, isFactor: Bool, meal: MealFact) {
            guard let entry = mealWeights[meal.id] else { return }
            var tally = tallies[key] ?? Tally(name: name, isFactor: isFactor)
            tally.count += 1
            tally.weight += entry.weight
            if entry.soon { tally.soon += 1 }
            tallies[key] = tally
        }
        for meal in meals {
            for foodID in Set(meal.items.map(\.foodID)) {
                let name = meal.items.first { $0.foodID == foodID }?.name ?? foodID
                add(foodID, name: name, isFactor: false, meal: meal)
            }
            if meal.freshness != .fresh {
                add("factor.leftovers", name: "Reste oder Aufgewärmtes", isFactor: true, meal: meal)
            }
            if meal.place == .out {
                add("factor.out", name: "Auswärts gegessen", isFactor: true, meal: meal)
            }
        }

        let findings = tallies.compactMap { key, tally -> TriggerFinding? in
            guard tally.count >= minimumOccurrences else { return nil }
            let rate = tally.weight / Double(tally.count)
            let lift = baseline > 0 ? rate / baseline : (rate > 0 ? 9.9 : 0)
            guard rate >= 0.4, lift >= 1.3, tally.soon >= 2 else { return nil }
            return TriggerFinding(
                key: key, name: tally.name, isFactor: tally.isFactor, occurrences: tally.count,
                followedSoon: tally.soon, rate: rate, lift: lift
            )
        }
        .sorted { lhs, rhs in
            if abs(lhs.lift - rhs.lift) > 0.01 { return lhs.lift > rhs.lift }
            return lhs.occurrences > rhs.occurrences
        }
        return TriggerReport(findings: findings, mealCount: meals.count, symptomCount: relevant.count, baseline: baseline)
    }
}
