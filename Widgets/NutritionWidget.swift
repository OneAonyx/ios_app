import AppIntents
import SwiftUI
import TagwerkCore
import TagwerkKit
import WidgetKit

/// Histamin-Tageslast, Eiweiß und Wasser auf Home- und Sperrbildschirm.
struct NutritionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.nutrition, provider: NutritionProvider()) { entry in
            NutritionWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "\(TagwerkIDs.urlScheme)://ernaehrung"))
        }
        .configurationDisplayName("Ernährung")
        .description("Histamin-Tageslast, Eiweiß und Wasser von heute. Mit Knopf für ein Glas Wasser.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct NutritionEntry: TimelineEntry {
    let date: Date
    let snapshot: NutritionWidgetSnapshot
}

struct NutritionProvider: TimelineProvider {
    func placeholder(in context: Context) -> NutritionEntry {
        NutritionEntry(date: .now, snapshot: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (NutritionEntry) -> Void) {
        let stored = NutritionSnapshotWriter.read()
        let useSample = context.isPreview && stored.mealCount == 0 && stored.waterML == 0
        completion(NutritionEntry(date: .now, snapshot: useSample ? Self.sample : stored))
    }

    /// Um Mitternacht auf leere Tageswerte wechseln. Die App lädt nach jeder Änderung neu.
    func getTimeline(in context: Context, completion: @escaping (Timeline<NutritionEntry>) -> Void) {
        let calendar = GermanCalendar.make()
        let stored = NutritionSnapshotWriter.read()
        let now = Date.now
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        let entries = [
            NutritionEntry(date: now, snapshot: stored.current(now: now, calendar: calendar)),
            NutritionEntry(date: midnight, snapshot: stored.current(now: midnight, calendar: calendar)),
        ]
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    static let sample = NutritionWidgetSnapshot(
        writtenAt: .now, day: .now, loadPoints: 3, levelRaw: HistamineLoad.Level.calm.rawValue,
        protein: 96, proteinTarget: 148, waterML: 1500, waterTarget: 2500, mealCount: 2, topContributors: ["Tomate"]
    )
}

struct NutritionWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NutritionEntry

    var body: some View {
        let snapshot = entry.snapshot
        switch family {
        case .accessoryInline:
            Text("\(Image(systemName: "drop.fill")) \(NutritionDay.liters(snapshot.waterML)) l · Histamin \(snapshot.level.title)")
        case .accessoryCircular:
            Gauge(value: min(Double(snapshot.waterML), Double(snapshot.waterTarget)), in: 0...Double(max(snapshot.waterTarget, 1))) {
                Image(systemName: "drop.fill")
            } currentValueLabel: {
                Text(NutritionDay.liters(snapshot.waterML))
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Histamin \(snapshot.level.title)", systemImage: symbol(snapshot.level))
                    .font(.headline)
                    .widgetAccentable()
                Text("Eiweiß \(Int(snapshot.protein.rounded())) / \(Int(snapshot.proteinTarget.rounded())) g")
                Text("Wasser \(NutritionDay.liters(snapshot.waterML)) / \(NutritionDay.liters(snapshot.waterTarget)) l")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 6) {
                Label("Histamin", systemImage: symbol(snapshot.level))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color(snapshot.level))
                Text(snapshot.level.title.capitalized)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(color(snapshot.level))
                ProgressView(value: snapshot.loadFraction)
                    .tint(color(snapshot.level))
                Spacer(minLength: 0)
                Text("Eiweiß \(Int(snapshot.protein.rounded())) / \(Int(snapshot.proteinTarget.rounded())) g")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text("\(Image(systemName: "drop.fill")) \(NutritionDay.liters(snapshot.waterML)) l")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.cyan)
                    Spacer(minLength: 0)
                    Button(intent: AddWaterIntent()) {
                        Image(systemName: "plus")
                            .font(.caption.weight(.bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .accessibilityLabel("Glas Wasser eintragen")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func symbol(_ level: HistamineLoad.Level) -> String { level.symbol }

    private func color(_ level: HistamineLoad.Level) -> Color {
        switch level {
        case .calm: .green
        case .elevated: .orange
        case .high: .red
        }
    }
}

/// Kontrollzentrum: ein Glas Wasser eintragen.
struct WaterControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WidgetKinds.waterControl) {
            ControlWidgetButton(action: AddWaterIntent()) {
                Label("Wasser +250 ml", systemImage: "drop.fill")
            }
        }
        .displayName("Glas Wasser")
        .description("Trägt in Orbit ein Glas Wasser (250 ml) ein.")
    }
}
