import SwiftUI
import TagwerkKit

@main
struct TagwerkApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if LaunchOptions.selfTest {
                    SelfTestView()
                } else {
                    RootView()
                }
            }
            .environment(model)
            .environment(model.calendarService)
            .modelContainer(model.container)
            .preferredColorScheme(LaunchOptions.forcedColorScheme)
            .onOpenURL { url in
                model.handle(url: url)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.appBecameActive()
            }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await BackgroundRefresh.run()
        }
    }
}

/// Startoptionen für die UI-Tests im CI (Screenshots in hell und dunkel).
enum LaunchOptions {
    static var forcedColorScheme: ColorScheme? {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-forceDark") { return .dark }
        if arguments.contains("-forceLight") { return .light }
        return nil
    }

    /// Onboarding im UI-Test gezielt zeigen.
    static var showOnboarding: Bool {
        ProcessInfo.processInfo.arguments.contains("-showOnboarding")
    }

    /// Selbsttest statt der normalen Oberfläche (nur UI-Tests im CI).
    static var selfTest: Bool {
        ProcessInfo.processInfo.arguments.contains("-selfTest")
    }
}
