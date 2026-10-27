import CoreSpotlight
import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit
import UniformTypeIdentifiers

/// Treffer aus der iPhone-Suche (Spotlight), der in Orbit geöffnet werden soll.
struct SpotlightLink: Identifiable, Hashable {
    enum Kind: String, CaseIterable {
        case task, food, exercise, recipe, habit, contract, birthday
    }

    let kind: Kind
    let itemID: String

    var id: String { SpotlightIndexer.identifier(kind, itemID) }
}

/// Macht Aufgaben, Lebensmittel, Übungen, Rezepte, Routinen, Verträge und Geburtstage
/// in der iPhone-Suche auffindbar. Alles bleibt auf dem Gerät.
@MainActor
enum SpotlightIndexer {
    private static let contentKey = "tagwerk.spotlight.content"
    private static let personalKey = "tagwerk.spotlight.personal"
    private static let contentKinds: [SpotlightLink.Kind] = [.food, .exercise, .recipe]
    private static let personalKinds: [SpotlightLink.Kind] = [.task, .habit, .contract, .birthday]

    nonisolated static func identifier(_ kind: SpotlightLink.Kind, _ id: String) -> String { "\(kind.rawValue):\(id)" }

    nonisolated static func link(for identifier: String) -> SpotlightLink? {
        guard let colon = identifier.firstIndex(of: ":"),
              let kind = SpotlightLink.Kind(rawValue: String(identifier[..<colon])) else { return nil }
        return SpotlightLink(kind: kind, itemID: String(identifier[identifier.index(after: colon)...]))
    }

    /// Indiziert nur, was sich geändert hat (Inhalte je App-Version, eigene Daten per Prüfsumme).
    static func refresh(context: ModelContext, now: Date = .now) async {
        guard CSSearchableIndex.isIndexingAvailable(), !AppInfo.isUITesting else { return }
        let defaults = UserDefaults.standard

        let foods = NutritionActions.catalog(in: context).foods
        let exercises = TrainingActions.catalog(in: context).exercises
        let recipes = NutritionActions.recipes(in: context).recipes
        let contentSignature = "\(AppInfo.version)-\(AppInfo.build)-\(foods.count)-\(exercises.count)-\(recipes.count)"
        if defaults.string(forKey: contentKey) != contentSignature {
            var items: [CSSearchableItem] = []
            items += foods.map { food in
                item(.food, food.id, title: food.name, detail: "Histamin \(food.score.rawValue) · \(food.score.title) · \(food.category.title)", keywords: food.aliases + ["Lebensmittel", "Histamin"])
            }
            items += exercises.map { exercise in
                let muscles = exercise.primary.map(\.title).joined(separator: ", ")
                return item(.exercise, exercise.id, title: exercise.name, detail: "Übung · \(muscles) · \(exercise.equipment.title)", keywords: exercise.aliases + ["Übung", "Training"])
            }
            items += recipes.map { recipe in
                item(.recipe, recipe.id, title: recipe.title, detail: "Rezept · \(recipe.minutes) Min. · \(recipe.summary)", keywords: recipe.tags + ["Rezept"])
            }
            if await replace(domains: contentKinds, with: items) {
                defaults.set(contentSignature, forKey: contentKey)
            }
        }

        let calendar = AppModel.calendar
        let tasks = ((try? context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate<TaskItem> { !$0.isDone }))) ?? []).prefix(500)
        var personal: [CSSearchableItem] = tasks.map { task in
            var parts: [String] = ["Aufgabe"]
            if let due = task.dueDate { parts.append(DueFormatter.label(due: due, hasTime: task.hasDueTime, now: now, calendar: calendar)) }
            if let list = task.list?.name { parts.append(list) }
            if !task.notes.isEmpty { parts.append(task.notes) }
            return item(.task, task.stableID, title: task.title, detail: parts.joined(separator: " · "), keywords: task.tags)
        }
        personal += LifeActions.habits(in: context).map { habit in
            item(.habit, habit.stableID, title: habit.name, detail: "\(habit.kind == .routine ? "Routine" : "Gewohnheit") · \(habit.schedule.summary)", keywords: ["Routine", "Gewohnheit"])
        }
        personal += LifeActions.contracts(in: context).map { contract in
            item(.contract, contract.stableID, title: contract.name, detail: "\(contract.kind.title) · \(ContractLogic.statusText(contract.fact, now: now, calendar: calendar))", keywords: [contract.provider, "Vertrag", "Frist"].filter { !$0.isEmpty })
        }
        personal += LifeActions.birthdays(in: context).map { birthday in
            let fact = birthday.fact
            return item(.birthday, birthday.stableID, title: birthday.name, detail: "Geburtstag · \(BirthdayLogic.dateText(fact)) · \(BirthdayLogic.whenText(fact, now: now, calendar: calendar))", keywords: ["Geburtstag"])
        }
        let personalSignature = checksum(personal.map { "\($0.uniqueIdentifier)|\($0.attributeSet.title ?? "")|\($0.attributeSet.contentDescription ?? "")" }.joined(separator: "\n"))
        if defaults.string(forKey: personalKey) != personalSignature, await replace(domains: personalKinds, with: personal) {
            defaults.set(personalSignature, forKey: personalKey)
        }
    }

    private static func item(_ kind: SpotlightLink.Kind, _ id: String, title: String, detail: String, keywords: [String]) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = title
        attributes.displayName = title
        attributes.contentDescription = detail
        attributes.keywords = keywords
        return CSSearchableItem(uniqueIdentifier: identifier(kind, id), domainIdentifier: kind.rawValue, attributeSet: attributes)
    }

    private static func replace(domains: [SpotlightLink.Kind], with items: [CSSearchableItem]) async -> Bool {
        let index = CSSearchableIndex.default()
        do {
            try await index.deleteSearchableItems(withDomainIdentifiers: domains.map(\.rawValue))
            if !items.isEmpty {
                try await index.indexSearchableItems(items)
            }
            return true
        } catch {
            return false
        }
    }

    /// FNV-1a, stabil über App-Starts (anders als `hashValue`).
    private static func checksum(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}

/// Öffnet einen Spotlight-Treffer als Blatt.
struct SpotlightSheet: View {
    let link: SpotlightLink

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    var body: some View {
        if link.kind == .birthday {
            BirthdayEditorView(birthday: LifeActions.birthdays(in: context).first { $0.stableID == link.itemID })
        } else {
            NavigationStack {
                content
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Fertig") { dismiss() }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch link.kind {
        case .food:
            FoodDetailView(foodID: link.itemID)
        case .exercise:
            ExerciseDetailView(exerciseID: link.itemID)
        case .recipe:
            RecipeDetailView(recipeID: link.itemID)
        case .habit:
            if let habit = LifeActions.habit(stableID: link.itemID, in: context) {
                HabitDetailView(habit: habit)
            } else {
                missing
            }
        case .contract:
            if let contract = LifeActions.contract(stableID: link.itemID, in: context) {
                ContractEditorView(contract: contract)
            } else {
                missing
            }
        case .task, .birthday:
            missing
        }
    }

    private var missing: some View {
        ContentUnavailableView("Nicht mehr vorhanden", systemImage: "questionmark.folder", description: Text("Dieser Eintrag wurde gelöscht."))
    }
}
