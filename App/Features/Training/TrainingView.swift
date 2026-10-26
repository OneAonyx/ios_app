import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Tab „Training“: nächste Einheit, Zyklus, Wochenvolumen, letzte Einheiten.
struct TrainingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutPlan.createdAt) private var plans: [WorkoutPlan]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    if let active = sessions.first(where: \.isActive) {
                        ActiveWorkoutCard(session: active)
                    }
                    if let plan = activePlan {
                        if !sessions.contains(where: \.isActive) {
                            NextWorkoutCard(plan: plan)
                        }
                        CycleCard(plan: plan)
                    } else {
                        Card {
                            VStack(alignment: .leading, spacing: Spacing.s) {
                                Text("Noch kein Trainingsplan")
                                    .font(.headline)
                                Button("Startplan anlegen") {
                                    TrainingActions.ensureStarterPlan(in: context)
                                    app.trainingChanged()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(ModuleAccent.training)
                            }
                        }
                    }
                    WeekVolumeCard(sessions: sessions)
                    RecentSessionsCard(sessions: Array(sessions.filter { !$0.isActive }.prefix(4)))
                    LinksCard()
                }
                .padding(.horizontal, Spacing.m)
                .padding(.bottom, Spacing.xl)
            }
            .background(Color.tagwerkPage)
            .navigationTitle("Training")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: TrainingRoute.self) { route in
                destination(route)
            }
        }
    }

    private var activePlan: WorkoutPlan? {
        plans.last(where: \.isActive) ?? plans.last
    }

    @ViewBuilder
    private func destination(_ route: TrainingRoute) -> some View {
        switch route {
        case .plan:
            if let plan = activePlan { PlanEditorView(plan: plan) }
        case .library:
            ExerciseLibraryView()
        case .stats:
            TrainingStatsView()
        case .body:
            BodyView()
        case .history:
            SessionHistoryView()
        case .session(let id):
            if let session = sessions.first(where: { $0.stableID == id }) { SessionDetailView(session: session) }
        case .exercise(let id):
            ExerciseDetailView(exerciseID: id)
        case .day(let id):
            if let day = activePlan?.days?.first(where: { $0.stableID == id }) { DayEditorView(day: day) }
        }
    }
}

// MARK: - Karten

private struct ActiveWorkoutCard: View {
    let session: WorkoutSession
    @Environment(AppModel.self) private var app

    var body: some View {
        let working = (session.sets ?? []).filter { $0.kind != .warmup }
        Card {
            HStack(spacing: Spacing.s) {
                IconBadge(systemImage: "figure.strengthtraining.traditional", tint: ModuleAccent.training, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Training läuft")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ModuleAccent.training)
                    Text(session.title)
                        .font(.headline)
                    HStack(spacing: Spacing.xs) {
                        Text(session.startedAt, style: .timer)
                            .monospacedDigit()
                        Text("· \(working.filter(\.isDone).count)/\(working.count) Sätze")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("Weiter") { app.isShowingWorkout = true }
                    .buttonStyle(.borderedProminent)
                    .tint(ModuleAccent.training)
                    .accessibilityIdentifier("training.resume")
            }
        }
    }
}

private struct NextWorkoutCard: View {
    let plan: WorkoutPlan

    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @State private var moduleOverride: Bool?

    var body: some View {
        let catalog = TrainingActions.catalog(in: context)
        let day = plan.nextDay
        let dayIndex = plan.nextDayIndex
        let includeModule = moduleOverride ?? (plan.moduleDayIndex == dayIndex)
        let cycle = plan.cycle
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack {
                    SectionHeader("Als Nächstes", systemImage: "arrow.forward.circle", tint: ModuleAccent.training)
                    if plan.isDeloadWeek {
                        Text("Deload")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .foregroundStyle(.green)
                            .background(Color.green.opacity(0.15), in: Capsule())
                    }
                }
                if let day {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.title)
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        Text([day.focus, "\(day.sortedExercises.filter { !$0.isOptional }.count) Übungen", "ca. \(day.estimatedMinutes(week: plan.currentWeek, cycle: cycle)) Min."]
                            .filter { !$0.isEmpty }
                            .joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(day.sortedExercises) { item in
                            HStack(alignment: .firstTextBaseline) {
                                if let superset = item.superset {
                                    Text(superset)
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(ModuleAccent.training)
                                        .frame(width: 14)
                                } else {
                                    Text("•")
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 14)
                                }
                                Text(catalog.name(for: item.exerciseID))
                                    .font(.subheadline)
                                    .foregroundStyle(item.isOptional ? Color.secondary : Color.primary)
                                Spacer(minLength: Spacing.xs)
                                Text(prescription(item, cycle: cycle))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let module = plan.module {
                        Toggle(isOn: Binding(get: { includeModule }, set: { moduleOverride = $0 })) {
                            Label("\(module.name) anhängen", systemImage: "plus.circle")
                                .font(.subheadline)
                        }
                        .tint(ModuleAccent.training)
                    }
                    Button {
                        app.startWorkout(day: day, includeModule: includeModule)
                    } label: {
                        Label("Training starten", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: TouchTarget.standard)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ModuleAccent.training)
                    .accessibilityIdentifier("training.start")
                    Menu {
                        ForEach(plan.rotationDays) { other in
                            Button(other.title) {
                                app.startWorkout(day: other, includeModule: moduleOverride ?? false)
                            }
                        }
                    } label: {
                        Label("Andere Einheit wählen", systemImage: "arrow.triangle.2.circlepath")
                            .font(.subheadline)
                    }
                } else {
                    Text("Der Plan hat noch keine Tage.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// „4 × 6–8“ (Sätze nach Zykluswoche).
    private func prescription(_ item: PlanExercise, cycle: Mesocycle) -> String {
        let sets = cycle.sets(base: item.sets, week: plan.currentWeek)
        let reps = item.repMin == item.repMax ? "\(item.repMin)" : "\(item.repMin)–\(item.repMax)"
        return "\(sets) × \(reps)"
    }
}

private struct CycleCard: View {
    let plan: WorkoutPlan
    @Environment(\.modelContext) private var context

    var body: some View {
        let cycle = plan.cycle
        let stagnating = TrainingActions.stagnatingExercises(in: plan, catalog: TrainingActions.catalog(in: context), in: context)
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader("Zyklus", systemImage: "arrow.triangle.2.circlepath", tint: ModuleAccent.training)
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cycle.label(week: plan.currentWeek))
                            .font(.headline)
                        Text(cycle.weekHint(week: plan.currentWeek))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: Spacing.s)
                }
                CycleDots(cycle: cycle, week: plan.currentWeek)
                if stagnating.count >= 2, !plan.isDeloadWeek {
                    Label("Mehrere Grundübungen stagnieren. Ein früherer Deload kann helfen (Plan → Woche).", systemImage: "leaf")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

private struct WeekVolumeCard: View {
    let sessions: [WorkoutSession]
    @Environment(\.modelContext) private var context

    var body: some View {
        let calendar = AppModel.calendar
        let start = AgendaBuilder.startOfWeek(containing: .now, calendar: calendar)
        let thisWeek = sessions.filter { !$0.isActive && $0.startedAt >= start }
        let volume = TrainingActions.weeklyVolume(containing: .now, catalog: TrainingActions.catalog(in: context), calendar: calendar, in: context)
            .filter { $0.target.lowerBound > 0 || $0.sets > 0 }
            .prefix(7)
        NavigationLink(value: TrainingRoute.stats) {
            Card {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    HStack {
                        SectionHeader("Diese Woche", systemImage: "chart.bar.fill", tint: ModuleAccent.training)
                        Text(thisWeek.count == 1 ? "1 Einheit" : "\(thisWeek.count) Einheiten")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    if thisWeek.isEmpty {
                        Text("Noch kein Training diese Woche. Die Balken zeigen dann deine Sätze je Muskel gegen den Zielbereich.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(volume)) { item in
                            VolumeBar(volume: item)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct RecentSessionsCard: View {
    let sessions: [WorkoutSession]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    SectionHeader("Letzte Einheiten", systemImage: "clock.arrow.circlepath", tint: ModuleAccent.training)
                    NavigationLink("Alle", value: TrainingRoute.history)
                        .font(.subheadline.weight(.semibold))
                }
                if sessions.isEmpty {
                    Text("Hier erscheinen deine Einheiten mit Dauer, Sätzen und Volumen.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sessions) { session in
                        NavigationLink(value: TrainingRoute.session(session.stableID)) {
                            SessionRow(session: session)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct SessionRow: View {
    let session: WorkoutSession

    var body: some View {
        let working = session.doneSets.filter { $0.kind != .warmup }
        HStack(spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.body.weight(.medium))
                Text("\(session.startedAt.trainingDayLabel()) · \(SessionSummary.make(start: session.startedAt, end: session.endedAt ?? .now, sets: [], records: [], previousVolume: nil).durationLabel) · \(working.count) Sätze")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(SessionSummary.make(start: session.startedAt, end: session.startedAt, sets: working.map(\.logged), records: [], previousVolume: nil).volumeLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct LinksCard: View {
    var body: some View {
        Card(padding: Spacing.xs) {
            VStack(spacing: 0) {
                link("Plan und Tage", "list.bullet.rectangle", .plan, id: "training.plan")
                Divider().padding(.leading, 52)
                link("Übungen", "books.vertical", .library, id: "training.library")
                Divider().padding(.leading, 52)
                link("Statistik", "chart.xyaxis.line", .stats, id: "training.stats")
                Divider().padding(.leading, 52)
                link("Körper", "figure.arms.open", .body, id: "training.body")
            }
        }
    }

    private func link(_ title: String, _ symbol: String, _ route: TrainingRoute, id: String) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: Spacing.s) {
                IconBadge(systemImage: symbol, tint: ModuleAccent.training, size: 32)
                Text(title)
                    .foregroundStyle(Color.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}
