import AppIntents
import Foundation
import TagwerkCore
import TagwerkKit

// Diese Datei gehört zu App UND Widget-Erweiterung (siehe project.yml, Ordner „Shared“):
// Das Widget braucht die Typen für seine Knöpfe, die App führt sie aus.
//
// Beide Intents sind `LiveActivityIntent`. Solche Intents führt iOS im Prozess der App
// aus (notfalls im Hintergrund gestartet), auch wenn sie aus einem Widget, dem
// Kontrollzentrum oder einem Wecker kommen. So stimmen Datenbank, Mitteilungen und
// Wecker sofort. Läuft der Code doch in der Erweiterung, greift die Warteschlange
// von `DoseActionCenter`.

/// Hakt eine bestimmte Einnahme ab (Widget-Knopf, „Genommen“ am Wecker).
struct TakeDoseIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Einnahme abhaken"
    static let description = IntentDescription("Markiert eine geplante Einnahme als genommen.")
    static let isDiscoverable = false
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Einnahme")
    var doseID: String

    @Parameter(title: "Quelle", default: "widget")
    var source: String

    init() {}

    init(doseID: String, source: String) {
        self.doseID = doseID
        self.source = source
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await DoseActionCenter.submit(PendingDoseAction(doseID: doseID, kind: .taken, at: .now, source: source))
        return .result()
    }
}

/// „Medikament genommen“: hakt die Einnahme ab, die gerade fällig ist
/// (Kontrollzentrum, Siri, Kurzbefehle).
struct TakeNextDoseIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Medikament genommen"
    static let description = IntentDescription("Hakt in Tagwerk die Einnahme ab, die gerade fällig ist.")
    static let openAppWhenRun: Bool = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date.now
        let calendar = GermanCalendar.make()
        let snapshot = DoseActionCenter.currentSnapshot()
        guard let dose = snapshot.actionableDose(now: now) else {
            if let next = snapshot.nextOpenDose(now: now) {
                let day = calendar.isDate(next.time, inSameDayAs: now) ? "" : "morgen "
                return .result(dialog: IntentDialog(stringLiteral: "Gerade ist nichts fällig. Als Nächstes: \(next.name) \(day)um \(GermanCalendar.time(next.time, calendar: calendar))."))
            }
            return .result(dialog: IntentDialog(stringLiteral: "Heute ist keine Einnahme mehr offen."))
        }
        await DoseActionCenter.submit(PendingDoseAction(doseID: dose.id, kind: .taken, at: now, source: "control"))
        return .result(dialog: IntentDialog(stringLiteral: "\(dose.name) ist abgehakt."))
    }
}
