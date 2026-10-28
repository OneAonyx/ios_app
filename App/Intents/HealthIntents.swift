import AppIntents
import Foundation
import TagwerkCore
import TagwerkKit

// Apple Health über Kurzbefehle: Die Kurzbefehle-App liest Health und gibt die Werte an Orbit.
// Orbit liefert Wasser und Gewicht zurück, die der Kurzbefehl in Health einträgt.

/// „Health-Werte an Orbit“: übernimmt Tageswerte aus Health. Alle Felder sind freiwillig.
struct ImportHealthValuesIntent: AppIntent {
    static let title: LocalizedStringResource = "Health-Werte an Orbit"
    static let description = IntentDescription("Übergibt Schritte, Strecke, Stockwerke, Schlaf, Ruhepuls und Gewicht aus Apple Health an Orbit. Leere Felder werden übersprungen.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Schritte")
    var steps: Int?

    @Parameter(title: "Strecke (km)")
    var distanceKm: Double?

    @Parameter(title: "Stockwerke")
    var flights: Int?

    @Parameter(title: "Schlaf (Stunden oder Minuten)")
    var sleep: Double?

    @Parameter(title: "Ruhepuls")
    var restingHeartRate: Int?

    @Parameter(title: "Gewicht (kg)")
    var weightKg: Double?

    @Parameter(title: "Tag (leer = heute)")
    var day: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Health-Werte an Orbit: \(\.$steps) Schritte") {
            \.$distanceKm
            \.$flights
            \.$sleep
            \.$restingHeartRate
            \.$weightKg
            \.$day
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let app = AppModel.shared
        let values = HealthValues(steps: steps, distanceKm: distanceKm, flights: flights, sleepHours: sleep, restingHeartRate: restingHeartRate, weightKg: weightKg)
        let result = HealthActions.importValues(values, day: day ?? .now, calendar: AppModel.calendar, in: app.context)
        app.healthChanged()
        var text = "Orbit hat übernommen: \(result.stored.summary)."
        if !result.rejected.isEmpty {
            text += " Nicht plausibel und übersprungen: \(result.rejected.joined(separator: ", "))."
        }
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

/// „Wasser für Health“: Wasser seit dem letzten Abruf in ml (0, wenn nichts dazukam).
struct WaterForHealthIntent: AppIntent {
    static let title: LocalizedStringResource = "Wasser für Health"
    static let description = IntentDescription("Gibt das Wasser in Millilitern zurück, das seit dem letzten Abruf heute in Orbit dazukam. Für die Aktion „Health-Probe protokollieren“.")
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        let milliliters = HealthActions.waterForHealth(calendar: AppModel.calendar, in: AppModel.shared.context)
        return .result(value: milliliters)
    }
}

/// „Gewicht für Health“: neuestes Gewicht aus Orbit, das noch nicht in Health ist (0 = nichts Neues).
struct WeightForHealthIntent: AppIntent {
    static let title: LocalizedStringResource = "Gewicht für Health"
    static let description = IntentDescription("Gibt das neueste in Orbit eingetragene Gewicht in kg zurück, wenn es noch nicht an Health ging. Sonst 0.")
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Double> {
        let weight = HealthActions.weightForHealth(in: AppModel.shared.context) ?? 0
        return .result(value: weight)
    }
}
