import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Rezepte mit Filter nach Stichworten.
struct RecipeListView: View {
    @Environment(\.modelContext) private var context
    @Query private var preferences: [FoodPreference]
    @Query private var customFoods: [CustomFood]
    @Query private var customRecipes: [CustomRecipe]
    @State private var query = ""
    @State private var tag: String?

    var body: some View {
        let catalog = NutritionActions.bundledFoods.adding(customFoods.map(\.info))
        let recipes = NutritionActions.bundledRecipes.adding(customRecipes.map(\.info))
        let tolerances = Dictionary(preferences.map { ($0.foodID, $0.tolerance) }, uniquingKeysWith: { $1 })
        let results = recipes.search(query, tag: tag, catalog: catalog)
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.xs) {
                        chip("Alle", isOn: tag == nil) { tag = nil }
                        ForEach(recipes.tags, id: \.self) { item in
                            chip(item, isOn: tag == item) { tag = tag == item ? nil : item }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section {
                ForEach(results) { recipe in
                    NavigationLink(value: NutritionRoute.recipe(recipe.id)) {
                        RecipeRow(recipe: recipe, catalog: catalog, tolerances: tolerances)
                    }
                }
            }
        }
        .overlay {
            if results.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .searchable(text: $query, prompt: "Rezept oder Zutat")
        .navigationTitle("Rezepte")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: NutritionRoute.mealPlan) {
                    Image(systemName: "calendar")
                }
                .accessibilityLabel("Wochenplan")
            }
        }
    }

    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .background(isOn ? ModuleAccent.nutrition : Color.tagwerkCard, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct RecipeRow: View {
    let recipe: RecipeInfo
    let catalog: FoodCatalog
    let tolerances: [String: Tolerance]

    var body: some View {
        let worst = recipe.worstScore(catalog: catalog) { tolerances[$0] ?? .unknown }
        HStack(spacing: Spacing.s) {
            IconBadge(systemImage: recipe.tags.contains("Frühstück") ? "sunrise.fill" : "frying.pan.fill", tint: ModuleAccent.nutrition, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.title)
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)
                Text("\(Int(recipe.proteinPerServing(catalog: catalog).rounded())) g Eiweiß · \(recipe.minutes) Min.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Spacing.xs)
            ScoreBadge(score: worst)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Ein Rezept: Zutaten mit Bewertung, Schritte, eintragen, einkaufen, planen.
struct RecipeDetailView: View {
    let recipeID: String

    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query private var preferences: [FoodPreference]
    @Query private var customFoods: [CustomFood]
    @Query private var customRecipes: [CustomRecipe]
    @State private var servings: Int?
    @State private var shoppingAdded = false
    @State private var planning = false

    var body: some View {
        let catalog = NutritionActions.bundledFoods.adding(customFoods.map(\.info))
        let recipes = NutritionActions.bundledRecipes.adding(customRecipes.map(\.info))
        let tolerances = Dictionary(preferences.map { ($0.foodID, $0.tolerance) }, uniquingKeysWith: { $1 })
        if let recipe = recipes.recipe(id: recipeID) {
            let portions = servings ?? recipe.servings
            List {
                Section {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(recipe.title)
                            .font(.title3.weight(.bold))
                        if !recipe.summary.isEmpty {
                            Text(recipe.summary)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: Spacing.s) {
                            StatTile(title: "Eiweiß", value: "\(Int(recipe.proteinPerServing(catalog: catalog).rounded())) g", detail: "pro Portion", tint: ModuleAccent.nutrition)
                            StatTile(title: "Energie", value: "\(Int(recipe.kcalPerServing(catalog: catalog).rounded()))", detail: "kcal pro Portion", tint: ModuleAccent.nutrition)
                            StatTile(title: "Zeit", value: "\(recipe.minutes)", detail: "Minuten", tint: ModuleAccent.nutrition)
                        }
                    }
                    .padding(.vertical, Spacing.xxs)
                }
                Section {
                    Stepper(value: Binding(get: { portions }, set: { servings = $0 }), in: 1...12) {
                        Text("\(portions) \(portions == 1 ? "Portion" : "Portionen")")
                    }
                    ForEach(recipe.ingredients.indices, id: \.self) { index in
                        let item = recipe.ingredients[index]
                        let food = NutritionActions.food(item.food, catalog: catalog)
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(recipe.label(for: item, servings: portions, catalog: catalog))
                                if let note = item.note {
                                    Text(note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            ScoreBadge(score: (tolerances[item.food] ?? .unknown).effectiveScore(general: food.score))
                        }
                    }
                } header: {
                    Text("Zutaten")
                }
                Section("Zubereitung") {
                    ForEach(recipe.steps.indices, id: \.self) { index in
                        let step = recipe.steps[index]
                        HStack(alignment: .top, spacing: Spacing.s) {
                            Text("\(index + 1)")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(ModuleAccent.nutrition)
                                .frame(width: 20)
                            Text(step)
                        }
                    }
                }
                Section {
                    Button {
                        app.logMeal(type: MealType.suggested(for: .now, calendar: AppModel.calendar), recipe: recipe)
                    } label: {
                        Label("Eine Portion als Mahlzeit eintragen", systemImage: "fork.knife")
                    }
                    .accessibilityIdentifier("recipe.log")
                    Button {
                        let needs = ShoppingPlanner.needs(for: [(recipe, portions)], catalog: catalog)
                        NutritionActions.addToShopping(needs, source: "recipe", catalog: catalog, in: context)
                        shoppingAdded = true
                    } label: {
                        Label(shoppingAdded ? "Auf der Einkaufsliste" : "Zutaten auf die Einkaufsliste", systemImage: shoppingAdded ? "checkmark" : "cart.badge.plus")
                    }
                    .disabled(shoppingAdded)
                    Button {
                        planning = true
                    } label: {
                        Label("In den Wochenplan", systemImage: "calendar.badge.plus")
                    }
                }
            }
            .navigationTitle(recipe.title)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $planning) {
                PlanRecipeSheet(recipe: recipe, servings: portions)
            }
        } else {
            ContentUnavailableView("Rezept nicht gefunden", systemImage: "book")
        }
    }
}

/// Rezept einem Tag im Wochenplan zuordnen.
private struct PlanRecipeSheet: View {
    let recipe: RecipeInfo
    let servings: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var day = Date.now
    @State private var mealType: MealType = .dinner

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Tag", selection: $day, displayedComponents: .date)
                Picker("Mahlzeit", selection: $mealType) {
                    ForEach([MealType.breakfast, .lunch, .dinner]) { type in
                        Text(type.title).tag(type)
                    }
                }
            }
            .navigationTitle(recipe.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Planen") {
                        NutritionActions.plan(recipe.id, servings: servings, on: day, mealType: mealType, calendar: AppModel.calendar, in: context)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Wochen-Essensplan: Mittag und Abend für sieben Tage, daraus die Einkaufsliste.
struct MealPlanView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MealPlanEntry.day) private var entries: [MealPlanEntry]
    @Query private var customRecipes: [CustomRecipe]
    @State private var weekOffset = 0
    @State private var choosing: PlanSlot?
    @State private var addedCount: Int?

    private struct PlanSlot: Identifiable {
        let day: Date
        let mealType: MealType
        var id: String { "\(day.timeIntervalSince1970)-\(mealType.rawValue)" }
    }

    var body: some View {
        let calendar = AppModel.calendar
        let monday = calendar.date(byAdding: .day, value: 7 * weekOffset, to: AgendaBuilder.startOfWeek(containing: .now, calendar: calendar)) ?? .now
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
        let end = calendar.date(byAdding: .day, value: 7, to: monday) ?? monday
        let recipes = NutritionActions.bundledRecipes.adding(customRecipes.map(\.info))
        let weekEntries = entries.filter { $0.day >= monday && $0.day < end }
        List {
            Section {
                HStack {
                    Button {
                        weekOffset -= 1
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    Text(weekOffset == 0 ? "Diese Woche" : (weekOffset == 1 ? "Nächste Woche" : "KW \(calendar.component(.weekOfYear, from: monday))"))
                        .font(.headline)
                    Spacer()
                    Button {
                        weekOffset += 1
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.borderless)
                }
            }
            ForEach(days, id: \.self) { day in
                Section(day.nutritionDayLabel(calendar: calendar)) {
                    ForEach([MealType.lunch, .dinner]) { type in
                        let entry = weekEntries.first { calendar.isDate($0.day, inSameDayAs: day) && $0.mealType == type }
                        Button {
                            choosing = PlanSlot(day: day, mealType: type)
                        } label: {
                            HStack {
                                Text(type == .lunch ? "Mittag" : "Abend")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 56, alignment: .leading)
                                if let entry, let recipe = recipes.recipe(id: entry.recipeID) {
                                    Text(recipe.title)
                                        .foregroundStyle(Color.primary)
                                        .lineLimit(2)
                                    Spacer()
                                    Text("\(entry.servings)×")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Rezept wählen")
                                        .foregroundStyle(.tertiary)
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(ModuleAccent.nutrition)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            if let entry {
                                Button("Entfernen", role: .destructive) {
                                    NutritionActions.delete(entry, in: context)
                                }
                            }
                        }
                    }
                }
            }
            Section {
                Button {
                    let needs = NutritionActions.planNeeds(from: monday, to: end, in: context)
                    addedCount = NutritionActions.addToShopping(needs, source: "plan", catalog: NutritionActions.catalog(in: context), in: context)
                } label: {
                    Label("Einkaufsliste für diese Woche füllen", systemImage: "cart.badge.plus")
                }
                .disabled(weekEntries.isEmpty)
                .accessibilityIdentifier("plan.shopping")
                if let addedCount {
                    Text(addedCount == 0 ? "Alles steht schon auf der Liste." : "\(addedCount) Artikel hinzugefügt.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Wochenplan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: NutritionRoute.shopping) {
                    Image(systemName: "cart")
                }
                .accessibilityLabel("Einkaufsliste")
            }
        }
        .sheet(item: $choosing) { slot in
            RecipePickerSheet { recipe, servings in
                NutritionActions.plan(recipe.id, servings: servings, on: slot.day, mealType: slot.mealType, calendar: AppModel.calendar, in: context)
            }
        }
    }
}

/// Rezept für den Wochenplan auswählen.
private struct RecipePickerSheet: View {
    let onPick: (RecipeInfo, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var customRecipes: [CustomRecipe]
    @Query private var customFoods: [CustomFood]
    @Query private var preferences: [FoodPreference]
    @State private var query = ""
    @State private var servings = 2

    var body: some View {
        let catalog = NutritionActions.bundledFoods.adding(customFoods.map(\.info))
        let recipes = NutritionActions.bundledRecipes.adding(customRecipes.map(\.info))
        let tolerances = Dictionary(preferences.map { ($0.foodID, $0.tolerance) }, uniquingKeysWith: { $1 })
        NavigationStack {
            List {
                Section {
                    Stepper("\(servings) \(servings == 1 ? "Portion" : "Portionen")", value: $servings, in: 1...12)
                }
                Section {
                    ForEach(recipes.search(query, catalog: catalog)) { recipe in
                        Button {
                            onPick(recipe, servings)
                            dismiss()
                        } label: {
                            RecipeRow(recipe: recipe, catalog: catalog, tolerances: tolerances)
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Rezept suchen")
            .navigationTitle("Rezept wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }
}
