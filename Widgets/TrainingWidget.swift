import AppIntents
import SwiftUI
import TagwerkCore
import TagwerkKit
import WidgetKit

/// Nächste Einheit auf Home- und Sperrbildschirm.
struct TrainingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.training, provider: TrainingProvider()) { entry in
            TrainingWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "\(TagwerkIDs.urlScheme)://training"))
        }
        .configurationDisplayName("Training")
        .description("Nächste Einheit, Zykluswoche und wann du zuletzt trainiert hast.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

struct TrainingEntry: TimelineEntry {
    let date: Date
    let snapshot: TrainingWidgetSnapshot
}

struct TrainingProvider: TimelineProvider {
    func placeholder(in context: Context) -> TrainingEntry {
        TrainingEntry(date: .now, snapshot: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (TrainingEntry) -> Void) {
        let snapshot = TrainingSnapshotWriter.read()
        completion(TrainingEntry(date: .now, snapshot: context.isPreview && !snapshot.hasPlan ? Self.sample : snapshot))
    }

    /// Neu zeichnen um Mitternacht („zuletzt vor X Tagen“). Die App lädt nach jeder Einheit neu.
    func getTimeline(in context: Context, completion: @escaping (Timeline<TrainingEntry>) -> Void) {
        let calendar = GermanCalendar.make()
        let snapshot = TrainingSnapshotWriter.read()
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? .now.addingTimeInterval(86_400)
        completion(Timeline(entries: [TrainingEntry(date: .now, snapshot: snapshot), TrainingEntry(date: midnight, snapshot: snapshot)], policy: .atEnd))
    }

    static let sample = TrainingWidgetSnapshot(
        writtenAt: .now, planName: "Oberkörper 4er", nextDayName: "Pull", nextDayShort: "B",
        exerciseCount: 7, estimatedMinutes: 70, weekLabel: "Woche 2 von 6", isDeload: false,
        lastTrainingAt: .now.addingTimeInterval(-2 * 86_400)
    )
}

struct TrainingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TrainingEntry

    var body: some View {
        let snapshot = entry.snapshot
        let calendar = GermanCalendar.make()
        switch family {
        case .accessoryInline:
            if let active = snapshot.activeDayName {
                Text("\(Image(systemName: "dumbbell.fill")) \(active) läuft")
            } else {
                Text("\(Image(systemName: "dumbbell.fill")) \(snapshot.nextDayShort) · \(snapshot.nextDayName)")
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Training", systemImage: "dumbbell.fill")
                    .font(.headline)
                    .widgetAccentable()
                if let active = snapshot.activeDayName, let start = snapshot.activeSessionStart {
                    Text(active)
                    Text(start, style: .timer)
                        .foregroundStyle(.secondary)
                } else if snapshot.hasPlan {
                    Text("\(snapshot.nextDayShort) · \(snapshot.nextDayName)")
                    Text(snapshot.lastTrainingLabel(now: entry.date, calendar: calendar))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Kein Plan")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 4) {
                Label(snapshot.isDeload ? "Deload" : "Training", systemImage: "dumbbell.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.36))
                Spacer(minLength: 0)
                if let active = snapshot.activeDayName, let start = snapshot.activeSessionStart {
                    Text(active)
                        .font(.headline)
                        .lineLimit(2)
                    Text(start, style: .timer)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else if snapshot.hasPlan {
                    Text(snapshot.nextDayShort)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(snapshot.nextDayName)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("\(snapshot.exerciseCount) Übungen · \(snapshot.estimatedMinutes) Min.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(snapshot.lastTrainingLabel(now: entry.date, calendar: calendar))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Noch kein Plan")
                        .font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

/// Kontrollzentrum: „Training starten“ öffnet Orbit mit der nächsten Einheit.
struct TrainingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WidgetKinds.trainingControl) {
            ControlWidgetButton(action: StartWorkoutIntent()) {
                Label("Training starten", systemImage: "figure.strengthtraining.traditional")
            }
        }
        .displayName("Training starten")
        .description("Öffnet Orbit mit der nächsten Einheit deines Plans.")
    }
}
