import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Filter im Lexikon.
private enum LexiconFilter: Hashable {
    case all
    case score(FoodScore)
    case mine

    var title: String {
        switch self {
        case .all: "Alle"
        case let .score(score): "\(score.rawValue)"
        case .mine: "Meine"
        }
    }
}

/// Lebensmittel-Lexikon mit Suche und Filter nach Bewertung.
struct FoodLexiconView: View {
    @Environment(\.modelContext) private var context
    @Query private var preferences: [FoodPreference]
    @Query private var customFoods: [CustomFood]
    @State private var query = ""
    @State private var filter: LexiconFilter = .all
    @State private var creating = false
    @State private var scanning = false
    @State private var askingClaude = false
    @AppStorage(SettingsKeys.sensitivities) private var sensitivityText = ""

    var body: some View {
        let profile = SensitivityProfile.decode(sensitivityText)
        let catalog = NutritionActions.catalog(custom: customFoods, profile: profile)
        let tolerances = Dictionary(preferences.map { ($0.foodID, $0.tolerance) }, uniquingKeysWith: { $1 })
        let mine = Set(preferences.filter { $0.tolerance != .unknown || $0.isFavorite }.map(\.foodID)).union(customFoods.map(\.stableID))
        let results = catalog.search(query).filter { food in
            switch filter {
            case .all: true
            case let .score(score): (tolerances[food.id] ?? .unknown).effectiveScore(general: food.score) == score
            case .mine: mine.contains(food.id)
            }
        }
        List {
            Section {
                Picker("Filter", selection: $filter) {
                    ForEach([LexiconFilter.all, .score(.good), .score(.moderate), .score(.poor), .score(.bad), .mine], id: \.self) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                Text("0 gut · 1 mäßig · 2 schlecht · 3 sehr schlecht verträglich, für eine übliche Portion. Bewertet für: \(profile.summary).")
            }
            if query.isEmpty {
                ForEach(FoodGroup.make(catalog.grouped(results))) { group in
                    Section(group.category.title) {
                        ForEach(group.foods) { food in
                            NavigationLink(value: NutritionRoute.food(food.id)) {
                                FoodRow(food: food, tolerance: tolerances[food.id] ?? .unknown)
                            }
                        }
                    }
                }
            } else {
                Section {
                    ForEach(results) { food in
                        NavigationLink(value: NutritionRoute.food(food.id)) {
                            FoodRow(food: food, tolerance: tolerances[food.id] ?? .unknown)
                        }
                    }
                }
            }
        }
        .overlay {
            if results.isEmpty {
                ContentUnavailableView {
                    Label("Nichts gefunden", systemImage: "magnifyingglass")
                } description: {
                    Text(query.isEmpty ? "In diesem Filter ist noch nichts." : "„\(query)“ ist nicht im Lexikon. Du kannst es selbst anlegen.")
                } actions: {
                    if !query.isEmpty {
                        Button("Als eigenes Lebensmittel anlegen") { creating = true }
                        Button("Claude fragen") { askingClaude = true }
                            .accessibilityIdentifier("lexicon.claude")
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Lebensmittel suchen")
        .navigationTitle("Lexikon")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if BarcodeScannerSheet.isSupported {
                    Button {
                        scanning = true
                    } label: {
                        Image(systemName: "barcode.viewfinder")
                    }
                    .accessibilityLabel("Barcode scannen")
                }
                Button {
                    creating = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Eigenes Lebensmittel")
            }
        }
        .sheet(isPresented: $creating) {
            CustomFoodEditor(initialName: query) { _ in }
        }
        .sheet(isPresented: $scanning) {
            BarcodeScannerSheet { _ in }
        }
        .sheet(isPresented: $askingClaude) {
            ClaudeRequestSheet(task: .food, preset: ClaudePreset(foodName: query))
        }
    }
}

/// Lebensmittel auswählen (Mahlzeit, Einkaufsliste). Antippen übernimmt die übliche Portion.
struct FoodPickerView: View {
    let title: String
    let onPick: (FoodInfo, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var preferences: [FoodPreference]
    @Query private var customFoods: [CustomFood]
    @State private var query = ""
    @State private var creating = false
    @State private var scanning = false

    var body: some View {
        let catalog = NutritionActions.catalog(custom: customFoods)
        let tolerances = Dictionary(preferences.map { ($0.foodID, $0.tolerance) }, uniquingKeysWith: { $1 })
        let favorites = preferences.filter(\.isFavorite).compactMap { catalog.food(id: $0.foodID) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        let favoriteIDs = Set(favorites.map(\.id))
        let recent = NutritionActions.recentFoodIDs(limit: 14, in: context)
            .filter { !favoriteIDs.contains($0) }
            .prefix(10)
            .compactMap { catalog.food(id: $0) }
        let results = query.isEmpty ? [] : catalog.search(query, limit: 60)
        NavigationStack {
            List {
                if query.isEmpty {
                    if !favorites.isEmpty {
                        Section("Favoriten") {
                            ForEach(favorites) { pickRow($0, tolerances: tolerances) }
                        }
                    }
                    if !recent.isEmpty {
                        Section("Zuletzt") {
                            ForEach(recent) { pickRow($0, tolerances: tolerances) }
                        }
                    }
                    Section("Lexikon") {
                        ForEach(FoodGroup.make(catalog.grouped())) { group in
                            DisclosureGroup {
                                ForEach(group.foods) { pickRow($0, tolerances: tolerances) }
                            } label: {
                                Label(group.category.title, systemImage: group.category.symbol)
                            }
                        }
                    }
                } else {
                    Section {
                        ForEach(results) { pickRow($0, tolerances: tolerances) }
                        Button {
                            creating = true
                        } label: {
                            Label("„\(query)“ als eigenes Lebensmittel", systemImage: "plus.circle")
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Lebensmittel suchen")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                if BarcodeScannerSheet.isSupported {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            scanning = true
                        } label: {
                            Image(systemName: "barcode.viewfinder")
                        }
                        .accessibilityLabel("Barcode scannen")
                    }
                }
            }
            .sheet(isPresented: $creating) {
                CustomFoodEditor(initialName: query) { food in
                    onPick(food, food.portion)
                    dismiss()
                }
            }
            .sheet(isPresented: $scanning) {
                BarcodeScannerSheet { food in
                    onPick(food, food.portion)
                    dismiss()
                }
            }
        }
    }

    private func pickRow(_ food: FoodInfo, tolerances: [String: Tolerance]) -> some View {
        Button {
            onPick(food, food.portion)
            dismiss()
        } label: {
            FoodRow(food: food, tolerance: tolerances[food.id] ?? .unknown, detail: food.unit ?? food.amountLabel(grams: food.portion))
        }
        .accessibilityIdentifier("foodPicker.\(food.id)")
    }
}

/// Ein Lebensmittel: Bewertung, Markierungen, Tipps, eigene Einschätzung.
struct FoodDetailView: View {
    let foodID: String

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var preferences: [FoodPreference]
    @Query private var customFoods: [CustomFood]
    @State private var addedToShopping = false
    @State private var editing = false

    var body: some View {
        let catalog = NutritionActions.catalog(custom: customFoods)
        let food = NutritionActions.food(foodID, catalog: catalog)
        let preference = preferences.first { $0.foodID == foodID }
        let tolerance = preference?.tolerance ?? .unknown
        let effective = tolerance.effectiveScore(general: food.score)
        let profile = catalog.profile ?? NutritionActions.profile
        let hints = food.hints(for: profile)
        List {
            Section {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    HStack(spacing: Spacing.s) {
                        IconBadge(systemImage: food.category.symbol, tint: effective.color, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(food.name)
                                .font(.title3.weight(.bold))
                            Text([food.brand, food.category.title].compactMap { $0 }.joined(separator: " · "))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    ScoreBadge(score: food.score, showsTitle: true)
                    if tolerance != .unknown, effective != food.score {
                        Text("Für dich gerechnet mit \(effective.rawValue), weil du „\(tolerance.title)“ gewählt hast.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, Spacing.xxs)
            }
            if !profile.active.isEmpty {
                Section {
                    ForEach(profile.ordered) { sensitivity in
                        SensitivityRow(sensitivity: sensitivity, food: food)
                    }
                } header: {
                    Text("Für eine Portion (\(food.amountLabel(grams: food.portion)))")
                } footer: {
                    Text("Bewertet nach deinen Profilen. Ändern unter Ernährung → Ziele und Einstellungen.")
                }
            }
            if !food.flags.isEmpty || !hints.isEmpty {
                Section("Warum") {
                    ForEach(food.flags) { flag in
                        Label(flag.title, systemImage: "tag")
                    }
                    ForEach(hints, id: \.self) { hint in
                        Label(hint, systemImage: "lightbulb")
                    }
                }
            }
            Section {
                Picker("Bei mir", selection: Binding(
                    get: { tolerance },
                    set: { value in
                        NutritionActions.setTolerance(value, for: foodID, in: context)
                        app.nutritionChanged()
                    }
                )) {
                    ForEach(Tolerance.allCases) { value in
                        Label(value.title, systemImage: value.symbol).tag(value)
                    }
                }
                .accessibilityIdentifier("food.tolerance")
                Toggle(isOn: Binding(
                    get: { preference?.isFavorite ?? false },
                    set: { NutritionActions.setFavorite($0, for: foodID, in: context) }
                )) {
                    Label("Favorit", systemImage: "star")
                }
            } header: {
                Text("Deine Erfahrung")
            } footer: {
                Text("Deine Einschätzung hat Vorrang vor der Standardbewertung und fließt in Tageslast und Rezepte ein.")
            }
            Section("Nährwerte je 100 g") {
                LabeledContent("Eiweiß", value: food.protein.map { "\(WeightFormat.number($0)) g" } ?? "–")
                LabeledContent("Energie", value: food.kcal.map { "\(Int($0.rounded())) kcal" } ?? "–")
                LabeledContent("Fett", value: food.ratings.fat.map { "\(WeightFormat.number($0)) g" } ?? "–")
                LabeledContent("Laktose", value: food.ratings.lactose.map { "\(WeightFormat.number($0)) g" } ?? "keine Angabe")
                LabeledContent("Übliche Portion", value: food.unit.map { "\($0) (\(WeightFormat.number(food.portion)) g)" } ?? food.amountLabel(grams: food.portion))
            }
            if let tip = food.category.tip(for: profile) {
                Section("Tipp") {
                    Text(tip)
                        .font(.subheadline)
                }
            }
            if let ingredients = food.ingredients, !ingredients.isEmpty {
                Section("Zutaten") {
                    Text(ingredients)
                        .font(.footnote)
                    IngredientReportView(report: NutritionActions.analyzer.analyze(ingredients))
                }
            }
            Section {
                Button {
                    app.logMeal(items: [MealDraftItem(foodID: food.id, grams: food.portion)])
                } label: {
                    Label("Als Mahlzeit eintragen", systemImage: "fork.knife")
                }
                Button {
                    NutritionActions.addShoppingItem(food.name, foodID: food.id, catalog: catalog, in: context)
                    addedToShopping = true
                } label: {
                    Label(addedToShopping ? "Auf der Einkaufsliste" : "Auf die Einkaufsliste", systemImage: addedToShopping ? "checkmark" : "cart.badge.plus")
                }
                .disabled(addedToShopping)
                if food.isCustom {
                    Button {
                        editing = true
                    } label: {
                        Label("Bearbeiten", systemImage: "pencil")
                    }
                    Button("Lebensmittel löschen", role: .destructive) {
                        NutritionActions.deleteCustomFood(id: food.id, in: context)
                        dismiss()
                    }
                }
            }
            Section {
                NutritionDisclaimer()
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(food.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editing) {
            CustomFoodEditor(existing: food) { _ in }
        }
    }
}

/// Bewertung eines Lebensmittels für ein Profil, mit Menge.
private struct SensitivityRow: View {
    let sensitivity: Sensitivity
    let food: FoodInfo

    var body: some View {
        let score = food.ratings.score(for: sensitivity, grams: food.portion)
        HStack(spacing: Spacing.s) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sensitivity.title)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: sensitivity.symbol)
                    .foregroundStyle(score.color)
            }
            Spacer(minLength: Spacing.xs)
            ScoreBadge(score: score)
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        switch sensitivity {
        case .lactose:
            let grams = food.lactose(grams: food.portion)
            return grams < 0.05 ? "laktosefrei" : "\(WeightFormat.number((grams * 10).rounded() / 10)) g Laktose"
        case .fat:
            return "\(WeightFormat.number(food.fat(grams: food.portion).rounded())) g Fett"
        case .fructose:
            var text = food.ratings.fructose == .good ? "unauffällig" : "Fruktose-Überschuss \(food.ratings.fructose.title)"
            if food.ratings.sorbitol { text += ", Sorbit" }
            return text
        case .histamine:
            return food.ratings.histamine.title
        }
    }
}

/// Eigenes Lebensmittel anlegen oder bearbeiten.
struct CustomFoodEditor: View {
    var initialName = ""
    var existing: FoodInfo?
    let onSave: (FoodInfo) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var category: FoodCategory = .other
    @State private var score: FoodScore = .moderate
    @State private var flags: Set<FoodFlag> = []
    @State private var protein = ""
    @State private var portion = 100.0
    @State private var didLoad = false

    init(initialName: String = "", existing: FoodInfo? = nil, onSave: @escaping (FoodInfo) -> Void) {
        self.initialName = initialName
        self.existing = existing
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("customFood.name")
                    Picker("Kategorie", selection: $category) {
                        ForEach(FoodCategory.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                }
                Section {
                    ForEach([FoodFlag.lactose, .fructose, .sorbitol, .fatRich]) { flag in
                        flagToggle(flag)
                    }
                } header: {
                    Text("Verträglichkeit")
                } footer: {
                    Text("Was auf der Packung steht oder was du weißt. Unsicher? Lieber einschalten und nach ein paar Mahlzeiten anpassen.")
                }
                if NutritionActions.profile.contains(.histamine) {
                    Section {
                        Picker("Bewertung", selection: $score) {
                            ForEach(FoodScore.allCases) { item in
                                Text(item.label).tag(item)
                            }
                        }
                        ForEach(FoodFlag.allCases.filter { $0.sensitivity == .histamine }) { flag in
                            flagToggle(flag)
                        }
                    } header: {
                        Text("Histamin")
                    }
                }
                Section("Nährwerte") {
                    HStack {
                        Text("Eiweiß je 100 g")
                        Spacer()
                        TextField("g", text: $protein)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    Stepper(value: $portion, in: 5...1_000, step: 5) {
                        LabeledContent("Übliche Portion", value: "\(WeightFormat.number(portion)) g")
                    }
                }
            }
            .navigationTitle(existing == nil ? "Eigenes Lebensmittel" : "Bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if let existing {
                name = existing.name
                category = existing.category
                // Gespeichert wird die Histamin-Bewertung, Laktose, Fruktose und Fett als Markierungen.
                let ratings = existing.ratings
                score = ratings.histamine
                var loaded = Set(ratings.histamineFlags)
                if (ratings.lactose ?? 0) >= 1 { loaded.insert(.lactose) }
                if ratings.fructose >= .poor { loaded.insert(.fructose) }
                if ratings.sorbitol { loaded.insert(.sorbitol) }
                if (ratings.fat ?? 0) >= 20 { loaded.insert(.fatRich) }
                flags = loaded
                protein = existing.protein.map { WeightFormat.number($0) } ?? ""
                portion = existing.portion
            } else {
                name = initialName
                if let guess = NutritionActions.bundledFoods.bestMatch(for: initialName) {
                    category = guess.category
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let catalog = NutritionActions.catalog(in: context)
        var info = existing ?? FoodInfo(
            id: NutritionActions.customFoodID(for: trimmed, catalog: catalog),
            name: trimmed, category: category, score: score, isCustom: true
        )
        info.name = trimmed
        info.category = category
        info.score = score
        info.flags = FoodFlag.allCases.filter(flags.contains)
        info.ratings = FoodRatings.legacy(score: score, flags: info.flags)
        info.protein = Double(protein.replacingOccurrences(of: ",", with: "."))
        info.portion = portion
        info.isCustom = true
        NutritionActions.saveCustomFood(info, in: context)
        onSave(info)
        dismiss()
    }

    private func flagToggle(_ flag: FoodFlag) -> some View {
        Toggle(flag.title, isOn: Binding(
            get: { flags.contains(flag) },
            set: { if $0 { flags.insert(flag) } else { flags.remove(flag) } }
        ))
    }
}
