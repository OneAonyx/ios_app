import Foundation

// MARK: - Bewertung

/// Histamin-Bewertung 0–3, wie in DACH-Listen üblich. Immer zusammen mit Zahl und Symbol
/// anzeigen, damit sie auch bei Farbschwäche lesbar bleibt.
public enum HistamineScore: Int, Codable, Sendable, CaseIterable, Comparable, Identifiable {
    case good = 0
    case moderate = 1
    case poor = 2
    case bad = 3

    public var id: Int { rawValue }

    public static func < (lhs: HistamineScore, rhs: HistamineScore) -> Bool { lhs.rawValue < rhs.rawValue }

    public var title: String {
        switch self {
        case .good: "gut verträglich"
        case .moderate: "mäßig verträglich"
        case .poor: "schlecht verträglich"
        case .bad: "sehr schlecht verträglich"
        }
    }

    /// „0 · gut verträglich“
    public var label: String { "\(rawValue) · \(title)" }

    public var symbol: String {
        switch self {
        case .good: "checkmark.circle.fill"
        case .moderate: "exclamationmark.circle.fill"
        case .poor: "exclamationmark.triangle.fill"
        case .bad: "xmark.octagon.fill"
        }
    }

    /// Farbname für die Oberfläche (grün, gelb, orange, rot).
    public var colorName: String {
        switch self {
        case .good: "green"
        case .moderate: "yellow"
        case .poor: "orange"
        case .bad: "red"
        }
    }
}

/// Markierungen wie in gängigen Listen.
public enum HistamineFlag: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Histaminreich bzw. schnell verderblich.
    case histamine = "H"
    /// Andere biogene Amine.
    case amines = "A"
    /// Setzt körpereigenes Histamin frei.
    case liberator = "L"
    /// Hemmt das Abbau-Enzym DAO.
    case daoBlocker = "B"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .histamine: "Histaminreich oder schnell verderblich"
        case .amines: "Andere biogene Amine"
        case .liberator: "Setzt Histamin frei (Liberator)"
        case .daoBlocker: "Hemmt den Histaminabbau (DAO)"
        }
    }

    public var shortTitle: String {
        switch self {
        case .histamine: "histaminreich"
        case .amines: "biogene Amine"
        case .liberator: "Liberator"
        case .daoBlocker: "hemmt DAO"
        }
    }
}

/// Eigene Erfahrung mit einem Lebensmittel. Hat immer Vorrang vor der Standardbewertung.
public enum Tolerance: String, Codable, Sendable, CaseIterable, Identifiable {
    case unknown
    case ok
    case caution
    case avoid

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .unknown: "Noch nicht eingeschätzt"
        case .ok: "Bei mir ok"
        case .caution: "Vorsicht"
        case .avoid: "Meiden"
        }
    }

    public var symbol: String {
        switch self {
        case .unknown: "questionmark.circle"
        case .ok: "hand.thumbsup.fill"
        case .caution: "hand.raised.fill"
        case .avoid: "nosign"
        }
    }

    /// Bewertung, mit der die App rechnet: eigene Einschätzung vor Standard.
    public func effectiveScore(general: HistamineScore) -> HistamineScore {
        switch self {
        case .unknown: general
        case .ok: .good
        case .caution: max(general, .poor)
        case .avoid: .bad
        }
    }
}

// MARK: - Kategorien

public enum FoodCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case vegetables, fruit, meat, sausage, fish, dairy, cheese, eggs, grains, bread, legumes, nuts, fats
    case herbs, sauces, sweets, drinks, alcohol, meals, supplements, other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .vegetables: "Gemüse"
        case .fruit: "Obst"
        case .meat: "Fleisch"
        case .sausage: "Wurst & Schinken"
        case .fish: "Fisch & Meeresfrüchte"
        case .dairy: "Milchprodukte"
        case .cheese: "Käse"
        case .eggs: "Eier"
        case .grains: "Getreide & Beilagen"
        case .bread: "Brot & Backwaren"
        case .legumes: "Hülsenfrüchte & Soja"
        case .nuts: "Nüsse & Samen"
        case .fats: "Öle & Fette"
        case .herbs: "Kräuter & Gewürze"
        case .sauces: "Saucen & Würzmittel"
        case .sweets: "Süßes & Snacks"
        case .drinks: "Getränke"
        case .alcohol: "Alkohol"
        case .meals: "Gerichte & Auswärts"
        case .supplements: "Proteinpulver & Ergänzungen"
        case .other: "Sonstiges"
        }
    }

    public var symbol: String {
        switch self {
        case .vegetables: "carrot.fill"
        case .fruit: "apple.logo"
        case .meat: "fork.knife"
        case .sausage: "fork.knife"
        case .fish: "fish.fill"
        case .dairy: "drop.fill"
        case .cheese: "triangle.fill"
        case .eggs: "oval.fill"
        case .grains: "leaf.fill"
        case .bread: "birthday.cake.fill"
        case .legumes: "leaf.circle.fill"
        case .nuts: "tree.fill"
        case .fats: "drop.halffull"
        case .herbs: "leaf"
        case .sauces: "takeoutbag.and.cup.and.straw.fill"
        case .sweets: "birthday.cake"
        case .drinks: "cup.and.saucer.fill"
        case .alcohol: "wineglass.fill"
        case .meals: "takeoutbag.and.cup.and.straw"
        case .supplements: "bolt.fill"
        case .other: "circle.grid.2x2"
        }
    }

    /// Frische-Tipp für die ganze Kategorie.
    public var tip: String? {
        switch self {
        case .meat:
            "Frisch kaufen und am selben Tag zubereiten oder sofort einfrieren. Reste schnell abkühlen und nicht lange aufheben."
        case .sausage:
            "Gepökelt, geräuchert oder luftgetrocknet heißt mehr Histamin. Frisch aufgeschnittener Kochschinken ist am mildesten."
        case .fish:
            "Nur sehr frisch oder tiefgekühlt, am besten gefroren zubereiten. Konserven, Geräuchertes und Eingelegtes enthalten viel Histamin."
        case .cheese:
            "Je länger gereift, desto mehr Histamin. Junge und frische Käse sind meist besser verträglich."
        case .dairy:
            "Frische Milchprodukte sind meist gut verträglich, Fermentiertes wie Joghurt oder Kefir eher mäßig."
        case .vegetables:
            "Tomate, Spinat, Aubergine und Avocado sind häufige Auslöser. Eingelegtes und Fermentiertes meiden."
        case .fruit:
            "Zitrusfrüchte, Erdbeeren, Ananas, Kiwi und Papaya gelten als Liberatoren."
        case .alcohol:
            "Alkohol hemmt den Histaminabbau und enthält oft selbst Histamin."
        case .sauces:
            "Essig, Sojasauce und andere fermentierte Würzmittel sind häufige versteckte Quellen."
        default:
            nil
        }
    }

    /// Wo das Lebensmittel im Supermarkt liegt.
    public var shoppingCategory: ShoppingCategory {
        switch self {
        case .vegetables, .fruit: .produce
        case .meat, .fish: .freshMeat
        case .sausage: .deli
        case .dairy, .cheese, .eggs: .dairy
        case .bread: .bakery
        case .grains, .legumes, .nuts: .pantry
        case .fats, .herbs, .sauces: .spices
        case .sweets: .sweets
        case .drinks, .alcohol: .drinks
        case .meals: .other
        case .supplements: .drugstore
        case .other: .other
        }
    }
}

// MARK: - Lebensmittel

public struct FoodInfo: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var aliases: [String]
    public var category: FoodCategory
    public var score: HistamineScore
    public var flags: [HistamineFlag]
    /// Eiweiß in g pro 100 g.
    public var protein: Double?
    /// Energie in kcal pro 100 g.
    public var kcal: Double?
    /// Übliche Portion in g.
    public var portion: Double
    /// Lesbare Portionsangabe, z. B. „1 Ei“.
    public var unit: String?
    public var hint: String?
    public var isCustom: Bool
    /// Bei gescannten Produkten.
    public var barcode: String?
    public var brand: String?
    public var ingredients: String?

    public init(
        id: String,
        name: String,
        aliases: [String] = [],
        category: FoodCategory,
        score: HistamineScore,
        flags: [HistamineFlag] = [],
        protein: Double? = nil,
        kcal: Double? = nil,
        portion: Double = 100,
        unit: String? = nil,
        hint: String? = nil,
        isCustom: Bool = false,
        barcode: String? = nil,
        brand: String? = nil,
        ingredients: String? = nil
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.category = category
        self.score = score
        self.flags = flags
        self.protein = protein
        self.kcal = kcal
        self.portion = portion
        self.unit = unit
        self.hint = hint
        self.isCustom = isCustom
        self.barcode = barcode
        self.brand = brand
        self.ingredients = ingredients
    }

    enum CodingKeys: String, CodingKey {
        case id, name, aliases, category, score, flags, protein, kcal, portion, unit, hint, isCustom, barcode, brand, ingredients
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        category = (try? c.decode(FoodCategory.self, forKey: .category)) ?? .other
        let rawScore = try c.decodeIfPresent(Int.self, forKey: .score) ?? 1
        score = HistamineScore(rawValue: min(max(rawScore, 0), 3)) ?? .moderate
        let rawFlags = try c.decodeIfPresent([String].self, forKey: .flags) ?? []
        flags = rawFlags.compactMap(HistamineFlag.init(rawValue:))
        protein = try c.decodeIfPresent(Double.self, forKey: .protein)
        kcal = try c.decodeIfPresent(Double.self, forKey: .kcal)
        portion = max(1, try c.decodeIfPresent(Double.self, forKey: .portion) ?? 100)
        unit = try c.decodeIfPresent(String.self, forKey: .unit)
        hint = try c.decodeIfPresent(String.self, forKey: .hint)
        isCustom = try c.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
        barcode = try c.decodeIfPresent(String.self, forKey: .barcode)
        brand = try c.decodeIfPresent(String.self, forKey: .brand)
        ingredients = try c.decodeIfPresent(String.self, forKey: .ingredients)
    }

    /// Eiweiß in einer Menge.
    public func protein(grams: Double) -> Double {
        (protein ?? 0) * grams / 100
    }

    public func kcal(grams: Double) -> Double {
        (kcal ?? 0) * grams / 100
    }

    /// „0 · gut verträglich · Liberator“
    public var scoreSummary: String {
        ([score.label] + flags.map(\.shortTitle)).joined(separator: " · ")
    }

    /// Lesbare Menge: „1 Ei“ bei der Standardportion, sonst „150 g“ bzw. „200 ml“.
    public func amountLabel(grams: Double) -> String {
        if let unit, abs(grams - portion) < 0.5 { return unit }
        let value = WeightFormat.number(grams.rounded())
        return category == .drinks || category == .alcohol ? "\(value) ml" : "\(value) g"
    }
}

/// Alle Lebensmittel: mitgelieferte und eigene.
public struct FoodCatalog: Sendable {
    public let foods: [FoodInfo]
    private let byID: [String: FoodInfo]

    public init(foods: [FoodInfo]) {
        self.foods = foods
        var map: [String: FoodInfo] = [:]
        for food in foods { map[food.id] = food }
        byID = map
    }

    public func food(id: String) -> FoodInfo? { byID[id] }

    public func food(barcode: String) -> FoodInfo? {
        foods.first { $0.barcode == barcode }
    }

    /// Name eines Lebensmittels, auch wenn es nicht mehr im Katalog ist.
    public func name(for id: String) -> String {
        byID[id]?.name ?? id
    }

    /// Mit eigenen Lebensmitteln (diese ersetzen gleichnamige IDs).
    public func adding(_ custom: [FoodInfo]) -> FoodCatalog {
        guard !custom.isEmpty else { return self }
        let ids = Set(custom.map(\.id))
        return FoodCatalog(foods: foods.filter { !ids.contains($0.id) } + custom)
    }

    /// Nach Name sortiert.
    public var sorted: [FoodInfo] {
        foods.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    /// Suche in Namen und Aliasen. Treffer am Wortanfang zuerst, dann der Rest.
    /// `substrings: false` lässt Treffer mitten im Wort weg (für die globale Suche, z. B. „arzt“ nicht in „Schwarztee“).
    public func search(_ query: String, limit: Int? = nil, substrings: Bool = true) -> [FoodInfo] {
        let needle = NameMatcher.normalize(query)
        guard !needle.isEmpty else { return limit.map { Array(sorted.prefix($0)) } ?? sorted }
        var ranked: [(FoodInfo, Int)] = []
        for food in foods {
            var best = Int.max
            for (index, name) in ([food.name] + food.aliases).enumerated() {
                let normalized = NameMatcher.normalize(name)
                let penalty = index == 0 ? 0 : 1
                if normalized == needle {
                    best = min(best, 0 + penalty)
                } else if normalized.hasPrefix(needle) {
                    best = min(best, 2 + penalty)
                } else if normalized.split(separator: " ").contains(where: { $0.hasPrefix(needle) }) {
                    best = min(best, 4 + penalty)
                } else if substrings, normalized.contains(needle) {
                    best = min(best, 6 + penalty)
                }
            }
            if best != Int.max { ranked.append((food, best)) }
        }
        let result = ranked
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return lhs.0.name.localizedCompare(rhs.0.name) == .orderedAscending
            }
            .map(\.0)
        return limit.map { Array(result.prefix($0)) } ?? result
    }

    /// Bester Treffer für einen Namen (für Siri und Einkaufsliste).
    public func bestMatch(for name: String) -> FoodInfo? {
        let needle = NameMatcher.normalize(name)
        guard !needle.isEmpty else { return nil }
        if let exact = foods.first(where: { food in
            ([food.name] + food.aliases).contains { NameMatcher.normalize($0) == needle }
        }) {
            return exact
        }
        // Mehrzahl und kleine Abweichungen („Tomaten“ → „Tomate“, „Avocados“ → „Avocado“).
        for suffix in ["s", "n", "en", "e"] where needle.hasSuffix(suffix) && needle.count > suffix.count + 2 {
            let trimmed = String(needle.dropLast(suffix.count))
            if let match = foods.first(where: { food in
                ([food.name] + food.aliases).contains { NameMatcher.normalize($0) == trimmed }
            }) {
                return match
            }
        }
        if let found = search(name, limit: 1).first { return found }
        // Längster Name, mit dem die Eingabe beginnt („Hähnchenbrustfilet“ → „Hähnchenbrust“).
        var best: (FoodInfo, Int)?
        for food in foods {
            for alias in [food.name] + food.aliases {
                let normalized = NameMatcher.normalize(alias)
                guard normalized.count >= 4, needle.hasPrefix(normalized) else { continue }
                if normalized.count > (best?.1 ?? 0) { best = (food, normalized.count) }
            }
        }
        return best?.0
    }

    /// Nach Kategorie gruppiert, in fester Reihenfolge.
    public func grouped(_ items: [FoodInfo]? = nil) -> [(FoodCategory, [FoodInfo])] {
        let source = items ?? sorted
        let groups = Dictionary(grouping: source, by: \.category)
        return FoodCategory.allCases.compactMap { category in
            guard let list = groups[category], !list.isEmpty else { return nil }
            return (category, list)
        }
    }

    /// Prüft die Inhalte (für Tests und Content-Pflege).
    public var validationIssues: [String] {
        var issues: [String] = []
        var seenIDs = Set<String>()
        var seenNames: [String: String] = [:]
        for food in foods {
            if !seenIDs.insert(food.id).inserted { issues.append("Doppelte ID \(food.id)") }
            if food.name.trimmingCharacters(in: .whitespaces).isEmpty { issues.append("Leerer Name bei \(food.id)") }
            for name in [food.name] + food.aliases {
                let key = NameMatcher.normalize(name)
                if let other = seenNames[key], other != food.id {
                    issues.append("Name „\(name)“ bei \(food.id) und \(other)")
                }
                seenNames[key] = food.id
            }
            if let protein = food.protein, protein < 0 || protein > 100 { issues.append("Eiweiß außerhalb 0–100 bei \(food.id)") }
            if food.portion <= 0 { issues.append("Portion ≤ 0 bei \(food.id)") }
        }
        return issues
    }

    public static func decode(_ data: Data) throws -> FoodCatalog {
        struct File: Decodable { let foods: [FoodInfo] }
        return FoodCatalog(foods: try JSONDecoder().decode(File.self, from: data).foods)
    }

    /// Das mitgelieferte Lexikon (`foods.de.json`).
    public static func bundled() -> FoodCatalog {
        guard let url = Bundle.module.url(forResource: "foods.de", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? decode(data)
        else { return FoodCatalog(foods: []) }
        return catalog
    }
}

// MARK: - Antworten für Siri

public enum FoodAnswer {
    /// „Avocado: sehr schlecht verträglich (3 von 3), histaminreich. Du hast sie als „Meiden“ markiert.“
    public static func sentence(for food: FoodInfo, tolerance: Tolerance = .unknown) -> String {
        var parts = ["\(food.name): \(food.score.title) (\(food.score.rawValue) von 3)"]
        if !food.flags.isEmpty {
            parts[0] += ", " + food.flags.map(\.shortTitle).joined(separator: ", ")
        }
        var text = parts[0] + "."
        switch tolerance {
        case .unknown: break
        case .ok: text += " Bei dir: verträglich."
        case .caution: text += " Bei dir: Vorsicht."
        case .avoid: text += " Bei dir: meiden."
        }
        if let hint = food.hint { text += " " + hint }
        return text
    }
}
