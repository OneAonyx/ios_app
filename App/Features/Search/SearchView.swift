import SwiftUI
import TagwerkKit

/// Globale Suche, geöffnet über die Lupe auf „Heute“.
struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            Group {
                if query.isEmpty {
                    ModulePlaceholderView(module: .search)
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Suche")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Aufgaben, Lebensmittel, Übungen …"
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .accessibilityIdentifier("search.done")
                }
            }
        }
    }
}
