import Foundation
import Observation
import SwiftData
import TagwerkCore
import TagwerkKit

/// Zentraler Zustand der App: Datenspeicher, Kalender, Navigation und Systemcheck.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    /// Deutscher Kalender (Woche ab Montag) für alle Datumsberechnungen der App.
    nonisolated static let calendar = GermanCalendar.make()

    let container: ModelContainer
    let calendarService = CalendarService()
    let systemCheck = SystemCheckModel()
    /// Gesetzt, wenn der Speicher nicht geöffnet werden konnte (Daten dann nur im Arbeitsspeicher).
    let storeError: String?

    var selectedTab: TagwerkModule = .today
    var isShowingSettings = false
    var isShowingSearch = false
    var isShowingSystemCheck = false
    var isShowingQuickAdd = false
    /// Vorbelegte Liste für die Schnellerfassung (z. B. aus einer Listenansicht).
    var quickAddList: TaskList?
    /// Aufgabe, deren Editor gerade offen ist.
    var editingTask: TaskItem?

    @ObservationIgnored private var reminderTask: Task<Void, Never>?

    private init() {
        var error: String?
        let container: ModelContainer
        if AppInfo.isUITesting {
            container = Self.makeFallbackContainer()
            DemoData.seed(into: container.mainContext, now: .now, calendar: Self.calendar)
        } else {
            do {
                container = try TagwerkStore.makeContainer()
            } catch let failure {
                error = "Der Speicher konnte nicht geöffnet werden (\(failure.localizedDescription)). Änderungen werden nicht gesichert."
                container = Self.makeFallbackContainer()
            }
        }
        self.container = container
        self.storeError = error
    }

    private static func makeFallbackContainer() -> ModelContainer {
        // In-Memory-Speicher kann praktisch nicht fehlschlagen.
        (try? TagwerkStore.makeContainer(inMemory: true))!
    }

    var context: ModelContext { container.mainContext }

    // MARK: Navigation

    func openSystemCheck() {
        isShowingSearch = false
        isShowingQuickAdd = false
        editingTask = nil
        isShowingSettings = true
        isShowingSystemCheck = true
    }

    func openQuickAdd(list: TaskList? = nil) {
        quickAddList = list
        isShowingQuickAdd = true
    }

    /// `tagwerk://claude/…` (Rücksprung aus Kurzbefehle), `tagwerk://systemcheck`, `tagwerk://neu`.
    func handle(url: URL) {
        if let callback = ClaudeCallback.parse(url) {
            openSystemCheck()
            systemCheck.handleClaudeCallback(callback)
            return
        }
        guard url.scheme?.lowercased() == TagwerkIDs.urlScheme else { return }
        switch url.host {
        case "systemcheck":
            openSystemCheck()
        case "neu", "new":
            selectedTab = .today
            openQuickAdd()
        default:
            break
        }
    }

    // MARK: Hintergrundarbeiten

    /// Nach jeder Änderung an Aufgaben: Erinnerungen neu planen (gebündelt).
    func tasksChanged() {
        reminderTask?.cancel()
        reminderTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let self, !Task.isCancelled else { return }
            await TaskReminderScheduler.reschedule(context: self.context, calendar: Self.calendar)
        }
    }

    /// Beim Öffnen der App: Kalenderrechte prüfen, Erinnerungen planen, täglich sichern.
    func appBecameActive() {
        calendarService.refreshAccess()
        tasksChanged()
        if storeError == nil, !AppInfo.isUITesting {
            BackupService.autoBackupIfNeeded(context: context, calendar: Self.calendar)
        }
        systemCheck.refreshOnActivate()
    }
}
