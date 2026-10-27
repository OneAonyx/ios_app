import Foundation

// MARK: - Datensicherung

public struct MealItemRecord: Codable, Sendable, Equatable {
    public var stableID: String
    public var foodID: String
    public var name: String
    public var grams: Double
    public var order: Int

    public init(stableID: String, foodID: String, name: String, grams: Double, order: Int) {
        self.stableID = stableID
        self.foodID = foodID
        self.name = name
        self.grams = grams
        self.order = order
    }
}

public struct MealRecord: Codable, Sendable, Equatable {
    public var stableID: String
    public var date: Date
    public var type: String
    public var freshness: String
    public var place: String
    public var recipeID: String?
    public var note: String
    public var items: [MealItemRecord]

    public init(stableID: String, date: Date, type: String, freshness: String, place: String, recipeID: String?, note: String, items: [MealItemRecord]) {
        self.stableID = stableID
        self.date = date
        self.type = type
        self.freshness = freshness
        self.place = place
        self.recipeID = recipeID
        self.note = note
        self.items = items
    }
}

public struct SymptomRecord: Codable, Sendable, Equatable {
    public var stableID: String
    public var date: Date
    public var type: String
    public var severity: Int
    public var durationMinutes: Int?
    public var note: String

    public init(stableID: String, date: Date, type: String, severity: Int, durationMinutes: Int?, note: String) {
        self.stableID = stableID
        self.date = date
        self.type = type
        self.severity = severity
        self.durationMinutes = durationMinutes
        self.note = note
    }
}

public struct WaterRecord: Codable, Sendable, Equatable {
    public var stableID: String
    public var date: Date
    public var milliliters: Int

    public init(stableID: String, date: Date, milliliters: Int) {
        self.stableID = stableID
        self.date = date
        self.milliliters = milliliters
    }
}

public struct FoodPreferenceRecord: Codable, Sendable, Equatable {
    public var foodID: String
    public var tolerance: String
    public var isFavorite: Bool
    public var note: String

    public init(foodID: String, tolerance: String, isFavorite: Bool, note: String) {
        self.foodID = foodID
        self.tolerance = tolerance
        self.isFavorite = isFavorite
        self.note = note
    }
}

public struct ShoppingRecord: Codable, Sendable, Equatable {
    public var stableID: String
    public var name: String
    public var category: String
    public var amount: String
    public var foodID: String?
    public var isDone: Bool
    public var createdAt: Date
    public var source: String

    public init(stableID: String, name: String, category: String, amount: String, foodID: String?, isDone: Bool, createdAt: Date, source: String) {
        self.stableID = stableID
        self.name = name
        self.category = category
        self.amount = amount
        self.foodID = foodID
        self.isDone = isDone
        self.createdAt = createdAt
        self.source = source
    }
}

public struct MealPlanRecord: Codable, Sendable, Equatable {
    public var stableID: String
    public var day: Date
    public var mealType: String
    public var recipeID: String
    public var servings: Int

    public init(stableID: String, day: Date, mealType: String, recipeID: String, servings: Int) {
        self.stableID = stableID
        self.day = day
        self.mealType = mealType
        self.recipeID = recipeID
        self.servings = servings
    }
}

/// Alles rund um Ernährung in der Datensicherung (ab Version 0.5).
public struct NutritionBackup: Codable, Sendable, Equatable {
    public var customFoods: [FoodInfo]
    public var preferences: [FoodPreferenceRecord]
    public var meals: [MealRecord]
    public var symptoms: [SymptomRecord]
    public var water: [WaterRecord]
    public var shopping: [ShoppingRecord]
    public var mealPlan: [MealPlanRecord]
    public var customRecipes: [RecipeInfo]

    public init(
        customFoods: [FoodInfo] = [], preferences: [FoodPreferenceRecord] = [], meals: [MealRecord] = [],
        symptoms: [SymptomRecord] = [], water: [WaterRecord] = [], shopping: [ShoppingRecord] = [],
        mealPlan: [MealPlanRecord] = [], customRecipes: [RecipeInfo] = []
    ) {
        self.customFoods = customFoods
        self.preferences = preferences
        self.meals = meals
        self.symptoms = symptoms
        self.water = water
        self.shopping = shopping
        self.mealPlan = mealPlan
        self.customRecipes = customRecipes
    }
}

// MARK: - Widget

/// Tageswerte für Widget, Kontrollzentrum und Siri.
public struct NutritionWidgetSnapshot: Codable, Sendable, Equatable {
    public var writtenAt: Date
    public var day: Date
    public var loadPoints: Double
    public var levelRaw: String
    public var protein: Double
    public var proteinTarget: Double
    public var waterML: Int
    public var waterTarget: Int
    public var mealCount: Int
    /// Größte Beiträge zur Tageslast, z. B. „Tomate“, „Reste“.
    public var topContributors: [String]
    public var lastSymptom: String?

    public init(
        writtenAt: Date, day: Date, loadPoints: Double, levelRaw: String, protein: Double, proteinTarget: Double,
        waterML: Int, waterTarget: Int, mealCount: Int, topContributors: [String], lastSymptom: String? = nil
    ) {
        self.writtenAt = writtenAt
        self.day = day
        self.loadPoints = loadPoints
        self.levelRaw = levelRaw
        self.protein = protein
        self.proteinTarget = proteinTarget
        self.waterML = waterML
        self.waterTarget = waterTarget
        self.mealCount = mealCount
        self.topContributors = topContributors
        self.lastSymptom = lastSymptom
    }

    public static let empty = NutritionWidgetSnapshot(
        writtenAt: .distantPast, day: .distantPast, loadPoints: 0, levelRaw: HistamineLoad.Level.calm.rawValue,
        protein: 0, proteinTarget: NutritionTargets.proteinTarget(bodyweight: nil), waterML: 0,
        waterTarget: NutritionTargets.defaultWaterML, mealCount: 0, topContributors: []
    )

    public var level: HistamineLoad.Level { HistamineLoad.Level(rawValue: levelRaw) ?? .calm }

    public var loadFraction: Double { min(1, loadPoints / HistamineLoad.scaleMax) }

    /// Werte von gestern zählen heute nicht mehr.
    public func isCurrent(now: Date, calendar: Calendar) -> Bool {
        calendar.isDate(day, inSameDayAs: now)
    }

    /// Heutige Werte oder leere, wenn der Schnappschuss von gestern ist.
    public func current(now: Date, calendar: Calendar) -> NutritionWidgetSnapshot {
        guard !isCurrent(now: now, calendar: calendar) else { return self }
        var fresh = NutritionWidgetSnapshot.empty
        fresh.writtenAt = writtenAt
        fresh.day = calendar.startOfDay(for: now)
        fresh.proteinTarget = proteinTarget
        fresh.waterTarget = waterTarget
        return fresh
    }

    /// Antwort für Siri: „Histamin heute: ruhig. Eiweiß 96 von 150 g, Wasser 1,5 von 2,5 l.“
    public func sentence(now: Date, calendar: Calendar) -> String {
        let today = current(now: now, calendar: calendar)
        var text = "Histamin heute: \(today.level.title)"
        if !today.topContributors.isEmpty, today.level != .calm {
            text += " (vor allem \(today.topContributors.prefix(2).joined(separator: ", ")))"
        }
        text += ". Eiweiß \(Int(today.protein.rounded())) von \(Int(today.proteinTarget.rounded())) g"
        text += ", Wasser \(NutritionDay.liters(today.waterML)) von \(NutritionDay.liters(today.waterTarget)) l."
        return text
    }
}

/// Wasser aus Widget oder Kontrollzentrum, bis die App es übernimmt.
public struct PendingWater: Codable, Sendable, Equatable {
    public var date: Date
    public var milliliters: Int

    public init(date: Date, milliliters: Int) {
        self.date = date
        self.milliliters = milliliters
    }
}
