import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Laufende Einheit im Vollbild: eine Übung pro Seite, große Knöpfe, Pausen-Timer.
struct WorkoutSessionView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt == nil }, sort: \WorkoutSession.startedAt, order: .reverse)
    private var activeSessions: [WorkoutSession]

    @State private var selectedSlot = 0
    @State private var editingSet: SetLog?
    @State private var swappingSlot: Int?
    @State private var addingExercise = false
    @State private var confirmFinish = false
    @State private var confirmDiscard = false
    @State private var summary: SessionSummary?
    @State private var summaryTitle = ""

    var body: some View {
        NavigationStack {
            Group {
                if let summary {
                    SessionSummaryView(summary: summary, title: summaryTitle) {
                        app.isShowingWorkout = false
                    }
                } else if let session = activeSessions.first {
                    content(session)
                } else {
                    ContentUnavailableView("Keine laufende Einheit", systemImage: "figure.strengthtraining.traditional")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Schließen") { app.isShowingWorkout = false }
                            }
                        }
                }
            }
            .background(Color.tagwerkPage)
        }
    }

    // MARK: Inhalt

    private func content(_ session: WorkoutSession) -> some View {
        let catalog = TrainingActions.catalog(in: context)
        let slots = session.slots
        return VStack(spacing: 0) {
            header(session)
            slotChips(session, slots: slots, catalog: catalog)
            TabView(selection: $selectedSlot) {
                ForEach(slots, id: \.self) { slot in
                    ExercisePage(session: session, slot: slot, catalog: catalog, onEdit: { editingSet = $0 }, onSwap: { swappingSlot = slot })
                        .tag(slot)
                }
                AddExercisePage { addingExercise = true }
                    .tag(-1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .safeAreaInset(edge: .bottom) {
            if app.workout.isResting {
                RestTimerBar(session: session, catalog: catalog)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    app.isShowingWorkout = false
                } label: {
                    Image(systemName: "chevron.down")
                }
                .accessibilityLabel("Minimieren")
                .accessibilityIdentifier("workout.minimize")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Beenden") { confirmFinish = true }
                    .accessibilityIdentifier("workout.finish")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        addingExercise = true
                    } label: {
                        Label("Übung hinzufügen", systemImage: "plus")
                    }
                    Button(role: .destructive) {
                        confirmDiscard = true
                    } label: {
                        Label("Einheit verwerfen", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Weitere Aktionen")
            }
        }
        .confirmationDialog("Einheit beenden?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Beenden und speichern") {
                summaryTitle = session.title
                withAnimation { summary = app.finishWorkout(session) }
            }
            Button("Weiter trainieren", role: .cancel) {}
        } message: {
            let open = (session.sets ?? []).filter { !$0.isDone && $0.kind != .warmup }.count
            Text(open == 0 ? "Alle Sätze sind erledigt." : "\(open) offene Sätze werden nicht gespeichert.")
        }
        .confirmationDialog("Einheit verwerfen?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Verwerfen", role: .destructive) { app.discardWorkout(session) }
        } message: {
            Text("Alle Sätze dieser Einheit werden gelöscht.")
        }
        .sheet(item: $editingSet) { set in
            SetEditorSheet(set: set, catalog: catalog)
        }
        .sheet(isPresented: Binding(get: { swappingSlot != nil }, set: { if !$0 { swappingSlot = nil } })) {
            if let slot = swappingSlot, let current = session.exerciseID(inSlot: slot) {
                ExercisePickerView(title: "Übung tauschen", alternativesTo: current) { exercise in
                    TrainingActions.swapExercise(inSlot: slot, of: session, to: exercise.id, catalog: TrainingActions.catalog(in: context), in: context)
                    app.workout.updateActivity(session: session, catalog: TrainingActions.catalog(in: context))
                }
            }
        }
        .sheet(isPresented: $addingExercise) {
            ExercisePickerView(title: "Übung hinzufügen") { exercise in
                TrainingActions.addExercise(exercise, to: session, in: context)
                selectedSlot = session.slots.max() ?? 0
                app.workout.updateActivity(session: session, catalog: TrainingActions.catalog(in: context))
            }
        }
        .onAppear {
            if !slots.contains(selectedSlot) {
                selectedSlot = TrainingActions.nextPendingSet(in: session)?.slot ?? slots.first ?? 0
            }
        }
        .onChange(of: app.workout.focusSlot) { _, slot in
            guard let slot, slot != selectedSlot else { return }
            withAnimation(.snappy) { selectedSlot = slot }
        }
    }

    private func header(_ session: WorkoutSession) -> some View {
        let working = (session.sets ?? []).filter { $0.kind != .warmup }
        let done = working.filter(\.isDone).count
        return VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.title)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Spacer()
                Text(session.startedAt, style: .timer)
                    .font(.system(.title3, design: .rounded, weight: .semibold).monospacedDigit())
                    .foregroundStyle(ModuleAccent.training)
            }
            HStack(spacing: Spacing.xs) {
                Text(session.isDeload ? "Deload-Woche" : "Woche \(session.week)")
                Text("·")
                Text("\(done) von \(working.count) Sätzen")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            ProgressView(value: Double(done), total: Double(max(working.count, 1)))
                .tint(ModuleAccent.training)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.top, Spacing.xs)
    }

    private func slotChips(_ session: WorkoutSession, slots: [Int], catalog: ExerciseCatalog) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(Array(slots.enumerated()), id: \.element) { index, slot in
                        let sets = session.sets(inSlot: slot).filter { $0.kind != .warmup }
                        let complete = !sets.isEmpty && sets.allSatisfy(\.isDone)
                        let name = catalog.name(for: session.exerciseID(inSlot: slot) ?? "")
                        Button {
                            withAnimation(.snappy) { selectedSlot = slot }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: complete ? "checkmark.circle.fill" : "\(index + 1).circle")
                                Text(name)
                                    .lineLimit(1)
                            }
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, Spacing.s)
                            .padding(.vertical, 8)
                            .foregroundStyle(slot == selectedSlot ? Color.white : (complete ? Color.green : Color.primary))
                            .background(slot == selectedSlot ? ModuleAccent.training : Color.tagwerkCard, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .id(slot)
                    }
                }
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.xs)
            }
            .onChange(of: selectedSlot) { _, slot in
                withAnimation { proxy.scrollTo(slot, anchor: .center) }
            }
        }
    }
}

// MARK: - Seite einer Übung

private struct ExercisePage: View {
    let session: WorkoutSession
    let slot: Int
    let catalog: ExerciseCatalog
    let onEdit: (SetLog) -> Void
    let onSwap: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @State private var showsCues = false

    var body: some View {
        let sets = session.sets(inSlot: slot)
        let exerciseID = sets.first?.exerciseID ?? ""
        let exercise = TrainingActions.info(for: exerciseID, catalog: catalog)
        let last = TrainingActions.history(for: exerciseID, excluding: session.stableID, limit: 1, in: context).first
        let working = sets.filter { $0.kind == .working }
        let partner = partnerName(for: sets.first)

        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(exercise.name)
                        .font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text([exercise.muscleSummary, exercise.equipment.title, exercise.unilateral ? "Gewicht je Seite" : ""].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let partner {
                        Label("Supersatz mit \(partner)", systemImage: "arrow.left.arrow.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(ModuleAccent.training)
                    }
                }

                Card(padding: Spacing.s) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        if let first = working.first {
                            Text("Ziel: \(first.targetLabel) Wdh. · RIR \(first.targetRIR)\(working.count > 1 && working.last?.targetRIR != first.targetRIR ? " (letzter Satz \(working.last?.targetRIR ?? 0))" : "")")
                                .font(.subheadline.weight(.semibold))
                        }
                        if let last {
                            Text("Letztes Mal (\(last.date.trainingDayLabel())): \(last.summary)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Erstes Mal: Wähle ein Gewicht, mit dem du das Ziel sauber schaffst.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if let note = sets.first?.note, !note.isEmpty {
                            Text(note)
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                VStack(spacing: Spacing.xs) {
                    ForEach(sets) { set in
                        SetRow(set: set, label: label(for: set, in: sets), exercise: exercise) {
                            onEdit(set)
                        } onToggle: {
                            if set.isDone {
                                TrainingActions.reopen(set, in: context)
                            } else {
                                app.completeSet(set, weight: set.weight, reps: set.reps, rir: set.rir ?? set.targetRIR)
                            }
                            app.workout.updateActivity(session: session, catalog: catalog)
                        }
                    }
                }

                HStack(spacing: Spacing.xs) {
                    Button {
                        TrainingActions.addSet(toSlot: slot, of: session, in: context)
                        app.workout.updateActivity(session: session, catalog: catalog)
                    } label: {
                        actionLabel("Satz", systemImage: "plus")
                    }
                    Button {
                        TrainingActions.addSet(toSlot: slot, of: session, kind: .drop, in: context)
                    } label: {
                        actionLabel("Drop-Satz", systemImage: "arrow.down.right")
                    }
                    Button(action: onSwap) {
                        actionLabel("Tauschen", systemImage: "arrow.triangle.swap")
                    }
                    .accessibilityIdentifier("workout.swap")
                }
                .buttonStyle(.bordered)
                .font(.subheadline.weight(.semibold))
                .tint(ModuleAccent.training)

                if !exercise.cues.isEmpty {
                    DisclosureGroup("Technik", isExpanded: $showsCues) {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            ForEach(exercise.cues, id: \.self) { cue in
                                Label(cue, systemImage: "checkmark")
                                    .font(.subheadline)
                            }
                        }
                        .padding(.top, Spacing.xxs)
                    }
                    .tint(ModuleAccent.training)
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
        }
    }

    private func label(for set: SetLog, in sets: [SetLog]) -> String {
        switch set.kind {
        case .warmup:
            let index = sets.filter { $0.kind == .warmup }.firstIndex { $0.stableID == set.stableID } ?? 0
            return "W\(index + 1)"
        case .drop:
            return "D"
        case .working:
            let index = sets.filter { $0.kind == .working }.firstIndex { $0.stableID == set.stableID } ?? 0
            return "\(index + 1)"
        }
    }

    private func partnerName(for set: SetLog?) -> String? {
        guard let group = set?.superset, !group.isEmpty else { return nil }
        let partners = session.slots
            .filter { $0 != slot }
            .filter { other in session.sets(inSlot: other).contains { $0.superset == group } }
            .compactMap { session.exerciseID(inSlot: $0) }
            .map { catalog.name(for: $0) }
        return partners.isEmpty ? nil : partners.joined(separator: ", ")
    }

    /// Symbol über dem Text, damit „Drop-Satz“ und „Tauschen“ nicht umbrechen.
    private func actionLabel(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage)
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: TouchTarget.standard)
    }
}

/// Ein Satz: Gewicht × Wiederholungen, RIR, großer Abhak-Knopf.
private struct SetRow: View {
    let set: SetLog
    let label: String
    let exercise: ExerciseInfo
    let onEdit: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: Spacing.s) {
            Button(action: onEdit) {
                HStack(spacing: Spacing.s) {
                    Text(label)
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(set.kind == .warmup ? Color.secondary : ModuleAccent.training)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(weightText)
                                .font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit())
                            Text("×")
                                .foregroundStyle(.secondary)
                            Text("\(set.reps)")
                                .font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit())
                        }
                        Text(detailText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Gewicht und Wiederholungen ändern")
            .accessibilityIdentifier("workout.set.edit")

            Button(action: onToggle) {
                Image(systemName: set.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 34))
                    .foregroundStyle(set.isDone ? Color.green : ModuleAccent.training)
                    .frame(width: TouchTarget.gym, height: TouchTarget.gym)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .medium), trigger: set.isDone)
            .accessibilityLabel(set.isDone ? "Satz wieder öffnen" : "Satz abhaken")
            .accessibilityIdentifier("workout.set.check")
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xxs)
        .background(
            set.isDone ? Color.green.opacity(0.10) : Color.tagwerkCard,
            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        )
        .opacity(set.kind == .warmup && !set.isDone ? 0.85 : 1)
    }

    private var weightText: String {
        if exercise.assisted { return set.weight > 0 ? "−\(WeightFormat.number(set.weight)) kg" : "frei" }
        if exercise.equipment == .bodyweight { return set.weight > 0 ? "+\(WeightFormat.number(set.weight)) kg" : "KG" }
        return "\(WeightFormat.number(set.weight)) kg"
    }

    private var detailText: String {
        switch set.kind {
        case .warmup: return "Aufwärmen"
        case .drop: return "Drop-Satz"
        case .working:
            if set.isDone, let rir = set.rir { return "RIR \(rir)" }
            return "Ziel \(set.targetLabel) · RIR \(set.targetRIR)"
        }
    }
}

/// Letzte Seite: weitere Übung ergänzen.
private struct AddExercisePage: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: Spacing.m) {
            Spacer()
            Image(systemName: "plus.circle")
                .font(.system(size: 44))
                .foregroundStyle(ModuleAccent.training)
            Text("Noch etwas dranhängen?")
                .font(.headline)
            Button("Übung hinzufügen", action: onAdd)
                .buttonStyle(.borderedProminent)
                .tint(ModuleAccent.training)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Pause

private struct RestTimerBar: View {
    let session: WorkoutSession
    let catalog: ExerciseCatalog

    @Environment(AppModel.self) private var app

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let end = app.workout.restEndsAt ?? context.date
            let remaining = max(0, end.timeIntervalSince(context.date))
            let total = max(app.workout.restDuration, 1)
            VStack(spacing: Spacing.xs) {
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(remaining > 0 ? "Pause" : "Pause vorbei")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(Self.format(remaining))
                            .font(.system(.title, design: .rounded, weight: .bold).monospacedDigit())
                            .foregroundStyle(remaining > 0 ? Color.primary : Color.green)
                    }
                    Spacer()
                    Button("+30 s") {
                        app.workout.addRest(30, session: session, catalog: catalog)
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: TouchTarget.gym)
                    Button(remaining > 0 ? "Überspringen" : "Weiter") {
                        app.workout.skipRest(session: session, catalog: catalog)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ModuleAccent.training)
                    .frame(minHeight: TouchTarget.gym)
                    .accessibilityIdentifier("workout.rest.skip")
                }
                ProgressView(value: total - remaining, total: total)
                    .tint(ModuleAccent.training)
                if let next = app.workout.nextSetText(session: session, catalog: catalog) {
                    Text(next)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(2)
                }
            }
            .padding(Spacing.m)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .padding(.horizontal, Spacing.s)
            .sensoryFeedback(.success, trigger: remaining == 0) { _, isOver in isOver }
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let value = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

// MARK: - Satz bearbeiten

struct SetEditorSheet: View {
    let set: SetLog
    let catalog: ExerciseCatalog

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @State private var weight: Double = 0
    @State private var reps: Int = 0
    @State private var rir: Int = 2
    @State private var didLoad = false

    var body: some View {
        let exercise = TrainingActions.info(for: set.exerciseID, catalog: catalog)
        let step = TrainingActions.increment(for: exercise, in: context)
        NavigationStack {
            VStack(spacing: Spacing.l) {
                Text(exercise.name)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                stepperRow(
                    title: exercise.assisted ? "Unterstützung (kg)" : (exercise.equipment == .bodyweight ? "Zusatzgewicht (kg)" : "Gewicht (kg)"),
                    value: WeightFormat.number(weight),
                    minus: { weight = max(0, weight - step) },
                    plus: { weight += step }
                )
                stepperRow(title: "Wiederholungen", value: "\(reps)", minus: { reps = max(0, reps - 1) }, plus: { reps += 1 })

                if set.kind != .warmup {
                    VStack(spacing: Spacing.xs) {
                        Text("Wiederholungen im Tank (RIR)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Picker("RIR", selection: $rir) {
                            ForEach(0...5, id: \.self) { value in
                                Text(value == 5 ? "5+" : "\(value)").tag(value)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Spacer()

                VStack(spacing: Spacing.s) {
                    Button {
                        app.completeSet(set, weight: weight, reps: reps, rir: set.kind == .warmup ? nil : rir)
                        app.workout.updateActivity(session: set.session!, catalog: catalog)
                        dismiss()
                    } label: {
                        Label(set.isDone ? "Speichern" : "Abhaken", systemImage: "checkmark")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: TouchTarget.gym)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ModuleAccent.training)
                    .disabled(set.session == nil)
                    .accessibilityIdentifier("setEditor.complete")

                    if !set.isDone {
                        Button("Nur Werte übernehmen") {
                            set.weight = weight
                            set.reps = reps
                            set.rir = set.kind == .warmup ? nil : rir
                            TrainingActions.save(context)
                            dismiss()
                        }
                    }
                    Button("Satz löschen", role: .destructive) {
                        TrainingActions.delete(set, in: context)
                        dismiss()
                    }
                    .font(.subheadline)
                }
            }
            .padding(Spacing.m)
            .navigationTitle(set.kind == .warmup ? "Aufwärmsatz" : (set.kind == .drop ? "Drop-Satz" : "Satz"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .sensoryFeedback(.selection, trigger: weight)
        .sensoryFeedback(.selection, trigger: reps)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            weight = set.weight
            reps = set.reps
            rir = set.rir ?? set.targetRIR
        }
    }

    private func stepperRow(title: String, value: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        VStack(spacing: Spacing.xs) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: Spacing.m) {
                roundButton("minus", label: "\(title) verringern", action: minus)
                Text(value)
                    .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                    .frame(minWidth: 110)
                    .contentTransition(.numericText())
                roundButton("plus", label: "\(title) erhöhen", action: plus)
            }
        }
    }

    private func roundButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.title2.weight(.bold))
                .frame(width: TouchTarget.gym + 8, height: TouchTarget.gym + 8)
                .background(ModuleAccent.training.opacity(0.15), in: Circle())
                .foregroundStyle(ModuleAccent.training)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Zusammenfassung

struct SessionSummaryView: View {
    let summary: SessionSummary
    let title: String
    let onDone: () -> Void

    @Environment(\.modelContext) private var context

    var body: some View {
        let catalog = TrainingActions.catalog(in: context)
        ScrollView {
            VStack(spacing: Spacing.l) {
                Image(systemName: summary.records.isEmpty ? "checkmark.seal.fill" : "trophy.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(summary.records.isEmpty ? Color.green : Color.orange)
                    .padding(.top, Spacing.l)
                VStack(spacing: Spacing.xxs) {
                    Text(summary.records.isEmpty ? "Stark gemacht!" : "Neue Rekorde!")
                        .font(.title.weight(.bold))
                    Text(title)
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: Spacing.s) {
                    StatTile(title: "Dauer", value: summary.durationLabel)
                    StatTile(title: "Sätze", value: "\(summary.workingSets)")
                    StatTile(
                        title: "Volumen", value: summary.volume > 0 ? summary.volumeLabel : "–",
                        detail: summary.volume > 0 ? nil : "nur Körpergewicht"
                    )
                    if summary.volumeChange != nil {
                        StatTile(title: "Vergleich", value: changeText, detail: "zur letzten gleichen Einheit")
                    }
                }
                if !summary.records.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            SectionHeader("Rekorde", systemImage: "trophy", tint: .orange)
                            ForEach(summary.records) { record in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(catalog.name(for: record.exerciseID))
                                        .font(.subheadline.weight(.semibold))
                                    Text(record.label)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Button(action: onDone) {
                    Text("Fertig")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: TouchTarget.gym)
                }
                .buttonStyle(.borderedProminent)
                .tint(ModuleAccent.training)
                .accessibilityIdentifier("summary.done")
            }
            .padding(Spacing.m)
        }
        .navigationTitle("Zusammenfassung")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var changeText: String {
        guard let change = summary.volumeChange else { return "–" }
        let percent = Int((change * 100).rounded())
        return percent >= 0 ? "+\(percent) %" : "\(percent) %"
    }
}
