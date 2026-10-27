import Foundation
import SwiftData
import TagwerkCore

/// Baut Claude-Anfragen aus den eigenen Daten und übernimmt Claudes Antworten.
@MainActor
public enum ClaudeBridgeActions {
    public static let defaultGoal = "Muskelaufbau (Hypertrophie), Oberkörper"
    public static let defaultExperience = "etwa 1 Jahr Krafttraining"

    public static var trainingGoal: String {
        let stored = UserDefaults.standard.string(forKey: SettingsKeys.trainingGoal) ?? ""
        return stored.isEmpty ? defaultGoal : stored
    }

    public static var trainingExperience: String {
        let stored = UserDefaults.standard.string(forKey: SettingsKeys.trainingExperience) ?? ""
        return stored.isEmpty ? defaultExperience : stored
    }

    // MARK: Anfragen

    public static func trainingPrompt(wish: String, ref: String = ClaudePromptBuilder.makeRef(), now: Date = .now, calendar: Calendar, in context: ModelContext) -> ClaudePrompt? {
        guard let plan = TrainingActions.activePlan(in: context) else { return nil }
        let catalog = TrainingActions.catalog(in: context)
        return ClaudePromptBuilder.trainingPlan(
            trainingContext(plan: plan, wish: wish, catalog: catalog, now: now, calendar: calendar, in: context),
            ref: ref
        )
    }

    static func trainingContext(plan: WorkoutPlan, wish: String, catalog: ExerciseCatalog, now: Date, calendar: Calendar, in context: ModelContext) -> ClaudePromptBuilder.TrainingContext {
        // Plan mit Übungsnamen statt IDs, damit Claude dieselben Namen zurückgibt.
        var template = TrainingActions.template(of: plan)
        func named(_ day: DayTemplate) -> DayTemplate {
            var copy = day
            copy.exercises = day.exercises.map { item in
                var item = item
                item.exercise = catalog.name(for: item.exercise)
                item.name = nil
                return item
            }
            return copy
        }
        template.format = PlanTemplate.format
        template.id = nil
        template.days = template.days.map(named)
        template.modules = template.modules.map(named)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let planJSON = (try? encoder.encode(template)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        // Letzte Leistung je Übung des Plans.
        let ids = plan.rotationDays.flatMap(\.sortedExercises).map(\.exerciseID)
        var seen = Set<String>()
        let recent = ids.filter { seen.insert($0).inserted }.compactMap { id -> String? in
            guard let last = TrainingActions.history(for: id, limit: 1, in: context).first, !last.workingSets.isEmpty else { return nil }
            return "\(catalog.name(for: id)): \(last.summary)"
        }

        let stagnating = TrainingActions.stagnatingExercises(in: plan, catalog: catalog, in: context).map { catalog.name(for: $0) }
        let volume = TrainingActions.weeklyVolume(containing: now, catalog: catalog, calendar: calendar, in: context)
            .filter { $0.sets > 0 }
            .map { "\($0.muscle.title) \(WeightFormat.number($0.sets))" }

        return ClaudePromptBuilder.TrainingContext(
            goal: trainingGoal,
            experience: trainingExperience,
            sessionsPerWeek: max(plan.preferredWeekdays.count, plan.rotationDays.count),
            planJSON: planJSON,
            recentSets: recent,
            stagnating: stagnating,
            weeklyVolume: volume,
            wish: wish,
            exerciseNames: catalog.sorted.map(\.name)
        )
    }

    public static func weeklyReviewPrompt(weekStart: Date, wish: String, ref: String = ClaudePromptBuilder.makeRef(), now: Date = .now, calendar: Calendar, in context: ModelContext) -> ClaudePrompt {
        let review = InsightsActions.weeklyReview(weekStart: weekStart, now: now, calendar: calendar, in: context)
        return ClaudePromptBuilder.weeklyReview(review, wish: wish, ref: ref)
    }

    public static func foodPrompt(name: String, brand: String? = nil, ingredients: String? = nil, ref: String = ClaudePromptBuilder.makeRef()) -> ClaudePrompt {
        let trimmedBrand = brand?.trimmingCharacters(in: .whitespaces)
        let trimmedIngredients = ingredients?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ClaudePromptBuilder.food(
            name: name.trimmingCharacters(in: .whitespaces),
            brand: trimmedBrand?.isEmpty == false ? trimmedBrand : nil,
            ingredients: trimmedIngredients?.isEmpty == false ? trimmedIngredients : nil,
            ref: ref
        )
    }

    public static func recipesPrompt(wish: String, count: Int = 3, servings: Int = 2, ref: String = ClaudePromptBuilder.makeRef(), in context: ModelContext) -> ClaudePrompt {
        let catalog = NutritionActions.catalog(in: context)
        let tolerances = NutritionActions.tolerances(in: context)
        let favorites = NutritionActions.favoriteIDs(in: context)
        let toleratedIDs = Set(tolerances.filter { $0.value == .ok }.keys).union(favorites.filter { (tolerances[$0] ?? .unknown) != .avoid })
        let tolerated = toleratedIDs.map { catalog.name(for: $0) }.sorted().prefix(40)
        let avoid = tolerances.filter { $0.value == .avoid }.keys.map { catalog.name(for: $0) }.sorted()
            + tolerances.filter { $0.value == .caution }.keys.map { "\(catalog.name(for: $0)) (nur wenig)" }.sorted()
        let perServing = NutritionActions.proteinTarget(in: context) / 4
        let protein = max(25, Int((perServing / 5).rounded()) * 5)
        return ClaudePromptBuilder.recipes(
            .init(wish: wish, count: count, servings: servings, proteinPerServing: protein, tolerated: Array(tolerated), avoid: avoid),
            ref: ref
        )
    }

    public static func patternsPrompt(wish: String, days: Int = 90, ref: String = ClaudePromptBuilder.makeRef(), now: Date = .now, calendar: Calendar, in context: ModelContext) -> ClaudePrompt {
        let start = now.addingTimeInterval(-Double(days) * 86_400)
        let report = NutritionActions.triggerReport(days: days, now: now, in: context)
        let summary = InsightsActions.symptomSummary(from: start, to: now.addingTimeInterval(1), in: context)
        let averages = CheckInAverages.compute(InsightsActions.checkIns(from: calendar.startOfDay(for: start), to: now.addingTimeInterval(1), in: context).map(\.fact))
        let catalog = NutritionActions.catalog(in: context)
        let avoid = NutritionActions.tolerances(in: context).filter { $0.value == .avoid }.keys.map { catalog.name(for: $0) }.sorted()
        return ClaudePromptBuilder.patterns(report, symptomSummary: summary, checkIns: averages, avoid: avoid, wish: wish, ref: ref)
    }

    // MARK: Antworten

    public static func parse(_ exchange: ClaudeExchange, in context: ModelContext) throws -> ClaudeAnswer {
        try ClaudeAnswerParser.parse(exchange.response, task: exchange.task, foods: NutritionActions.catalog(in: context))
    }

    /// Ordnet eine eingetroffene Antwort der passenden Anfrage zu: zuerst über die Kennung,
    /// sonst die zuletzt abgeschickte. `nil`, wenn keine Anfrage wartet.
    @discardableResult
    public static func receive(_ response: String, now: Date = .now, in context: ModelContext) -> ClaudeExchange? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let byRef = ClaudeAnswerParser.ref(in: trimmed).flatMap { InsightsActions.exchange(ref: $0, in: context) }
        guard let exchange = byRef ?? InsightsActions.waitingExchange(in: context) else { return nil }
        InsightsActions.attach(trimmed, to: exchange, now: now, in: context)
        return exchange
    }

    /// Plan übernehmen: als neuer Plan anlegen und aktivieren.
    @discardableResult
    public static func applyPlan(_ template: PlanTemplate, from exchange: ClaudeExchange, activate: Bool = true, in context: ModelContext) -> WorkoutPlan {
        let imported = PlanImporter.resolve(template, catalog: TrainingActions.catalog(in: context))
        let plan = TrainingActions.importPlan(imported, in: context)
        if activate { TrainingActions.activate(plan, in: context) }
        InsightsActions.setStatus(.applied, of: exchange, in: context)
        return plan
    }

    @discardableResult
    public static func applyFood(_ food: FoodInfo, from exchange: ClaudeExchange, in context: ModelContext) -> CustomFood {
        let saved = NutritionActions.saveCustomFood(food, in: context)
        InsightsActions.setStatus(.applied, of: exchange, in: context)
        return saved
    }

    /// Rezepte (und dafür nötige neue Lebensmittel) speichern.
    public static func applyRecipes(_ recipes: [RecipeInfo], newFoods: [FoodInfo], from exchange: ClaudeExchange, in context: ModelContext) {
        let existing = NutritionActions.catalog(in: context)
        for food in newFoods where existing.food(id: food.id) == nil {
            NutritionActions.saveCustomFood(food, in: context)
        }
        for recipe in recipes {
            NutritionActions.saveCustomRecipe(recipe, in: context)
        }
        InsightsActions.setStatus(.applied, of: exchange, in: context)
    }
}
