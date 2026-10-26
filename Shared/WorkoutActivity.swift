import ActivityKit
import AppIntents
import Foundation
import TagwerkCore
import TagwerkKit

// Gehört zu App UND Widget-Erweiterung (siehe project.yml, Ordner „Shared“).

/// Live Activity während eines Trainings: Zeit, aktuelle Übung, Pause.
struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var sessionStart: Date
        var exerciseName: String
        /// z. B. „Satz 2 von 4 · 80 kg × 8“
        var detail: String
        /// Ende der laufenden Pause, `nil` = keine Pause.
        var restEndsAt: Date?
        var restSeconds: Int
        var doneSets: Int
        var totalSets: Int
    }

    /// „A · Push“
    var title: String
}

/// „+30 s“ in der Live Activity.
struct AddRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause verlängern"
    static let isDiscoverable = false
    static let openAppWhenRun: Bool = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await WorkoutActionCenter.submit(.addRest)
        return .result()
    }
}

/// „Überspringen“ in der Live Activity.
struct SkipRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause überspringen"
    static let isDiscoverable = false
    static let openAppWhenRun: Bool = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await WorkoutActionCenter.submit(.skipRest)
        return .result()
    }
}

/// „Satz fertig“ in der Live Activity: nächsten Satz mit den vorgeschlagenen Werten abhaken.
struct CompleteSetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Satz fertig"
    static let isDiscoverable = false
    static let openAppWhenRun: Bool = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await WorkoutActionCenter.submit(.completeSet)
        return .result()
    }
}

/// „Starte mein Training“: öffnet Orbit mit der nächsten Einheit (Kontrollzentrum, Siri).
struct StartWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Training starten"
    static let description = IntentDescription("Öffnet Orbit und startet die nächste Einheit deines Trainingsplans.")
    static let openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await WorkoutActionCenter.requestStart()
        return .result()
    }
}
