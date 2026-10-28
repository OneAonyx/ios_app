import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Plan-Check im Training-Tab: die wichtigsten Vorschläge, übernehmen oder später.
struct CoachCard: View {
    /// Ändert sich nach jeder Einheit, damit die Vorschläge neu berechnet werden.
    let refreshKey: Int

    @Environment(\.modelContext) private var context
    @State private var suggestions: [CoachSuggestion] = []
    @State private var revision = 0

    var body: some View {
        Group {
            if !suggestions.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        HStack {
                            SectionHeader("Plan-Check", systemImage: "wand.and.stars", tint: ModuleAccent.training)
                            if suggestions.count > 2 {
                                NavigationLink(value: TrainingRoute.coach) {
                                    Text("Alle \(suggestions.count)")
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                        }
                        ForEach(suggestions.prefix(2)) { suggestion in
                            CoachSuggestionRow(suggestion: suggestion) { revision += 1 }
                        }
                    }
                }
                .accessibilityIdentifier("training.coach")
            }
        }
        .task(id: refreshKey * 1_000 + revision) {
            suggestions = CoachActions.suggestions(calendar: AppModel.calendar, in: context)
        }
    }
}

/// Alle Vorschläge mit Erklärung.
struct CoachView: View {
    @Environment(\.modelContext) private var context
    @State private var suggestions: [CoachSuggestion]?
    @State private var revision = 0

    var body: some View {
        List {
            Section {
                Text("Orbit schaut auf den Kraftverlauf je Übung (letzte 8 Wochen) und die Sätze je Muskel (letzte 2 Wochen). Übernommene Vorschläge ändern den Plan sofort, „Später“ blendet einen Vorschlag für 4 Wochen aus.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let suggestions {
                if suggestions.isEmpty {
                    Section {
                        Label("Gerade nichts zu ändern. Der Plan passt zu deinem Fortschritt.", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                } else {
                    Section("Vorschläge") {
                        ForEach(suggestions) { suggestion in
                            CoachSuggestionRow(suggestion: suggestion) { revision += 1 }
                        }
                    }
                }
            }
        }
        .navigationTitle("Plan-Check")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: revision) {
            suggestions = CoachActions.suggestions(calendar: AppModel.calendar, limit: 12, in: context)
        }
    }
}

/// Ein Vorschlag mit „Übernehmen“ und „Später“.
struct CoachSuggestionRow: View {
    let suggestion: CoachSuggestion
    let onChange: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.title)
                        .font(.subheadline.weight(.semibold))
                    Text(suggestion.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: suggestion.symbol)
                    .foregroundStyle(ModuleAccent.training)
            }
            HStack(spacing: Spacing.xs) {
                Button("Übernehmen") {
                    CoachActions.apply(suggestion, in: context)
                    app.trainingChanged()
                    onChange()
                }
                .buttonStyle(.borderedProminent)
                .tint(ModuleAccent.training)
                .controlSize(.small)
                .accessibilityIdentifier("coach.apply")
                Button("Später") {
                    CoachActions.dismiss(suggestion)
                    onChange()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.leading, 28)
        }
        .padding(.vertical, 2)
    }
}
