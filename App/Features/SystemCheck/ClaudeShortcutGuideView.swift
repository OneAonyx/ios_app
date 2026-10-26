import SwiftUI
import TagwerkCore
import TagwerkKit

/// Schritt-für-Schritt-Anleitung für den Kurzbefehl „Orbit Claude“.
struct ClaudeShortcutGuideView: View {
    @Environment(\.openURL) private var openURL

    private struct Step: Identifiable {
        let id: Int
        let title: String
        let detail: String
    }

    private let steps: [Step] = [
        Step(id: 1, title: "Claude-App bereithalten",
             detail: "Installiere die Claude-App aus dem App Store und melde dich mit deinem Konto an."),
        Step(id: 2, title: "Neuen Kurzbefehl erstellen",
             detail: "Öffne die Kurzbefehle-App, tippe auf „+“ und nenne den Kurzbefehl genau „\(TagwerkIDs.claudeShortcutName)“."),
        Step(id: 3, title: "Claude fragen",
             detail: "Füge die Aktion „Ask Claude“ der Claude-App hinzu (auf Deutsch eventuell „Claude fragen“). Setze als Nachricht die Variable „Kurzbefehleingabe“."),
        Step(id: 4, title: "Antwort an Orbit geben",
             detail: "Füge die Aktion „Claude-Antwort übernehmen“ von Orbit hinzu. Wähle als Antwort das Ergebnis von „Ask Claude“."),
        Step(id: 5, title: "Antwort ausgeben",
             detail: "Füge als letzte Aktion „Stoppen und ausgeben“ hinzu (englisch „Stop and Output“), ebenfalls mit dem Ergebnis von „Ask Claude“."),
        Step(id: 6, title: "Testen",
             detail: "Zurück in Orbit: Systemcheck → Claude-Brücke → „Kurzbefehl starten“."),
    ]

    var body: some View {
        List {
            Section {
                Text("Orbit nutzt dein normales Claude-Konto über die Claude-App. Du brauchst keinen API-Key, und es entstehen keine Zusatzkosten. Anfragen zählen zu deinem normalen Nutzungslimit.")
                    .font(.subheadline)
            }

            Section("Einmalig einrichten") {
                ForEach(steps) { step in
                    HStack(alignment: .top, spacing: Spacing.s) {
                        Text("\(step.id)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(ModuleAccent.sleep)
                            .frame(width: 30, height: 30)
                            .background(ModuleAccent.sleep.opacity(0.14), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title)
                                .font(.headline)
                            Text(step.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section {
                Button {
                    if let url = URL(string: "shortcuts://") { openURL(url) }
                } label: {
                    Label("Kurzbefehle-App öffnen", systemImage: "square.stack.3d.up")
                }
            } footer: {
                Text("Klappt der automatische Rückweg nicht, nutze im Systemcheck „Anfrage kopieren“ und „Einfügen“.")
            }
        }
        .navigationTitle("Kurzbefehl anlegen")
        .navigationBarTitleDisplayMode(.inline)
    }
}
