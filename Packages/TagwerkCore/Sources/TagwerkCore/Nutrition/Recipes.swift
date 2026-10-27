import Foundation

// MARK: - Rezepte

public struct RecipeIngredient: Codable, Sendable, Hashable {
    /// ID im Lebensmittel-Lexikon.
    public var food: String
    /// Menge für das ganze Rezept.
    public var grams: Double
    /// Lesbare Menge, z. B. „2 EL“. Ohne Angabe „300 g“.
    public var amount: String?
    public var note: String?

    public init(food: String, grams: Double, amount: String? = nil, note: String? = nil) {
        self.food = food
        self.grams = grams
        self.amount = amount
        self.note = note
    }
}

public struct RecipeInfo: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var summary: String
    public var servings: Int
    public var minutes: Int
    public var tags: [String]
    public var ingredients: [RecipeIngredient]
    public var steps: [String]
    public var isCustom: Bool

    public init(
        id: String, title: String, summary: String = "", servings: Int, minutes: Int, tags: [String] = [],
        ingredients: [RecipeIngredient], steps: [String], isCustom: Bool = false
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.servings = max(1, servings)
        self.minutes = minutes
        self.tags = tags
        self.ingredients = ingredients
        self.steps = steps
        self.isCustom = isCustom
    }

    enum CodingKeys: String, CodingKey {
        case id, title, summary, servings, minutes, tags, ingredients, steps, isCustom
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        servings = max(1, try c.decodeIfPresent(Int.self, forKey: .servings) ?? 2)
        minutes = try c.decodeIfPresent(Int.self, forKey: .minutes) ?? 30
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        ingredients = try c.decodeIfPresent([RecipeIngredient].self, forKey: .ingredients) ?? []
        steps = try c.decodeIfPresent([String].self, forKey: .steps) ?? []
        isCustom = try c.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
    }

    public func proteinPerServing(catalog: FoodCatalog) -> Double {
        ingredients.reduce(0) { $0 + (catalog.food(id: $1.food)?.protein(grams: $1.grams) ?? 0) } / Double(servings)
    }

    public func kcalPerServing(catalog: FoodCatalog) -> Double {
        ingredients.reduce(0) { $0 + (catalog.food(id: $1.food)?.kcal(grams: $1.grams) ?? 0) } / Double(servings)
    }

    /// Schlechteste Zutat, mit eigener Einschätzung.
    public func worstScore(catalog: FoodCatalog, tolerance: (String) -> Tolerance = { _ in .unknown }) -> HistamineScore {
        ingredients.compactMap { item in
            catalog.food(id: item.food).map { tolerance(item.food).effectiveScore(general: $0.score) }
        }
        .max() ?? .good
    }

    /// „300 g Hähnchenbrust“ bzw. „2 EL Olivenöl“, auf `servings` Portionen umgerechnet.
    public func label(for item: RecipeIngredient, servings target: Int? = nil, catalog: FoodCatalog) -> String {
        let factor = Double(target ?? servings) / Double(servings)
        let name = catalog.name(for: item.food)
        if let amount = item.amount, abs(factor - 1) < 0.01 {
            return "\(amount) \(name)"
        }
        let grams = item.grams * factor
        let unit = catalog.food(id: item.food).map { $0.category == .drinks || $0.category == .alcohol } == true ? "ml" : "g"
        return "\(WeightFormat.number(grams.rounded())) \(unit) \(name)"
    }

    /// Zutaten für `portions` gegessene Portionen (für das Tagebuch).
    public func mealItems(portions: Double = 1) -> [(foodID: String, grams: Double)] {
        ingredients
            .filter { $0.food != "salz" && $0.food != "wasser" }
            .map { ($0.food, ($0.grams / Double(servings) * portions * 10).rounded() / 10) }
    }
}

public struct RecipeCatalog: Sendable {
    public let recipes: [RecipeInfo]

    public init(recipes: [RecipeInfo]) {
        self.recipes = recipes
    }

    public func recipe(id: String) -> RecipeInfo? { recipes.first { $0.id == id } }

    public func adding(_ custom: [RecipeInfo]) -> RecipeCatalog {
        guard !custom.isEmpty else { return self }
        let ids = Set(custom.map(\.id))
        return RecipeCatalog(recipes: recipes.filter { !ids.contains($0.id) } + custom)
    }

    public var sorted: [RecipeInfo] {
        recipes.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    /// Alle Stichworte („Frühstück“, „Meal Prep“ …) in fester Reihenfolge.
    public var tags: [String] {
        let preferred = ["Frühstück", "Mittag", "Abend", "Snack", "Süß", "Vegetarisch", "Fisch", "Suppe", "Meal Prep", "Grill"]
        let all = Set(recipes.flatMap(\.tags))
        return preferred.filter(all.contains) + all.subtracting(preferred).sorted()
    }

    public func search(_ query: String, tag: String? = nil, catalog: FoodCatalog) -> [RecipeInfo] {
        let needle = NameMatcher.normalize(query)
        return sorted.filter { recipe in
            if let tag, !recipe.tags.contains(tag) { return false }
            guard !needle.isEmpty else { return true }
            if NameMatcher.normalize(recipe.title).contains(needle) { return true }
            return recipe.ingredients.contains { NameMatcher.normalize(catalog.name(for: $0.food)).contains(needle) }
        }
    }

    public static func decode(_ data: Data) throws -> RecipeCatalog {
        struct File: Decodable { let recipes: [RecipeInfo] }
        return RecipeCatalog(recipes: try JSONDecoder().decode(File.self, from: data).recipes)
    }

    /// Die mitgelieferten Rezepte (`recipes.de.json`).
    public static func bundled() -> RecipeCatalog {
        guard let url = Bundle.module.url(forResource: "recipes.de", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? decode(data)
        else { return RecipeCatalog(recipes: []) }
        return catalog
    }
}

// MARK: - Einkaufsliste

/// Bereiche im Supermarkt, in Laufreihenfolge.
public enum ShoppingCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case produce, bakery, freshMeat, deli, dairy, pantry, spices, frozen, sweets, drinks, drugstore, other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .produce: "Obst & Gemüse"
        case .bakery: "Brot & Backwaren"
        case .freshMeat: "Fleisch & Fisch (frisch)"
        case .deli: "Wurst & Aufschnitt"
        case .dairy: "Milchprodukte & Eier"
        case .pantry: "Vorrat"
        case .spices: "Gewürze & Öle"
        case .frozen: "Tiefkühl"
        case .sweets: "Süßes & Snacks"
        case .drinks: "Getränke"
        case .drugstore: "Drogerie & Ergänzungen"
        case .other: "Sonstiges"
        }
    }

    public var symbol: String {
        switch self {
        case .produce: "carrot.fill"
        case .bakery: "birthday.cake.fill"
        case .freshMeat: "fish.fill"
        case .deli: "fork.knife"
        case .dairy: "drop.fill"
        case .pantry: "archivebox.fill"
        case .spices: "leaf.fill"
        case .frozen: "snowflake"
        case .sweets: "birthday.cake"
        case .drinks: "waterbottle.fill"
        case .drugstore: "cross.case.fill"
        case .other: "bag.fill"
        }
    }

    public var order: Int { Self.allCases.firstIndex(of: self) ?? 99 }

    /// Bereich für einen frei eingegebenen Artikel.
    public static func guess(for name: String, catalog: FoodCatalog) -> ShoppingCategory {
        let normalized = NameMatcher.normalize(name)
        if normalized.contains("tiefkuehl") || normalized.hasPrefix("tk ") { return .frozen }
        return catalog.bestMatch(for: name)?.category.shoppingCategory ?? .other
    }
}

/// Ein Artikel, der für Rezepte gebraucht wird.
public struct ShoppingNeed: Sendable, Hashable, Identifiable {
    public var foodID: String
    public var name: String
    public var grams: Double
    public var category: ShoppingCategory
    public var score: HistamineScore
    public var note: String?

    public var id: String { foodID }

    /// „600 g“, „1,2 kg“, „750 ml“
    public var amountText: String {
        ShoppingNeed.amount(grams: grams, isLiquid: category == .drinks || foodID == "milch" || foodID == "gemuesebruehe")
    }

    public static func amount(grams: Double, isLiquid: Bool) -> String {
        let unitSmall = isLiquid ? "ml" : "g"
        let unitLarge = isLiquid ? "l" : "kg"
        if grams >= 1000 {
            return "\(WeightFormat.number((grams / 100).rounded() / 10)) \(unitLarge)"
        }
        let rounded = grams >= 100 ? (grams / 10).rounded() * 10 : grams.rounded()
        return "\(WeightFormat.number(rounded)) \(unitSmall)"
    }
}

public enum ShoppingPlanner {
    /// Was nicht auf die Liste soll (hat man immer da).
    public static let staples: Set<String> = ["salz", "wasser"]

    /// Zutaten mehrerer Rezepte, zusammengefasst und auf Portionen umgerechnet.
    public static func needs(for recipes: [(recipe: RecipeInfo, servings: Int)], catalog: FoodCatalog) -> [ShoppingNeed] {
        var grams: [String: Double] = [:]
        var notes: [String: String] = [:]
        for (recipe, servings) in recipes {
            let factor = Double(servings) / Double(recipe.servings)
            for item in recipe.ingredients where !staples.contains(item.food) {
                grams[item.food, default: 0] += item.grams * factor
                if let note = item.note { notes[item.food] = note }
            }
        }
        return grams.compactMap { foodID, total -> ShoppingNeed? in
            let food = catalog.food(id: foodID)
            return ShoppingNeed(
                foodID: foodID,
                name: food?.name ?? foodID,
                grams: total,
                category: food?.category.shoppingCategory ?? .other,
                score: food?.score ?? .good,
                note: notes[foodID]
            )
        }
        .sorted { lhs, rhs in
            if lhs.category.order != rhs.category.order { return lhs.category.order < rhs.category.order }
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
    }
}
