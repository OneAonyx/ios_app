import SwiftUI
import TagwerkCore
import TagwerkKit

/// Alle Funktionen von Orbit nach Bereichen, mit dem Ort in der App.
struct FeatureDirectoryView: View {
    var body: some View {
        List {
            FeatureDirectorySections()
        }
        .navigationTitle("Alle Funktionen")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Die Abschnitte des Verzeichnisses (auch in der leeren Suche).
struct FeatureDirectorySections: View {
    var body: some View {
        ForEach(FeatureIndex.grouped, id: \.area) { group in
            Section(group.area.title) {
                ForEach(group.features) { feature in
                    FeatureRow(feature: feature)
                }
            }
        }
    }
}

/// Eine Funktion: Symbol, Name, Ort. Tippen öffnet sie dort, wo sie wohnt.
struct FeatureRow: View {
    let feature: Feature

    @Environment(AppModel.self) private var app

    var body: some View {
        Button {
            app.open(feature: feature)
        } label: {
            HStack(spacing: Spacing.s) {
                IconBadge(systemImage: feature.symbol, tint: feature.area.tint, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(feature.title)
                        .foregroundStyle(Color.primary)
                    Text(feature.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: feature.isAction ? "plus.circle" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(feature.isAction ? "Öffnet das Eintragen" : "Öffnet \(feature.path)")
        .accessibilityIdentifier("feature.\(feature.id)")
    }
}

extension FeatureArea {
    var tint: Color {
        switch self {
        case .today: ModuleAccent.today
        case .planner: ModuleAccent.tasks
        case .training: ModuleAccent.training
        case .nutrition: ModuleAccent.nutrition
        case .health: ModuleAccent.health
        case .settings: .gray
        }
    }
}
