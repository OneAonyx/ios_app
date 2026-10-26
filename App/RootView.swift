import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

struct RootView: View {
    @Environment(AppModel.self) private var app
    @AppStorage(SettingsKeys.onboardingDone) private var onboardingDone = false
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt == nil }) private var activeSessions: [WorkoutSession]

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.selectedTab) {
            Tab(TagwerkModule.today.title, systemImage: TagwerkModule.today.systemImage, value: TagwerkModule.today) {
                TodayView()
            }
            Tab(TagwerkModule.planner.title, systemImage: TagwerkModule.planner.systemImage, value: TagwerkModule.planner) {
                PlannerView()
            }
            Tab(TagwerkModule.training.title, systemImage: TagwerkModule.training.systemImage, value: TagwerkModule.training) {
                TrainingView()
            }
            Tab(TagwerkModule.nutrition.title, systemImage: TagwerkModule.nutrition.systemImage, value: TagwerkModule.nutrition) {
                PlaceholderTab(module: .nutrition)
            }
            Tab(TagwerkModule.health.title, systemImage: TagwerkModule.health.systemImage, value: TagwerkModule.health) {
                HealthView()
            }
            // Keine eigene Such-Tab: Beim iPhone passen nur 5 Einträge in die Leiste,
            // ein sechster landet unter „Mehr“. Die Suche sitzt als Lupe auf „Heute“.
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .modifier(WorkoutAccessory(isActive: !activeSessions.isEmpty && !app.isShowingWorkout))
        .fullScreenCover(isPresented: $app.isShowingWorkout) {
            WorkoutSessionView()
        }
        .sheet(isPresented: $app.isShowingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $app.isShowingSearch) {
            SearchView()
        }
        .sheet(isPresented: $app.isShowingQuickAdd) {
            QuickAddView(presetList: app.quickAddList)
        }
        .sheet(item: $app.editingTask) { task in
            TaskEditorView(task: task)
        }
        .sheet(item: $app.editingMedication) { medication in
            MedicationEditorView(medication: medication)
        }
        .sheet(isPresented: $app.isAddingMedication) {
            MedicationEditorView(medication: nil)
        }
        .fullScreenCover(isPresented: onboardingBinding) {
            OnboardingView()
        }
    }

    /// Onboarding beim ersten Start. In UI-Tests nur, wenn ausdrücklich verlangt.
    private var onboardingBinding: Binding<Bool> {
        Binding(
            get: {
                if LaunchOptions.showOnboarding { return !onboardingDone }
                return !onboardingDone && !AppInfo.isUITesting
            },
            set: { isShown in
                if !isShown { onboardingDone = true }
            }
        )
    }
}

/// Mini-Player über der Tab-Leiste, solange ein Training läuft (ab iOS 26.1).
private struct WorkoutAccessory: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: isActive) {
                WorkoutMiniPlayer()
            }
        } else {
            content
        }
    }
}

/// Laufendes Training kompakt: Einheit, Zeit, Pause. Antippen öffnet die Einheit.
struct WorkoutMiniPlayer: View {
    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt == nil }, sort: \WorkoutSession.startedAt, order: .reverse)
    private var active: [WorkoutSession]

    var body: some View {
        if let session = active.first {
            Button {
                app.isShowingWorkout = true
            } label: {
                HStack(spacing: Spacing.s) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .foregroundStyle(ModuleAccent.training)
                    Text(session.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: Spacing.xs)
                    let now = Date.now
                    if let end = app.workout.restEndsAt, end > now {
                        Label {
                            Text(timerInterval: now...end, countsDown: true)
                                .monospacedDigit()
                        } icon: {
                            Image(systemName: "timer")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ModuleAccent.training)
                    } else {
                        Text(session.startedAt, style: .timer)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, Spacing.m)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Training läuft: \(session.title)")
        }
    }
}

/// Bereich, der in einer späteren Phase gebaut wird.
private struct PlaceholderTab: View {
    let module: TagwerkModule

    var body: some View {
        NavigationStack {
            ModulePlaceholderView(module: module)
                .navigationTitle(module.title)
        }
    }
}
