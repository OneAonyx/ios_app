import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Ernährungsplan für die Woche: je Tag und Mahlzeit zwei Optionen, mit einem Tipp in den Wochenplan übernehmen.
struct WeekTemplateView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query private var customFoods: [CustomFood]
    @AppStorage(SettingsKeys.mealPlanChoices) private var choicesText = ""
    @State private var confirmingWeek: Int?
    @State private var appliedText: String?

    var body: some View {
        if let template = NutritionActions.weekTemplate {
            content(template)
        } else {
            ContentUnavailableView("Plan nicht gefunden", systemImage: "list.bullet.clipboard")
        }
    }

    private func content(_ template: MealPlanTemplate) -> some View {
        let catalog = NutritionActions.catalog(custom: customFoods)
        let recipes = NutritionActions.bundledRecipes
        let choices = NutritionActions.decodeChoices(choicesText)
        return List {
            Section {
                Text(template.summary)
                    .font(.subheadline)
                DisclosureGroup("So ist der Plan aufgebaut") {
                    ForEach(template.guidelines, id: \.self) { line in
                        Text(line)
                            .font(.footnote)
                            .padding(.vertical, 2)
                    }
                }
                .accessibilityIdentifier("weekTemplate.guidelines")
            } header: {
                Text(template.title)
            }

            ForEach(template.orderedDays) { day in
                Section {
                    ForEach(MealType.allCases) { meal in
                        mealRow(day: day, meal: meal, choices: choices, recipes: recipes, catalog: catalog)
                    }
                } header: {
                    Text(day.title)
                } footer: {
                    Text(dayTotals(day, choices: choices, recipes: recipes, catalog: catalog))
                }
            }

            Section {
                Button {
                    confirmingWeek = 0
                } label: {
                    Label("Für diese Woche übernehmen", systemImage: "calendar.badge.plus")
                }
                .accessibilityIdentifier("weekTemplate.applyThisWeek")
                Button {
                    confirmingWeek = 1
                } label: {
                    Label("Für nächste Woche übernehmen", systemImage: "calendar.badge.clock")
                }
                if let appliedText {
                    Label(appliedText, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    NavigationLink(value: NutritionRoute.mealPlan) {
                        Label("Zum Wochenplan und zur Einkaufsliste", systemImage: "cart")
                    }
                }
            } footer: {
                Text("Trägt je Mahlzeit eine Portion in den Wochenplan ein. Mittagsgerichte sind für zwei Portionen gedacht: einmal kochen, morgen weiteressen. Die Einkaufsliste füllst du im Wochenplan mit einem Tipp.")
            }

            Section {
                ForEach(Self.sources, id: \.self) { source in
                    Text(source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Grundlagen")
            } footer: {
                Text("Eine Orientierung, keine Ernährungstherapie. Ob Laktose oder Fruktose die Ursache sind, klärt ein Wasserstoff-Atemtest beim Hausarzt oder Gastroenterologen. Bei anhaltenden Beschwerden, Gewichtsverlust oder Blut im Stuhl bitte ärztlich abklären lassen.")
            }
        }
        .navigationTitle("Ernährungsplan")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Plan übernehmen?", isPresented: Binding(get: { confirmingWeek != nil }, set: { if !$0 { confirmingWeek = nil } }), titleVisibility: .visible) {
            Button("Übernehmen") {
                apply(template, weekOffset: confirmingWeek ?? 0, choices: choices)
            }
        } message: {
            Text("Schon geplante Mahlzeiten in dieser Woche werden ersetzt.")
        }
    }

    private func mealRow(day: MealPlanTemplate.Day, meal: MealType, choices: [String: String], recipes: RecipeCatalog, catalog: FoodCatalog) -> some View {
        let options = day.options(for: meal)
        let key = MealPlanTemplate.choiceKey(weekday: day.weekday, meal: meal)
        let chosen = choices[key].flatMap { options.contains($0) ? $0 : nil } ?? options.first ?? ""
        let recipe = recipes.recipe(id: chosen)
        return VStack(alignment: .leading, spacing: 4) {
            Picker(selection: Binding(
                get: { chosen },
                set: { value in
                    var updated = choices
                    updated[key] = value == options.first ? nil : value
                    choicesText = NutritionActions.encodeChoices(updated)
                }
            )) {
                ForEach(options, id: \.self) { id in
                    Text(recipes.recipe(id: id)?.title ?? id).tag(id)
                }
            } label: {
                Label(meal.title, systemImage: meal.symbol)
            }
            .pickerStyle(.navigationLink)
            if let recipe {
                NavigationLink(value: NutritionRoute.recipe(recipe.id)) {
                    Text(Self.nutritionLine(recipe, catalog: catalog))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Rezept \(recipe.title) ansehen")
            }
        }
    }

    /// „46 g Eiweiß · 680 kcal · 15 g Fett · 2 Optionen“
    static func nutritionLine(_ recipe: RecipeInfo, catalog: FoodCatalog) -> String {
        let protein = Int(recipe.proteinPerServing(catalog: catalog).rounded())
        let kcal = Int(recipe.kcalPerServing(catalog: catalog).rounded())
        let fat = Int(recipe.fatPerServing(catalog: catalog).rounded())
        return "\(protein) g Eiweiß · \(kcal) kcal · \(fat) g Fett · \(recipe.minutes) Min."
    }

    private func dayTotals(_ day: MealPlanTemplate.Day, choices: [String: String], recipes: RecipeCatalog, catalog: FoodCatalog) -> String {
        var protein = 0.0
        var kcal = 0.0
        for meal in MealType.allCases {
            let options = day.options(for: meal)
            let id = choices[MealPlanTemplate.choiceKey(weekday: day.weekday, meal: meal)].flatMap { options.contains($0) ? $0 : nil } ?? options.first
            guard let id, let recipe = recipes.recipe(id: id) else { continue }
            protein += recipe.proteinPerServing(catalog: catalog)
            kcal += recipe.kcalPerServing(catalog: catalog)
        }
        return "Tag: etwa \(GermanNumber.grouped(Int((kcal / 10).rounded()) * 10)) kcal und \(Int(protein.rounded())) g Eiweiß"
    }

    private func apply(_ template: MealPlanTemplate, weekOffset: Int, choices: [String: String]) {
        let calendar = AppModel.calendar
        let monday = AgendaBuilder.startOfWeek(containing: .now, calendar: calendar)
        let start = calendar.date(byAdding: .day, value: 7 * weekOffset, to: monday) ?? monday
        let count = NutritionActions.applyTemplate(template, weekStart: start, choices: choices, calendar: calendar, in: context)
        app.nutritionChanged()
        appliedText = "\(count) Mahlzeiten für \(weekOffset == 0 ? "diese" : "nächste") Woche eingetragen"
        confirmingWeek = nil
    }

    static let sources = [
        "Laktose: EFSA-Gremium für Ernährung (2010). Scientific Opinion on lactose thresholds in lactose intolerance and galactosaemia. EFSA Journal 8(9):1777. Bis etwa 12 g Laktose auf einmal (z. B. ein Glas Milch) vertragen die meisten Betroffenen ohne oder mit leichten Beschwerden, verteilt über den Tag mehr.",
        "Fruktose: Fedewa A, Rao SSC (2014). Dietary fructose intolerance, fructan intolerance and FODMAPs. Current Gastroenterology Reports 16:370. Beschwerden hängen vor allem von freier Fruktose im Überschuss zur Glukose, von Sorbit und von der Menge auf einmal ab.",
        "Fett und große Mahlzeiten: Feinle-Bisset C, Azpiroz F (2013). Dietary and lifestyle factors in functional dyspepsia. Nature Reviews Gastroenterology & Hepatology 10:150–157. Fettreiche und große Mahlzeiten verzögern die Magenentleerung und verstärken Völlegefühl und Übelkeit.",
        "Eiweiß: Morton RW et al. (2018). A systematic review, meta-analysis and meta-regression of the effect of protein supplementation on resistance training-induced gains in muscle mass and strength. British Journal of Sports Medicine 52:376–384. Zuwachs bis etwa 1,6 g je kg Körpergewicht am Tag, darüber kaum noch Unterschied.",
        "Eiweiß je Mahlzeit: Schoenfeld BJ, Aragon AA (2018). How much protein can the body use in a single meal for muscle-building? Journal of the International Society of Sports Nutrition 15:10. Empfehlung: etwa 0,4 g je kg pro Mahlzeit, verteilt auf mindestens vier Mahlzeiten.",
        "Ausgewogen essen: Deutsche Gesellschaft für Ernährung (2024). Gut essen und trinken – die DGE-Empfehlungen. Viel Gemüse, Vollkorn, Hülsenfrüchte und Obst, wenig rotes Fleisch und Wurst.",
    ]
}
