import SwiftUI
import TagwerkKit

struct SearchView: View {
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
            .searchable(text: $query, prompt: "Aufgaben, Lebensmittel, Übungen …")
        }
    }
}
