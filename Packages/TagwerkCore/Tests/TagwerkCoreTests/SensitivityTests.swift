import Foundation
import Testing
@testable import TagwerkCore

@Suite("Ernährung: Verträglichkeits-Profile")
struct SensitivityTests {
    let foods = FoodCatalog.bundled()
    let rules = IngredientAnalyzer.bundled()

    @Test func profileStorage() {
        #expect(SensitivityProfile.decode(nil) == .standard)
        #expect(SensitivityProfile.decode("") == .standard)
        #expect(SensitivityProfile.decode("none").active.isEmpty)
        #expect(SensitivityProfile.decode("histamine,lactose").ordered == [.lactose, .histamine])
        #expect(SensitivityProfile.standard.encoded == "lactose,fructose,fat")
        #expect(SensitivityProfile(active: []).encoded == "none")
        #expect(SensitivityProfile.standard.summary == "Laktose, Fruktose, Fett")
    }

    @Test func everyFoodHasFatAndLexiconStaysValid() {
        #expect(foods.validationIssues.isEmpty, "\(foods.validationIssues)")
        let missing = foods.foods.filter { $0.ratings.fat == nil }.map(\.id)
        #expect(missing.isEmpty, "Ohne Fett: \(missing)")
        #expect(foods.foods.count >= 360)
    }

    @Test func standardProfileRatesLactoseFructoseAndFat() {
        let catalog = foods.applying(.standard)
        func score(_ id: String) -> FoodScore? { catalog.food(id: id)?.score }
        #expect(score("milch") == .bad, "Glas Milch: etwa 10 g Laktose")
        #expect(score("milch-laktosefrei") == .good)
        #expect(score("magerquark-laktosefrei") == .good)
        #expect(score("parmesan") == .good, "Hartkäse ist praktisch laktosefrei")
        #expect(score("apfel") == .bad)
        #expect(score("heidelbeeren") == .moderate)
        #expect(score("kartoffelchips") == .poor, "50 g Chips: etwa 17 g Fett")
        #expect(score("wagyu") == .bad)
        #expect(score("haehnchenbrust") == .good)
        #expect(score("reis") == .good)
        // Histamin zählt im Standard nicht mehr.
        #expect(score("tomate") == .good)
        #expect(foods.applying(SensitivityProfile(active: [.histamine])).food(id: "tomate")?.score == .poor)
        #expect(catalog.food(id: "milch")?.flags.contains(.lactose) == true)
        #expect(catalog.food(id: "apfel")?.flags.contains(.sorbitol) == true)
    }

    @Test func amountMatters() throws {
        let catalog = foods.applying(.standard)
        let milk = try #require(catalog.food(id: "milch"))
        #expect(catalog.score(milk, grams: 20) == .moderate, "Schuss Milch im Kaffee: 1 g Laktose")
        #expect(catalog.score(milk, grams: 200) == .bad)
        let oil = try #require(catalog.food(id: "olivenoel"))
        #expect(catalog.score(oil, grams: 10) == .moderate)
        #expect(catalog.score(oil, grams: 40) == .bad)
    }

    @Test func heavyMealsAndLactoseCountInDailyLoad() throws {
        let catalog = foods.applying(.standard)
        func item(_ id: String, _ grams: Double) throws -> MealItemFact {
            let food = try #require(catalog.food(id: id))
            return MealItemFact(food: food, grams: grams, score: catalog.score(food, grams: grams))
        }
        let burger = MealFact(id: "1", date: .now, type: .dinner, items: [try item("wagyu", 200), try item("pommes", 200)])
        #expect(burger.isHeavy)
        #expect(burger.fat > 80)
        let light = MealFact(id: "2", date: .now, type: .lunch, items: [try item("haehnchenbrust", 150), try item("reis", 80)])
        #expect(!light.isHeavy)

        let heavyLoad = DailyLoad.compute([burger], sensitivities: SensitivityProfile.standard.active)
        #expect(heavyLoad.contributors.contains { $0.name == "Große oder fettige Mahlzeit" })
        #expect(heavyLoad.level != .calm)

        let milkMeal = MealFact(id: "3", date: .now, type: .breakfast, items: [try item("milch", 300)])
        #expect(milkMeal.lactose > MealLimits.lactosePerMeal)
        let milkLoad = DailyLoad.compute([milkMeal], sensitivities: [.lactose])
        #expect(milkLoad.contributors.contains { $0.name == "Viel Laktose auf einmal" })

        // Reste zählen nur im Histamin-Profil.
        var leftovers = light
        leftovers.freshness = .leftover
        #expect(DailyLoad.compute([leftovers], sensitivities: [.lactose]).points == 0)
        #expect(DailyLoad.compute([leftovers], sensitivities: [.histamine]).points > 0)

        let day = NutritionDay(day: .now, meals: [light, milkMeal], waterML: 0, proteinTarget: 150, sensitivities: SensitivityProfile.standard.active)
        #expect(day.sensitivityLines.contains { $0.hasPrefix("Laktose 14,4 g") })
        #expect(day.sensitivityLines.contains { $0.hasPrefix("Fett") })
    }

    @Test func ingredientRulesFollowProfile() {
        let text = "Zucker, Magermilchpulver, Hefeextrakt, Sorbit, Zwiebelpulver"
        let standard = rules.filtered(SensitivityProfile.standard.active).analyze(text)
        let ids = Set(standard.hits.map(\.rule.id))
        #expect(ids.contains("lac-milchpulver"))
        #expect(ids.contains("fru-sorbit"))
        #expect(ids.contains("fru-zwiebel-knoblauch"))
        #expect(!ids.contains("hefeextrakt"), "Histamin-Regeln sind im Standard aus")
        #expect(standard.worstScore == .bad)

        let all = rules.analyze(text)
        #expect(all.hits.contains { $0.rule.id == "hefeextrakt" })
        #expect(all.worstScore(for: .histamine) == .bad)
        #expect(all.flags.contains(.lactose) && all.flags.contains(.sorbitol))

        let lactoseFree = rules.analyze("Laktosefreie Milch, Milcheiweiß, Milchsäurebakterien")
        #expect(!lactoseFree.hits.contains { $0.rule.sensitivity == .lactose })
        let lacticAcid = rules.analyze("Wasser, Milchsäure, Salz")
        #expect(!lacticAcid.hits.contains { $0.rule.sensitivity == .lactose }, "Milchsäure enthält keine Laktose")
        let sorbitE = rules.analyze("Süßungsmittel: E 420, Aroma")
        #expect(sorbitE.hits.contains { $0.rule.id == "fru-sorbit" })
    }

    @Test func scannedProductKeepsAllRatings() throws {
        let json = """
        {"status":1,"product":{"product_name_de":"Kartoffelchips Paprika","brands":"Test",
         "ingredients_text_de":"Kartoffeln, Sonnenblumenöl, Molkenpulver, Zucker, Paprika",
         "nutriments":{"proteins_100g":6,"energy-kcal_100g":540,"fat_100g":34}}}
        """
        let product = try OpenFoodFacts.parse(Data(json.utf8), barcode: "4001234567890")
        #expect(product.fatPer100 == 34)
        let food = product.foodInfo(report: rules.analyze(product.ingredients ?? ""), catalog: foods)
        #expect(food.flags.contains(.fatRich))
        #expect(food.flags.contains(.lactose))
        #expect(food.ratings.fat == 30)
        #expect(food.applying(.standard).score == .bad)
    }

    @Test func claudeFoodAnswerCarriesRatings() throws {
        let response = """
        {"format":"orbit.food.v1","ref":"R1","name":"Sahnejoghurt Erdbeere","category":"dairy","score":1,"flags":[],"lactose":4,"fructose":1,"fat":10,"protein":3,"kcal":120,"portion":150}
        """
        guard case .food(let food) = try ClaudeAnswerParser.parse(response, task: .food, foods: foods) else {
            Issue.record("Kein Lebensmittel")
            return
        }
        #expect(food.ratings.lactose == 4)
        #expect(food.flags.contains(.lactose))
        #expect(food.applying(.standard).score == .poor, "150 g mit 4 g/100 g: 6 g Laktose")

        let prompt = ClaudePromptBuilder.food(name: "Test", profile: .standard, ref: "R1")
        #expect(prompt.text.contains("Laktoseintoleranz"))
        #expect(!prompt.text.contains("Histaminintoleranz"))
        let recipes = ClaudePromptBuilder.recipes(.init(wish: "", tolerated: [], avoid: []), profile: .standard, ref: "R2")
        #expect(recipes.text.contains("laktosefrei"))
        #expect(!recipes.text.contains("histaminarm"))
    }

    @Test func roundTripKeepsRatings() throws {
        let food = try #require(foods.food(id: "apfel"))
        let data = try JSONEncoder().encode(food)
        let decoded = try JSONDecoder().decode(FoodInfo.self, from: data)
        #expect(decoded.ratings == food.ratings)
        #expect(decoded.histamineHint == food.histamineHint)
    }
}
