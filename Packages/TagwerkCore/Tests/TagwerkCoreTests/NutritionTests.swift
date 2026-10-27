import Foundation
import Testing
@testable import TagwerkCore

private let foods = FoodCatalog.bundled()
private let analyzer = IngredientAnalyzer.bundled()
private let recipes = RecipeCatalog.bundled()

private func item(_ id: String, _ grams: Double, tolerance: Tolerance = .unknown) -> MealItemFact {
    let food = foods.food(id: id)!
    return MealItemFact(
        foodID: id, name: food.name, grams: grams, score: tolerance.effectiveScore(general: food.score),
        flags: food.flags, proteinPer100: food.protein ?? 0, kcalPer100: food.kcal ?? 0
    )
}

private func meal(_ id: String, _ when: Date, _ items: [MealItemFact], freshness: Freshness = .fresh, place: MealPlace = .home) -> MealFact {
    MealFact(id: id, date: when, type: .lunch, freshness: freshness, place: place, items: items)
}

@Suite("Ernährung: Inhalte")
struct NutritionContentTests {
    @Test func lexiconIsCompleteAndClean() throws {
        #expect(foods.foods.count >= 300)
        #expect(foods.validationIssues == [])
        // Jede Bewertung kommt vor, jede Kategorie mit Lebensmitteln.
        for score in HistamineScore.allCases {
            #expect(foods.foods.contains { $0.score == score }, "\(score)")
        }
        let tomato = try #require(foods.food(id: "tomate"))
        #expect(tomato.score == .poor)
        #expect(tomato.flags.contains(.liberator))
        #expect(foods.food(id: "haehnchenbrust")?.score == .good)
        #expect(foods.food(id: "parmesan")?.score == .bad)
        #expect(foods.food(id: "spinat")?.score == .bad)
        #expect(foods.food(id: "rotwein")?.flags.contains(.daoBlocker) == true)
        #expect((foods.food(id: "magerquark")?.protein ?? 0) >= 10)
    }

    @Test func searchFindsNamesAliasesAndPlurals() {
        #expect(foods.search("tomat").first?.id == "tomate")
        #expect(foods.search("Möhre").first?.id == "karotte")
        #expect(foods.search("hähnchen").first?.id == "haehnchenbrust")
        #expect(foods.bestMatch(for: "Tomaten")?.id == "tomate")
        #expect(foods.bestMatch(for: "Avocados")?.id == "avocado")
        #expect(foods.bestMatch(for: "Hähnchenbrustfilet")?.id == "haehnchenbrust")
        #expect(foods.bestMatch(for: "Quark")?.id == "magerquark")
        #expect(foods.search("").count == foods.foods.count)
        #expect(foods.search("xyzxyz").isEmpty)
    }

    @Test func groupedKeepsCategoryOrder() {
        let groups = foods.grouped()
        #expect(groups.first?.0 == .vegetables)
        #expect(groups.map(\.1.count).reduce(0, +) == foods.foods.count)
    }

    @Test func customFoodsReplaceAndExtend() {
        let custom = FoodInfo(id: "barcode-4000000000000", name: "Testjoghurt", category: .dairy, score: .moderate, isCustom: true)
        let extended = foods.adding([custom])
        #expect(extended.foods.count == foods.foods.count + 1)
        #expect(extended.food(id: custom.id)?.isCustom == true)
    }

    @Test func toleranceOverridesGeneralScore() {
        #expect(Tolerance.ok.effectiveScore(general: .bad) == .good)
        #expect(Tolerance.caution.effectiveScore(general: .good) == .poor)
        #expect(Tolerance.caution.effectiveScore(general: .bad) == .bad)
        #expect(Tolerance.avoid.effectiveScore(general: .good) == .bad)
        #expect(Tolerance.unknown.effectiveScore(general: .moderate) == .moderate)
    }

    @Test func siriSentence() throws {
        let avocado = try #require(foods.food(id: "avocado"))
        let text = FoodAnswer.sentence(for: avocado, tolerance: .avoid)
        #expect(text.hasPrefix("Avocado: sehr schlecht verträglich (3 von 3), histaminreich."))
        #expect(text.contains("Bei dir: meiden."))
    }

    @Test func recipesUseLexiconAndAreLowHistamine() throws {
        #expect(recipes.recipes.count >= 30)
        for recipe in recipes.recipes {
            for ingredient in recipe.ingredients {
                #expect(foods.food(id: ingredient.food) != nil, "\(recipe.id): \(ingredient.food)")
            }
            #expect(recipe.worstScore(catalog: foods) <= .moderate, "\(recipe.id)")
            #expect(!recipe.steps.isEmpty)
        }
        let highProtein = recipes.recipes.filter { $0.proteinPerServing(catalog: foods) >= 25 }
        #expect(highProtein.count >= 25)
        #expect(recipes.tags.first == "Frühstück")
    }
}

@Suite("Ernährung: Zutatenliste")
struct IngredientTests {
    @Test func findsCriticalIngredientsAndENumbers() {
        let text = "Tomaten (45 %), Wasser, Zucker, Hefeextrakt, Branntweinessig, Salz, Konservierungsstoff: E 211, Antioxidationsmittel: E-224, Aroma"
        let report = analyzer.analyze(text)
        let ids = Set(report.hits.map(\.rule.id))
        #expect(ids.contains("tomate"))
        #expect(ids.contains("hefeextrakt"))
        #expect(ids.contains("branntweinessig"))
        #expect(ids.contains("benzoate"))
        #expect(ids.contains("sulfite"))
        #expect(!ids.contains("essig"), "Branntweinessig zählt als eigene, mildere Regel")
        #expect(report.worstScore == .bad)
        #expect(report.hits.first?.score == .bad)
        #expect(report.summary.hasPrefix("Sehr kritisch: "))
        #expect(report.ingredientCount >= 8)
    }

    @Test func avoidsFalsePositives() {
        let text = "Schweinefleisch, Olivenöl, Zitronensäure, Kakaobutter, Gewürze, Seelachs, Organisch, Tomatenmark"
        let ids = Set(analyzer.analyze(text).hits.map(\.rule.id))
        #expect(!ids.contains("wein"), "„Schwein“ ist kein Wein")
        #expect(!ids.contains("olive"))
        #expect(!ids.contains("zitrone"))
        #expect(!ids.contains("kakao"))
        #expect(!ids.contains("hefeextrakt"), "„Gewürze“ ist keine Würze")
        #expect(!ids.contains("lachs"))
        #expect(!ids.contains("anis"))
        #expect(ids.contains("tomatenmark"))
        #expect(!ids.contains("tomate"), "Längstes Stichwort gewinnt")
    }

    @Test func unremarkableList() {
        let report = analyzer.analyze("Hähnchenbrustfilet, Wasser, Salz, Reis")
        #expect(report.isEmpty)
        #expect(report.summary == "Keine bekannten Auslöser in 4 Zutaten gefunden.")
        #expect(analyzer.analyze("").summary == "Keine Zutaten erkannt.")
    }

    @Test func eNumberParsing() {
        #expect(IngredientAnalyzer.eNumbers(in: NameMatcher.normalize("E 220, E621, e-160b, Ei")) == ["220", "621", "160b"])
        let report = analyzer.analyze("Farbstoff: E 160b")
        #expect(report.hits.first?.rule.id == "annatto")
    }
}

@Suite("Ernährung: Tageslast und Ziele")
struct LoadTests {
    @Test func freshLowHistamineMealIsCalm() {
        let lunch = meal("1", date(2026, 10, 27, 12), [item("haehnchenbrust", 150), item("reis", 70), item("zucchini", 200)])
        let load = HistamineLoad.compute([lunch])
        #expect(load.points == 0)
        #expect(load.level == .calm)
    }

    @Test func pizzaAndLeftoversRaiseTheLoad() {
        let pizza = meal("1", date(2026, 10, 27, 19), [item("pizza", 300)])
        let load = HistamineLoad.compute([pizza])
        #expect(load.points == 18)
        #expect(load.level == .high)
        #expect(load.contributors.first?.name == "Pizza")

        let tomato = meal("2", date(2026, 10, 27, 12), [item("tomate", 100)])
        #expect(HistamineLoad.compute([tomato]).points == 3)
        let reheated = meal("3", date(2026, 10, 27, 12), [item("tomate", 100)], freshness: .reheated)
        let reheatedLoad = HistamineLoad.compute([reheated])
        #expect(reheatedLoad.points == 6)
        #expect(reheatedLoad.level == .elevated)
        #expect(reheatedLoad.contributors.map(\.name).contains("Aufgewärmt"))
    }

    @Test func toleranceChangesLoad() {
        let mine = meal("1", date(2026, 10, 27, 12), [item("tomate", 100, tolerance: .ok)])
        #expect(HistamineLoad.compute([mine]).points == 0)
    }

    @Test func proteinAndWaterTargets() {
        #expect(NutritionTargets.proteinTarget(bodyweight: 82.4) == 148)
        #expect(NutritionTargets.proteinTarget(bodyweight: nil) == 144)
        #expect(NutritionTargets.proteinTarget(bodyweight: 80, perKg: 2.2) == 176)
        let day = NutritionDay(
            day: date(2026, 10, 27),
            meals: [meal("1", date(2026, 10, 27, 8), [item("magerquark", 250), item("haferflocken", 50)])],
            waterML: 1500, proteinTarget: 150
        )
        #expect(abs(day.protein - 36.5) < 0.01)
        #expect(day.proteinLabel == "37 von 150 g")
        #expect(day.waterLabel == "1,5 von 2,5 l")
        #expect(abs(day.waterFraction - 0.6) < 0.001)
    }

    @Test func mealTypeByTime() {
        #expect(MealType.suggested(for: date(2026, 10, 27, 7, 30), calendar: berlin) == .breakfast)
        #expect(MealType.suggested(for: date(2026, 10, 27, 12, 30), calendar: berlin) == .lunch)
        #expect(MealType.suggested(for: date(2026, 10, 27, 15, 30), calendar: berlin) == .snack)
        #expect(MealType.suggested(for: date(2026, 10, 27, 19), calendar: berlin) == .dinner)
    }
}

@Suite("Ernährung: Symptome und Muster")
struct TriggerTests {
    @Test func symptomParser() {
        #expect(SymptomParser.parse("Kopfschmerz 4")?.type == .headache)
        #expect(SymptomParser.parse("Kopfschmerz 4")?.severity == 4)
        #expect(SymptomParser.parse("übelkeit")?.severity == 3)
        #expect(SymptomParser.parse("laufende Nase 2")?.type == .runnyNose)
        #expect(SymptomParser.parse("morgen zahnarzt") == nil)
    }

    @Test func findsFoodFollowedBySymptoms() {
        var meals: [MealFact] = []
        var symptoms: [SymptomFact] = []
        // 14 Tage: Mittags Hähnchen, an 6 Tagen zusätzlich Tomate, danach 1 Std. später Kopfschmerz (5 von 6).
        for day in 1...14 {
            let noon = date(2026, 10, day, 12)
            var items = [item("haehnchenbrust", 150), item("reis", 70)]
            if day <= 6 {
                items.append(item("tomate", 100))
                if day != 3 { symptoms.append(SymptomFact(date: noon.addingTimeInterval(3_600), type: .headache, severity: 3)) }
            }
            meals.append(meal("m\(day)", noon, items))
            meals.append(meal("a\(day)", date(2026, 10, day, 19), [item("kartoffel", 250), item("magerquark", 150)]))
        }
        let report = TriggerAnalysis.analyze(meals: meals, symptoms: symptoms)
        #expect(report.hasEnoughData)
        let first = report.findings.first
        #expect(first?.key == "tomate")
        #expect(first?.occurrences == 6)
        #expect(first?.followedSoon == 5)
        #expect(first?.sentence == "5 von 6 Mal Beschwerden innerhalb von 3 Std.")
        #expect((first?.lift ?? 0) > 2)
        #expect(!report.findings.contains { $0.key == "haehnchenbrust" }, "Täglich gegessen, keine Auffälligkeit")
        #expect(!report.findings.contains { $0.key == "kartoffel" })
        // Nur Übelkeit: keine Funde.
        #expect(TriggerAnalysis.analyze(meals: meals, symptoms: symptoms, only: .nausea).findings.isEmpty)
    }

    @Test func leftoversAppearAsFactor() {
        var meals: [MealFact] = []
        var symptoms: [SymptomFact] = []
        for day in 1...12 {
            let noon = date(2026, 10, day, 12)
            let leftovers = day % 3 == 0
            meals.append(meal("m\(day)", noon, [item("haehnchenbrust", 150)], freshness: leftovers ? .leftover : .fresh))
            if leftovers { symptoms.append(SymptomFact(date: noon.addingTimeInterval(5_400), type: .flush, severity: 2)) }
        }
        let report = TriggerAnalysis.analyze(meals: meals, symptoms: symptoms)
        #expect(report.findings.first?.key == "factor.leftovers")
        #expect(report.findings.first?.isFactor == true)
    }

    @Test func tooLittleData() {
        let report = TriggerAnalysis.analyze(meals: [meal("1", date(2026, 10, 1, 12), [item("tomate", 100)])], symptoms: [])
        #expect(!report.hasEnoughData)
        #expect(report.missingDataText == "Noch 9 Mahlzeiten und 3 Symptome eintragen, dann zeigt Orbit erste Muster.")
    }

    @Test func symptomWeights() {
        #expect(TriggerAnalysis.weight(minutesAfterMeal: -5) == 0)
        #expect(TriggerAnalysis.weight(minutesAfterMeal: 60) == 1)
        #expect(TriggerAnalysis.weight(minutesAfterMeal: 300) == 0.5)
        #expect(TriggerAnalysis.weight(minutesAfterMeal: 1_000) == 0.2)
        #expect(TriggerAnalysis.weight(minutesAfterMeal: 2_000) == 0)
    }
}

@Suite("Ernährung: Einkauf, Barcode, Sicherung")
struct ShoppingAndScanTests {
    @Test func shoppingNeedsMergeAndScale() throws {
        let rice = try #require(recipes.recipe(id: "haehnchen-reis-zucchini"))
        let curry = try #require(recipes.recipe(id: "kurkuma-haehnchen-kokos"))
        let needs = ShoppingPlanner.needs(for: [(rice, 2), (curry, 4)], catalog: foods)
        let chicken = try #require(needs.first { $0.foodID == "haehnchenbrust" })
        #expect(chicken.grams == 900)
        #expect(chicken.amountText == "900 g")
        #expect(!needs.contains { $0.foodID == "salz" })
        #expect(needs.first?.category == .produce)
        let rices = try #require(needs.first { $0.foodID == "reis" })
        #expect(rices.grams == 420)
        #expect(ShoppingNeed.amount(grams: 1_250, isLiquid: false) == "1,3 kg")
        #expect(ShoppingNeed.amount(grams: 750, isLiquid: true) == "750 ml")
    }

    @Test func shoppingCategoryGuess() {
        #expect(ShoppingCategory.guess(for: "Tomaten", catalog: foods) == .produce)
        #expect(ShoppingCategory.guess(for: "Hähnchenbrust", catalog: foods) == .freshMeat)
        #expect(ShoppingCategory.guess(for: "Quark", catalog: foods) == .dairy)
        #expect(ShoppingCategory.guess(for: "TK Erbsen", catalog: foods) == .frozen)
        #expect(ShoppingCategory.guess(for: "Zahnpasta", catalog: foods) == .other)
    }

    @Test func recipeLabelsAndMealItems() throws {
        let oats = try #require(recipes.recipe(id: "overnight-oats-quark"))
        #expect(oats.label(for: oats.ingredients[0], catalog: foods) == "60 g Haferflocken")
        #expect(oats.label(for: oats.ingredients[4], catalog: foods) == "1 EL Chiasamen")
        #expect(oats.label(for: oats.ingredients[0], servings: 2, catalog: foods) == "120 g Haferflocken")
        let frikadellen = try #require(recipes.recipe(id: "frikadellen"))
        let items = frikadellen.mealItems(portions: 1)
        #expect(!items.contains { $0.foodID == "salz" })
        #expect(items.first { $0.foodID == "rinderhack" }?.grams == 166.7)
    }

    @Test func barcodeValidation() {
        #expect(Barcode.isValid("4006381333931"))
        #expect(Barcode.isValid("96385074"))
        #expect(Barcode.isValid("036000291452"))
        #expect(!Barcode.isValid("4006381333932"))
        #expect(!Barcode.isValid("abc"))
        #expect(Barcode.clean("4 006381-333931") == "4006381333931")
    }

    @Test func parsesOpenFoodFactsResponse() throws {
        let json = """
        {"code":"4006381333931","status":1,"product":{"product_name":"Tomato Ketchup","product_name_de":"Tomatenketchup",
         "brands":"Testmarke, Andere","ingredients_text_de":"Tomaten, Branntweinessig, Zucker, Salz, Gewürze",
         "nutriments":{"proteins_100g":1.2,"energy-kcal_100g":102},"quantity":"500 ml"}}
        """
        let product = try OpenFoodFacts.parse(Data(json.utf8), barcode: "4006381333931")
        #expect(product.name == "Tomatenketchup")
        #expect(product.brand == "Testmarke")
        #expect(product.displayName == "Testmarke Tomatenketchup")
        #expect(product.proteinPer100 == 1.2)
        #expect(product.kcalPer100 == 102)
        let report = analyzer.analyze(product.ingredients ?? "")
        let food = product.foodInfo(report: report, catalog: foods)
        #expect(food.id == "barcode-4006381333931")
        #expect(food.score == .poor)
        #expect(food.isCustom)
        #expect(food.category == .sauces)

        let missing = Data(#"{"status":0,"status_verbose":"product not found"}"#.utf8)
        #expect(throws: OpenFoodFacts.ParseError.notFound) { try OpenFoodFacts.parse(missing, barcode: "1") }
        #expect(OpenFoodFacts.productURL(barcode: "4006381333931")?.absoluteString.contains("/api/v2/product/4006381333931.json") == true)
    }

    @Test func backupAndSnapshotRoundTrip() throws {
        let backup = NutritionBackup(
            customFoods: [FoodInfo(id: "barcode-1", name: "Test", category: .dairy, score: .moderate, isCustom: true, barcode: "1")],
            preferences: [FoodPreferenceRecord(foodID: "tomate", tolerance: Tolerance.ok.rawValue, isFavorite: true, note: "")],
            meals: [MealRecord(
                stableID: "m1", date: date(2026, 10, 27, 12), type: MealType.lunch.rawValue, freshness: Freshness.leftover.rawValue,
                place: MealPlace.home.rawValue, recipeID: nil, note: "",
                items: [MealItemRecord(stableID: "i1", foodID: "tomate", name: "Tomate", grams: 100, order: 0)]
            )],
            symptoms: [SymptomRecord(stableID: "s1", date: date(2026, 10, 27, 13), type: SymptomType.headache.rawValue, severity: 3, durationMinutes: 60, note: "")],
            water: [WaterRecord(stableID: "w1", date: date(2026, 10, 27, 9), milliliters: 250)],
            shopping: [ShoppingRecord(stableID: "sh1", name: "Reis", category: ShoppingCategory.pantry.rawValue, amount: "1 kg", foodID: "reis", isDone: false, createdAt: date(2026, 10, 27), source: "manual")],
            mealPlan: [MealPlanRecord(stableID: "p1", day: date(2026, 10, 28), mealType: MealType.dinner.rawValue, recipeID: "frikadellen", servings: 2)],
            customRecipes: []
        )
        let document = BackupDocument(createdAt: date(2026, 10, 27), appVersion: "0.5.0", lists: [], tasks: [], nutrition: backup)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(BackupDocument.self, from: encoder.encode(document))
        #expect(restored.nutrition == backup)

        let snapshot = NutritionWidgetSnapshot(
            writtenAt: date(2026, 10, 27, 13), day: date(2026, 10, 27), loadPoints: 6, levelRaw: HistamineLoad.Level.elevated.rawValue,
            protein: 96, proteinTarget: 150, waterML: 1500, waterTarget: 2500, mealCount: 2, topContributors: ["Tomate", "Reste"]
        )
        #expect(snapshot.sentence(now: date(2026, 10, 27, 14), calendar: berlin) == "Histamin heute: erhöht (vor allem Tomate, Reste). Eiweiß 96 von 150 g, Wasser 1,5 von 2,5 l.")
        let tomorrow = snapshot.current(now: date(2026, 10, 28, 8), calendar: berlin)
        #expect(tomorrow.waterML == 0)
        #expect(tomorrow.proteinTarget == 150)
        #expect(tomorrow.level == .calm)
    }
}
