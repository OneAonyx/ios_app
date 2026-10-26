import Charts
import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Alle Übungen, nach Muskelgruppe sortiert, mit Suche.
struct ExerciseLibraryView: View {
    @Environment(\.modelContext) private var context
    @State private var query = ""
    @State private var creating = false

    var body: some View {
        let catalog = TrainingActions.catalog(in: context)
        let results = catalog.search(query)
        let groups = Dictionary(grouping: results) { $0.primary.first ?? .abs }
        List {
            ForEach(groups.keys.sorted(), id: \.self) { muscle in
                Section(muscle.title) {
                    ForEach(groups[muscle] ?? []) { exercise in
                        NavigationLink(value: TrainingRoute.exercise(exercise.id)) {
                            ExerciseListRow(exercise: exercise)
                        }
                    }
                }
            }
        }
        .overlay {
            if results.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .searchable(text: $query, prompt: "Übung suchen")
        .navigationTitle("Übungen")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    creating = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Eigene Übung")
            }
        }
        .sheet(isPresented: $creating) {
            CustomExerciseEditor(initialName: query) { _ in }
        }
    }
}

struct ExerciseListRow: View {
    let exercise: ExerciseInfo

    var body: some View {
        HStack(spacing: Spacing.s) {
            ExerciseSymbol(exercise: exercise, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .foregroundStyle(Color.primary)
                Text([exercise.muscleSummary, exercise.equipment.title, exercise.isCustom ? "eigene" : ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Übung auswählen (Tauschen, Hinzufügen). Mit `alternativesTo` stehen passende Alternativen oben.
struct ExercisePickerView: View {
    let title: String
    var alternativesTo: String?
    let onPick: (ExerciseInfo) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var query = ""
    @State private var creating = false

    var body: some View {
        let catalog = TrainingActions.catalog(in: context)
        let alternatives = alternativesTo.map { catalog.alternatives(to: $0) } ?? []
        let results = catalog.search(query)
        let groups = Dictionary(grouping: results) { $0.primary.first ?? .abs }
        NavigationStack {
            List {
                if query.isEmpty, !alternatives.isEmpty {
                    Section("Passende Alternativen") {
                        ForEach(alternatives) { exercise in
                            pickRow(exercise)
                        }
                    }
                }
                ForEach(groups.keys.sorted(), id: \.self) { muscle in
                    Section(muscle.title) {
                        ForEach(groups[muscle] ?? []) { exercise in
                            pickRow(exercise)
                        }
                    }
                }
                Section {
                    Button {
                        creating = true
                    } label: {
                        Label(query.isEmpty ? "Eigene Übung anlegen" : "„\(query)“ als eigene Übung anlegen", systemImage: "plus.circle")
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Übung suchen")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .sheet(isPresented: $creating) {
                CustomExerciseEditor(initialName: query) { created in
                    onPick(created)
                    dismiss()
                }
            }
        }
    }

    private func pickRow(_ exercise: ExerciseInfo) -> some View {
        Button {
            onPick(exercise)
            dismiss()
        } label: {
            ExerciseListRow(exercise: exercise)
        }
    }
}

/// Eine Übung: Muskeln, Technik, eigener Steigerungsschritt, Verlauf und Rekorde.
struct ExerciseDetailView: View {
    let exerciseID: String

    @Environment(\.modelContext) private var context
    @State private var incrementText = ""

    var body: some View {
        let catalog = TrainingActions.catalog(in: context)
        let exercise = TrainingActions.info(for: exerciseID, catalog: catalog)
        let history = TrainingActions.history(for: exerciseID, limit: 30, in: context)
        let chronological = history.reversed().filter { $0.bestEstimatedOneRepMax != nil }
        let bestWeight = history.compactMap(\.topWeight).max()
        let bestE1RM = history.compactMap(\.bestEstimatedOneRepMax).max()
        let step = TrainingActions.increment(for: exercise, in: context)

        List {
            Section {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.s) {
                        ExerciseSymbol(exercise: exercise, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name)
                                .font(.headline)
                            Text("\(exercise.mechanic.title) · \(exercise.equipment.title)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !exercise.primary.isEmpty {
                        Text("Hauptmuskeln: \(exercise.primary.map(\.title).joined(separator: ", "))")
                            .font(.footnote)
                    }
                    if !exercise.secondary.isEmpty {
                        Text("Mit beteiligt: \(exercise.secondary.map(\.title).joined(separator: ", "))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, Spacing.xxs)
            }
            if !exercise.cues.isEmpty {
                Section("Technik") {
                    ForEach(exercise.cues, id: \.self) { cue in
                        Label(cue, systemImage: "checkmark")
                            .font(.subheadline)
                    }
                }
            }
            Section {
                Stepper(value: Binding(
                    get: { step },
                    set: { TrainingActions.setIncrement($0, for: exerciseID, in: context) }
                ), in: 0.5...20, step: 0.5) {
                    HStack {
                        Text("Steigerung")
                        Spacer()
                        Text("\(WeightFormat.number(step)) kg")
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Um so viel steigt das Gewicht, wenn alle Sätze das obere Ende erreichen. Passe es an die Hanteln und Gewichte in deinem Gym an.")
            }
            if !history.isEmpty {
                Section("Verlauf") {
                    HStack {
                        StatTile(title: "Höchstgewicht", value: bestWeight.map { "\(WeightFormat.number($0)) kg" } ?? "–")
                        StatTile(title: "Geschätztes Max.", value: bestE1RM.map { "\(WeightFormat.number($0.rounded())) kg" } ?? "–")
                    }
                    .listRowInsets(EdgeInsets(top: Spacing.xs, leading: Spacing.s, bottom: Spacing.xs, trailing: Spacing.s))
                    if chronological.count >= 2 {
                        Chart(chronological.map { ChartPoint(date: $0.date, value: $0.bestEstimatedOneRepMax ?? 0) }) { point in
                            LineMark(x: .value("Datum", point.date), y: .value("e1RM", point.value))
                                .interpolationMethod(.monotone)
                                .foregroundStyle(ModuleAccent.training)
                            PointMark(x: .value("Datum", point.date), y: .value("e1RM", point.value))
                                .foregroundStyle(ModuleAccent.training)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 180)
                        .accessibilityLabel("Verlauf des geschätzten Maximums")
                    }
                    ForEach(history.prefix(10), id: \.date) { performance in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(performance.date.trainingDayLabel())
                                .font(.subheadline.weight(.medium))
                            Text(performance.summary.isEmpty ? "nur Aufwärmen" : performance.summary)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Ein Punkt in einem Verlaufsdiagramm.
struct ChartPoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// Eigene Übung anlegen.
struct CustomExerciseEditor: View {
    var initialName = ""
    let onCreate: (ExerciseInfo) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var primary: Set<MuscleGroup> = [.chest]
    @State private var equipment: Equipment = .machine
    @State private var mechanic: Mechanic = .isolation
    @State private var rest = 90
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Gerät", selection: $equipment) {
                        ForEach(Equipment.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    Picker("Art", selection: $mechanic) {
                        Text(Mechanic.compound.title).tag(Mechanic.compound)
                        Text(Mechanic.isolation.title).tag(Mechanic.isolation)
                    }
                    Stepper("Pause \(rest) s", value: $rest, in: 30...300, step: 15)
                }
                Section("Hauptmuskeln") {
                    ForEach(MuscleGroup.allCases) { muscle in
                        Button {
                            if primary.contains(muscle) { primary.remove(muscle) } else { primary.insert(muscle) }
                        } label: {
                            HStack {
                                Text(muscle.title)
                                    .foregroundStyle(Color.primary)
                                Spacer()
                                if primary.contains(muscle) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(ModuleAccent.training)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Eigene Übung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anlegen") { create() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || primary.isEmpty)
                }
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            name = initialName
        }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        var id = PlanImporter.customID(for: trimmed)
        if TrainingActions.catalog(in: context).exercise(id: id) != nil {
            id += "-\(Int(Date.now.timeIntervalSince1970) % 10_000)"
        }
        let info = ExerciseInfo(
            id: id, name: trimmed, primary: primary.sorted(), equipment: equipment, mechanic: mechanic,
            rest: rest, isCustom: true
        )
        TrainingActions.createCustomExercise(info, in: context)
        onCreate(info)
        dismiss()
    }
}
