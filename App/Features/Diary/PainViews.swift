import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Farbe zur Schmerzstärke 0–10.
enum PainColor {
    static func color(_ intensity: Int) -> Color {
        switch PainScale.level(intensity) {
        case 0: .green
        case 1: .yellow
        case 2: .orange
        default: .red
        }
    }
}

/// Auswahl-Chip (mehrfach wählbar).
struct ToggleChip: View {
    let title: String
    let isOn: Bool
    var tint: Color = .red
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                }
                Text(title)
                    .font(.subheadline)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .background(isOn ? tint : tint.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Schmerz eintragen oder bearbeiten: Körperkarte, Stärke 0–10, Art, Dauer, Auslöser, was geholfen hat.
struct PainEditorView: View {
    var entry: PainEntry?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var side: BodyMapSide = .front
    @State private var regions: [BodyRegion] = []
    @State private var intensity = 5
    @State private var qualities: Set<PainQuality> = []
    @State private var date = Date.now
    @State private var duration = 0
    @State private var triggers: Set<PainTrigger> = []
    @State private var reliefs: Set<PainRelief> = []
    @State private var note = ""
    @State private var loaded = false
    @State private var showsList = false

    private let durations: [(Int, String)] = [
        (0, "noch nicht vorbei / unbekannt"), (15, "15 Min."), (30, "30 Min."), (60, "1 Std."), (120, "2 Std."),
        (240, "4 Std."), (480, "8 Std."), (1_440, "ganzer Tag"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Ansicht", selection: $side) {
                        ForEach(BodyMapSide.allCases) { view in
                            Text(view.title).tag(view)
                        }
                    }
                    .pickerStyle(.segmented)
                    BodyMapView(view: side, selected: Set(regions)) { region in
                        toggle(region)
                    }
                    .frame(maxHeight: 340)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xs)
                    if regions.isEmpty {
                        Text("Tippe auf die Stelle, die schmerzt. Mehrere sind möglich.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        FlowLayout(spacing: Spacing.xs) {
                            ForEach(regions) { region in
                                ToggleChip(title: region.title, isOn: true) { toggle(region) }
                            }
                        }
                    }
                    DisclosureGroup("Aus Liste wählen", isExpanded: $showsList) {
                        ForEach(BodyRegion.allCases) { region in
                            Button {
                                toggle(region)
                            } label: {
                                HStack {
                                    Text(region.title)
                                        .foregroundStyle(Color.primary)
                                    Spacer()
                                    if regions.contains(region) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.red)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Wo?")
                }

                Section {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(intensity)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(PainColor.color(intensity))
                            .contentTransition(.numericText())
                        Text("von 10 · \(PainScale.label(intensity))")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(get: { Double(intensity) }, set: { intensity = Int($0.rounded()) }), in: 0...10, step: 1) {
                        Text("Stärke")
                    } minimumValueLabel: {
                        Text("0").font(.caption)
                    } maximumValueLabel: {
                        Text("10").font(.caption)
                    }
                    .tint(PainColor.color(intensity))
                    .accessibilityValue("\(intensity) von 10, \(PainScale.label(intensity))")
                    .accessibilityIdentifier("pain.intensity")
                } header: {
                    Text("Wie stark?")
                } footer: {
                    Text("0 = kein Schmerz, 10 = stärkster vorstellbarer Schmerz. Diese Skala nutzen auch Ärztinnen und Ärzte.")
                }

                Section("Wie fühlt es sich an?") {
                    chips(PainQuality.allCases, selection: $qualities, title: \.title)
                }

                Section {
                    DatePicker("Beginn", selection: $date)
                    Picker("Dauer", selection: $duration) {
                        ForEach(durations.indices, id: \.self) { index in
                            Text(durations[index].1).tag(durations[index].0)
                        }
                    }
                } header: {
                    Text("Wann?")
                }

                Section("Möglicher Auslöser") {
                    chips(PainTrigger.allCases, selection: $triggers, title: \.title)
                }

                Section("Was hat geholfen?") {
                    chips(PainRelief.allCases, selection: $reliefs, title: \.title)
                    TextField("Notiz, z. B. Ibuprofen 400 um 15 Uhr", text: $note, axis: .vertical)
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
            .navigationTitle(entry == nil ? "Schmerz eintragen" : "Schmerz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                        .accessibilityIdentifier("pain.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(regions.isEmpty)
                        .accessibilityIdentifier("pain.save")
                }
            }
            .onAppear(perform: load)
        }
    }

    private func chips<Item: Hashable & Identifiable>(_ items: [Item], selection: Binding<Set<Item>>, title: KeyPath<Item, String>) -> some View {
        FlowLayout(spacing: Spacing.xs) {
            ForEach(items) { item in
                ToggleChip(title: item[keyPath: title], isOn: selection.wrappedValue.contains(item)) {
                    if selection.wrappedValue.contains(item) {
                        selection.wrappedValue.remove(item)
                    } else {
                        selection.wrappedValue.insert(item)
                    }
                }
            }
        }
        .padding(.vertical, Spacing.xxs)
    }

    private func toggle(_ region: BodyRegion) {
        if let index = regions.firstIndex(of: region) {
            regions.remove(at: index)
        } else {
            regions.append(region)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let entry else { return }
        let fact = entry.fact
        regions = fact.regions
        intensity = fact.intensity
        qualities = Set(fact.qualities)
        date = fact.date
        duration = fact.durationMinutes ?? 0
        triggers = Set(fact.triggers)
        reliefs = Set(fact.reliefs)
        note = fact.note
        if let first = regions.first, first.positions[.front] == nil { side = .back }
    }

    private func save() {
        let fact = PainFact(
            date: date,
            regions: regions,
            intensity: intensity,
            qualities: PainQuality.allCases.filter(qualities.contains),
            durationMinutes: duration > 0 ? duration : nil,
            triggers: PainTrigger.allCases.filter(triggers.contains),
            reliefs: PainRelief.allCases.filter(reliefs.contains),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if let entry {
            DiaryActions.apply(fact, to: entry)
            DiaryActions.save(context)
        } else {
            DiaryActions.addPain(fact, in: context)
        }
        app.diaryChanged()
        dismiss()
    }
}

/// Eine Zeile im Verlauf.
struct PainRow: View {
    let entry: PainEntry
    var showsDate = false

    var body: some View {
        let fact = entry.fact
        HStack(spacing: Spacing.s) {
            Text("\(fact.intensity)")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(PainColor.color(fact.intensity), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel("Stärke \(fact.intensity) von 10")
            VStack(alignment: .leading, spacing: 1) {
                Text(fact.regionText)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)
                Text(detail(fact))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func detail(_ fact: PainFact) -> String {
        let calendar = AppModel.calendar
        var parts: [String] = []
        parts.append(showsDate
            ? "\(fact.date.nutritionDayLabel(calendar: calendar)), \(GermanCalendar.time(fact.date, calendar: calendar))"
            : GermanCalendar.time(fact.date, calendar: calendar))
        if !fact.qualities.isEmpty { parts.append(fact.qualities.map(\.title).joined(separator: ", ")) }
        if let minutes = fact.durationMinutes { parts.append(DurationText.short(minutes)) }
        if !fact.reliefs.isEmpty { parts.append("geholfen: " + fact.reliefs.map(\.title).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}

/// Alle Schmerzen mit Übersicht der letzten 30 Tage.
struct PainHistoryView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \PainEntry.date, order: .reverse) private var pains: [PainEntry]
    @State private var editing: PainEntry?

    var body: some View {
        let calendar = AppModel.calendar
        let now = Date.now
        let from = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)) ?? now
        let summary = PainSummary.compute(pains.map(\.fact), from: from, to: now.addingTimeInterval(1), calendar: calendar)
        let counts = Dictionary(summary.regions.map { ($0.region, $0.count) }, uniquingKeysWith: { lhs, _ in lhs })
        let days = Dictionary(grouping: pains) { calendar.startOfDay(for: $0.date) }
        List {
            if !pains.isEmpty {
                Section {
                    HStack(spacing: Spacing.s) {
                        stat("Einträge", "\(summary.count)")
                        stat("Tage", "\(summary.days)")
                        stat("Ø Stärke", summary.averageIntensity.map { WeightFormat.number(($0 * 10).rounded() / 10) } ?? "–")
                        stat("Höchste", summary.maxIntensity.map(String.init) ?? "–")
                    }
                    if summary.count > 0 {
                        BodyHeatMap(counts: counts)
                            .frame(maxHeight: 260)
                            .padding(.vertical, Spacing.xs)
                        ForEach(summary.regions.prefix(5)) { line in
                            LabeledContent(line.region.title, value: "\(line.count)× · Ø \(WeightFormat.number((line.averageIntensity * 10).rounded() / 10)) · max. \(line.maxIntensity)")
                        }
                    }
                } header: {
                    Text("Letzte 30 Tage")
                }
            }
            ForEach(days.keys.sorted(by: >), id: \.self) { day in
                Section(day.nutritionDayLabel(calendar: calendar)) {
                    ForEach(days[day] ?? []) { entry in
                        Button {
                            editing = entry
                        } label: {
                            PainRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Löschen", role: .destructive) {
                                DiaryActions.delete(entry, in: context)
                                app.diaryChanged()
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if pains.isEmpty {
                ContentUnavailableView(
                    "Noch keine Schmerzen",
                    systemImage: "figure.stand",
                    description: Text("Trag Schmerzen mit Ort und Stärke ein. Im Arztbericht siehst du dann, wo, wie oft und wie stark.")
                )
            }
        }
        .navigationTitle("Schmerzen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    app.openPainEntry()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Schmerz eintragen")
                .accessibilityIdentifier("pains.add")
            }
        }
        .sheet(item: $editing) { entry in
            PainEditorView(entry: entry)
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
