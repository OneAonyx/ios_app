import Foundation
import SwiftData
import TagwerkCore

/// Version 4 des Datenmodells (Phase 4): Ernährung, Histamin und Symptome.
///
/// Aufgaben (V1), Medikamente (V2) und Training (V3) sind unverändert und werden übernommen.
/// Der Umstieg von V3 ist eine leichte Migration (nur neue Tabellen).
public enum TagwerkSchemaV4: VersionedSchema {
    public static let versionIdentifier = Schema.Version(4, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            TagwerkSchemaV1.TaskItem.self,
            TagwerkSchemaV1.Subtask.self,
            TagwerkSchemaV1.TaskList.self,
            TagwerkSchemaV2.Medication.self,
            TagwerkSchemaV2.DoseLog.self,
            TagwerkSchemaV3.WorkoutPlan.self,
            TagwerkSchemaV3.PlanDay.self,
            TagwerkSchemaV3.PlanExercise.self,
            TagwerkSchemaV3.WorkoutSession.self,
            TagwerkSchemaV3.SetLog.self,
            TagwerkSchemaV3.CustomExercise.self,
            TagwerkSchemaV3.ExercisePreference.self,
            TagwerkSchemaV3.BodyMetric.self,
            FoodPreference.self,
            CustomFood.self,
            MealEntry.self,
            MealItem.self,
            SymptomEntry.self,
            WaterLog.self,
            ShoppingItem.self,
            MealPlanEntry.self,
            CustomRecipe.self,
        ]
    }

    /// Eigene Einschätzung und Favorit je Lebensmittel.
    @Model
    public final class FoodPreference {
        public var foodID: String = ""
        public var toleranceRaw: String = Tolerance.unknown.rawValue
        public var isFavorite: Bool = false
        public var note: String = ""
        public var updatedAt: Date = Date()

        public init(foodID: String) {
            self.foodID = foodID
        }
    }

    /// Eigenes oder gescanntes Lebensmittel.
    @Model
    public final class CustomFood {
        /// Gleich der Lebensmittel-ID (z. B. „custom-…“ oder „barcode-4006…“).
        public var stableID: String = UUID().uuidString
        public var name: String = ""
        public var aliasesText: String = ""
        public var categoryRaw: String = FoodCategory.other.rawValue
        public var score: Int = 1
        public var flagsText: String = ""
        public var protein: Double?
        public var kcal: Double?
        public var portion: Double = 100
        public var unit: String?
        public var hint: String?
        public var barcode: String?
        public var brand: String?
        public var ingredients: String?
        public var createdAt: Date = Date()

        public init(stableID: String, name: String, createdAt: Date = Date()) {
            self.stableID = stableID
            self.name = name
            self.createdAt = createdAt
        }
    }

    /// Eine Mahlzeit im Tagebuch.
    @Model
    public final class MealEntry {
        public var stableID: String = UUID().uuidString
        public var date: Date = Date()
        public var typeRaw: String = MealType.lunch.rawValue
        public var freshnessRaw: String = Freshness.fresh.rawValue
        public var placeRaw: String = MealPlace.home.rawValue
        /// Rezept, aus dem die Mahlzeit stammt.
        public var recipeID: String?
        public var note: String = ""
        public var createdAt: Date = Date()

        @Relationship(deleteRule: .cascade, inverse: \MealItem.meal)
        public var items: [MealItem]? = []

        public init(date: Date, type: MealType, stableID: String = UUID().uuidString, createdAt: Date = Date()) {
            self.stableID = stableID
            self.date = date
            self.typeRaw = type.rawValue
            self.createdAt = createdAt
        }
    }

    /// Ein Lebensmittel in einer Mahlzeit. Der Name wird mitgespeichert, falls das
    /// Lebensmittel später gelöscht wird.
    @Model
    public final class MealItem {
        public var stableID: String = UUID().uuidString
        public var foodID: String = ""
        public var name: String = ""
        public var grams: Double = 100
        public var position: Int = 0
        public var meal: MealEntry?

        public init(foodID: String, name: String, grams: Double, position: Int, stableID: String = UUID().uuidString) {
            self.stableID = stableID
            self.foodID = foodID
            self.name = name
            self.grams = grams
            self.position = position
        }
    }

    @Model
    public final class SymptomEntry {
        public var stableID: String = UUID().uuidString
        public var date: Date = Date()
        public var typeRaw: String = SymptomType.other.rawValue
        public var severity: Int = 3
        /// Dauer in Minuten, `nil` = unbekannt.
        public var durationMinutes: Int?
        public var note: String = ""
        public var createdAt: Date = Date()

        public init(date: Date, type: SymptomType, severity: Int, stableID: String = UUID().uuidString) {
            self.stableID = stableID
            self.date = date
            self.typeRaw = type.rawValue
            self.severity = severity
        }
    }

    @Model
    public final class WaterLog {
        public var stableID: String = UUID().uuidString
        public var date: Date = Date()
        public var milliliters: Int = 250

        public init(date: Date, milliliters: Int, stableID: String = UUID().uuidString) {
            self.stableID = stableID
            self.date = date
            self.milliliters = milliliters
        }
    }

    @Model
    public final class ShoppingItem {
        public var stableID: String = UUID().uuidString
        public var name: String = ""
        public var categoryRaw: String = ShoppingCategory.other.rawValue
        /// Menge als Text („600 g“, „2 Stück“).
        public var amount: String = ""
        public var foodID: String?
        public var isDone: Bool = false
        public var doneAt: Date?
        /// „manual“, „recipe“ oder „plan“.
        public var sourceRaw: String = "manual"
        public var createdAt: Date = Date()

        public init(name: String, category: ShoppingCategory, amount: String = "", foodID: String? = nil, source: String = "manual", stableID: String = UUID().uuidString, createdAt: Date = Date()) {
            self.stableID = stableID
            self.name = name
            self.categoryRaw = category.rawValue
            self.amount = amount
            self.foodID = foodID
            self.sourceRaw = source
            self.createdAt = createdAt
        }
    }

    /// Rezept an einem Tag im Wochen-Essensplan.
    @Model
    public final class MealPlanEntry {
        public var stableID: String = UUID().uuidString
        /// Tagesbeginn.
        public var day: Date = Date()
        public var mealTypeRaw: String = MealType.dinner.rawValue
        public var recipeID: String = ""
        public var servings: Int = 2

        public init(day: Date, mealType: MealType, recipeID: String, servings: Int, stableID: String = UUID().uuidString) {
            self.stableID = stableID
            self.day = day
            self.mealTypeRaw = mealType.rawValue
            self.recipeID = recipeID
            self.servings = servings
        }
    }

    /// Eigenes Rezept. Zutaten als JSON, damit das Modell schlank bleibt.
    @Model
    public final class CustomRecipe {
        public var stableID: String = UUID().uuidString
        public var title: String = ""
        public var summary: String = ""
        public var servings: Int = 2
        public var minutes: Int = 30
        public var tagsText: String = ""
        public var ingredientsData: Data?
        public var stepsText: String = ""
        public var createdAt: Date = Date()

        public init(title: String, stableID: String = UUID().uuidString, createdAt: Date = Date()) {
            self.stableID = stableID
            self.title = title
            self.createdAt = createdAt
        }
    }
}

public typealias FoodPreference = TagwerkSchemaV4.FoodPreference
public typealias CustomFood = TagwerkSchemaV4.CustomFood
public typealias MealEntry = TagwerkSchemaV4.MealEntry
public typealias MealItem = TagwerkSchemaV4.MealItem
public typealias SymptomEntry = TagwerkSchemaV4.SymptomEntry
public typealias WaterLog = TagwerkSchemaV4.WaterLog
public typealias ShoppingItem = TagwerkSchemaV4.ShoppingItem
public typealias MealPlanEntry = TagwerkSchemaV4.MealPlanEntry
public typealias CustomRecipe = TagwerkSchemaV4.CustomRecipe

// MARK: - Bequeme Zugriffe

public extension TagwerkSchemaV4.FoodPreference {
    var tolerance: Tolerance {
        get { Tolerance(rawValue: toleranceRaw) ?? .unknown }
        set { toleranceRaw = newValue.rawValue; updatedAt = .now }
    }
}

public extension TagwerkSchemaV4.CustomFood {
    var info: FoodInfo {
        FoodInfo(
            id: stableID,
            name: name,
            aliases: aliasesText.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            category: FoodCategory(rawValue: categoryRaw) ?? .other,
            score: HistamineScore(rawValue: min(max(score, 0), 3)) ?? .moderate,
            flags: flagsText.split(separator: ",").compactMap { HistamineFlag(rawValue: String($0)) },
            protein: protein,
            kcal: kcal,
            portion: max(1, portion),
            unit: unit,
            hint: hint,
            isCustom: true,
            barcode: barcode,
            brand: brand,
            ingredients: ingredients
        )
    }

    func apply(_ info: FoodInfo) {
        name = info.name
        aliasesText = info.aliases.joined(separator: ";")
        categoryRaw = info.category.rawValue
        score = info.score.rawValue
        flagsText = info.flags.map(\.rawValue).joined(separator: ",")
        protein = info.protein
        kcal = info.kcal
        portion = info.portion
        unit = info.unit
        hint = info.hint
        barcode = info.barcode
        brand = info.brand
        ingredients = info.ingredients
    }
}

public extension TagwerkSchemaV4.MealEntry {
    var type: MealType {
        get { MealType(rawValue: typeRaw) ?? .snack }
        set { typeRaw = newValue.rawValue }
    }

    var freshness: Freshness {
        get { Freshness(rawValue: freshnessRaw) ?? .fresh }
        set { freshnessRaw = newValue.rawValue }
    }

    var place: MealPlace {
        get { MealPlace(rawValue: placeRaw) ?? .home }
        set { placeRaw = newValue.rawValue }
    }

    var sortedItems: [MealItem] {
        (items ?? []).sorted { $0.position < $1.position }
    }

    /// Für Berechnungen. `tolerance` liefert die eigene Einschätzung je Lebensmittel.
    func fact(catalog: FoodCatalog, tolerance: (String) -> Tolerance) -> MealFact {
        MealFact(
            id: stableID,
            date: date,
            type: type,
            freshness: freshness,
            place: place,
            items: sortedItems.map { item in
                let food = catalog.food(id: item.foodID)
                let general = food?.score ?? .moderate
                return MealItemFact(
                    foodID: item.foodID,
                    name: food?.name ?? item.name,
                    grams: item.grams,
                    score: tolerance(item.foodID).effectiveScore(general: general),
                    flags: food?.flags ?? [],
                    proteinPer100: food?.protein ?? 0,
                    kcalPer100: food?.kcal ?? 0
                )
            }
        )
    }

    /// „Hähnchenbrust, Reis, Zucchini“
    var itemSummary: String {
        sortedItems.map(\.name).joined(separator: ", ")
    }
}

public extension TagwerkSchemaV4.SymptomEntry {
    var type: SymptomType {
        get { SymptomType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    var fact: SymptomFact {
        SymptomFact(date: date, type: type, severity: severity)
    }
}

public extension TagwerkSchemaV4.ShoppingItem {
    var category: ShoppingCategory {
        get { ShoppingCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
}

public extension TagwerkSchemaV4.MealPlanEntry {
    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .dinner }
        set { mealTypeRaw = newValue.rawValue }
    }
}

public extension TagwerkSchemaV4.CustomRecipe {
    var ingredients: [RecipeIngredient] {
        get {
            guard let ingredientsData else { return [] }
            return (try? JSONDecoder().decode([RecipeIngredient].self, from: ingredientsData)) ?? []
        }
        set { ingredientsData = try? JSONEncoder().encode(newValue) }
    }

    var info: RecipeInfo {
        RecipeInfo(
            id: stableID,
            title: title,
            summary: summary,
            servings: servings,
            minutes: minutes,
            tags: tagsText.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            ingredients: ingredients,
            steps: stepsText.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            isCustom: true
        )
    }

    func apply(_ info: RecipeInfo) {
        title = info.title
        summary = info.summary
        servings = info.servings
        minutes = info.minutes
        tagsText = info.tags.joined(separator: ";")
        ingredients = info.ingredients
        stepsText = info.steps.joined(separator: "\n")
    }
}
