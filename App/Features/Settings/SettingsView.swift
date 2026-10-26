import SwiftUI
import TagwerkKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Phase 0") {
                    NavigationLink {
                        SystemCheckView()
                    } label: {
                        Label("Systemcheck", systemImage: "checkmark.seal")
                    }
                }

                Section("App") {
                    LabeledContent("Version", value: "\(AppInfo.version) (\(AppInfo.build))")
                    LabeledContent("Bundle-ID", value: AppInfo.bundleIdentifier)
                    LabeledContent("Signatur", value: SigningInfo.describe())
                    LabeledContent("Widget-Daten", value: AppGroup.isAvailable ? "verfügbar" : "nicht verfügbar")
                    LabeledContent("App Group", value: AppGroup.identifier)
                    LabeledContent("Installiert über", value: AppGroup.isSideloaded ? "kostenlose Apple-ID (SideStore/iloader)" : "Xcode, TestFlight oder Simulator")
                }

                Section {
                    Text("Tagwerk ist kein Medizinprodukt. Histamin-Bewertungen sind eine Orientierung, und Erinnerungen ersetzen keine ärztliche Beratung. Alle Daten bleiben auf deinem iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Hinweis")
                }
            }
            .navigationTitle("Einstellungen")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}
