import SwiftUI
import TagwerkKit

@main
struct TagwerkApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(LaunchOptions.forcedColorScheme)
                .onOpenURL { url in
                    model.handle(url: url)
                }
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
}
