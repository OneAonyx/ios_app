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
    @State private var editMode: EditMode = .inactive

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

            Section {
                ForEach(Array(days.enumerated()), id: \.element.stableID) { index, day in
                    let isNext = index == plan.nextDayIndex
                    let move: (Int) -> Void = { offset in
                        withAnimation { TrainingActions.moveDay(day, by: offset, in: context) }
                        changed()
                    }
                    HStack(spacing: Spacing.s) {
                        PositionBadge(text: day.shortName.isEmpty ? "\(index + 1)" : day.shortName, highlighted: isNext)
                        NavigationLink(value: TrainingRoute.day(day.stableID)) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: Spacing.xs) {
                                    Text(day.name)
                                    if isNext {
                                        Text("Als Nächstes")
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .foregroundStyle(ModuleAccent.training)
                                            .background(ModuleAccent.training.opacity(0.14), in: Capsule())
                                    }
                                }
                                Text("\(day.sortedExercises.count) Übungen · ca. \(day.estimatedMinutes(week: plan.currentWeek, cycle: plan.cycle)) Min.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(editMode.isEditing)
                        if editMode.isEditing {
                            MoveButtons(canMoveUp: index > 0, canMoveDown: index < days.count - 1, onUp: { move(-1) }, onDown: { move(1) })
                        }
                    }
                    .frame(minHeight: TouchTarget.standard)
                    .contextMenu {
                        Button {
                            TrainingActions.setNextDay(day, in: context)
                            changed()
                        } label: {
                            Label("Als Nächstes", systemImage: "arrow.forward.circle")
                        }
                        if index > 0 {
                            Button { move(-1) } label: { Label("Nach oben", systemImage: "arrow.up") }
                        }
                        if index < days.count - 1 {
                            Button { move(1) } label: { Label("Nach unten", systemImage: "arrow.down") }
                        }
                    }
                    .accessibilityAction(named: "Als Nächstes") {
                        TrainingActions.setNextDay(day, in: context)
                        changed()
                    }
                    .accessibilityAction(named: "Nach oben") { move(-1) }
                    .accessibilityAction(named: "Nach unten") { move(1) }
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
                    Label("Tag hinzufügen", systemImage: "plus.circle.fill")
                        .frame(minHeight: TouchTarget.standard)
                }
            } header: {
                HStack {
                    Text("Tage in der Rotation")
                    Spacer()
                    if days.count > 1 {
                        ReorderToggle(editMode: $editMode)
                            .accessibilityIdentifier("plan.reorder")
                    }
                }
            } footer: {
                Text("Lange drücken: als nächste Einheit setzen oder verschieben. Die Kürzel (A, B, C …) bleiben beim Tag.")
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
        .environment(\.editMode, $editMode)
        .navigationTitle("Plan")
        .navigationBarTitleDisplayMode(.inline)
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
    @State private var swapping: PlanExercise?
    @State private var editMode: EditMode = .inactive

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
                ForEach(Array(items.enumerated()), id: \.element.stableID) { index, item in
                    let name = catalog.name(for: item.exerciseID)
                    let move: (Int) -> Void = { offset in
                        withAnimation { TrainingActions.moveExercise(item, by: offset, in: context) }
                        app.trainingChanged()
                    }
                    DayExerciseRow(
                        position: item.superset.map { "\(index + 1)\($0)" } ?? "\(index + 1)",
                        name: name,
                        muscles: catalog.exercise(id: item.exerciseID)?.muscleSummary ?? "",
                        detail: Self.detail(item),
                        isEditing: editMode.isEditing,
                        canMoveUp: index > 0,
                        canMoveDown: index < items.count - 1,
                        onEdit: { editing = item },
                        onMove: move
                    )
                    .frame(minHeight: TouchTarget.standard)
                    .swipeActions(edge: .leading) {
                        if index > 0 {
                            Button { move(-1) } label: { Label("Nach oben", systemImage: "arrow.up") }
                                .tint(.blue)
                        }
                        if index < items.count - 1 {
                            Button { move(1) } label: { Label("Nach unten", systemImage: "arrow.down") }
                                .tint(.indigo)
                        }
                    }
                    .contextMenu {
                        Button { editing = item } label: { Label("Sätze und Pause", systemImage: "slider.horizontal.3") }
                        Button { swapping = item } label: { Label("Übung tauschen", systemImage: "arrow.triangle.2.circlepath") }
                        if index > 0 {
                            Button { move(-1) } label: { Label("Nach oben", systemImage: "arrow.up") }
                        }
                        if index < items.count - 1 {
                            Button { move(1) } label: { Label("Nach unten", systemImage: "arrow.down") }
                        }
                        Button(role: .destructive) {
                            TrainingActions.delete(item, in: context)
                            app.trainingChanged()
                        } label: {
                            Label("Entfernen", systemImage: "trash")
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(index + 1). \(name), \(item.template.prescription)")
                    .accessibilityAction(named: "Nach oben") { move(-1) }
                    .accessibilityAction(named: "Nach unten") { move(1) }
                    .accessibilityAction(named: "Übung tauschen") { swapping = item }
                    .accessibilityAction(named: "Bearbeiten") { editing = item }
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
                    Label("Übung hinzufügen", systemImage: "plus.circle.fill")
                        .frame(minHeight: TouchTarget.standard)
                }
                .accessibilityIdentifier("day.addExercise")
            } header: {
                HStack {
                    Text("Übungen in Reihenfolge")
                    Spacer()
                    if items.count > 1 {
                        ReorderToggle(editMode: $editMode)
                            .accessibilityIdentifier("day.reorder")
                    }
                }
            } footer: {
                Text("Antippen: Sätze, Wiederholungen und Pause. Lange drücken oder nach rechts wischen: verschieben, tauschen, entfernen. Gleiche Supersatz-Buchstaben werden im Training abwechselnd geführt.")
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle(day.title)
        .navigationBarTitleDisplayMode(.inline)
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
        .sheet(item: $swapping) { item in
            ExercisePickerView(title: "Übung tauschen", alternativesTo: item.exerciseID) { exercise in
                TrainingActions.swapExercise(item, to: exercise, in: context)
                app.trainingChanged()
            }
        }
        .sheet(item: $editing) { item in
            PlanExerciseEditor(item: item, name: catalog.name(for: item.exerciseID))
        }
    }
}

/// Eine Übung im Tag-Editor: Nummer, Name, Muskeln, Sätze; im Anordnen-Modus mit Pfeilen.
private struct DayExerciseRow: View {
    let position: String
    let name: String
    let muscles: String
    let detail: String
    let isEditing: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onEdit: () -> Void
    let onMove: (Int) -> Void

    var body: some View {
        HStack(spacing: Spacing.s) {
            PositionBadge(text: position)
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .foregroundStyle(Color.primary)
                    if !muscles.isEmpty {
                        Text(muscles)
                            .font(.caption)
                            .foregroundStyle(ModuleAccent.training)
                    }
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isEditing)
            if isEditing {
                MoveButtons(canMoveUp: canMoveUp, canMoveDown: canMoveDown, onUp: { onMove(-1) }, onDown: { onMove(1) })
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
    }
}

extension DayEditorView {
    /// „3 × 8–10 · Pause 90 s · Supersatz A · optional“
    static func detail(_ item: PlanExercise) -> String {
        var parts: [String] = [item.template.prescription, "Pause \(item.restSeconds) s"]
        if let superset = item.superset { parts.append("Supersatz \(superset)") }
        if item.isOptional { parts.append("optional") }
        return parts.joined(separator: " · ")
    }
}

/// Sätze, Wiederholungsbereich, RIR, Pause, Supersatz einer Plan-Übung.
struct PlanExerciseEditor: View {
    @Bindable var item: PlanExercise
    let name: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @State private var swapping = false
    @State private var confirmRemove = false

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
                Section {
                    Button {
                        swapping = true
                    } label: {
                        Label("Übung tauschen", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .accessibilityIdentifier("planExercise.swap")
                    Button(role: .destructive) {
                        confirmRemove = true
                    } label: {
                        Label("Aus dem Tag entfernen", systemImage: "trash")
                    }
                } footer: {
                    Text("Beim Tauschen bleiben Sätze, Wiederholungen und Pause erhalten.")
                }
            }
            .sheet(isPresented: $swapping) {
                ExercisePickerView(title: "Übung tauschen", alternativesTo: item.exerciseID) { exercise in
                    TrainingActions.swapExercise(item, to: exercise, in: context)
                    app.trainingChanged()
                }
            }
            .confirmationDialog("\(name) entfernen?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Entfernen", role: .destructive) {
                    TrainingActions.delete(item, in: context)
                    app.trainingChanged()
                    dismiss()
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
