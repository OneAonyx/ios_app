import AppIntents
import Foundation
import TagwerkCore
import TagwerkKit

// Gehört zu App UND Widget-Erweiterung (Ordner „Shared“): Widget und Kontrollzentrum
// brauchen die Typen für ihre Knöpfe, die App führt sie aus (`LiveActivityIntent`).

/// „Wasser trinken“: trägt ein Glas Wasser ein (Widget, Kontrollzentrum, Siri).
struct AddWaterIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Wasser trinken"
    static let description = IntentDescription("Trägt in Orbit ein Glas Wasser ein.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Menge (ml)", default: 250)
    var milliliters: Int

    init() {}

    init(milliliters: Int) {
        self.milliliters = milliliters
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await NutritionActionCenter.submit(milliliters)
        let snapshot = NutritionSnapshotWriter.read().current(now: .now, calendar: GermanCalendar.make())
        return .result(dialog: IntentDialog(stringLiteral: "\(milliliters) ml eingetragen. Heute: \(NutritionDay.liters(snapshot.waterML)) von \(NutritionDay.liters(snapshot.waterTarget)) Litern."))
    }
}

/// „Symptom erfassen“: öffnet Orbit mit der Erfassung von Beschwerden.
struct LogSymptomIntent: AppIntent {
    static let title: LocalizedStringResource = "Beschwerden eintragen"
    static let description = IntentDescription("Öffnet Orbit, um Beschwerden wie Kopfschmerz oder Hautrötung einzutragen.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await NutritionActionCenter.requestSymptomEntry()
        return .result()
    }
}
