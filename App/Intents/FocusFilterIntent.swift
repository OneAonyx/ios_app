import AppIntents
import SwiftData
import TagwerkCore
import TagwerkKit

/// Aufgabenliste für Fokus-Filter und Kurzbefehle.
struct TaskListEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Liste"
    static let defaultQuery = TaskListQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct TaskListQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [TaskListEntity] {
        allLists().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [TaskListEntity] {
        allLists()
    }

    @MainActor
    private func allLists() -> [TaskListEntity] {
        let lists = (try? AppModel.shared.context.fetch(FetchDescriptor<TaskList>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
        return lists.map { TaskListEntity(id: $0.stableID, name: $0.name) }
    }
}

/// Fokus-Filter (Einstellungen → Fokus → z. B. „Arbeit“ → Filter hinzufügen → Orbit).
/// Blendet auf „Heute“ Bereiche aus oder zeigt nur eine Liste. Erinnerungen an
/// Medikamente bleiben immer aktiv.
struct OrbitFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Orbit im Fokus"
    static let description = IntentDescription("Blendet auf „Heute“ Training oder Ernährung aus oder zeigt nur eine Aufgabenliste, solange der Fokus aktiv ist.")

    @Parameter(title: "Training ausblenden", default: false)
    var hideTraining: Bool

    @Parameter(title: "Ernährung ausblenden", default: false)
    var hideNutrition: Bool

    @Parameter(title: "Nur diese Liste")
    var list: TaskListEntity?

    var state: FocusFilterState {
        FocusFilterState(hideTraining: hideTraining, hideNutrition: hideNutrition, listID: list?.id, listName: list?.name)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "Orbit", subtitle: "\(state.summary)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        FocusFilterStore.write(state)
        AppModel.shared.focusFilterChanged()
        return .result()
    }
}
