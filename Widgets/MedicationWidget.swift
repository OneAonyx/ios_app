import AppIntents
import SwiftUI
import TagwerkCore
import TagwerkKit
import WidgetKit

/// Medikamente auf dem Home- und Sperrbildschirm, mit „Genommen“-Knopf.
struct MedicationWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.medication, provider: MedicationProvider()) { entry in
            MedicationWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "\(TagwerkIDs.urlScheme)://gesundheit"))
        }
        .configurationDisplayName("Medikamente")
        .description("Nächste Einnahme mit „Genommen“-Knopf und Fortschritt des Tages.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct MedicationEntry: TimelineEntry {
    let date: Date
    let snapshot: MedicationWidgetSnapshot

    var calendar: Calendar { GermanCalendar.make() }
    var todayDoses: [MedicationWidgetSnapshot.Dose] { snapshot.doses(on: date, calendar: calendar) }
    var progress: (done: Int, total: Int) { snapshot.progress(on: date, calendar: calendar) }
    var next: MedicationWidgetSnapshot.Dose? { snapshot.nextOpenDose(now: date) }

    func timeText(_ dose: MedicationWidgetSnapshot.Dose) -> String {
        let time = GermanCalendar.time(dose.time, calendar: calendar)
        return calendar.isDate(dose.time, inSameDayAs: date) ? time : "morgen \(time)"
    }
}

struct MedicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> MedicationEntry {
        MedicationEntry(date: .now, snapshot: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (MedicationEntry) -> Void) {
        let snapshot = MedicationSnapshotWriter.read()
        completion(MedicationEntry(date: .now, snapshot: context.isPreview && snapshot.doses.isEmpty ? Self.sample : snapshot))
    }

    /// Ein Eintrag für jetzt und je einer zu jeder Einnahme (und 61 Min. danach, wenn sie
    /// als überfällig gilt), dazu Mitternacht. Die App lädt das Widget nach jeder Änderung neu.
    func getTimeline(in context: Context, completion: @escaping (Timeline<MedicationEntry>) -> Void) {
        let snapshot = MedicationSnapshotWriter.read()
        let now = Date.now
        let calendar = GermanCalendar.make()
        var moments: Set<Date> = [now]
        for dose in snapshot.doses where dose.time > now {
            moments.insert(dose.time.addingTimeInterval(-DoseTiming.dueBefore))
            moments.insert(dose.time)
        }
        for dose in snapshot.doses where dose.time.addingTimeInterval(DoseTiming.lateAfter + 60) > now {
            moments.insert(dose.time.addingTimeInterval(DoseTiming.lateAfter + 60))
        }
        moments.insert(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400))
        let entries = moments
            .filter { $0 >= now }
            .sorted()
            .prefix(40)
            .map { MedicationEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    static let sample: MedicationWidgetSnapshot = {
        let calendar = GermanCalendar.make()
        let today = calendar.startOfDay(for: .now)
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today) ?? today
        }
        return MedicationWidgetSnapshot(writtenAt: .now, doses: [
            .init(id: "a|1", medicationID: "a", name: "Vitamin D3", detail: "1 Tablette", time: at(8), colorName: "orange", symbol: "sun.max.fill", state: .taken),
            .init(id: "b|1", medicationID: "b", name: "DAO-Enzym", detail: "1 Kapsel · vor dem Essen", time: at(12, 15), colorName: "teal", symbol: "capsule.fill", state: .open),
            .init(id: "c|1", medicationID: "c", name: "Cetirizin 10 mg", detail: "1 Tablette", time: at(21), colorName: "purple", symbol: "pills.fill", state: .open),
        ])
    }()
}

struct MedicationWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MedicationEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        case .accessoryInline:
            inline
        case .systemMedium:
            medium
        default:
            small
        }
    }

    // MARK: Sperrbildschirm

    private var circular: some View {
        let progress = entry.progress
        return Gauge(value: Double(progress.done), in: 0...Double(max(progress.total, 1))) {
            Image(systemName: "pills.fill")
        } currentValueLabel: {
            Text("\(progress.done)/\(progress.total)")
                .font(.system(.caption, design: .rounded, weight: .bold))
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
    }

    private var rectangular: some View {
        let progress = entry.progress
        return VStack(alignment: .leading, spacing: 1) {
            Label("Medikamente \(progress.done)/\(progress.total)", systemImage: "pills.fill")
                .font(.headline)
                .widgetAccentable()
            if let next = entry.next {
                Text(next.name)
                    .lineLimit(1)
                Text("\(entry.timeText(next)) · \(next.detail)")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(progress.total == 0 ? "Heute nichts geplant" : "Alles erledigt")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: some View {
        let progress = entry.progress
        if let next = entry.next {
            return Text("\(Image(systemName: "pills.fill")) \(next.name) \(entry.timeText(next))")
        }
        return Text("\(Image(systemName: "pills.fill")) \(progress.done)/\(progress.total) genommen")
    }

    // MARK: Home-Bildschirm

    private var small: some View {
        let progress = entry.progress
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("\(progress.done)/\(progress.total)", systemImage: "pills.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.mint)
                Spacer()
            }
            Spacer(minLength: 0)
            if let next = entry.next {
                Text(next.name)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(entry.timeText(next))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(next.time < entry.date ? Color.red : Color.secondary)
                Button(intent: TakeDoseIntent(doseID: next.id, source: "widget")) {
                    Label("Genommen", systemImage: "checkmark")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ListColor.color(named: next.colorName))
            } else {
                Image(systemName: progress.total == 0 ? "moon.zzz.fill" : "checkmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(progress.total == 0 ? Color.secondary : Color.green)
                Text(progress.total == 0 ? "Heute nichts geplant" : "Alles erledigt")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        let progress = entry.progress
        let doses = Array(entry.todayDoses.prefix(4))
        return HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Heute", systemImage: "pills.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.mint)
                Spacer(minLength: 0)
                ZStack {
                    Circle().stroke(Color.mint.opacity(0.2), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: progress.total == 0 ? 0 : CGFloat(progress.done) / CGFloat(progress.total))
                        .stroke(Color.mint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(progress.done)/\(progress.total)")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .minimumScaleFactor(0.6)
                }
                .frame(width: 64, height: 64)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 4) {
                if doses.isEmpty {
                    Spacer()
                    Text("Heute sind keine Einnahmen geplant.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ForEach(doses) { dose in
                        MediumDoseRow(dose: dose, entry: entry)
                    }
                    if entry.todayDoses.count > doses.count {
                        Text("+ \(entry.todayDoses.count - doses.count) weitere")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private struct MediumDoseRow: View {
    let dose: MedicationWidgetSnapshot.Dose
    let entry: MedicationEntry

    var body: some View {
        HStack(spacing: 8) {
            Text(entry.timeText(dose))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(dose.isOpen && dose.time < entry.date ? Color.red : Color.secondary)
                .frame(width: 40, alignment: .leading)
            Text(dose.name)
                .font(.subheadline)
                .lineLimit(1)
                .strikethrough(dose.state == .skipped)
                .foregroundStyle(dose.isOpen ? Color.primary : Color.secondary)
            Spacer(minLength: 0)
            if dose.isOpen {
                Button(intent: TakeDoseIntent(doseID: dose.id, source: "widget")) {
                    Image(systemName: "circle")
                        .font(.title3)
                        .foregroundStyle(ListColor.color(named: dose.colorName))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(dose.name) genommen")
            } else {
                Image(systemName: dose.state == .taken ? "checkmark.circle.fill" : "minus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(dose.state == .taken ? Color.green : Color.gray)
            }
        }
    }
}

/// Kontrollzentrum: „Medikament genommen“ hakt die gerade fällige Einnahme ab.
struct MedicationControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WidgetKinds.medicationControl) {
            ControlWidgetButton(action: TakeNextDoseIntent()) {
                Label("Medikament genommen", systemImage: "pills.fill")
            }
        }
        .displayName("Medikament genommen")
        .description("Hakt in Tagwerk die Einnahme ab, die gerade fällig ist.")
    }
}
