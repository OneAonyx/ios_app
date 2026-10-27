import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Tab „Ernährung“: Tagebuch mit Histamin-Tageslast, Eiweiß, Wasser und Mahlzeiten.
struct NutritionView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \MealEntry.date) private var meals: [MealEntry]
    @Query(sort: \WaterLog.date) private var water: [WaterLog]
    @Query(sort: \SymptomEntry.date, order: .reverse) private var symptoms: [SymptomEntry]
    @Query private var preferences: [FoodPreference]
    @Query private var customFoods: [CustomFood]
    @Query(sort: \BodyMetric.date, order: .reverse) private var metrics: [BodyMetric]
    @AppStorage(SettingsKeys.proteinPerKg) private var proteinPerKg = NutritionTargets.defaultProteinPerKg
    @AppStorage(SettingsKeys.waterTarget) private var waterTarget = NutritionTargets.defaultWaterML
    @State private var dayOffset = 0

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { timeline in
                content(now: timeline.date)
            }
            .background(Color.tagwerkPage)
            .navigationTitle("Ernährung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        app.logMeal(date: selectedDate(now: .now))
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Mahlzeit eintragen")
                    .accessibilityIdentifier("nutrition.add")
                }
            }
            .navigationDestination(for: NutritionRoute.self) { route in
                NutritionDestination(route: route)
            }
        }
    }

    private func selectedDate(now: Date) -> Date {
        let calendar = AppModel.calendar
        guard dayOffset != 0 else { return now }
        let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }

    private func content(now: Date) -> some View {
        let calendar = AppModel.calendar
        let date = selectedDate(now: now)
        let catalog = NutritionActions.bundledFoods.adding(customFoods.map(\.info))
        let tolerances = Dictionary(preferences.map { ($0.foodID, $0.tolerance) }, uniquingKeysWith: { $1 })
        let dayMeals = meals.filter { calendar.isDate($0.date, inSameDayAs: date) }
        let facts = dayMeals.map { $0.fact(catalog: catalog) { tolerances[$0] ?? .unknown } }
        let bodyweight = metrics.first { $0.type == .weight }?.value
        let day = NutritionDay(
            day: calendar.startOfDay(for: date),
            meals: facts,
            waterML: water.filter { calendar.isDate($0.date, inSameDayAs: date) }.reduce(0) { $0 + $1.milliliters },
            proteinTarget: NutritionTargets.proteinTarget(bodyweight: bodyweight, perKg: proteinPerKg),
            waterTarget: waterTarget
        )
        let daySymptoms = symptoms.filter { calendar.isDate($0.date, inSameDayAs: date) }

        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                DaySwitcher(date: date, offset: $dayOffset, now: now)
                DayOverviewCard(day: day, isToday: dayOffset == 0, date: date)
                MealsCard(meals: dayMeals, facts: facts, date: date)
                SymptomsDayCard(symptoms: daySymptoms, isToday: dayOffset == 0)
                NutritionLinksCard()
                NutritionDisclaimer()
                    .padding(.horizontal, Spacing.xs)
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.xl)
        }
    }
}

/// Ziel einer Navigation im Tab „Ernährung“ (auch aus „Gesundheit“ genutzt).
struct NutritionDestination: View {
    let route: NutritionRoute

    var body: some View {
        switch route {
        case .lexicon: FoodLexiconView()
        case let .food(id): FoodDetailView(foodID: id)
        case .shopping: ShoppingListView()
        case .recipes: RecipeListView()
        case let .recipe(id): RecipeDetailView(recipeID: id)
        case .mealPlan: MealPlanView()
        case .patterns: PatternsView()
        case .ingredientCheck: IngredientCheckView()
        case .symptoms: SymptomHistoryView()
        case .settings: NutritionSettingsView()
        }
    }
}

// MARK: - Karten

private struct DaySwitcher: View {
    let date: Date
    @Binding var offset: Int
    let now: Date

    var body: some View {
        HStack {
            Button {
                offset -= 1
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Vortag")
            .accessibilityIdentifier("nutrition.previousDay")
            Spacer()
            VStack(spacing: 0) {
                Text(date.nutritionDayLabel(now: now))
                    .font(.headline)
                if offset != 0 {
                    Button("Zu heute") { offset = 0 }
                        .font(.caption)
                }
            }
            Spacer()
            Button {
                offset += 1
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 36, height: 36)
            }
            .disabled(offset >= 0)
            .accessibilityLabel("Nächster Tag")
        }
        .padding(.top, Spacing.xs)
    }
}

private struct DayOverviewCard: View {
    let day: NutritionDay
    let isToday: Bool
    let date: Date

    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context

    var body: some View {
        let load = day.load
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader("Histamin-Tageslast", systemImage: "gauge.with.dots.needle.33percent", tint: ModuleAccent.nutrition)
                    Label(load.level.title, systemImage: load.level.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(load.level.color)
                        .fixedSize()
                }
                LoadBar(load: load)
                if load.contributors.isEmpty {
                    Text(day.meals.isEmpty ? "Noch keine Mahlzeit eingetragen." : "Bisher nur gut verträgliche Lebensmittel.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text(loadContributorsText(load))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Divider()
                NutritionRings(day: day)
                HStack(spacing: Spacing.xs) {
                    Button {
                        NutritionActions.addWater(at: isToday ? .now : date, in: context)
                        app.nutritionChanged()
                    } label: {
                        Label("Glas Wasser", systemImage: "plus")
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.bordered)
                    .tint(.cyan)
                    .accessibilityIdentifier("nutrition.water")
                    if day.waterML > 0 {
                        Button {
                            NutritionActions.undoLastWater(on: date, calendar: AppModel.calendar, in: context)
                            app.nutritionChanged()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .frame(minWidth: 36, minHeight: 36)
                        }
                        .buttonStyle(.bordered)
                        .tint(.secondary)
                        .accessibilityLabel("Letztes Glas zurücknehmen")
                    }
                }
                .sensoryFeedback(.increase, trigger: day.waterML)
            }
        }
    }
}

private struct MealsCard: View {
    let meals: [MealEntry]
    let facts: [MealFact]
    let date: Date

    @Environment(AppModel.self) private var app

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader("Mahlzeiten", systemImage: "fork.knife", tint: ModuleAccent.nutrition)
                ForEach(MealType.allCases) { type in
                    let ofType = meals.filter { $0.type == type }
                    if ofType.isEmpty {
                        Button {
                            app.logMeal(type: type, date: defaultDate(for: type))
                        } label: {
                            HStack(spacing: Spacing.s) {
                                Image(systemName: type.symbol)
                                    .foregroundStyle(ModuleAccent.nutrition)
                                    .frame(width: 28)
                                Text(type.title)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(ModuleAccent.nutrition)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("nutrition.meal.\(type.rawValue)")
                    } else {
                        ForEach(ofType) { meal in
                            MealRow(meal: meal, fact: facts.first { $0.id == meal.stableID })
                        }
                    }
                }
            }
        }
    }

    private func defaultDate(for type: MealType) -> Date {
        let calendar = AppModel.calendar
        let now = Date.now
        if calendar.isDate(date, inSameDayAs: now), MealType.suggested(for: now, calendar: calendar) == type {
            return now
        }
        return calendar.date(bySettingHour: type.defaultHour, minute: 0, second: 0, of: date) ?? date
    }
}

private struct MealRow: View {
    let meal: MealEntry
    let fact: MealFact?

    @Environment(AppModel.self) private var app

    var body: some View {
        Button {
            app.editingMeal = meal
        } label: {
            HStack(alignment: .top, spacing: Spacing.s) {
                Image(systemName: meal.type.symbol)
                    .foregroundStyle(ModuleAccent.nutrition)
                    .frame(width: 28)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    // Ein Text, damit Name und Uhrzeit bei großer Schrift gemeinsam umbrechen.
                    (Text(meal.type.title).font(.subheadline.weight(.semibold))
                        + Text("  " + GermanCalendar.time(meal.date, calendar: AppModel.calendar))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.secondary))
                    Text(meal.itemSummary.isEmpty ? "Ohne Lebensmittel" : meal.itemSummary)
                        .font(.subheadline)
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.leading)
                    let tags = [
                        meal.freshness == .fresh ? nil : meal.freshness.shortTitle,
                        meal.place == .out ? meal.place.title : nil,
                        fact.map { "\(Int($0.protein.rounded())) g Eiweiß" },
                    ].compactMap { $0 }
                    if !tags.isEmpty {
                        Text(tags.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: Spacing.xs)
                if let worst = fact?.worstScore {
                    ScoreBadge(score: worst)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("nutrition.mealRow")
    }
}

private struct SymptomsDayCard: View {
    let symptoms: [SymptomEntry]
    let isToday: Bool

    @Environment(AppModel.self) private var app

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack {
                    SectionHeader("Beschwerden", systemImage: "waveform.path.ecg", tint: ModuleAccent.health)
                    Button {
                        app.isAddingSymptom = true
                    } label: {
                        Label("Eintragen", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                    }
                    .tint(ModuleAccent.health)
                    .accessibilityIdentifier("nutrition.symptom.add")
                }
                if symptoms.isEmpty {
                    Text(isToday ? "Heute keine Beschwerden eingetragen." : "Keine Beschwerden eingetragen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(symptoms) { symptom in
                        SymptomRow(symptom: symptom)
                    }
                }
            }
        }
    }
}

private struct NutritionLinksCard: View {
    var body: some View {
        Card(padding: Spacing.xs) {
            VStack(spacing: 0) {
                link("Lebensmittel-Lexikon", "books.vertical", .lexicon, id: "nutrition.lexicon")
                Divider().padding(.leading, 52)
                link("Zutatenliste prüfen", "text.viewfinder", .ingredientCheck, id: "nutrition.ingredients")
                Divider().padding(.leading, 52)
                link("Einkaufsliste", "cart", .shopping, id: "nutrition.shopping")
                Divider().padding(.leading, 52)
                link("Rezepte", "book", .recipes, id: "nutrition.recipes")
                Divider().padding(.leading, 52)
                link("Wochenplan", "calendar", .mealPlan, id: "nutrition.plan")
                Divider().padding(.leading, 52)
                link("Muster und Auslöser", "magnifyingglass.circle", .patterns, id: "nutrition.patterns")
                Divider().padding(.leading, 52)
                link("Ziele und Einstellungen", "slider.horizontal.3", .settings, id: "nutrition.settings")
            }
        }
    }

    private func link(_ title: String, _ symbol: String, _ route: NutritionRoute, id: String) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: Spacing.s) {
                IconBadge(systemImage: symbol, tint: ModuleAccent.nutrition, size: 32)
                Text(title)
                    .foregroundStyle(Color.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/// Ein Symptom mit Stärke.
struct SymptomRow: View {
    let symptom: SymptomEntry
    var showsDate = false

    var body: some View {
        HStack(spacing: Spacing.s) {
            IconBadge(systemImage: symptom.type.symbol, tint: ModuleAccent.health, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(symptom.type.title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Spacing.xs)
            SeverityDots(value: symptom.severity)
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let calendar = AppModel.calendar
        var parts: [String] = []
        if showsDate { parts.append(symptom.date.nutritionDayLabel()) }
        parts.append(GermanCalendar.time(symptom.date, calendar: calendar))
        parts.append(SymptomSeverity.title(symptom.severity))
        if let minutes = symptom.durationMinutes, minutes > 0 {
            parts.append(minutes >= 60 ? "\(WeightFormat.number((Double(minutes) / 30).rounded() / 2)) Std." : "\(minutes) Min.")
        }
        if !symptom.note.isEmpty { parts.append(symptom.note) }
        return parts.joined(separator: " · ")
    }
}

struct SeverityDots: View {
    let value: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { index in
                Circle()
                    .fill(index <= value ? ModuleAccent.health : Color.secondary.opacity(0.2))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityLabel("Stärke \(value) von 5")
    }
}
