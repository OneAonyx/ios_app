import SwiftUI
import TagwerkKit

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.selectedTab) {
            Tab(TagwerkModule.today.title, systemImage: TagwerkModule.today.systemImage, value: TagwerkModule.today) {
                TodayView()
            }
            Tab(TagwerkModule.planner.title, systemImage: TagwerkModule.planner.systemImage, value: TagwerkModule.planner) {
                PlaceholderTab(module: .planner)
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
            Tab(value: TagwerkModule.search, role: .search) {
                SearchView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(isPresented: $app.isShowingSettings) {
            SettingsView()
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
