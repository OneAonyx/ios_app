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
    /// Medikament, dessen Editor gerade offen ist (`isAddingMedication` für ein neues).
    var editingMedication: Medication?
    var isAddingMedication = false
    /// Navigation im Tab „Gesundheit“ (Medikament-IDs).
    var healthPath: [String] = []

    @ObservationIgnored private var refreshTask: Task<Void, Never>?

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

        // Einnahmen aus Widget, Kontrollzentrum, Wecker und Mitteilung direkt verarbeiten.
        DoseActionCenter.handler = { action in
            await AppModel.shared.handleDoseAction(action)
        }
        DoseActionCenter.refreshSnapshot = {
            AppModel.shared.writeMedicationSnapshot()
        }
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

    func openMedications() {
        isShowingSearch = false
        isShowingQuickAdd = false
        isShowingSettings = false
        editingTask = nil
        selectedTab = .health
    }

    /// `tagwerk://claude/…` (Rücksprung aus Kurzbefehle), `tagwerk://systemcheck`, `tagwerk://neu`,
    /// `tagwerk://gesundheit` (aus dem Medikamenten-Widget).
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
        case "gesundheit", "medikamente", "health":
            openMedications()
        default:
            break
        }
    }

    // MARK: Hintergrundarbeiten

    /// Nach jeder Änderung an Aufgaben: Erinnerungen neu planen (gebündelt).
    func tasksChanged() {
        scheduleRefresh()
    }

    /// Nach jeder Änderung an Medikamenten oder Einnahmen: Widgets, Erinnerungen, Wecker.
    func medicationsChanged() {
        writeMedicationSnapshot()
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let self, !Task.isCancelled else { return }
            await self.refreshNow()
        }
    }

    /// Plant alles neu: Nachschub-Aufgaben, Widget-Daten, Wecker, Mitteilungen.
    func refreshNow() async {
        let now = Date.now
        let calendar = Self.calendar
        if storeError == nil {
            MedicationActions.ensureRefillTasks(in: context, now: now, calendar: calendar)
        }
        writeMedicationSnapshot(now: now)
        let alarmsActive = AlarmProbe.isAuthorized && !AppInfo.isUITesting
        if alarmsActive {
            await MedicationAlarmScheduler.reschedule(medications: MedicationActions.fetchAll(in: context), now: now, calendar: calendar)
        }
        await ReminderScheduler.reschedule(context: context, now: now, calendar: calendar, alarmsActive: alarmsActive)
    }

    func writeMedicationSnapshot(now: Date = .now) {
        guard !AppInfo.isUITesting else { return }
        MedicationSnapshotWriter.write(context: context, now: now, calendar: Self.calendar)
    }

    /// Einnahme von außerhalb (Widget, Kontrollzentrum, Wecker, Mitteilung, Siri).
    func handleDoseAction(_ action: PendingDoseAction) async {
        MedicationActions.record(
            doseID: action.doseID,
            status: action.kind == .taken ? .taken : .skipped,
            at: action.at,
            in: context,
            calendar: Self.calendar
        )
        MedicationNotifications.removeNotifications(forDose: action.doseID)
        MedicationAlarmScheduler.cancel(doseID: action.doseID)
        // Sofort, nicht gebündelt: Bei einem Hintergrundstart bleibt nur wenig Zeit.
        refreshTask?.cancel()
        await refreshNow()
    }

    /// Beim Öffnen der App: Abgehaktes aus Widgets übernehmen, Kalenderrechte prüfen,
    /// alles neu planen, täglich sichern.
    func appBecameActive() {
        if storeError == nil {
            let processed = MedicationActions.processPendingActions(in: context, calendar: Self.calendar)
            if processed > 0 {
                writeMedicationSnapshot()
            }
        }
        calendarService.refreshAccess()
        scheduleRefresh()
        if storeError == nil, !AppInfo.isUITesting {
            BackupService.autoBackupIfNeeded(context: context, calendar: Self.calendar)
        }
        systemCheck.refreshOnActivate()
        BackgroundRefresh.schedule()
    }

    /// Hintergrundaktualisierung: hält Mitteilungen und Wecker auch ohne Öffnen der App aktuell.
    func backgroundRefresh() async {
        if storeError == nil {
            MedicationActions.processPendingActions(in: context, calendar: Self.calendar)
        }
        await refreshNow()
        BackgroundRefresh.schedule()
    }
}
