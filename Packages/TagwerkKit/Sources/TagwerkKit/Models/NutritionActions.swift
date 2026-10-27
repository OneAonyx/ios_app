import Foundation
import SwiftData
import TagwerkCore

/// Medikament „vor dem Essen“ (z. B. DAO-Enzym), nach dem beim Eintragen einer Mahlzeit gefragt wird.
public struct MealMedicationPrompt: Identifiable {
    public enum State {
        /// In den letzten 90 Minuten genommen.
        case taken(Date)
        /// Geplante Einnahme ist jetzt dran.
        case due(DoseEntry)
        /// Bei Bedarf: jederzeit möglich.
        case asNeeded
    }

    public let medication: Medication
    public let state: State

    public var id: String { medication.stableID }
}

/// Alle Änderungen rund um Ernährung, Symptome und Wasser an einer Stelle.
@MainActor
public enum NutritionActions {
    // MARK: Inhalte

    /// Mitgelieferte Lebensmittel, Regeln und Rezepte (einmal geladen).
    public static let bundledFoods = FoodCatalog.bundled()
    public static let analyzer = IngredientAnalyzer.bundled()
    public static let bundledRecipes = RecipeCatalog.bundled()

    /// Mitgelieferte plus eigene und gescannte Lebensmittel.
    public static func catalog(in context: ModelContext) -> FoodCatalog {
        let custom = (try? context.fetch(FetchDescriptor<CustomFood>())) ?? []
        return bundledFoods.adding(custom.map(\.info))
    }

    public static func recipes(in context: ModelContext) -> RecipeCatalog {
        let custom = (try? context.fetch(FetchDescriptor<CustomRecipe>())) ?? []
        return bundledRecipes.adding(custom.map(\.info))
    }

    /// Lebensmittel oder ein Platzhalter, falls es fehlt.
    public static func food(_ id: String, name: String? = nil, catalog: FoodCatalog) -> FoodInfo {
        catalog.food(id: id) ?? FoodInfo(id: id, name: name ?? id, category: .other, score: .moderate, isCustom: true)
    }

    // MARK: Verträglichkeit und Favoriten

    public static func preference(for foodID: String, in context: ModelContext) -> FoodPreference? {
        var descriptor = FetchDescriptor<FoodPreference>(predicate: #Predicate { $0.foodID == foodID })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private static func ensurePreference(for foodID: String, in context: ModelContext) -> FoodPreference {
        if let existing = preference(for: foodID, in: context) { return existing }
        let created = FoodPreference(foodID: foodID)
        context.insert(created)
        return created
    }

    /// Eigene Einschätzungen aller Lebensmittel.
    public static func tolerances(in context: ModelContext) -> [String: Tolerance] {
        let all = (try? context.fetch(FetchDescriptor<FoodPreference>())) ?? []
        var map: [String: Tolerance] = [:]
        for preference in all where preference.tolerance != .unknown {
            map[preference.foodID] = preference.tolerance
        }
        return map
    }

    public static func tolerance(for foodID: String, in context: ModelContext) -> Tolerance {
        preference(for: foodID, in: context)?.tolerance ?? .unknown
    }

    public static func setTolerance(_ tolerance: Tolerance, for foodID: String, in context: ModelContext) {
        ensurePreference(for: foodID, in: context).tolerance = tolerance
        save(context)
    }

    public static func setFavorite(_ isFavorite: Bool, for foodID: String, in context: ModelContext) {
        ensurePreference(for: foodID, in: context).isFavorite = isFavorite
        save(context)
    }

    public static func favoriteIDs(in context: ModelContext) -> Set<String> {
        let all = (try? context.fetch(FetchDescriptor<FoodPreference>(predicate: #Predicate { $0.isFavorite == true }))) ?? []
        return Set(all.map(\.foodID))
    }

    // MARK: Eigene Lebensmittel und Rezepte

    @discardableResult
    public static func saveCustomFood(_ info: FoodInfo, in context: ModelContext) -> CustomFood {
        let id = info.id
        var descriptor = FetchDescriptor<CustomFood>(predicate: #Predicate { $0.stableID == id })
        descriptor.fetchLimit = 1
        let food = (try? context.fetch(descriptor))?.first ?? {
            let created = CustomFood(stableID: id, name: info.name)
            context.insert(created)
            return created
        }()
        food.apply(info)
        save(context)
        return food
    }

    public static func deleteCustomFood(id: String, in context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<CustomFood>(predicate: #Predicate { $0.stableID == id }))) ?? []
        all.forEach(context.delete)
        save(context)
    }

    /// Neue ID für ein eigenes Lebensmittel aus dem Namen.
    public static func customFoodID(for name: String, catalog: FoodCatalog) -> String {
        let base = "custom-" + NameMatcher.normalize(name).replacingOccurrences(of: " ", with: "-")
        var id = base
        var counter = 2
        while catalog.food(id: id) != nil {
            id = "\(base)-\(counter)"
            counter += 1
        }
        return id
    }

    @discardableResult
    public static func saveCustomRecipe(_ info: RecipeInfo, in context: ModelContext) -> CustomRecipe {
        let id = info.id
        var descriptor = FetchDescriptor<CustomRecipe>(predicate: #Predicate { $0.stableID == id })
        descriptor.fetchLimit = 1
        let recipe = (try? context.fetch(descriptor))?.first ?? {
            let created = CustomRecipe(title: info.title, stableID: id)
            context.insert(created)
            return created
        }()
        recipe.apply(info)
        save(context)
        return recipe
    }

    public static func deleteCustomRecipe(id: String, in context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<CustomRecipe>(predicate: #Predicate { $0.stableID == id }))) ?? []
        all.forEach(context.delete)
        save(context)
    }

    // MARK: Mahlzeiten

    @discardableResult
    public static func addMeal(
        type: MealType,
        date: Date,
        freshness: Freshness = .fresh,
        place: MealPlace = .home,
        items: [(foodID: String, grams: Double)],
        recipeID: String? = nil,
        note: String = "",
        catalog: FoodCatalog,
        in context: ModelContext
    ) -> MealEntry {
        let meal = MealEntry(date: date, type: type)
        meal.freshness = freshness
        meal.place = place
        meal.recipeID = recipeID
        meal.note = note
        context.insert(meal)
        for (index, item) in items.enumerated() {
            let created = MealItem(foodID: item.foodID, name: catalog.name(for: item.foodID), grams: item.grams, position: index)
            context.insert(created)
            created.meal = meal
        }
        save(context)
        return meal
    }

    /// Ersetzt die Lebensmittel einer Mahlzeit.
    public static func setItems(_ items: [(foodID: String, grams: Double)], of meal: MealEntry, catalog: FoodCatalog, in context: ModelContext) {
        for existing in meal.items ?? [] { context.delete(existing) }
        meal.items = []
        for (index, item) in items.enumerated() {
            let created = MealItem(foodID: item.foodID, name: catalog.name(for: item.foodID), grams: item.grams, position: index)
            context.insert(created)
            created.meal = meal
        }
        save(context)
    }

    public static func delete(_ meal: MealEntry, in context: ModelContext) {
        context.delete(meal)
        save(context)
    }

    public static func meals(from start: Date, to end: Date, in context: ModelContext) -> [MealEntry] {
        let descriptor = FetchDescriptor<MealEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    public static func meals(on day: Date, calendar: Calendar, in context: ModelContext) -> [MealEntry] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return meals(from: start, to: end, in: context)
    }

    /// Zuletzt gegessene Lebensmittel, neueste zuerst, ohne Doppelte.
    public static func recentFoodIDs(limit: Int = 12, in context: ModelContext) -> [String] {
        var descriptor = FetchDescriptor<MealEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 30
        let recent = (try? context.fetch(descriptor)) ?? []
        var seen = Set<String>()
        var result: [String] = []
        for meal in recent {
            for item in meal.sortedItems where seen.insert(item.foodID).inserted {
                result.append(item.foodID)
                if result.count >= limit { return result }
            }
        }
        return result
    }

    /// Mahlzeiten als Werte für Berechnungen.
    public static func facts(_ meals: [MealEntry], catalog: FoodCatalog, in context: ModelContext) -> [MealFact] {
        let tolerances = tolerances(in: context)
        return meals.map { $0.fact(catalog: catalog) { tolerances[$0] ?? .unknown } }
    }

    // MARK: Symptome

    @discardableResult
    public static func addSymptom(
        _ type: SymptomType, severity: Int, date: Date = .now, durationMinutes: Int? = nil, note: String = "",
        in context: ModelContext
    ) -> SymptomEntry {
        let entry = SymptomEntry(date: date, type: type, severity: min(max(severity, 1), 5))
        entry.durationMinutes = durationMinutes
        entry.note = note
        context.insert(entry)
        save(context)
        return entry
    }

    public static func delete(_ symptom: SymptomEntry, in context: ModelContext) {
        context.delete(symptom)
        save(context)
    }

    public static func symptoms(from start: Date, to end: Date, in context: ModelContext) -> [SymptomEntry] {
        let descriptor = FetchDescriptor<SymptomEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Muster der letzten `days` Tage.
    public static func triggerReport(days: Int = 90, type: SymptomType? = nil, now: Date = .now, in context: ModelContext) -> TriggerReport {
        let start = now.addingTimeInterval(-Double(days) * 86_400)
        let catalog = catalog(in: context)
        let mealFacts = facts(meals(from: start, to: now.addingTimeInterval(1), in: context), catalog: catalog, in: context)
        let symptomFacts = symptoms(from: start, to: now.addingTimeInterval(86_400), in: context).map(\.fact)
        // Wenig Schlaf und viel Stress aus den Check-ins zählen als Umstände mit.
        let factors = InsightsActions.dayFactors(from: start, to: now.addingTimeInterval(86_400), calendar: .current, in: context)
        return TriggerAnalysis.analyze(meals: mealFacts, symptoms: symptomFacts, dayFactors: factors, only: type)
    }

    // MARK: Wasser

    @discardableResult
    public static func addWater(_ milliliters: Int = NutritionTargets.glassML, at date: Date = .now, in context: ModelContext) -> WaterLog {
        let log = WaterLog(date: date, milliliters: milliliters)
        context.insert(log)
        save(context)
        return log
    }

    public static func waterLogs(on day: Date, calendar: Calendar, in context: ModelContext) -> [WaterLog] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let descriptor = FetchDescriptor<WaterLog>(predicate: #Predicate { $0.date >= start && $0.date < end }, sortBy: [SortDescriptor(\.date)])
        return (try? context.fetch(descriptor)) ?? []
    }

    public static func water(on day: Date, calendar: Calendar, in context: ModelContext) -> Int {
        waterLogs(on: day, calendar: calendar, in: context).reduce(0) { $0 + $1.milliliters }
    }

    /// Letztes Glas des Tages zurücknehmen.
    public static func undoLastWater(on day: Date, calendar: Calendar, in context: ModelContext) {
        guard let last = waterLogs(on: day, calendar: calendar, in: context).last else { return }
        context.delete(last)
        save(context)
    }

    /// Wasser aus Widget oder Kontrollzentrum übernehmen.
    @discardableResult
    public static func processPendingWater(in context: ModelContext) -> Int {
        let pending = NutritionActionCenter.takeQueued()
        for entry in pending {
            context.insert(WaterLog(date: entry.date, milliliters: entry.milliliters))
        }
        if !pending.isEmpty { save(context) }
        return pending.count
    }

    // MARK: Tageswerte

    public static var proteinPerKg: Double {
        let stored = UserDefaults.standard.double(forKey: SettingsKeys.proteinPerKg)
        return stored > 0 ? stored : NutritionTargets.defaultProteinPerKg
    }

    public static var waterTarget: Int {
        let stored = UserDefaults.standard.integer(forKey: SettingsKeys.waterTarget)
        return stored > 0 ? stored : NutritionTargets.defaultWaterML
    }

    /// Letztes eingetragenes Körpergewicht (Training → Körper).
    public static func bodyweight(in context: ModelContext) -> Double? {
        let raw = BodyMetricType.weight.rawValue
        var descriptor = FetchDescriptor<BodyMetric>(predicate: #Predicate { $0.typeRaw == raw }, sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.value
    }

    public static func proteinTarget(in context: ModelContext) -> Double {
        NutritionTargets.proteinTarget(bodyweight: bodyweight(in: context), perKg: proteinPerKg)
    }

    public static func day(_ date: Date, calendar: Calendar, in context: ModelContext) -> NutritionDay {
        let catalog = catalog(in: context)
        let meals = meals(on: date, calendar: calendar, in: context)
        return NutritionDay(
            day: calendar.startOfDay(for: date),
            meals: facts(meals, catalog: catalog, in: context),
            waterML: water(on: date, calendar: calendar, in: context),
            proteinTarget: proteinTarget(in: context),
            waterTarget: waterTarget
        )
    }

    // MARK: Medikamente vor dem Essen

    /// Aktive Medikamente mit dem Hinweis „vor dem Essen“ und ihr Stand rund um `now`.
    public static func beforeMealMedications(now: Date = .now, calendar: Calendar, in context: ModelContext) -> [MealMedicationPrompt] {
        guard UserDefaults.standard.object(forKey: SettingsKeys.askBeforeMealMedication) as? Bool ?? true else { return [] }
        let medications = MedicationActions.fetchAll(in: context).filter { $0.isActive && $0.timing == .beforeMeal }
        let window: TimeInterval = 90 * 60
        return medications.compactMap { medication in
            if let recent = (medication.logs ?? [])
                .filter({ $0.status == .taken })
                .compactMap(\.takenAt)
                .filter({ $0 <= now.addingTimeInterval(60) && now.timeIntervalSince($0) < window })
                .max() {
                return MealMedicationPrompt(medication: medication, state: .taken(recent))
            }
            if medication.schedule.isScheduled {
                let entries = medication.entries(from: now.addingTimeInterval(-window), to: now.addingTimeInterval(window), now: now, calendar: calendar)
                if let due = entries.first(where: { $0.state == .due || $0.state == .late || $0.state == .upcoming }) {
                    return MealMedicationPrompt(medication: medication, state: .due(due))
                }
                // Keine geplante Einnahme in der Nähe: als zusätzliche Einnahme anbieten.
                return MealMedicationPrompt(medication: medication, state: .asNeeded)
            }
            return MealMedicationPrompt(medication: medication, state: .asNeeded)
        }
    }

    // MARK: Einkaufsliste

    @discardableResult
    public static func addShoppingItem(
        _ name: String, amount: String = "", foodID: String? = nil, category: ShoppingCategory? = nil,
        source: String = "manual", catalog: FoodCatalog, in context: ModelContext
    ) -> ShoppingItem {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedFood = foodID.flatMap { catalog.food(id: $0) } ?? catalog.bestMatch(for: trimmed).flatMap {
            NameMatcher.similarity($0.name, trimmed) >= 0.6 ? $0 : nil
        }
        let item = ShoppingItem(
            name: trimmed,
            category: category ?? resolvedFood?.category.shoppingCategory ?? ShoppingCategory.guess(for: trimmed, catalog: catalog),
            amount: amount,
            foodID: resolvedFood?.id,
            source: source
        )
        context.insert(item)
        save(context)
        return item
    }

    public static func toggle(_ item: ShoppingItem, in context: ModelContext) {
        item.isDone.toggle()
        item.doneAt = item.isDone ? .now : nil
        save(context)
    }

    public static func delete(_ item: ShoppingItem, in context: ModelContext) {
        context.delete(item)
        save(context)
    }

    public static func clearDoneShopping(in context: ModelContext) {
        let done = (try? context.fetch(FetchDescriptor<ShoppingItem>(predicate: #Predicate { $0.isDone == true }))) ?? []
        done.forEach(context.delete)
        save(context)
    }

    /// Zutaten auf die Einkaufsliste. Offene Einträge zum selben Lebensmittel aus Rezepten oder dem
    /// Wochenplan werden ersetzt, eigene Einträge bleiben unverändert. Gibt die Anzahl neuer Einträge zurück.
    @discardableResult
    public static func addToShopping(_ needs: [ShoppingNeed], source: String, catalog: FoodCatalog, in context: ModelContext) -> Int {
        let open = (try? context.fetch(FetchDescriptor<ShoppingItem>(predicate: #Predicate { $0.isDone == false }))) ?? []
        var added = 0
        for need in needs {
            if let existing = open.first(where: { $0.foodID == need.foodID }) {
                if existing.sourceRaw != "manual" { existing.amount = need.amountText }
                continue
            }
            let item = ShoppingItem(name: need.name, category: need.category, amount: need.amountText, foodID: need.foodID, source: source)
            context.insert(item)
            added += 1
        }
        save(context)
        return added
    }

    // MARK: Wochenplan

    public static func planEntries(from start: Date, to end: Date, in context: ModelContext) -> [MealPlanEntry] {
        let descriptor = FetchDescriptor<MealPlanEntry>(predicate: #Predicate { $0.day >= start && $0.day < end }, sortBy: [SortDescriptor(\.day)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Rezept für Tag und Mahlzeit setzen (ersetzt einen vorhandenen Eintrag).
    @discardableResult
    public static func plan(_ recipeID: String, servings: Int, on day: Date, mealType: MealType, calendar: Calendar, in context: ModelContext) -> MealPlanEntry {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        for existing in planEntries(from: start, to: end, in: context) where existing.mealType == mealType {
            context.delete(existing)
        }
        let entry = MealPlanEntry(day: start, mealType: mealType, recipeID: recipeID, servings: max(1, servings))
        context.insert(entry)
        save(context)
        return entry
    }

    public static func delete(_ entry: MealPlanEntry, in context: ModelContext) {
        context.delete(entry)
        save(context)
    }

    /// Was für den Wochenplan eingekauft werden muss.
    public static func planNeeds(from start: Date, to end: Date, in context: ModelContext) -> [ShoppingNeed] {
        let recipes = recipes(in: context)
        let pairs = planEntries(from: start, to: end, in: context).compactMap { entry -> (recipe: RecipeInfo, servings: Int)? in
            recipes.recipe(id: entry.recipeID).map { ($0, entry.servings) }
        }
        return ShoppingPlanner.needs(for: pairs, catalog: catalog(in: context))
    }

    // MARK: Widget

    public static func snapshot(now: Date = .now, calendar: Calendar, in context: ModelContext) -> NutritionWidgetSnapshot {
        let today = day(now, calendar: calendar, in: context)
        let load = today.load
        let lastSymptom = symptoms(from: calendar.startOfDay(for: now), to: now.addingTimeInterval(60), in: context).first
        return NutritionWidgetSnapshot(
            writtenAt: now,
            day: calendar.startOfDay(for: now),
            loadPoints: (load.points * 10).rounded() / 10,
            levelRaw: load.level.rawValue,
            protein: today.protein.rounded(),
            proteinTarget: today.proteinTarget,
            waterML: today.waterML,
            waterTarget: today.waterTarget,
            mealCount: today.meals.count,
            topContributors: Array(load.contributors.prefix(3).map(\.name)),
            lastSymptom: lastSymptom.map { "\($0.type.title) (\($0.severity))" }
        )
    }

    public static func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            print("Orbit: Speichern fehlgeschlagen: \(error)")
        }
    }
}
