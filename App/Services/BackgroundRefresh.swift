import BackgroundTasks
import Foundation
import TagwerkKit

/// Hintergrundaktualisierung, damit Medikamenten-Erinnerungen weiterlaufen, auch wenn
/// die App ein paar Tage nicht geöffnet wird (Mitteilungen werden nur 72 Std. im Voraus geplant).
enum BackgroundRefresh {
    static let identifier = "de.tagwerk.app.refresh"

    /// Bittet iOS um eine Aktualisierung in frühestens 4 Stunden. iOS entscheidet selbst, wann.
    static func schedule() {
        guard !AppInfo.isUITesting else { return }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date.now.addingTimeInterval(4 * 3_600)
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor
    static func run() async {
        await AppModel.shared.backgroundRefresh()
    }
}
