import Foundation
import Observation
import TagwerkCore
import TagwerkKit

/// Zentraler Zustand der App: Navigation und die Phase-0-Tests.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    var selectedTab: TagwerkModule = .today
    var isShowingSettings = false
    var isShowingSearch = false
    var isShowingSystemCheck = false

    let systemCheck = SystemCheckModel()

    private init() {}

    func openSystemCheck() {
        isShowingSettings = false
        isShowingSearch = false
        selectedTab = .today
        isShowingSystemCheck = true
    }

    /// `tagwerk://claude/…` (Rücksprung aus Kurzbefehle) und `tagwerk://systemcheck`.
    func handle(url: URL) {
        if let callback = ClaudeCallback.parse(url) {
            openSystemCheck()
            systemCheck.handleClaudeCallback(callback)
        } else if url.scheme?.lowercased() == TagwerkIDs.urlScheme, url.host == "systemcheck" {
            openSystemCheck()
        }
    }
}
