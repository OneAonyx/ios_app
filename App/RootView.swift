import SwiftUI
import TagwerkCore
import TagwerkKit

struct RootView: View {
    @Environment(AppModel.self) private var app
    @AppStorage(SettingsKeys.onboardingDone) private var onboardingDone = false

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
                PlaceholderTab(module: .training)
            }
            Tab(TagwerkModule.nutrition.title, systemImage: TagwerkModule.nutrition.systemImage, value: TagwerkModule.nutrition) {
                PlaceholderTab(module: .nutrition)
            }
            Tab(TagwerkModule.health.title, systemImage: TagwerkModule.health.systemImage, value: TagwerkModule.health) {
                PlaceholderTab(module: .health)
            }
            // Keine eigene Such-Tab: Beim iPhone passen nur 5 Einträge in die Leiste,
            // ein sechster landet unter „Mehr“. Die Suche sitzt als Lupe auf „Heute“.
        }
        .tabBarMinimizeBehavior(.onScrollDown)
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
