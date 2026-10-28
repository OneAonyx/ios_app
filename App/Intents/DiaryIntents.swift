import AppIntents
import Foundation
import TagwerkCore
import TagwerkKit

// Arzt-Tagebuch für Kurzbefehle und Siri. Ohne eigene Siri-Sätze (die zehn Plätze sind belegt),
// aber in der Kurzbefehle-App und in Automationen nutzbar.

/// Sportart für Kurzbefehle.
enum ActivityChoice: String, AppEnum {
    case walking, running, cycling, swimming, hiking, ballSports, racketSports, yoga, stretching, homeWorkout, climbing, dancing, martialArts, other

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Bewegung"
    static let caseDisplayRepresentations: [ActivityChoice: DisplayRepresentation] = [
        .walking: "Spazieren, Gehen",
        .running: "Laufen",
        .cycling: "Radfahren",
        .swimming: "Schwimmen",
        .hiking: "Wandern",
        .ballSports: "Ballsport",
        .racketSports: "Tennis, Badminton",
        .yoga: "Yoga",
        .stretching: "Dehnen, Mobility",
        .homeWorkout: "Training zuhause",
        .climbing: "Klettern, Bouldern",
        .dancing: "Tanzen",
        .martialArts: "Kampfsport",
        .other: "Sonstiges",
    ]

    var kind: ActivityKind { ActivityKind(rawValue: rawValue) ?? .other }
}

/// Anstrengung für Kurzbefehle.
enum IntensityChoice: String, AppEnum {
    case light, moderate, vigorous

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Anstrengung"
    static let caseDisplayRepresentations: [IntensityChoice: DisplayRepresentation] = [
        .light: "leicht",
        .moderate: "mittel",
        .vigorous: "intensiv",
    ]

    var intensity: ActivityIntensity {
        switch self {
        case .light: .light
        case .moderate: .moderate
        case .vigorous: .vigorous
        }
    }
}

/// „Bewegung eintragen“: trägt direkt ein, z. B. aus einer Automation nach dem Radfahren.
struct LogActivityIntent: AppIntent {
    static let title: LocalizedStringResource = "Bewegung eintragen"
    static let description = IntentDescription("Trägt Bewegung oder Sport ins Arzt-Tagebuch von Orbit ein.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Art", default: .walking)
    var kind: ActivityChoice

    @Parameter(title: "Minuten", default: 30)
    var minutes: Int

    @Parameter(title: "Anstrengung", default: .moderate)
    var intensity: IntensityChoice

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$kind) \(\.$minutes) Minuten, \(\.$intensity)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let app = AppModel.shared
        let duration = min(max(minutes, 1), 600)
        let fact = ActivityFact(date: .now.addingTimeInterval(-Double(duration) * 60), kind: kind.kind, minutes: duration, intensity: intensity.intensity)
        DiaryActions.addActivity(fact, in: app.context)
        app.diaryChanged()
        return .result(dialog: IntentDialog(stringLiteral: "\(fact.summary) eingetragen."))
    }
}

/// „Schmerz eintragen“: öffnet Orbit mit der Körperkarte.
struct LogPainIntent: AppIntent {
    static let title: LocalizedStringResource = "Schmerz eintragen"
    static let description = IntentDescription("Öffnet Orbit, um Schmerzen mit Ort und Stärke einzutragen.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.openPainEntry()
        return .result()
    }
}

/// „Heute keine Beschwerden“: vermerkt einen beschwerdefreien Tag.
struct SymptomFreeTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Heute keine Beschwerden"
    static let description = IntentDescription("Vermerkt im Arzt-Tagebuch, dass du heute keine Beschwerden hattest.")
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let app = AppModel.shared
        let facts = DiaryActions.today(calendar: AppModel.calendar, in: app.context)
        if facts.symptoms + facts.pains > 0 {
            return .result(dialog: "Für heute stehen schon Beschwerden im Tagebuch. Nichts geändert.")
        }
        DiaryActions.setSymptomFree(true, calendar: AppModel.calendar, in: app.context)
        app.diaryChanged()
        return .result(dialog: "Vermerkt: heute keine Beschwerden.")
    }
}
