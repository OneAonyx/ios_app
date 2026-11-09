import Foundation
import Testing
@testable import TagwerkCore

@Suite("Ernährung: Wochenplan-Vorlage")
struct MealPlanTemplateTests {
    let foods = FoodCatalog.bundled().applying(.standard)
    let recipes = RecipeCatalog.bundled()

    @Test func planIsCompleteAndValid() throws {
        let plan = try #require(MealPlanTemplate.bundledWeek())
        #expect(plan.validationIssues(recipes: recipes).isEmpty, "\(plan.validationIssues(recipes: recipes))")
        #expect(plan.orderedDays.first?.weekday == 2, "Montag zuerst")
        #expect(plan.orderedDays.last?.weekday == 1)
        #expect(plan.days.allSatisfy { day in MealType.allCases.allSatisfy { day.options(for: $0).count >= 2 } }, "Jede Mahlzeit hat eine Alternative")
        #expect(plan.recipeIDs.count >= 20, "abwechslungsreich")
        #expect(!plan.guidelines.isEmpty)
    }

    @Test func planFitsLactoseFructoseFatAndNoFish() throws {
        let plan = try #require(MealPlanTemplate.bundledWeek())
        for id in plan.recipeIDs {
            let recipe = try #require(recipes.recipe(id: id))
            let categories = recipe.ingredients.compactMap { foods.food(id: $0.food)?.category }
            #expect(!categories.contains(.fish), "\(id) enthält Fisch")
            let lactose = recipe.ingredients.reduce(0.0) { $0 + (foods.food(id: $1.food)?.lactose(grams: $1.grams) ?? 0) } / Double(recipe.servings)
            #expect(lactose < 1, "\(id): \(lactose) g Laktose je Portion")
            #expect(recipe.fatPerServing(catalog: foods) <= 23, "\(id): \(recipe.fatPerServing(catalog: foods)) g Fett")
            #expect(recipe.worstScore(catalog: foods) <= .moderate, "\(id) hat eine schlecht verträgliche Zutat")
            for item in recipe.ingredients {
                let food = try #require(foods.food(id: item.food))
                #expect(food.ratings.fructose <= .moderate, "\(id): \(food.name) mit viel Fruktose")
            }
        }
    }

    @Test func dailyProteinAndEnergyFitMuscleGain() throws {
        let plan = try #require(MealPlanTemplate.bundledWeek())
        for day in plan.days {
            var protein = 0.0
            var kcal = 0.0
            for meal in MealType.allCases {
                let recipe = try #require(recipes.recipe(id: day.options(for: meal)[0]))
                protein += recipe.proteinPerServing(catalog: foods)
                kcal += recipe.kcalPerServing(catalog: foods)
            }
            #expect(protein >= 145, "\(day.title): \(Int(protein)) g Eiweiß")
            #expect((2_000...2_800).contains(kcal), "\(day.title): \(Int(kcal)) kcal")
        }
    }

    @Test func entriesForAWeekUseChoices() throws {
        let plan = try #require(MealPlanTemplate.bundledWeek())
        let monday = date(2026, 11, 9)
        let entries = plan.entries(weekStart: monday, calendar: berlin)
        #expect(entries.count == 28)
        #expect(entries.first?.recipeID == "wp-protein-oats-beeren")
        let key = MealPlanTemplate.choiceKey(weekday: 2, meal: .breakfast)
        let chosen = plan.entries(weekStart: monday, choices: [key: "wp-skyr-bowl-banane"], calendar: berlin)
        #expect(chosen.first?.recipeID == "wp-skyr-bowl-banane")
        let invalid = plan.entries(weekStart: monday, choices: [key: "gibt-es-nicht"], calendar: berlin)
        #expect(invalid.first?.recipeID == "wp-protein-oats-beeren")
    }
}
