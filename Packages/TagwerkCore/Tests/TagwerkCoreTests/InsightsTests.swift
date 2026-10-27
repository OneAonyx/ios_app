import Foundation
import Testing
@testable import TagwerkCore

private let foods = FoodCatalog.bundled()

private func nutritionItem(_ id: String, _ grams: Double) -> MealItemFact {
    let food = foods.food(id: id)!
    return MealItemFact(foodID: id, name: food.name, grams: grams, score: food.score, flags: food.flags, proteinPer100: food.protein ?? 0, kcalPer100: food.kcal ?? 0)
}

@Suite("Einblicke: Check-ins")
struct CheckInTests {
    @Test func kindByTime() {
        #expect(CheckInKind.current(now: date(2026, 10, 27, 7), calendar: berlin) == .morning)
        #expect(CheckInKind.current(now: date(2026, 10, 27, 14), calendar: berlin) == nil)
        #expect(CheckInKind.current(now: date(2026, 10, 27, 21), calendar: berlin) == .evening)
    }

    @Test func scalesAndCompleteness() {
        #expect(CheckInScale.scales(for: .morning) == [.sleep, .energy])
        #expect(CheckInScale.mood.emoji(5) == "😄")
        #expect(CheckInScale.stress.label(5) == "sehr hoch")
        #expect(!CheckInScale.stress.higherIsBetter)
        let fact = CheckInFact(day: date(2026, 10, 27), sleep: 2, energy: 3)
        #expect(fact.isComplete(.morning))
        #expect(!fact.isComplete(.evening))
    }

    @Test func badSleepAndStressBecomeFactors() {
        let fact = CheckInFact(day: date(2026, 10, 27), sleep: 1, stress: 5)
        let factors = fact.factors(calendar: berlin)
        #expect(factors.map(\.key) == ["factor.sleep", "factor.stress"])
        #expect(factors[0].contains(date(2026, 10, 27, 12)))
        #expect(!factors[0].contains(date(2026, 10, 28, 0, 30)))
        #expect(CheckInFact(day: date(2026, 10, 27), sleep: 4, stress: 2).factors(calendar: berlin).isEmpty)
    }

    @Test func averages() {
        let averages = CheckInAverages.compute([
            CheckInFact(day: date(2026, 10, 26), sleep: 3, mood: 4),
            CheckInFact(day: date(2026, 10, 27), sleep: 4, mood: 5, stress: 2),
        ])
        #expect(averages.sleep == 3.5)
        #expect(averages.stress == 2)
        #expect(averages.energy == nil)
        #expect(CheckInAverages.format(averages.mood) == "4,5")
        #expect(CheckInAverages.format(nil) == "–")
    }

    @Test func sleepFactorShowsUpInPatterns() {
        var meals: [MealFact] = []
        var symptoms: [SymptomFact] = []
        var factors: [DayFactor] = []
        for day in 1...12 {
            let noon = date(2026, 10, day, 12)
            meals.append(MealFact(id: "m\(day)", date: noon, type: .lunch, items: [nutritionItem("haehnchenbrust", 150), nutritionItem("reis", 70)]))
            if day % 3 == 0 {
                factors += CheckInFact(day: date(2026, 10, day), sleep: 1).factors(calendar: berlin)
                symptoms.append(SymptomFact(date: noon.addingTimeInterval(3_600), type: .headache, severity: 3))
            }
        }
        let report = TriggerAnalysis.analyze(meals: meals, symptoms: symptoms, dayFactors: factors)
        #expect(report.findings.first?.key == "factor.sleep")
        #expect(report.findings.first?.name == "Schlecht geschlafen")
    }
}

@Suite("Einblicke: Wochenrückblick")
struct WeeklyReviewTests {
    private func input() -> WeeklyReviewInput {
        let monday = date(2026, 10, 26)
        let meal = MealFact(id: "1", date: date(2026, 10, 27, 12), type: .lunch, items: [nutritionItem("haehnchenbrust", 200), nutritionItem("magerquark", 500)])
        let tomato = MealFact(id: "2", date: date(2026, 10, 28, 12), type: .lunch, freshness: .reheated, items: [nutritionItem("tomate", 200)])
        return WeeklyReviewInput(
            weekStart: monday,
            tasksCompleted: 12,
            tasksOverdue: 2,
            medication: AdherenceSummary(taken: 20, skipped: 1, missed: 0),
            workouts: [
                WorkoutFact(date: date(2026, 10, 26, 18), title: "A · Push", workingSets: 21, volume: 9_800),
                WorkoutFact(date: date(2026, 10, 27, 18), title: "B · Pull", workingSets: 20, volume: 8_400),
            ],
            plannedWorkouts: 4,
            records: ["Neuer Rekord: Bankdrücken 85 kg"],
            nutritionDays: [
                NutritionDay(day: date(2026, 10, 27), meals: [meal], waterML: 2_500, proteinTarget: 148),
                NutritionDay(day: date(2026, 10, 28), meals: [tomato], waterML: 1_500, proteinTarget: 148),
            ],
            symptoms: [
                SymptomFact(date: date(2026, 10, 28, 14), type: .headache, severity: 3),
                SymptomFact(date: date(2026, 10, 28, 20), type: .headache, severity: 4),
            ],
            checkIns: [CheckInFact(day: monday, sleep: 4, energy: 4, mood: 4, stress: 2)],
            weightBefore: 82.4,
            weightAfter: 82.1
        )
    }

    @Test func sectionsAndHighlights() throws {
        let review = WeeklyReview.make(input(), calendar: berlin)
        #expect(review.title == "KW 44 · 26. Okt. – 1. Nov.")
        #expect(review.sections.map(\.id) == ["tasks", "medication", "training", "nutrition", "symptoms", "checkins", "weight"])
        let training = try #require(review.sections.first { $0.id == "training" })
        #expect(training.lines[0].value == "2 von 4")
        #expect(training.lines[0].tone == .attention)
        #expect(training.lines.first { $0.label == "Volumen" }?.value == "18.200 kg")
        let medication = try #require(review.sections.first { $0.id == "medication" })
        #expect(medication.lines[0].value == "95 %")
        let nutrition = try #require(review.sections.first { $0.id == "nutrition" })
        #expect(nutrition.lines[0].detail == "1 von 2 Tagen erhöht oder hoch")
        let symptoms = try #require(review.sections.first { $0.id == "symptoms" })
        #expect(symptoms.lines[0].value == "1 von 7")
        #expect(symptoms.lines[0].detail == "Kopfschmerz 2×")
        let weight = try #require(review.sections.first { $0.id == "weight" })
        #expect(weight.lines[0].detail == "−0,3 kg zur Vorwoche")
        #expect(review.highlights.contains("12 Aufgaben erledigt"))
        #expect(review.highlights.contains("Neuer Rekord: Bankdrücken 85 kg"))
        #expect(review.highlights.contains("6 Tage ohne Beschwerden"))
        #expect(review.plainText.hasPrefix("Wochenrückblick KW 44"))
        #expect(review.plainText.contains("- Einnahmetreue: 95 % (20 von 21 genommen)"))
    }

    @Test func emptyWeek() {
        let review = WeeklyReview.make(WeeklyReviewInput(weekStart: date(2026, 10, 26)), calendar: berlin)
        #expect(review.isEmpty)
        #expect(review.highlights.isEmpty)
    }

    @Test func reminderOnSundayEvening() throws {
        let tuesday = try #require(ReviewReminders.candidate(now: date(2026, 10, 27, 9), calendar: berlin))
        #expect(parts(tuesday.fireDate) == (2026, 11, 1, 18, 0))
        #expect(tuesday.id == "review.20261101")
        #expect(tuesday.referenceID == String(Int(date(2026, 10, 26).timeIntervalSince1970)))
        let lateSunday = try #require(ReviewReminders.candidate(now: date(2026, 11, 1, 19), calendar: berlin))
        #expect(parts(lateSunday.fireDate) == (2026, 11, 8, 18, 0))
    }
}

@Suite("Einblicke: Arztbericht")
struct DoctorReportTests {
    @Test func aggregates() {
        let rows = [
            DoctorReport.SymptomLogRow(date: date(2026, 10, 5, 13), type: .headache, severity: 3, durationMinutes: 60, note: ""),
            DoctorReport.SymptomLogRow(date: date(2026, 10, 6, 13), type: .headache, severity: 5, durationMinutes: nil, note: ""),
            DoctorReport.SymptomLogRow(date: date(2026, 10, 20, 9), type: .flush, severity: 2, durationMinutes: 30, note: "nach Pizza"),
            DoctorReport.SymptomLogRow(date: date(2026, 9, 1, 9), type: .flush, severity: 2, durationMinutes: nil, note: "außerhalb"),
        ]
        let report = DoctorReport.make(
            from: date(2026, 10, 1), to: date(2026, 10, 28), createdAt: date(2026, 10, 27, 12), name: "Test",
            medications: [
                .init(name: "Cetirizin 10 mg", schedule: "Täglich um 21:00", hint: "vor dem Schlafen", adherence: AdherenceSummary(taken: 25, skipped: 1, missed: 1), extraIntakes: 0, isActive: true),
                .init(name: "Ibuprofen 400 mg", schedule: "Bei Bedarf", hint: nil, adherence: nil, extraIntakes: 3, isActive: true),
            ],
            symptoms: rows, findings: [], mealCount: 60, avoidedFoods: ["Tomate"], cautionFoods: ["Banane"],
            loads: [HistamineLoad(points: 2, contributors: []), HistamineLoad(points: 12, contributors: [])],
            weights: [.init(date: date(2026, 10, 2), value: 82.6), .init(date: date(2026, 10, 26), value: 82.1)],
            checkIns: [CheckInFact(day: date(2026, 10, 10), sleep: 3)],
            calendar: berlin
        )
        #expect(report.symptomLog.count == 3, "Nur im Zeitraum")
        #expect(report.symptomTypes.map(\.type) == [.headache, .flush])
        #expect(report.symptomTypes.first?.averageSeverity == 4)
        #expect(report.symptomWeeks.count == 5)
        #expect(report.symptomWeeks.map(\.count) == [0, 2, 0, 1, 0])
        #expect(report.symptomDayCount(calendar: berlin) == 3)
        #expect(report.medications[0].adherenceText == "93 % (25 von 27)")
        #expect(report.medications[1].adherenceText == "3× genommen")
        #expect(report.elevatedLoadDays == 1)
        #expect(report.weightChangeText == "82,6 → 82,1 kg (−0,5 kg)")
        #expect(report.periodLabel(calendar: berlin) == "1. Okt. – 27. Okt. 2026")
        #expect(report.checkIns.sleep == 3)
    }
}

@Suite("Einblicke: Claude-Brücke")
struct ClaudeTaskTests {
    @Test func promptsContainFormatRefAndNoPersonalData() {
        let review = WeeklyReview.make(WeeklyReviewInput(weekStart: date(2026, 10, 26), tasksCompleted: 3), calendar: berlin)
        let prompt = ClaudePromptBuilder.weeklyReview(review, wish: "", ref: "ABC123")
        #expect(prompt.text.contains("\"format\":\"orbit.text.v1\""))
        #expect(prompt.text.contains("\"ref\":\"ABC123\""))
        #expect(prompt.text.contains("- Erledigt: 3"))
        #expect(prompt.includedData == ["Kennzahlen Aufgaben"])

        let food = ClaudePromptBuilder.food(name: "Quinoa-Riegel", ingredients: "Quinoa, Cashew, Datteln", ref: "R1")
        #expect(food.text.contains("ZUTATEN: Quinoa, Cashew, Datteln"))
        #expect(food.includedData == ["Name des Lebensmittels", "Zutatenliste"])

        let plan = ClaudePromptBuilder.trainingPlan(
            .init(goal: "Muskelaufbau", experience: "1 Jahr", sessionsPerWeek: 4, planJSON: "{}", recentSets: ["Bankdrücken: 80 × 8"],
                  stagnating: [], weeklyVolume: ["Brust 16"], wish: "Mehr Rücken", exerciseNames: ["Bankdrücken (Langhantel)"]),
            ref: "P1"
        )
        #expect(plan.text.contains("WUNSCH: Mehr Rücken"))
        #expect(plan.text.contains("orbit.plan.v1"))
        #expect(plan.includedData.contains("Dein Wunsch"))

        let recipes = ClaudePromptBuilder.recipes(.init(wish: "schnell", tolerated: ["Hähnchenbrust"], avoid: ["Tomate"]), ref: "X")
        #expect(recipes.text.contains("MEIDE ICH: Tomate"))
        let patterns = ClaudePromptBuilder.patterns(
            TriggerReport(findings: [], mealCount: 20, symptomCount: 4, baseline: 0.2), symptomSummary: ["Kopfschmerz 4×"],
            checkIns: nil, avoid: [], wish: "", ref: "Y"
        )
        #expect(patterns.text.contains("Keine auffälligen Muster."))
        #expect(ClaudePromptBuilder.makeRef().count == 6)
    }

    @Test func parsesPlanFromCodeBlock() throws {
        let response = """
        Hier ist dein Plan:
        ```json
        {"format":"orbit.plan.v1","ref":"P1","name":"Neu","days":[{"name":"Push","exercises":[{"name":"Bankdrücken (Langhantel)","sets":4,"reps":"6-8"}]}]}
        ```
        """
        guard case let .plan(template) = try ClaudeAnswerParser.parse(response, task: .trainingPlan, foods: foods) else {
            Issue.record("Kein Plan"); return
        }
        #expect(template.name == "Neu")
        #expect(ClaudeAnswerParser.ref(in: response) == "P1")
    }

    @Test func parsesTextWithAndWithoutJSON() throws {
        let json = #"{"format":"orbit.text.v1","ref":"A","title":"Deine Woche","text":"**Gut:** viel Training"}"#
        guard case let .text(title, body) = try ClaudeAnswerParser.parse(json, task: .weeklyReview, foods: foods) else {
            Issue.record("Kein Text"); return
        }
        #expect(title == "Deine Woche")
        #expect(body == "**Gut:** viel Training")
        guard case let .text(_, prose) = try ClaudeAnswerParser.parse("Du hast gut trainiert.", task: .patterns, foods: foods) else {
            Issue.record("Kein Text"); return
        }
        #expect(prose == "Du hast gut trainiert.")
        #expect(throws: ClaudeAnswerError.empty) { try ClaudeAnswerParser.parse("  ", task: .patterns, foods: foods) }
    }

    @Test func parsesFood() throws {
        let response = #"{"format":"orbit.food.v1","ref":"F","name":"Quinoa-Riegel","category":"sweets","score":2,"flags":["L","X"],"hint":"Cashew.","protein":8,"portion":40}"#
        guard case let .food(food) = try ClaudeAnswerParser.parse(response, task: .food, foods: foods) else {
            Issue.record("Kein Lebensmittel"); return
        }
        #expect(food.id == "custom-quinoa-riegel")
        #expect(food.category == .sweets)
        #expect(food.score == .poor)
        #expect(food.flags == [.liberator])
        #expect(food.portion == 40)
        #expect(food.isCustom)
        let wrong = #"{"format":"orbit.recipes.v1","name":"x","score":1}"#
        #expect(throws: ClaudeAnswerError.wrongFormat("orbit.recipes.v1")) { try ClaudeAnswerParser.parse(wrong, task: .food, foods: foods) }
    }

    @Test func parsesRecipesAndMatchesIngredients() throws {
        let response = """
        {"format":"orbit.recipes.v1","ref":"R","recipes":[{"title":"Pute mit Hirse","servings":2,"minutes":20,"tags":["Abend"],
         "ingredients":[{"name":"Putenbrust","grams":300},{"name":"Hirse","grams":120},{"name":"Zucchini","grams":200},{"name":"Drachenfrucht","grams":50}],
         "steps":["Hirse kochen.","Pute braten."]}]}
        """
        guard case let .recipes(recipes, newFoods) = try ClaudeAnswerParser.parse(response, task: .recipes, foods: foods) else {
            Issue.record("Keine Rezepte"); return
        }
        let recipe = try #require(recipes.first)
        #expect(recipe.id == "claude-pute-mit-hirse")
        #expect(recipe.ingredients.map(\.food) == ["putenbrust", "hirse", "zucchini", "custom-drachenfrucht"])
        #expect(newFoods.map(\.name) == ["Drachenfrucht"])
        #expect(recipe.isCustom)
        #expect(recipe.proteinPerServing(catalog: foods.adding(newFoods)) > 30)
    }

    @Test func insightsBackupRoundTrip() throws {
        let backup = InsightsBackup(
            checkIns: [CheckInRecord(stableID: "c1", day: date(2026, 10, 27), sleep: 3, sleepHours: 7.5, energy: 4, mood: nil, stress: nil, note: "", updatedAt: date(2026, 10, 27, 8))],
            claudeExchanges: [ClaudeExchangeRecord(stableID: "x1", task: ClaudeTask.food.rawValue, ref: "ABC", title: "Quinoa", prompt: "…", response: "{}", status: ClaudeExchangeStatus.answered.rawValue, createdAt: date(2026, 10, 27, 9), answeredAt: nil)]
        )
        let document = BackupDocument(createdAt: date(2026, 10, 27), appVersion: "0.6.0", lists: [], tasks: [], insights: backup)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(BackupDocument.self, from: encoder.encode(document)).insights == backup)
    }
}
