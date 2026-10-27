import AppIntents
import SwiftUI
import TagwerkCore
import TagwerkKit
import WidgetKit

// MARK: - Daten

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: TodayWidgetSnapshot

    var calendar: Calendar { GermanCalendar.make() }

    /// Stand von gestern: Zähler und „Als Nächstes“ passen nicht mehr.
    var isStale: Bool { !calendar.isDate(snapshot.writtenAt, inSameDayAs: date) }

    var nextUp: (title: String, time: Date, symbol: String)? {
        guard !isStale, let title = snapshot.nextUpTitle, let time = snapshot.nextUpTime, time.addingTimeInterval(60) >= date else { return nil }
        return (title, time, snapshot.nextUpSymbol ?? "arrow.forward.circle")
    }

    var dateText: String {
        let weekday = GermanCalendar.longWeekdays[calendar.component(.weekday, from: date) - 1]
        return "\(weekday), \(calendar.component(.day, from: date)). \(GermanCalendar.shortMonths[calendar.component(.month, from: date) - 1])"
    }

    func timeText(_ time: Date) -> String {
        let clock = GermanCalendar.time(time, calendar: calendar)
        let minutes = Int(time.timeIntervalSince(date) / 60)
        if minutes <= 0 { return "jetzt" }
        if minutes < 60 { return "\(clock) · in \(minutes) Min." }
        return clock
    }
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, snapshot: .placeholder(now: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        let stored = TodaySnapshotStore.read()
        let useSample = context.isPreview && (stored == nil || stored?.tasks.isEmpty == true)
        completion(TodayEntry(date: .now, snapshot: useSample ? .placeholder(now: .now) : (stored ?? .placeholder(now: .now))))
    }

    /// Jetzt, kurz nach dem nächsten Termin und um Mitternacht. Die App lädt nach jeder Änderung neu.
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date.now
        let calendar = GermanCalendar.make()
        let snapshot = TodaySnapshotStore.read() ?? TodayWidgetSnapshot(writtenAt: now)
        var moments: [Date] = [now]
        if let next = snapshot.nextUpTime, next > now {
            moments.append(next.addingTimeInterval(-3_600))
            moments.append(next.addingTimeInterval(61))
        }
        moments.append(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400))
        let entries = Set(moments.filter { $0 >= now }).sorted().map { TodayEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Widget „Heute“

/// Als Nächstes, Fortschritt des Tages und die wichtigsten Aufgaben.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.today, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "\(TagwerkIDs.urlScheme)://heute"))
        }
        .configurationDisplayName("Heute")
        .description("Als Nächstes, Aufgaben, Medikamente und Routinen von heute.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            if let next = entry.nextUp {
                Text("\(Image(systemName: next.symbol)) \(GermanCalendar.time(next.time, calendar: entry.calendar)) \(next.title)")
            } else {
                Text("\(Image(systemName: "checklist")) \(entry.snapshot.tasksOpen) Aufgaben offen")
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                if let next = entry.nextUp {
                    Label(next.title, systemImage: next.symbol)
                        .font(.headline)
                        .widgetAccentable()
                    Text(entry.timeText(next.time))
                } else {
                    Label("Heute", systemImage: "sun.max.fill")
                        .font(.headline)
                        .widgetAccentable()
                }
                Text(counts)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemSmall:
            small
        case .systemLarge:
            large
        default:
            medium
        }
    }

    private var counts: String {
        var parts = ["\(entry.snapshot.tasksOpen) offen"]
        if entry.snapshot.dosesTotal > 0 { parts.append("Medis \(entry.snapshot.dosesDone)/\(entry.snapshot.dosesTotal)") }
        return parts.joined(separator: " · ")
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.dateText)
                .font(.caption2.weight(.bold))
                .foregroundStyle(ModuleAccent.today)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            StatLine(symbol: "checklist", tint: ModuleAccent.tasks, done: entry.snapshot.tasksDone, total: entry.snapshot.tasksDone + entry.snapshot.tasksOpen)
            if entry.snapshot.dosesTotal > 0 {
                StatLine(symbol: "pills.fill", tint: ModuleAccent.medication, done: entry.snapshot.dosesDone, total: entry.snapshot.dosesTotal)
            }
            if entry.snapshot.habitsTotal > 0 {
                StatLine(symbol: "repeat", tint: .teal, done: entry.snapshot.habitsDone, total: entry.snapshot.habitsTotal)
            }
            Spacer(minLength: 0)
            if let next = entry.nextUp {
                Text(next.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(entry.timeText(next.time))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.dateText)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(ModuleAccent.today)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                StatLine(symbol: "checklist", tint: ModuleAccent.tasks, done: entry.snapshot.tasksDone, total: entry.snapshot.tasksDone + entry.snapshot.tasksOpen)
                if entry.snapshot.dosesTotal > 0 {
                    StatLine(symbol: "pills.fill", tint: ModuleAccent.medication, done: entry.snapshot.dosesDone, total: entry.snapshot.dosesTotal)
                }
                if entry.snapshot.habitsTotal > 0 {
                    StatLine(symbol: "repeat", tint: .teal, done: entry.snapshot.habitsDone, total: entry.snapshot.habitsTotal)
                }
                Spacer(minLength: 0)
            }
            .frame(width: 92, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                if let next = entry.nextUp {
                    NextUpLine(title: next.title, detail: entry.timeText(next.time), symbol: next.symbol)
                }
                ForEach(entry.snapshot.tasks.prefix(entry.nextUp == nil ? 4 : 2)) { task in
                    TaskLineView(task: task, interactive: false)
                }
                if entry.snapshot.tasks.isEmpty && entry.nextUp == nil {
                    Text("Nichts mehr offen für heute.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.dateText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ModuleAccent.today)
                    .textCase(.uppercase)
                Spacer()
                Link(destination: URL(string: "\(TagwerkIDs.urlScheme)://neu")!) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(ModuleAccent.tasks)
                }
                .accessibilityLabel("Neue Aufgabe")
            }
            HStack(spacing: 14) {
                StatLine(symbol: "checklist", tint: ModuleAccent.tasks, done: entry.snapshot.tasksDone, total: entry.snapshot.tasksDone + entry.snapshot.tasksOpen)
                if entry.snapshot.dosesTotal > 0 {
                    StatLine(symbol: "pills.fill", tint: ModuleAccent.medication, done: entry.snapshot.dosesDone, total: entry.snapshot.dosesTotal)
                }
                if entry.snapshot.habitsTotal > 0 {
                    StatLine(symbol: "repeat", tint: .teal, done: entry.snapshot.habitsDone, total: entry.snapshot.habitsTotal)
                }
            }
            if let next = entry.nextUp {
                NextUpLine(title: next.title, detail: entry.timeText(next.time), symbol: next.symbol)
                    .padding(8)
                    .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Divider()
            if entry.snapshot.tasks.isEmpty {
                Label("Alles erledigt", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            }
            ForEach(entry.snapshot.tasks.prefix(5)) { task in
                TaskLineView(task: task, interactive: true)
            }
            Spacer(minLength: 0)
            if let upcoming = entry.snapshot.upcoming {
                Label(upcoming, systemImage: "gift.fill")
                    .font(.caption)
                    .foregroundStyle(.pink)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Widget „Aufgaben“

/// Aufgaben von heute zum Abhaken direkt auf dem Home-Bildschirm.
struct TasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.tasks, provider: TodayProvider()) { entry in
            TasksWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "\(TagwerkIDs.urlScheme)://aufgaben"))
        }
        .configurationDisplayName("Aufgaben")
        .description("Fokus und fällige Aufgaben von heute. Zum Abhaken antippen.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct TasksWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        let limit = family == .systemLarge ? 6 : 3
        VStack(alignment: .leading, spacing: family == .systemLarge ? 9 : 6) {
            HStack(alignment: .firstTextBaseline) {
                Label("Heute", systemImage: "checklist")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ModuleAccent.tasks)
                Text("\(entry.snapshot.tasksDone) von \(entry.snapshot.tasksDone + entry.snapshot.tasksOpen)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Link(destination: URL(string: "\(TagwerkIDs.urlScheme)://neu")!) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(ModuleAccent.tasks)
                }
                .accessibilityLabel("Neue Aufgabe")
            }
            if entry.snapshot.tasks.isEmpty {
                Spacer(minLength: 0)
                Label("Alles erledigt für heute", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            ForEach(entry.snapshot.tasks.prefix(limit)) { task in
                TaskLineView(task: task, interactive: true)
            }
            if entry.snapshot.tasks.count > limit {
                Text("+ \(entry.snapshot.tasks.count - limit) weitere")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Bausteine

private struct StatLine: View {
    let symbol: String
    let tint: Color
    let done: Int
    let total: Int

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 16)
            Text("\(done)/\(total)")
                .font(.system(.subheadline, design: .rounded, weight: .bold).monospacedDigit())
            if total > 0, done >= total {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(.green)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct NextUpLine: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(ModuleAccent.today)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Als Nächstes: \(title), \(detail)")
    }
}

private struct TaskLineView: View {
    let task: TodayWidgetSnapshot.TaskLine
    let interactive: Bool

    var body: some View {
        HStack(spacing: 8) {
            if interactive {
                Button(intent: CompleteTaskIntent(taskID: task.id)) {
                    Image(systemName: "circle")
                        .font(.body)
                        .foregroundStyle(task.priority >= 2 ? .orange : ModuleAccent.tasks)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(task.title) abhaken")
            } else {
                Image(systemName: task.isFocus ? "star.circle" : "circle")
                    .font(.caption)
                    .foregroundStyle(task.isFocus ? .yellow : .secondary)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(task.title)
                    .font(.subheadline)
                    .lineLimit(1)
                if !task.detail.isEmpty {
                    Text(task.detail)
                        .font(.caption2)
                        .foregroundStyle(task.detail == "überfällig" ? .red : .secondary)
                }
            }
            Spacer(minLength: 0)
            if interactive, task.isFocus {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Fokus")
            }
        }
    }
}

// MARK: - Kontrollzentrum

/// Kontrollzentrum: neue Aufgabe in der Schnellerfassung.
struct QuickTaskControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WidgetKinds.quickTaskControl) {
            ControlWidgetButton(action: OpenOrbitURLIntent(target: .quickTask)) {
                Label("Neue Aufgabe", systemImage: "plus.circle")
            }
        }
        .displayName("Neue Aufgabe")
        .description("Öffnet die Schnellerfassung von Orbit.")
    }
}

/// Kontrollzentrum: Check-in (Stimmung, Energie, Schlaf).
struct CheckInControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WidgetKinds.checkInControl) {
            ControlWidgetButton(action: OpenOrbitURLIntent(target: .checkIn)) {
                Label("Check-in", systemImage: "face.smiling")
            }
        }
        .displayName("Check-in")
        .description("Öffnet den Check-in für Stimmung, Energie und Schlaf.")
    }
}
