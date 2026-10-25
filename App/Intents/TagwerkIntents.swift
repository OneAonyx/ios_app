import AppIntents
import TagwerkKit

/// Letzte Aktion im Kurzbefehl „Tagwerk Claude“: übergibt Claudes Antwort an Tagwerk.
struct ImportClaudeResponseIntent: AppIntent {
    static let title: LocalizedStringResource = "Claude-Antwort übernehmen"
    static let description = IntentDescription(
        "Übergibt eine Antwort von Claude an Tagwerk. Wird im Kurzbefehl „Tagwerk Claude“ benutzt."
    )
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Antwort")
    var response: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        ClaudeBridgeInbox.store(response)
        return .result(dialog: "Antwort an Tagwerk übergeben.")
    }
}

/// Öffnet den Systemcheck, z. B. per Siri: „Tagwerk Systemcheck“.
struct OpenSystemCheckIntent: AppIntent {
    static let title: LocalizedStringResource = "Systemcheck öffnen"
    static let description = IntentDescription("Öffnet den Phase-0-Systemcheck in Tagwerk.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.openSystemCheck()
        return .result()
    }
}

struct TagwerkShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenSystemCheckIntent(),
            phrases: [
                "Öffne den Systemcheck in \(.applicationName)",
                "\(.applicationName) Systemcheck",
            ],
            shortTitle: "Systemcheck",
            systemImageName: "checkmark.seal"
        )
    }
}
