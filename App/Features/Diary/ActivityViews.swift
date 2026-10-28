import Charts
import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Bewegung oder Sport eintragen (außerhalb des Gyms; Gym-Einheiten zählen automatisch).
struct ActivityEditorView: View {
    var entry: ActivityEntry?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var kind: ActivityKind?
    @State private var minutes = 30
    @State private var intensity: ActivityIntensity = .moderate
    @State private var date = Date.now
    @State private var note = ""
    @State private var loaded = false

    private let presets = [15, 30, 45, 60, 90, 120]

    var body: some View {
        NavigationStack {
            Form {
                Section("Was?") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: Spacing.xs)], spacing: Spacing.xs) {
                        ForEach(ActivityKind.loggable) { item in
                            Button {
                                if kind != item, entry == nil {
                                    minutes = item.defaultMinutes
                                    intensity = item.defaultIntensity
                                }
                                kind = item
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: item.symbol)
                                        .font(.title3)
                                    Text(item.title)
                                        .font(.caption)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .minimumScaleFactor(0.85)
                                }
                                .frame(maxWidth: .infinity, minHeight: 64)
                                .foregroundStyle(kind == item ? Color.white : Color.primary)
                                .background(kind == item ? Color.green : Color.tagwerkPage, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(kind == item ? .isSelected : [])
                            .accessibilityIdentifier("activity.\(item.rawValue)")
                        }
                    }
                    .padding(.vertical, Spacing.xxs)
                }

                Section {
                    Stepper(value: $minutes, in: 5...600, step: 5) {
                        Text(DurationText.short(minutes))
                            .font(.headline)
                            .monospacedDigit()
                    }
                    FlowLayout(spacing: Spacing.xs) {
                        ForEach(presets, id: \.self) { value in
                            ToggleChip(title: DurationText.short(value), isOn: minutes == value, tint: .green) {
                                minutes = value
                            }
                        }
                    }
                    .padding(.vertical, Spacing.xxs)
                } header: {
                    Text("Wie lange?")
                }

                Section {
                    Picker("Anstrengung", selection: $intensity) {
                        ForEach(ActivityIntensity.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Wie anstrengend?")
                } footer: {
                    Text(intensity.detail)
                }

                Section {
                    DatePicker("Beginn", selection: $date)
                    TextField("Notiz (optional)", text: $note, axis: .vertical)
                }

                if let entry {
                    Section {
                        Button("Eintrag löschen", role: .destructive) {
                            DiaryActions.delete(entry, in: context)
                            app.diaryChanged()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(entry == nil ? "Bewegung eintragen" : "Bewegung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                        .accessibilityIdentifier("activity.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(kind == nil)
                        .accessibilityIdentifier("activity.save")
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let entry else { return }
        kind = entry.kind
        minutes = entry.minutes
        intensity = entry.intensity
        date = entry.date
        note = entry.note
    }

    private func save() {
        guard let kind else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let entry {
            entry.kind = kind
            entry.minutes = minutes
            entry.intensity = intensity
            entry.date = date
            entry.note = trimmed
            DiaryActions.save(context)
        } else {
            DiaryActions.addActivity(ActivityFact(date: date, kind: kind, minutes: minutes, intensity: intensity, note: trimmed), in: context)
        }
        app.diaryChanged()
        dismiss()
    }
}

/// Zeile für Bewegung (von Hand oder Gym).
struct ActivityRow: View {
    let fact: ActivityFact
    var showsDate = false

    var body: some View {
        let calendar = AppModel.calendar
        HStack(spacing: Spacing.s) {
            IconBadge(systemImage: fact.kind.symbol, tint: fact.kind == .gym ? ModuleAccent.training : .green)
            VStack(alignment: .leading, spacing: 1) {
                Text(fact.kind == .gym && !fact.note.isEmpty ? "Gym · \(fact.note)" : fact.kind.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.primary)
                let when = showsDate
                    ? "\(fact.date.nutritionDayLabel(calendar: calendar)), \(GermanCalendar.time(fact.date, calendar: calendar))"
                    : GermanCalendar.time(fact.date, calendar: calendar)
                Text("\(when) · \(DurationText.short(fact.minutes)) · \(fact.intensity.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Bewegung der letzten Wochen: Minuten gegen das WHO-Ziel, alle Einträge.
struct ActivityHistoryView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \ActivityEntry.date, order: .reverse) private var entries: [ActivityEntry]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @State private var editing: ActivityEntry?

    var body: some View {
        let calendar = AppModel.calendar
        let now = Date.now
        // Liest beide Abfragen, damit die Ansicht nach Änderungen neu zeichnet.
        let _ = entries.count + sessions.count
        let weekStart = AgendaBuilder.startOfWeek(containing: now, calendar: calendar)
        let from = calendar.date(byAdding: .day, value: -7 * 7, to: weekStart) ?? weekStart
        let facts = DiaryActions.activityFacts(from: from, to: now.addingTimeInterval(1), in: context)
        let weeks = ActivityStats.weeks(facts, from: from, to: now.addingTimeInterval(1), calendar: calendar)
        let thisWeek = weeks.last
        let byDay = Dictionary(grouping: facts.reversed()) { calendar.startOfDay(for: $0.date) }
        List {
            Section {
                HStack(spacing: Spacing.m) {
                    ProgressRing(fraction: min(1, Double(thisWeek?.weightedMinutes ?? 0) / Double(ActivityStats.weeklyTarget)), tint: .green, lineWidth: 9) {
                        VStack(spacing: 0) {
                            Text("\(thisWeek?.weightedMinutes ?? 0)")
                                .font(.system(.title3, design: .rounded, weight: .bold))
                            Text("von 150")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 86, height: 86)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Diese Woche")
                            .font(.headline)
                        Text(weekText(thisWeek))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Ziel: 150 Min. mittel oder 75 Min. intensiv pro Woche (intensiv zählt doppelt).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, Spacing.xxs)
                Chart(weeks) { week in
                    BarMark(x: .value("Woche", week.weekStart, unit: .weekOfYear), y: .value("Minuten", week.weightedMinutes))
                        .foregroundStyle(week.weightedMinutes >= ActivityStats.weeklyTarget ? Color.green : Color.green.opacity(0.45))
                    RuleMark(y: .value("Ziel", ActivityStats.weeklyTarget))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .frame(height: 140)
                .accessibilityLabel("Bewegungsminuten der letzten 8 Wochen")
            } header: {
                Text("Bewegung")
            }

            ForEach(byDay.keys.sorted(by: >), id: \.self) { day in
                Section(day.nutritionDayLabel(calendar: calendar)) {
                    ForEach(byDay[day] ?? []) { fact in
                        if let entry = entries.first(where: { $0.stableID == fact.id }) {
                            Button {
                                editing = entry
                            } label: {
                                ActivityRow(fact: fact)
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button("Löschen", role: .destructive) {
                                    DiaryActions.delete(entry, in: context)
                                    app.diaryChanged()
                                }
                            }
                        } else {
                            ActivityRow(fact: fact)
                        }
                    }
                }
            }
        }
        .overlay {
            if facts.isEmpty {
                ContentUnavailableView(
                    "Noch keine Bewegung",
                    systemImage: "figure.walk",
                    description: Text("Trag Spaziergänge, Radfahren, Laufen und anderen Sport ein. Gym-Einheiten zählen automatisch mit.")
                )
            }
        }
        .navigationTitle("Bewegung")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    app.openActivityEntry()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Bewegung eintragen")
                .accessibilityIdentifier("activities.add")
            }
        }
        .sheet(item: $editing) { entry in
            ActivityEditorView(entry: entry)
        }
    }

    /// „50 Min. an 1 Tag, 2 Einheiten“
    private func weekText(_ week: ActivityWeek?) -> String {
        let minutes = week?.minutes ?? 0
        let days = week?.activeDays ?? 0
        let sessions = week?.sessions ?? 0
        return "\(minutes) Min. an \(days) \(days == 1 ? "Tag" : "Tagen"), \(sessions) \(sessions == 1 ? "Einheit" : "Einheiten")"
    }
}
