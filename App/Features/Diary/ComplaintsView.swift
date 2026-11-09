import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Beschwerden und Schmerzen an einem Ort: gemeinsamer Verlauf, umschaltbar auf nur eine Art.
struct ComplaintsView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case all, symptoms, pains
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "Alle"
            case .symptoms: "Beschwerden"
            case .pains: "Schmerzen"
            }
        }
    }

    @State var mode: Mode = .all

    var body: some View {
        Group {
            switch mode {
            case .all: ComplaintsTimeline()
            case .symptoms: SymptomHistoryView()
            case .pains: PainHistoryView()
            }
        }
        .safeAreaInset(edge: .top) {
            Picker("Anzeigen", selection: $mode) {
                ForEach(Mode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.xs)
            .background(.bar)
            .accessibilityIdentifier("complaints.mode")
        }
    }
}

/// Gemeinsamer Verlauf: Beschwerden und Schmerzen nach Tagen.
private struct ComplaintsTimeline: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \SymptomEntry.date, order: .reverse) private var symptoms: [SymptomEntry]
    @Query(sort: \PainEntry.date, order: .reverse) private var pains: [PainEntry]
    @State private var editingPain: PainEntry?

    private enum Item: Identifiable {
        case symptom(SymptomEntry)
        case pain(PainEntry)

        var id: String {
            switch self {
            case .symptom(let entry): "s-\(entry.stableID)"
            case .pain(let entry): "p-\(entry.stableID)"
            }
        }

        var date: Date {
            switch self {
            case .symptom(let entry): entry.date
            case .pain(let entry): entry.date
            }
        }
    }

    var body: some View {
        let calendar = AppModel.calendar
        let now = Date.now
        let since = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)) ?? now
        let items = (symptoms.map(Item.symptom) + pains.map(Item.pain)).sorted { $0.date > $1.date }
        let days = Dictionary(grouping: items) { calendar.startOfDay(for: $0.date) }
        let symptomDays = Set(symptoms.filter { $0.date >= since }.map { calendar.startOfDay(for: $0.date) })
        let painDays = Set(pains.filter { $0.date >= since }.map { calendar.startOfDay(for: $0.date) })
        List {
            if !items.isEmpty {
                Section {
                    HStack(spacing: Spacing.s) {
                        stat("Tage mit Beschwerden", "\(symptomDays.count)")
                        stat("Tage mit Schmerzen", "\(painDays.count)")
                        stat("Ohne beides", "\(max(0, 30 - symptomDays.union(painDays).count))")
                    }
                    NavigationLink {
                        PatternsView()
                    } label: {
                        Label("Muster: Was steckt dahinter?", systemImage: "magnifyingglass.circle")
                    }
                    .accessibilityIdentifier("complaints.patterns")
                } header: {
                    Text("Letzte 30 Tage")
                }
            }
            ForEach(days.keys.sorted(by: >), id: \.self) { day in
                Section(day.nutritionDayLabel(calendar: calendar)) {
                    ForEach(days[day] ?? []) { item in
                        switch item {
                        case .symptom(let entry):
                            SymptomRow(symptom: entry)
                                .swipeActions {
                                    Button("Löschen", role: .destructive) {
                                        NutritionActions.delete(entry, in: context)
                                        app.nutritionChanged()
                                    }
                                }
                        case .pain(let entry):
                            Button {
                                editingPain = entry
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
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView(
                    "Noch nichts eingetragen",
                    systemImage: "waveform.path.ecg",
                    description: Text("Trag Beschwerden (z. B. Blähungen, Bauchschmerz) und Schmerzen mit Ort und Stärke ein. Zusammen mit dem Ernährungstagebuch zeigt Orbit dann Muster.")
                )
            }
        }
        .navigationTitle("Beschwerden und Schmerzen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ComplaintAddMenu()
            }
        }
        .sheet(item: $editingPain) { entry in
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
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// „+“ mit Wahl: Beschwerde oder Schmerz.
struct ComplaintAddMenu: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Menu {
            Button {
                app.isAddingSymptom = true
            } label: {
                Label("Beschwerde (Bauch, Kopf …)", systemImage: "waveform.path.ecg")
            }
            Button {
                app.openPainEntry()
            } label: {
                Label("Schmerz mit Ort und Stärke", systemImage: "figure.stand")
            }
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Eintragen")
        .accessibilityIdentifier("complaints.add")
    }
}
