import AppIntents
import Foundation
import TagwerkCore
import TagwerkKit

// Gehört zu App UND Widget-Erweiterung (Ordner „Shared“).

/// Hakt eine Aufgabe aus dem Widget „Aufgaben“ ab. Läuft im Prozess der App,
/// sonst über die Warteschlange von `TaskActionCenter`.
struct CompleteTaskIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Aufgabe abhaken"
    static let description = IntentDescription("Markiert eine Aufgabe in Orbit als erledigt.")
    static let isDiscoverable = false
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Aufgabe")
    var taskID: String

    init() {}

    init(taskID: String) {
        self.taskID = taskID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await TaskActionCenter.complete(taskID: taskID)
        return .result()
    }
}

/// Ziele in Orbit für Kontrollzentrum und Kurzbefehle.
enum OrbitRoute: String, AppEnum {
    case quickTask = "neu"
    case checkIn = "checkin"
    case life = "leben"
    case today = "heute"

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Bereich"
    static let caseDisplayRepresentations: [OrbitRoute: DisplayRepresentation] = [
        .quickTask: "Neue Aufgabe",
        .checkIn: "Check-in",
        .life: "Leben",
        .today: "Heute",
    ]
}

/// Öffnet Orbit an einer bestimmten Stelle (Kontrollzentrum).
struct OpenOrbitURLIntent: AppIntent {
    static let title: LocalizedStringResource = "Orbit öffnen"
    static let description = IntentDescription("Öffnet Orbit an einer bestimmten Stelle.")
    static let isDiscoverable = false
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Ziel", default: .today)
    var target: OrbitRoute

    init() {}

    init(target: OrbitRoute) {
        self.target = target
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await RouteCenter.open(target.rawValue)
        return .result()
    }
}
