import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Einkaufsliste nach Bereichen im Supermarkt, mit Warnung bei kritischen Lebensmitteln.
struct ShoppingListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ShoppingItem.createdAt) private var items: [ShoppingItem]
    @Query private var preferences: [FoodPreference]
    @Query private var customFoods: [CustomFood]
    @State private var newItem = ""
    @State private var picking = false
    @FocusState private var focused: Bool

    var body: some View {
        let catalog = NutritionActions.bundledFoods.adding(customFoods.map(\.info))
        let tolerances = Dictionary(preferences.map { ($0.foodID, $0.tolerance) }, uniquingKeysWith: { $1 })
        let open = items.filter { !$0.isDone }
        let done = items.filter(\.isDone)
        let groups = Dictionary(grouping: open, by: \.category)
        List {
            Section {
                HStack {
                    TextField("Artikel hinzufügen", text: $newItem)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit { add(catalog: catalog) }
                        .accessibilityIdentifier("shopping.new")
                    if !newItem.isEmpty {
                        Button {
                            add(catalog: catalog)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                        }
                        .tint(ModuleAccent.nutrition)
                        .accessibilityLabel("Hinzufügen")
                    }
                    Button {
                        picking = true
                    } label: {
                        Image(systemName: "books.vertical")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Aus dem Lexikon")
                }
                if let match = suggestion(catalog: catalog) {
                    let score = (tolerances[match.id] ?? .unknown).effectiveScore(general: match.score)
                    if score >= .poor {
                        Label("\(match.name): \(score.title)", systemImage: score.symbol)
                            .font(.footnote)
                            .foregroundStyle(score.textColor)
                    }
                }
            }
            ForEach(ShoppingCategory.allCases) { category in
                if let entries = groups[category], !entries.isEmpty {
                    Section {
                        ForEach(entries) { item in
                            ShoppingRow(item: item, score: score(of: item, catalog: catalog, tolerances: tolerances))
                        }
                        .onDelete { offsets in
                            offsets.map { entries[$0] }.forEach { NutritionActions.delete($0, in: context) }
                        }
                    } header: {
                        Label(category.title, systemImage: category.symbol)
                    }
                }
            }
            if !done.isEmpty {
                Section("Erledigt") {
                    ForEach(done) { item in
                        ShoppingRow(item: item, score: nil)
                    }
                    Button("Erledigte entfernen", role: .destructive) {
                        NutritionActions.clearDoneShopping(in: context)
                    }
                }
            }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView(
                    "Einkaufsliste ist leer",
                    systemImage: "cart",
                    description: Text("Tippe oben einen Artikel ein oder füge Zutaten aus Rezepten und dem Wochenplan hinzu.")
                )
                .padding(.top, 120)
            }
        }
        .navigationTitle("Einkaufsliste")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: NutritionRoute.mealPlan) {
                    Image(systemName: "calendar")
                }
                .accessibilityLabel("Wochenplan")
            }
        }
        .sheet(isPresented: $picking) {
            FoodPickerView(title: "Auf die Liste") { food, _ in
                NutritionActions.addShoppingItem(food.name, foodID: food.id, catalog: catalog, in: context)
            }
        }
    }

    private func suggestion(catalog: FoodCatalog) -> FoodInfo? {
        let text = newItem.trimmingCharacters(in: .whitespaces)
        guard text.count >= 3 else { return nil }
        return catalog.bestMatch(for: text)
    }

    private func score(of item: ShoppingItem, catalog: FoodCatalog, tolerances: [String: Tolerance]) -> HistamineScore? {
        guard let id = item.foodID, let food = catalog.food(id: id) else { return nil }
        return (tolerances[id] ?? .unknown).effectiveScore(general: food.score)
    }

    private func add(catalog: FoodCatalog) {
        let text = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // „500 g Hackfleisch“ → Menge und Name trennen.
        let (amount, name) = Self.splitAmount(text)
        NutritionActions.addShoppingItem(name, amount: amount, catalog: catalog, in: context)
        newItem = ""
        focused = true
    }

    /// Trennt eine führende Mengenangabe ab: „2 Gurken“, „500 g Quark“, „1,5 l Milch“.
    static func splitAmount(_ text: String) -> (amount: String, name: String) {
        let parts = text.split(separator: " ", maxSplits: 2).map(String.init)
        guard let first = parts.first, first.first?.isNumber == true, parts.count >= 2 else { return ("", text) }
        let units: Set<String> = ["g", "kg", "ml", "l", "stück", "stk", "pck", "packung", "dose", "dosen", "bund", "becher", "flasche", "flaschen", "glas"]
        if parts.count == 3, units.contains(parts[1].lowercased()) {
            return ("\(first) \(parts[1])", parts[2])
        }
        return (first, parts.dropFirst().joined(separator: " "))
    }
}

private struct ShoppingRow: View {
    let item: ShoppingItem
    let score: HistamineScore?

    @Environment(\.modelContext) private var context

    var body: some View {
        Button {
            NutritionActions.toggle(item, in: context)
        } label: {
            HStack(spacing: Spacing.s) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isDone ? Color.green : ModuleAccent.nutrition)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .strikethrough(item.isDone)
                        .foregroundStyle(item.isDone ? Color.secondary : Color.primary)
                    if !item.amount.isEmpty {
                        Text(item.amount)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: Spacing.xs)
                if let score, score >= .poor, !item.isDone {
                    ScoreBadge(score: score)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: item.isDone)
        .accessibilityIdentifier("shopping.item")
    }
}
