import SwiftUI
import TagwerkCore
import TagwerkKit

/// Blatt von „Heute“ aus: dieselbe Liste wie in den Einstellungen.
struct TodayLayoutEditor: View {
    @Binding var layoutText: String
    let initial: TodayLayout
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TodayLayoutList(layoutText: $layoutText, initial: initial)
                .navigationTitle("Startseite anpassen")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { dismiss() }
                            .accessibilityIdentifier("layout.done")
                    }
                }
        }
    }
}

/// Karten auf „Heute“ ein- und ausblenden und sortieren.
struct TodayLayoutList: View {
    @Binding var layoutText: String
    @State private var layout: TodayLayout

    init(layoutText: Binding<String>, initial: TodayLayout) {
        _layoutText = layoutText
        _layout = State(initialValue: initial)
    }

    var body: some View {
        List {
            Section {
                Label("Überblick mit Aufgaben und Einnahmen", systemImage: "chart.pie")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Immer oben")
            }

            Section {
                ForEach(layout.order) { card in
                    Toggle(isOn: binding(for: card)) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.title)
                                Text(card.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: card.symbol)
                        }
                    }
                    .accessibilityIdentifier("layout.\(card.rawValue)")
                }
                .onMove { source, destination in
                    layout.move(fromOffsets: source, toOffset: destination)
                    save()
                }
            } header: {
                Text("Karten")
            } footer: {
                Text("Zum Sortieren eine Karte am Griff ziehen. Die meisten Karten erscheinen ohnehin nur, wenn es heute etwas dafür gibt.")
            }

            if !layout.isStandard {
                Section {
                    Button("Auf Standard zurücksetzen") {
                        withAnimation { layout = .standard }
                        save()
                    }
                }
            }
        }
        .environment(\.editMode, .constant(.active))
    }

    private func binding(for card: TodayCard) -> Binding<Bool> {
        Binding(
            get: { layout.isVisible(card) },
            set: { visible in
                layout.setVisible(card, visible)
                save()
            }
        )
    }

    private func save() {
        layoutText = layout.isStandard ? "" : layout.encoded
    }
}
