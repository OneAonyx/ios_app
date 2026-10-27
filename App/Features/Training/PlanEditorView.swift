import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit
import UniformTypeIdentifiers

/// Plan bearbeiten: Tage, Zyklus, Wunsch-Wochentage, Erinnerung, Zusatzmodul, Import.
struct PlanEditorView: View {
    @Bindable var plan: WorkoutPlan

    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @State private var importing = false
    @State private var askingClaude = false
    @State private var confirmReset = false
    @State private var newDayName = ""
    @State private var addingDay = false

    var body: some View {
        let days = plan.rotationDays
        Form {
            Section {
                TextField("Name", text: $plan.name)
                Stepper(value: Binding(
                    get: { plan.currentWeek },
                    set: { plan.currentWeek = min(max($0, 1), plan.mesoLength); changed() }
                ), in: 1...plan.mesoLength) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.cycle.label(week: plan.currentWeek))
                        Text(plan.cycle.weekHint(week: plan.currentWeek))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Picker("Als Nächstes", selection: Binding(get: { plan.nextDayIndex }, set: { plan.nextDayIndex = $0; changed() })) {
                    ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                        Text(day.title).tag(index)
                    }
                }
            } header: {
                Text("Plan")
            } footer: {
                Text("Die Rotation geht A → B → C → D. Nach dem letzten Tag beginnt die nächste Woche, nach Woche \(plan.mesoLength) (Deload) ein neuer Zyklus.")
            }

            Section("Tage") {
                ForEach(days) { day in
                    NavigationLink(value: TrainingRoute.day(day.stableID)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(day.title)
                            Text("\(day.sortedExercises.count) Übungen · ca. \(day.estimatedMinutes(week: plan.currentWeek, cycle: plan.cycle)) Min.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onMove { source, destination in
                    TrainingActions.moveDays(in: plan, from: source, to: destination, in: context)
                    changed()
                }
                .onDelete { offsets in
                    for index in offsets { TrainingActions.delete(days[index], in: context) }
                    changed()
                }
                Button {
                    addingDay = true
                } label: {
                    Label("Tag hinzufügen", systemImage: "plus.circle")
                }
            }

            if let module = plan.module {
                Section {
                    Picker("\(module.name) anhängen an", selection: Binding(get: { plan.moduleDayIndex }, set: { plan.moduleDayIndex = $0; changed() })) {
                        Text("Aus").tag(-1)
                        ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                            Text(day.title).tag(index)
                        }
                    }
                    NavigationLink(value: TrainingRoute.day(module.stableID)) {
                        Text("Übungen im Modul")
                    }
                } header: {
                    Text("Zusatzmodul")
                } footer: {
                    Text(module.focus.isEmpty ? "Wird beim gewählten Tag automatisch angehängt." : module.focus)
                }
            }

            Section {
                WeekdayPicker(selection: Binding(get: { plan.preferredWeekdays }, set: { plan.preferredWeekdays = $0; changed() }))
                Toggle("Erinnerung an Trainingstagen", isOn: Binding(
                    get: { plan.reminderMinute >= 0 },
                    set: { plan.reminderMinute = $0 ? 17 * 60 : -1; changed() }
                ))
                if plan.reminderMinute >= 0 {
                    DatePicker("Uhrzeit", selection: reminderTime, displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("Wunsch-Wochentage")
            } footer: {
                Text("Erscheinen als Training in Agenda und Woche. Ein verpasster Tag bringt die Rotation nicht durcheinander.")
            }

            Section {
                ShareLink(item: planJSON, preview: SharePreview("\(plan.name).json")) {
                    Label("Plan als JSON teilen", systemImage: "square.and.arrow.up")
                }
                Button {
                    askingClaude = true
                } label: {
                    Label("Mit Claude anpassen", systemImage: "sparkles")
                }
                .accessibilityIdentifier("plan.claude")
                Button {
                    importing = true
                } label: {
                    Label("Plan importieren (JSON)", systemImage: "square.and.arrow.down")
                }
                .accessibilityIdentifier("plan.import")
                Button("Zyklus neu starten (Woche 1, Tag A)") {
                    TrainingActions.restartCycle(plan, in: context)
                    changed()
                }
                Button("Startplan neu anlegen", role: .destructive) {
                    confirmReset = true
                }
            } footer: {
                Text("Claude bekommt deinen Plan, deine letzten Top-Sätze und Stagnationen und schlägt einen neuen Plan vor. Ein übernommener Plan wird der aktive Plan, dein Verlauf bleibt erhalten.")
            }
        }
        .navigationTitle("Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .onDisappear { changed() }
        .sheet(isPresented: $importing) {
            PlanImportView()
        }
        .sheet(isPresented: $askingClaude) {
            ClaudeRequestSheet(task: .trainingPlan)
        }
        .alert("Tag hinzufügen", isPresented: $addingDay) {
            TextField("Name, z. B. Beine", text: $newDayName)
            Button("Hinzufügen") {
                let name = newDayName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { TrainingActions.addDay(to: plan, name: name, in: context) }
                newDayName = ""
                changed()
            }
            Button("Abbrechen", role: .cancel) { newDayName = "" }
        }
        .confirmationDialog("Startplan neu anlegen?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Neu anlegen") {
                if let template = PlanTemplate.bundledUpperFourDay() {
                    TrainingActions.createPlan(from: template, in: context)
                    changed()
                }
            }
        } message: {
            Text("Der Oberkörper-4er wird als neuer, aktiver Plan angelegt. Der bisherige Plan und dein Verlauf bleiben gespeichert.")
        }
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                AppModel.calendar.date(bySettingHour: max(0, plan.reminderMinute) / 60, minute: max(0, plan.reminderMinute) % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = AppModel.calendar.dateComponents([.hour, .minute], from: date)
                plan.reminderMinute = (parts.hour ?? 17) * 60 + (parts.minute ?? 0)
                changed()
            }
        )
    }

    private var planJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(TrainingActions.template(of: plan)) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private func changed() {
        TrainingActions.save(context)
        app.trainingChanged()
    }
}

/// Ein Trainingstag: Name, Übungen mit Sätzen, Wiederholungen, RIR und Pause.
struct DayEditorView: View {
    @Bindable var day: PlanDay

    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @State private var adding = false
    @State private var editing: PlanExercise?

    var body: some View {
        let catalog = TrainingActions.catalog(in: context)
        let items = day.sortedExercises
        Form {
            Section {
                TextField("Name", text: $day.name)
                if !day.isModule {
                    TextField("Kürzel", text: $day.shortName)
                }
                TextField("Schwerpunkt (optional)", text: $day.focus)
            }
            Section {
                ForEach(items) { item in
                    Button {
                        editing = item
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(catalog.name(for: item.exerciseID))
                                    .foregroundStyle(Color.primary)
                                Text(item.template.prescription + " · Pause \(item.restSeconds) s" + (item.superset.map { " · Supersatz \($0)" } ?? "") + (item.isOptional ? " · optional" : ""))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "slider.horizontal.3")
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .onMove { source, destination in
                    TrainingActions.moveExercises(in: day, from: source, to: destination, in: context)
                    app.trainingChanged()
                }
                .onDelete { offsets in
                    for index in offsets { TrainingActions.delete(items[index], in: context) }
                    app.trainingChanged()
                }
                Button {
                    adding = true
                } label: {
                    Label("Übung hinzufügen", systemImage: "plus.circle")
                }
            } header: {
                Text("Übungen")
            } footer: {
                Text("Gleiche Supersatz-Buchstaben werden im Training abwechselnd mit kurzer Pause geführt.")
            }
        }
        .navigationTitle(day.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .onDisappear {
            TrainingActions.save(context)
            app.trainingChanged()
        }
        .sheet(isPresented: $adding) {
            ExercisePickerView(title: "Übung hinzufügen") { exercise in
                TrainingActions.addExercise(exercise, to: day, in: context)
                app.trainingChanged()
            }
        }
        .sheet(item: $editing) { item in
            PlanExerciseEditor(item: item, name: catalog.name(for: item.exerciseID))
        }
    }
}

/// Sätze, Wiederholungsbereich, RIR, Pause, Supersatz einer Plan-Übung.
struct PlanExerciseEditor: View {
    @Bindable var item: PlanExercise
    let name: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("\(item.sets) Sätze", value: $item.sets, in: 1...10)
                    Stepper("Mindestens \(item.repMin) Wdh.", value: Binding(get: { item.repMin }, set: { item.repMin = $0; item.repMax = max(item.repMax, $0) }), in: 1...50)
                    Stepper("Höchstens \(item.repMax) Wdh.", value: Binding(get: { item.repMax }, set: { item.repMax = max($0, item.repMin) }), in: 1...50)
                    Stepper("RIR \(item.rir)", value: $item.rir, in: 0...5)
                    Stepper("Pause \(item.restSeconds) s", value: $item.restSeconds, in: 30...300, step: 15)
                } footer: {
                    Text("RIR = Wiederholungen im Tank. In Woche 1 gilt eine mehr, in den harten Wochen eine weniger, im Deload 4.")
                }
                Section {
                    TextField("Supersatz (z. B. A)", text: Binding(
                        get: { item.superset ?? "" },
                        set: { item.superset = $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : String($0.prefix(2)).uppercased() }
                    ))
                    Toggle("Optional", isOn: $item.isOptional)
                    TextField("Notiz", text: $item.note, axis: .vertical)
                }
            }
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        TrainingActions.save(context)
                        app.trainingChanged()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Plan aus JSON übernehmen (z. B. Antwort von Claude), mit Vorschau.
struct PlanImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @State private var text = ""
    @State private var imported: ImportedPlan?
    @State private var errorMessage: String?
    @State private var pickingFile = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("JSON oder ganze Claude-Antwort einfügen", text: $text, axis: .vertical)
                        .lineLimit(4...10)
                        .font(.footnote.monospaced())
                    PasteButton(payloadType: String.self) { strings in
                        text = strings.first ?? ""
                        check()
                    }
                    Button("Datei wählen") { pickingFile = true }
                    Button("Prüfen") { check() }
                        .disabled(text.isEmpty)
                } footer: {
                    Text("Format „orbit.plan.v1“: Tage mit Übungen, Sätzen, Wiederholungen, RIR und Pause. Übungsnamen werden der Bibliothek zugeordnet.")
                }
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                if let imported {
                    let catalog = TrainingActions.catalog(in: context)
                    Section("Vorschau: \(imported.template.name)") {
                        ForEach(Array(imported.template.days.enumerated()), id: \.offset) { _, day in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(day.name).font(.headline)
                                ForEach(Array(day.exercises.enumerated()), id: \.offset) { _, item in
                                    Text("\(item.name ?? catalog.name(for: item.exercise)) – \(item.prescription)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if !imported.unmatched.isEmpty {
                        Section {
                            ForEach(imported.unmatched, id: \.self) { name in
                                Text(name)
                            }
                        } header: {
                            Text("Neue eigene Übungen")
                        } footer: {
                            Text("Diese Namen gibt es in der Bibliothek nicht. Sie werden als eigene Übungen angelegt.")
                        }
                    }
                    Section {
                        Button("Plan übernehmen") {
                            TrainingActions.importPlan(imported, in: context)
                            app.trainingChanged()
                            dismiss()
                        }
                        .font(.headline)
                    }
                }
            }
            .navigationTitle("Plan importieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.json, .plainText]) { result in
                guard case .success(let url) = result else { return }
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    text = String(decoding: data, as: UTF8.self)
                    check()
                }
            }
        }
    }

    private func check() {
        do {
            let template = try PlanImporter.parse(text)
            imported = PlanImporter.resolve(template, catalog: TrainingActions.catalog(in: context))
            errorMessage = nil
        } catch {
            imported = nil
            errorMessage = error.localizedDescription
        }
    }
}
