import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Mahlzeit eintragen oder bearbeiten.
struct MealEditorView: View {
    /// Vorhandene Mahlzeit (Bearbeiten) oder `nil` mit `draft` (neu).
    let meal: MealEntry?
    let draft: MealDraft?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var type: MealType = .lunch
    @State private var date: Date = .now
    @State private var freshness: Freshness = .fresh
    @State private var place: MealPlace = .home
    @State private var note = ""
    @State private var items: [MealDraftItem] = []
    @State private var recipeID: String?
    @State private var didLoad = false
    @State private var isPicking = false
    @State private var confirmDelete = false

    init(meal: MealEntry) {
        self.meal = meal
        self.draft = nil
    }

    init(draft: MealDraft) {
        self.meal = nil
        self.draft = draft
    }

    var body: some View {
        let catalog = NutritionActions.catalog(in: context)
        let tolerances = NutritionActions.tolerances(in: context)
        let fact = MealFact(
            id: "draft", date: date, type: type, freshness: freshness, place: place,
            items: items.map { item in
                let food = NutritionActions.food(item.foodID, catalog: catalog)
                return MealItemFact(
                    foodID: item.foodID, name: food.name, grams: item.grams,
                    score: (tolerances[item.foodID] ?? .unknown).effectiveScore(general: food.score),
                    flags: food.flags, proteinPer100: food.protein ?? 0, kcalPer100: food.kcal ?? 0
                )
            }
        )
        let mealLoad = HistamineLoad.compute([fact])
        NavigationStack {
            Form {
                if meal == nil {
                    MealMedicationSection()
                }
                Section {
                    Picker("Mahlzeit", selection: $type) {
                        ForEach(MealType.allCases) { type in
                            Label(type.title, systemImage: type.symbol).tag(type)
                        }
                    }
                    DatePicker("Zeit", selection: $date)
                }
                Section {
                    ForEach($items) { $item in
                        MealItemEditorRow(item: $item, food: NutritionActions.food(item.foodID, catalog: catalog), tolerance: tolerances[item.foodID] ?? .unknown)
                    }
                    .onDelete { items.remove(atOffsets: $0) }
                    Button {
                        isPicking = true
                    } label: {
                        Label("Lebensmittel hinzufügen", systemImage: "plus.circle.fill")
                    }
                    .accessibilityIdentifier("mealEditor.addFood")
                } header: {
                    Text("Was gab es?")
                } footer: {
                    if !items.isEmpty {
                        Text("\(Int(fact.protein.rounded())) g Eiweiß · \(Int(fact.kcal.rounded())) kcal · Histamin \(mealLoad.level.title)")
                    }
                }
                Section {
                    Picker("Zubereitung", selection: $freshness) {
                        ForEach(Freshness.allCases) { value in
                            Label(value.title, systemImage: value.symbol).tag(value)
                        }
                    }
                    Picker("Ort", selection: $place) {
                        ForEach(MealPlace.allCases) { value in
                            Label(value.title, systemImage: value.symbol).tag(value)
                        }
                    }
                    TextField("Notiz", text: $note, axis: .vertical)
                } footer: {
                    Text("Reste und Aufgewärmtes enthalten mehr Histamin als frisch Gekochtes.")
                }
                if meal != nil {
                    Section {
                        Button("Mahlzeit löschen", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(meal == nil ? "Mahlzeit eintragen" : "Mahlzeit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save(catalog: catalog) }
                        .disabled(items.isEmpty)
                        .accessibilityIdentifier("mealEditor.save")
                }
            }
            .sheet(isPresented: $isPicking) {
                FoodPickerView(title: "Lebensmittel") { food, grams in
                    items.append(MealDraftItem(foodID: food.id, grams: grams))
                }
            }
            .confirmationDialog("Mahlzeit löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    if let meal { NutritionActions.delete(meal, in: context) }
                    app.nutritionChanged()
                    dismiss()
                }
            }
        }
        .onAppear(perform: loadValues)
    }

    private func loadValues() {
        guard !didLoad else { return }
        didLoad = true
        if let meal {
            type = meal.type
            date = meal.date
            freshness = meal.freshness
            place = meal.place
            note = meal.note
            recipeID = meal.recipeID
            items = meal.sortedItems.map { MealDraftItem(foodID: $0.foodID, grams: $0.grams) }
        } else if let draft {
            type = draft.type
            date = draft.date
            items = draft.items
            recipeID = draft.recipeID
            freshness = draft.freshness
        }
    }

    private func save(catalog: FoodCatalog) {
        let pairs = items.map { (foodID: $0.foodID, grams: $0.grams) }
        if let meal {
            meal.type = type
            meal.date = date
            meal.freshness = freshness
            meal.place = place
            meal.note = note
            NutritionActions.setItems(pairs, of: meal, catalog: catalog, in: context)
        } else {
            NutritionActions.addMeal(
                type: type, date: date, freshness: freshness, place: place, items: pairs,
                recipeID: recipeID, note: note, catalog: catalog, in: context
            )
        }
        app.nutritionChanged()
        dismiss()
    }
}

/// Menge eines Lebensmittels in der Mahlzeit.
private struct MealItemEditorRow: View {
    @Binding var item: MealDraftItem
    let food: FoodInfo
    let tolerance: Tolerance

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(food.name)
                    .font(.body.weight(.medium))
                ToleranceMark(tolerance: tolerance)
                Spacer()
                ScoreBadge(score: tolerance.effectiveScore(general: food.score))
            }
            Stepper(value: $item.grams, in: 5...2_000, step: step) {
                Text(food.amountLabel(grams: item.grams))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var step: Double {
        food.portion <= 20 ? 5 : (food.portion <= 80 ? 10 : 25)
    }
}

/// „DAO schon genommen?“ – Medikamente mit dem Hinweis „vor dem Essen“.
private struct MealMedicationSection: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @State private var refresh = 0

    var body: some View {
        let prompts = NutritionActions.beforeMealMedications(calendar: AppModel.calendar, in: context)
        if !prompts.isEmpty {
            Section {
                ForEach(prompts) { prompt in
                    row(prompt)
                }
            } header: {
                Text("Vor dem Essen")
            }
            .id(refresh)
        }
    }

    @ViewBuilder
    private func row(_ prompt: MealMedicationPrompt) -> some View {
        let medication = prompt.medication
        HStack(spacing: Spacing.s) {
            MedicationIcon(symbol: medication.symbol, colorName: medication.colorName, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(medication.displayName)
                    .font(.subheadline.weight(.semibold))
                switch prompt.state {
                case let .taken(date):
                    Text("Genommen um \(GermanCalendar.time(date, calendar: AppModel.calendar))")
                        .font(.caption)
                        .foregroundStyle(.green)
                case .due:
                    Text("Schon genommen?")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .asNeeded:
                    Text("Bei Bedarf vor dem Essen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Spacing.xs)
            switch prompt.state {
            case .taken:
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
            case let .due(entry):
                Button("Genommen") {
                    MedicationActions.take(entry, medication: medication, in: context)
                    done()
                }
                .buttonStyle(.borderedProminent)
                .tint(ModuleAccent.medication)
                .accessibilityIdentifier("mealEditor.medication.take")
            case .asNeeded:
                Button("Jetzt genommen") {
                    MedicationActions.takeExtra(medication, amount: medication.defaultAmount, in: context)
                    done()
                }
                .buttonStyle(.bordered)
                .tint(ModuleAccent.medication)
            }
        }
    }

    private func done() {
        app.medicationsChanged()
        refresh += 1
    }
}
