import Charts
import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Statistik: Wochenvolumen je Muskel, Einheiten pro Woche, Kraftverlauf der Grundübungen.
struct TrainingStatsView: View {
    @Environment(\.modelContext) private var context
    // Für Häufigkeit (8 Wochen) und die häufigsten Grundübungen reichen die letzten 80 Einheiten.
    @Query private var sessions: [WorkoutSession]
    @State private var weekOffset = 0
    @State private var selectedLift = "bench-press-barbell"

    init() {
        var recent = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.endedAt != nil }, sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        recent.fetchLimit = 80
        _sessions = Query(recent)
    }

    var body: some View {
        let calendar = AppModel.calendar
        let catalog = TrainingActions.catalog(in: context)
        let thisMonday = AgendaBuilder.startOfWeek(containing: .now, calendar: calendar)
        let monday = calendar.date(byAdding: .day, value: 7 * weekOffset, to: thisMonday) ?? thisMonday
        let volume = TrainingActions.weeklyVolume(containing: monday, catalog: catalog, calendar: calendar, in: context)
        let lifts = compoundLifts(catalog: catalog)

        List {
            Section {
                HStack {
                    Button {
                        weekOffset -= 1
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    Text(weekTitle(monday: monday, calendar: calendar))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button {
                        weekOffset += 1
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.borderless)
                    .disabled(weekOffset >= 0)
                }
                if volume.isEmpty {
                    Text("In dieser Woche wurde nicht trainiert.")
                        .foregroundStyle(.secondary)
                } else {
                    MuscleMapView(volume: volume)
                    ForEach(volume) { item in
                        VolumeBar(volume: item)
                            .padding(.vertical, 2)
                    }
                }
            } header: {
                Text("Sätze je Muskel")
            } footer: {
                Text("Hauptmuskeln zählen ganz, mitbeteiligte halb. Grün hinterlegt ist der Zielbereich für Muskelaufbau. Auf der Karte: je kräftiger die Farbe, desto näher an der Obergrenze.")
            }

            Section("Einheiten pro Woche") {
                Chart(weeklyCounts(calendar: calendar)) { point in
                    BarMark(x: .value("Woche", point.date, unit: .weekOfYear), y: .value("Einheiten", point.value))
                        .foregroundStyle(ModuleAccent.training)
                }
                .chartYScale(domain: 0...max(5, (weeklyCounts(calendar: calendar).map(\.value).max() ?? 0) + 1))
                .frame(height: 160)
            }

            if !lifts.isEmpty {
                Section {
                    Picker("Übung", selection: $selectedLift) {
                        ForEach(lifts) { exercise in
                            Text(exercise.name).tag(exercise.id)
                        }
                    }
                    let history = TrainingActions.history(for: selectedLift, limit: 30, in: context)
                        .reversed()
                        .compactMap { performance in performance.bestEstimatedOneRepMax.map { ChartPoint(date: performance.date, value: $0) } }
                    if history.count >= 2 {
                        Chart(history) { point in
                            LineMark(x: .value("Datum", point.date), y: .value("kg", point.value))
                                .interpolationMethod(.monotone)
                                .foregroundStyle(ModuleAccent.training)
                            PointMark(x: .value("Datum", point.date), y: .value("kg", point.value))
                                .foregroundStyle(ModuleAccent.training)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 180)
                    } else {
                        Text("Nach zwei Einheiten mit dieser Übung erscheint hier der Verlauf.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    NavigationLink(value: TrainingRoute.exercise(selectedLift)) {
                        Text("Details und Rekorde")
                    }
                } header: {
                    Text("Kraftverlauf (geschätztes Maximum)")
                }
            }
        }
        .navigationTitle("Statistik")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !lifts.contains(where: { $0.id == selectedLift }), let first = lifts.first {
                selectedLift = first.id
            }
        }
    }

    /// Grundübungen aus dem Verlauf (häufigste zuerst).
    private func compoundLifts(catalog: ExerciseCatalog) -> [ExerciseInfo] {
        var counts: [String: Int] = [:]
        for session in sessions.prefix(40) {
            for id in Set(session.doneSets.map(\.exerciseID)) { counts[id, default: 0] += 1 }
        }
        return counts
            .compactMap { id, count in catalog.exercise(id: id).flatMap { $0.isCompound ? ($0, count) : nil } }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }

    private func weeklyCounts(calendar: Calendar) -> [ChartPoint] {
        let thisMonday = AgendaBuilder.startOfWeek(containing: .now, calendar: calendar)
        return (0..<8).reversed().compactMap { offset in
            guard let monday = calendar.date(byAdding: .day, value: -7 * offset, to: thisMonday),
                  let next = calendar.date(byAdding: .day, value: 7, to: monday)
            else { return nil }
            let count = sessions.filter { $0.startedAt >= monday && $0.startedAt < next }.count
            return ChartPoint(date: monday, value: Double(count))
        }
    }

    private func weekTitle(monday: Date, calendar: Calendar) -> String {
        if weekOffset == 0 { return "Diese Woche" }
        if weekOffset == -1 { return "Letzte Woche" }
        return "KW \(calendar.component(.weekOfYear, from: monday))"
    }
}

/// Alle Einheiten.
struct SessionHistoryView: View {
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt != nil }, sort: \WorkoutSession.startedAt, order: .reverse)
    private var sessions: [WorkoutSession]
    @Environment(\.modelContext) private var context

    var body: some View {
        List {
            ForEach(sessions) { session in
                NavigationLink(value: TrainingRoute.session(session.stableID)) {
                    SessionRow(session: session)
                }
            }
            .onDelete { offsets in
                for index in offsets { TrainingActions.discard(sessions[index], in: context) }
            }
        }
        .overlay {
            if sessions.isEmpty {
                ContentUnavailableView("Noch keine Einheiten", systemImage: "figure.strengthtraining.traditional")
            }
        }
        .navigationTitle("Verlauf")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Eine abgeschlossene Einheit mit allen Sätzen.
struct SessionDetailView: View {
    let session: WorkoutSession
    @Environment(\.modelContext) private var context

    var body: some View {
        let catalog = TrainingActions.catalog(in: context)
        let working = session.doneSets.filter { $0.kind != .warmup }
        let summary = SessionSummary.make(start: session.startedAt, end: session.endedAt ?? .now, sets: working.map(\.logged), records: [], previousVolume: nil)
        List {
            Section {
                HStack {
                    StatTile(title: "Dauer", value: summary.durationLabel)
                    StatTile(title: "Sätze", value: "\(summary.workingSets)")
                    StatTile(title: "Volumen", value: summary.volumeLabel)
                }
                .listRowInsets(EdgeInsets(top: Spacing.xs, leading: Spacing.s, bottom: Spacing.xs, trailing: Spacing.s))
            } footer: {
                Text("\(session.startedAt.trainingDayLabel()) · \(session.isDeload ? "Deload-Woche" : "Woche \(session.week)")")
            }
            ForEach(session.slots, id: \.self) { slot in
                let sets = session.sets(inSlot: slot).filter(\.isDone)
                if let first = sets.first {
                    Section(catalog.name(for: first.exerciseID)) {
                        ForEach(sets) { set in
                            HStack {
                                Text(set.kind == .warmup ? "Aufwärmen" : (set.kind == .drop ? "Drop-Satz" : "Satz \(set.setIndex + 1)"))
                                    .foregroundStyle(set.kind == .working ? Color.primary : Color.secondary)
                                Spacer()
                                Text("\(WeightFormat.number(set.weight)) kg × \(set.reps)\(set.rir.map { " · RIR \($0)" } ?? "")")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
        }
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Körpergewicht und Maße mit Verlauf.
struct BodyView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyMetric.date, order: .reverse) private var metrics: [BodyMetric]
    @State private var adding = false
    @State private var selectedType: BodyMetricType = .weight

    var body: some View {
        let ofType = metrics.filter { $0.type == selectedType }
        let latest = Dictionary(grouping: metrics, by: \.type).compactMapValues(\.first)
        let bmi = latest[.weight].flatMap { weight in latest[.height].flatMap { BodyIndex.bmi(weight: weight.value, heightCM: $0.value) } }
        let weightTrend = ProgressAssessment.bodyweight(
            metrics.filter { $0.type == .weight }.map { (date: $0.date, value: $0.value) }, now: .now
        )
        List {
            Section {
                if let bmi {
                    LabeledContent("BMI", value: BodyIndex.format(bmi))
                } else if latest[.height] == nil {
                    Button {
                        selectedType = .height
                        adding = true
                    } label: {
                        Label("Größe eintragen", systemImage: "figure.stand")
                    }
                    .accessibilityIdentifier("body.addHeight")
                }
                if let weightTrend {
                    BodyweightTrendRow(trend: weightTrend)
                }
                NavigationLink(value: TrainingRoute.photos) {
                    Label("Fortschrittsfotos", systemImage: "person.crop.rectangle.stack")
                }
                .accessibilityIdentifier("body.photos")
                NavigationLink(value: TrainingRoute.progress) {
                    Label("Fortschritt aller Übungen", systemImage: "chart.line.uptrend.xyaxis")
                }
            } footer: {
                if bmi != nil {
                    Text("Der BMI unterscheidet nicht zwischen Muskeln und Fett. Bei viel Muskelmasse ist er wenig aussagekräftig.")
                }
            }
            Section {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.xs) {
                    ForEach(BodyMetricType.allCases) { type in
                        Button {
                            selectedType = type
                        } label: {
                            StatTile(
                                title: type.title,
                                value: latest[type].map { type.label($0.value) } ?? "–",
                                detail: latest[type].map { $0.date.trainingDayLabel() },
                                tint: type == selectedType ? ModuleAccent.training : .primary
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowInsets(EdgeInsets(top: Spacing.xs, leading: Spacing.s, bottom: Spacing.xs, trailing: Spacing.s))
            }
            Section(selectedType.title) {
                let points = ofType.reversed().map { ChartPoint(date: $0.date, value: $0.value) }
                if points.count >= 2 {
                    Chart(points) { point in
                        LineMark(x: .value("Datum", point.date), y: .value(selectedType.unit, point.value))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(ModuleAccent.training)
                        PointMark(x: .value("Datum", point.date), y: .value(selectedType.unit, point.value))
                            .foregroundStyle(ModuleAccent.training)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 180)
                }
                if ofType.isEmpty {
                    Text("Noch keine Einträge.")
                        .foregroundStyle(.secondary)
                }
                ForEach(ofType) { metric in
                    HStack {
                        Text(metric.date.trainingDayLabel())
                        Spacer()
                        Text(metric.type.label(metric.value))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    for index in offsets { TrainingActions.delete(ofType[index], in: context) }
                }
            }
        }
        .navigationTitle("Körper")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    adding = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Eintrag hinzufügen")
            }
        }
        .sheet(isPresented: $adding) {
            BodyMetricEditor(type: selectedType, last: latest[selectedType]?.value)
        }
    }
}

private struct BodyMetricEditor: View {
    let type: BodyMetricType
    let last: Double?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var selected: BodyMetricType = .weight
    @State private var value: Double = 80
    @State private var date: Date = .now
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Art", selection: $selected) {
                    ForEach(BodyMetricType.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                HStack {
                    Text("Wert")
                    Spacer()
                    TextField("Wert", value: $value, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(maxWidth: 90)
                        .accessibilityIdentifier("body.value")
                    Text(selected.unit)
                        .foregroundStyle(.secondary)
                }
                Stepper("Feiner einstellen", value: $value, in: 0...400, step: selected.step)
                DatePicker("Datum", selection: $date, in: ...Date.now)
            }
            .navigationTitle("Neuer Eintrag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        TrainingActions.addMetric(selected, value: value, date: date, in: context)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            selected = type
            value = last ?? Self.defaultValue(type)
        }
        .onChange(of: selected) { _, newType in
            if !newType.range.contains(value) { value = Self.defaultValue(newType) }
        }
    }

    static func defaultValue(_ type: BodyMetricType) -> Double {
        switch type {
        case .weight: 80
        case .height: 180
        case .bodyFat: 15
        default: 40
        }
    }
}
