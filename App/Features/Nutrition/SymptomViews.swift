import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Symptom eintragen: Art, Stärke, Zeit, Dauer.
struct SymptomEditorView: View {
    var preset: SymptomType?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var type: SymptomType?
    @State private var severity = 3
    @State private var date = Date.now
    @State private var duration = 0
    @State private var note = ""

    private let durations: [(Int, String)] = [(0, "Unbekannt"), (15, "15 Min."), (30, "30 Min."), (60, "1 Std."), (120, "2 Std."), (240, "4 Std."), (480, "8 Std. und mehr")]

    var body: some View {
        NavigationStack {
            Form {
                Section("Was?") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: Spacing.xs)], spacing: Spacing.xs) {
                        ForEach(SymptomType.allCases) { item in
                            Button {
                                type = item
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
                                .foregroundStyle(type == item ? Color.white : Color.primary)
                                .background(type == item ? ModuleAccent.health : Color.tagwerkPage, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(type == item ? .isSelected : [])
                            .accessibilityIdentifier("symptom.\(item.rawValue)")
                        }
                    }
                    .padding(.vertical, Spacing.xxs)
                }
                Section {
                    Picker("Stärke", selection: $severity) {
                        ForEach(SymptomSeverity.range, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Stärke")
                } footer: {
                    Text("\(severity) · \(SymptomSeverity.title(severity))")
                }
                Section {
                    DatePicker("Beginn", selection: $date)
                    Picker("Dauer", selection: $duration) {
                        ForEach(durations.indices, id: \.self) { index in
                            Text(durations[index].1).tag(durations[index].0)
                        }
                    }
                    TextField("Notiz", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("Beschwerden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        guard let type else { return }
                        NutritionActions.addSymptom(type, severity: severity, date: date, durationMinutes: duration > 0 ? duration : nil, note: note, in: context)
                        app.nutritionChanged()
                        dismiss()
                    }
                    .disabled(type == nil)
                    .accessibilityIdentifier("symptom.save")
                }
            }
        }
        .onAppear {
            if type == nil { type = preset }
        }
    }
}

/// Alle Beschwerden, nach Tagen.
struct SymptomHistoryView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \SymptomEntry.date, order: .reverse) private var symptoms: [SymptomEntry]

    var body: some View {
        let calendar = AppModel.calendar
        let days = Dictionary(grouping: symptoms) { calendar.startOfDay(for: $0.date) }
        let sortedDays = days.keys.sorted(by: >)
        List {
            ForEach(sortedDays, id: \.self) { day in
                Section(day.nutritionDayLabel(calendar: calendar)) {
                    ForEach(days[day] ?? []) { symptom in
                        SymptomRow(symptom: symptom)
                            .swipeActions {
                                Button("Löschen", role: .destructive) {
                                    NutritionActions.delete(symptom, in: context)
                                    app.nutritionChanged()
                                }
                            }
                    }
                }
            }
        }
        .overlay {
            if symptoms.isEmpty {
                ContentUnavailableView(
                    "Noch keine Beschwerden",
                    systemImage: "waveform.path.ecg",
                    description: Text("Trage Beschwerden ein, sobald sie auftreten. Zusammen mit dem Ernährungstagebuch zeigt Orbit dann Muster.")
                )
            }
        }
        .navigationTitle("Beschwerden")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    app.isAddingSymptom = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Beschwerden eintragen")
            }
        }
    }
}

/// Auslöser-Analyse: Lebensmittel und Umstände, nach denen auffällig oft Beschwerden kamen.
struct PatternsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MealEntry.date) private var meals: [MealEntry]
    @Query(sort: \SymptomEntry.date) private var symptoms: [SymptomEntry]
    @State private var type: SymptomType?
    @State private var days = 90

    var body: some View {
        // Die Abfragen sorgen dafür, dass die Auswertung bei neuen Einträgen neu rechnet.
        let _ = (meals.count, symptoms.count)
        let report = NutritionActions.triggerReport(days: days, type: type, in: context)
        let presentTypes = SymptomType.allCases.filter { item in symptoms.contains { $0.type == item } }
        List {
            Section {
                Picker("Beschwerden", selection: $type) {
                    Text("Alle").tag(SymptomType?.none)
                    ForEach(presentTypes) { item in
                        Text(item.title).tag(SymptomType?.some(item))
                    }
                }
                Picker("Zeitraum", selection: $days) {
                    Text("30 Tage").tag(30)
                    Text("90 Tage").tag(90)
                    Text("1 Jahr").tag(365)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("\(report.mealCount) Mahlzeiten und \(report.symptomCount) Beschwerden ausgewertet.")
            }
            if let missing = report.missingDataText {
                Section {
                    Label(missing, systemImage: "hourglass")
                        .font(.subheadline)
                }
            } else if report.findings.isEmpty {
                Section {
                    Label("Bisher kein auffälliges Muster. Gut so – oder es braucht noch mehr Einträge.", systemImage: "checkmark.seal")
                        .font(.subheadline)
                }
            } else {
                Section {
                    ForEach(report.findings) { finding in
                        FindingRow(finding: finding)
                    }
                } header: {
                    Text("Auffällig")
                } footer: {
                    Text("Gezählt werden Beschwerden bis 24 Stunden nach dem Essen, am stärksten zwischen 15 Minuten und 3 Stunden. Ein Muster ist ein Hinweis, keine Diagnose. Teste Verdächtiges gezielt, am besten mit ärztlicher Begleitung.")
                }
            }
            Section {
                NavigationLink {
                    SymptomHistoryView()
                } label: {
                    Label("Alle Beschwerden", systemImage: "list.bullet")
                }
            }
        }
        .navigationTitle("Muster")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FindingRow: View {
    let finding: TriggerFinding

    var body: some View {
        let content = HStack(spacing: Spacing.s) {
            IconBadge(systemImage: finding.isFactor ? "clock.arrow.circlepath" : "fork.knife", tint: finding.lift >= 2 ? .red : .orange, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.primary)
                Text(finding.sentence)
                    .font(.subheadline)
                    .foregroundStyle(Color.primary)
                Text(finding.comparison)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let together = finding.companionText {
                    Label(together, systemImage: "link")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        if finding.isFactor {
            content
        } else {
            NavigationLink {
                FoodDetailView(foodID: finding.key)
            } label: {
                content
            }
        }
    }
}

/// Ziele für Eiweiß und Wasser, Nachfrage zu Medikamenten vor dem Essen.
struct NutritionSettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKeys.proteinPerKg) private var proteinPerKg = NutritionTargets.defaultProteinPerKg
    @AppStorage(SettingsKeys.waterTarget) private var waterTarget = NutritionTargets.defaultWaterML
    @AppStorage(SettingsKeys.askBeforeMealMedication) private var askMedication = true
    @Query private var customFoods: [CustomFood]

    var body: some View {
        let bodyweight = NutritionActions.bodyweight(in: context)
        Form {
            Section {
                Stepper(value: $proteinPerKg, in: 1.2...2.6, step: 0.1) {
                    LabeledContent("Eiweiß je kg", value: "\(WeightFormat.number((proteinPerKg * 10).rounded() / 10)) g")
                }
                LabeledContent("Tagesziel", value: "\(Int(NutritionTargets.proteinTarget(bodyweight: bodyweight, perKg: proteinPerKg))) g")
            } header: {
                Text("Eiweiß")
            } footer: {
                Text(bodyweight.map { "Gerechnet mit deinem Gewicht von \(WeightFormat.number($0)) kg (Training → Körper). Für Muskelaufbau gelten 1,6–2,2 g je kg als guter Bereich." }
                    ?? "Trage dein Gewicht unter Training → Körper ein. Bis dahin rechnet Orbit mit 80 kg. Für Muskelaufbau gelten 1,6–2,2 g je kg als guter Bereich.")
            }
            Section("Wasser") {
                Stepper(value: $waterTarget, in: 1_000...5_000, step: 250) {
                    LabeledContent("Tagesziel", value: "\(NutritionDay.liters(waterTarget)) l")
                }
            }
            Section {
                Toggle("Beim Eintragen nachfragen", isOn: $askMedication)
            } header: {
                Text("Medikamente vor dem Essen")
            } footer: {
                Text("Fragt bei Medikamenten mit dem Hinweis „vor dem Essen“ (z. B. DAO-Enzym), ob du sie schon genommen hast.")
            }
            if !customFoods.isEmpty {
                Section("Eigene und gescannte Lebensmittel") {
                    ForEach(customFoods.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }) { food in
                        NavigationLink(value: NutritionRoute.food(food.stableID)) {
                            FoodRow(food: food.info)
                        }
                    }
                }
            }
        }
        .navigationTitle("Ziele")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: proteinPerKg) { app.nutritionChanged() }
        .onChange(of: waterTarget) { app.nutritionChanged() }
    }
}
