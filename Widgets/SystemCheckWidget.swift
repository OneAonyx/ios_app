import SwiftUI
import TagwerkCore
import TagwerkKit
import WidgetKit

/// Phase-0-Widget: zeigt den Wert, den die App in den gemeinsamen Speicher geschrieben hat.
struct SystemCheckWidget: Widget {
    let kind = "TagwerkSystemCheck"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SystemCheckProvider()) { entry in
            SystemCheckWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Tagwerk Systemcheck")
        .description("Zeigt, ob App und Widget Daten teilen.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular])
    }
}

struct SystemCheckEntry: TimelineEntry {
    let date: Date
    let snapshot: SystemCheckWidgetSnapshot?
    let appGroupAvailable: Bool
}

struct SystemCheckProvider: TimelineProvider {
    func placeholder(in context: Context) -> SystemCheckEntry {
        SystemCheckEntry(
            date: .now,
            snapshot: SystemCheckWidgetSnapshot(writtenAt: .now, counter: 1, appGroupID: TagwerkIDs.appGroup),
            appGroupAvailable: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SystemCheckEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SystemCheckEntry>) -> Void) {
        // Die App lädt das Widget nach jedem Schreiben neu, deshalb kein Zeitplan nötig.
        completion(Timeline(entries: [currentEntry()], policy: .never))
    }

    private func currentEntry() -> SystemCheckEntry {
        SystemCheckEntry(
            date: .now,
            snapshot: WidgetDataStore.readSystemCheckSnapshot(),
            appGroupAvailable: AppGroup.isAvailable
        )
    }
}

struct SystemCheckWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SystemCheckEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: entry.snapshot == nil ? "questionmark" : "checkmark.seal.fill")
                        .font(.caption)
                    if let snapshot = entry.snapshot {
                        Text("#\(snapshot.counter)")
                            .font(.caption2.weight(.semibold))
                    }
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("Tagwerk")
                    .font(.headline)
                if let snapshot = entry.snapshot {
                    Text("Wert #\(snapshot.counter)")
                    Text(snapshot.writtenAt, style: .time)
                        .foregroundStyle(.secondary)
                } else {
                    Text(statusText)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 4) {
                Label("Tagwerk", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.indigo)
                Spacer(minLength: 0)
                if let snapshot = entry.snapshot {
                    Text("#\(snapshot.counter)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                    Text("aus der App, \(snapshot.writtenAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var statusText: String {
        entry.appGroupAvailable
            ? "Noch kein Wert. Starte Test 3 in der App."
            : "Kein gemeinsamer Speicher."
    }
}
