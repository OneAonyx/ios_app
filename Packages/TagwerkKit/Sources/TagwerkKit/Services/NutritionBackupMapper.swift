import Foundation
import SwiftData
import TagwerkCore

/// Übersetzt Ernährung, Symptome und Wasser zwischen Datenbank und Datensicherung.
@MainActor
enum NutritionBackupMapper {
    static func makeBackup(context: ModelContext) throws -> NutritionBackup {
        let customFoods = try context.fetch(FetchDescriptor<CustomFood>(sortBy: [SortDescriptor(\.createdAt)]))
        let preferences = try context.fetch(FetchDescriptor<FoodPreference>())
        let meals = try context.fetch(FetchDescriptor<MealEntry>(sortBy: [SortDescriptor(\.date)]))
        let symptoms = try context.fetch(FetchDescriptor<SymptomEntry>(sortBy: [SortDescriptor(\.date)]))
        let water = try context.fetch(FetchDescriptor<WaterLog>(sortBy: [SortDescriptor(\.date)]))
        let shopping = try context.fetch(FetchDescriptor<ShoppingItem>(sortBy: [SortDescriptor(\.createdAt)]))
        let plan = try context.fetch(FetchDescriptor<MealPlanEntry>(sortBy: [SortDescriptor(\.day)]))
        let recipes = try context.fetch(FetchDescriptor<CustomRecipe>(sortBy: [SortDescriptor(\.createdAt)]))

        return NutritionBackup(
            customFoods: customFoods.map(\.info),
            preferences: preferences.map {
                FoodPreferenceRecord(foodID: $0.foodID, tolerance: $0.toleranceRaw, isFavorite: $0.isFavorite, note: $0.note)
            },
            meals: meals.map { meal in
                MealRecord(
                    stableID: meal.stableID, date: meal.date, type: meal.typeRaw, freshness: meal.freshnessRaw,
                    place: meal.placeRaw, recipeID: meal.recipeID, note: meal.note,
                    items: meal.sortedItems.map {
                        MealItemRecord(stableID: $0.stableID, foodID: $0.foodID, name: $0.name, grams: $0.grams, order: $0.position)
                    }
                )
            },
            symptoms: symptoms.map {
                SymptomRecord(stableID: $0.stableID, date: $0.date, type: $0.typeRaw, severity: $0.severity, durationMinutes: $0.durationMinutes, note: $0.note)
            },
            water: water.map { WaterRecord(stableID: $0.stableID, date: $0.date, milliliters: $0.milliliters) },
            shopping: shopping.map {
                ShoppingRecord(
                    stableID: $0.stableID, name: $0.name, category: $0.categoryRaw, amount: $0.amount, foodID: $0.foodID,
                    isDone: $0.isDone, createdAt: $0.createdAt, source: $0.sourceRaw
                )
            },
            mealPlan: plan.map {
                MealPlanRecord(stableID: $0.stableID, day: $0.day, mealType: $0.mealTypeRaw, recipeID: $0.recipeID, servings: $0.servings)
            },
            customRecipes: recipes.map(\.info)
        )
    }

    static func restore(_ backup: NutritionBackup, context: ModelContext) throws {
        for item in try context.fetch(FetchDescriptor<MealItem>()) { context.delete(item) }
        for meal in try context.fetch(FetchDescriptor<MealEntry>()) { context.delete(meal) }
        for food in try context.fetch(FetchDescriptor<CustomFood>()) { context.delete(food) }
        for preference in try context.fetch(FetchDescriptor<FoodPreference>()) { context.delete(preference) }
        for symptom in try context.fetch(FetchDescriptor<SymptomEntry>()) { context.delete(symptom) }
        for log in try context.fetch(FetchDescriptor<WaterLog>()) { context.delete(log) }
        for item in try context.fetch(FetchDescriptor<ShoppingItem>()) { context.delete(item) }
        for entry in try context.fetch(FetchDescriptor<MealPlanEntry>()) { context.delete(entry) }
        for recipe in try context.fetch(FetchDescriptor<CustomRecipe>()) { context.delete(recipe) }
        try context.save()

        for info in backup.customFoods {
            let food = CustomFood(stableID: info.id, name: info.name)
            food.apply(info)
            context.insert(food)
        }
        for record in backup.preferences {
            let preference = FoodPreference(foodID: record.foodID)
            preference.toleranceRaw = record.tolerance
            preference.isFavorite = record.isFavorite
            preference.note = record.note
            context.insert(preference)
        }
        for record in backup.meals {
            let meal = MealEntry(date: record.date, type: MealType(rawValue: record.type) ?? .snack, stableID: record.stableID)
            meal.freshnessRaw = record.freshness
            meal.placeRaw = record.place
            meal.recipeID = record.recipeID
            meal.note = record.note
            context.insert(meal)
            for itemRecord in record.items {
                let item = MealItem(foodID: itemRecord.foodID, name: itemRecord.name, grams: itemRecord.grams, position: itemRecord.order, stableID: itemRecord.stableID)
                context.insert(item)
                item.meal = meal
            }
        }
        for record in backup.symptoms {
            let symptom = SymptomEntry(date: record.date, type: SymptomType(rawValue: record.type) ?? .other, severity: record.severity, stableID: record.stableID)
            symptom.durationMinutes = record.durationMinutes
            symptom.note = record.note
            context.insert(symptom)
        }
        for record in backup.water {
            context.insert(WaterLog(date: record.date, milliliters: record.milliliters, stableID: record.stableID))
        }
        for record in backup.shopping {
            let item = ShoppingItem(
                name: record.name, category: ShoppingCategory(rawValue: record.category) ?? .other, amount: record.amount,
                foodID: record.foodID, source: record.source, stableID: record.stableID, createdAt: record.createdAt
            )
            item.isDone = record.isDone
            context.insert(item)
        }
        for record in backup.mealPlan {
            context.insert(MealPlanEntry(
                day: record.day, mealType: MealType(rawValue: record.mealType) ?? .dinner, recipeID: record.recipeID,
                servings: record.servings, stableID: record.stableID
            ))
        }
        for info in backup.customRecipes {
            let recipe = CustomRecipe(title: info.title, stableID: info.id)
            recipe.apply(info)
            context.insert(recipe)
        }
    }
}
