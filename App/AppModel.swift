import Foundation
import Observation
import SwiftData
import TagwerkCore
import TagwerkKit
import UIKit

/// Wochenrückblick im eigenen Blatt.
struct ReviewLink: Identifiable, Hashable {
    let weekStart: Date
    var id: Date { weekStart }
}

/// Claude-Anfrage im eigenen Blatt (stableID).
struct ExchangeLink: Identifiable, Hashable {
    let id: String
}

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
    /// Laufende Trainingseinheit: Pause, Live Activity.
    let workout = WorkoutRunner()
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
    /// Trainingseinheit im Vollbild.
    var isShowingWorkout = false
    /// Neue Mahlzeit (vorbelegt) bzw. Mahlzeit im Editor.
    var mealDraft: MealDraft?
    var editingMeal: MealEntry?
    /// Beschwerden eintragen.
    var isAddingSymptom = false
    /// Einblicke: Check-in, Wochenrückblick, Claude-Zentrale und eine Claude-Anfrage im eigenen Blatt.
    var isShowingCheckIn = false
    var presentedReview: ReviewLink?
    var isShowingClaudeHub = false
    var presentedExchange: ExchangeLink?
    /// Claude-Anfrage, die gerade auf dem Bildschirm ist (dann kein zweites Blatt öffnen).
    @ObservationIgnored var visibleExchangeID: String?

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
        // Training: Knöpfe der Live Activity, „Training starten“ aus Siri und Kontrollzentrum.
        WorkoutActionCenter.handler = { command in
            AppModel.shared.handleWorkoutCommand(command)
        }
        WorkoutActionCenter.startHandler = {
            AppModel.shared.startWorkout()
        }
        // Ernährung: Wasser aus Widget, Kontrollzentrum und Siri, „Symptom erfassen“.
        NutritionActionCenter.handler = { milliliters in
            AppModel.shared.addWater(milliliters)
        }
        NutritionActionCenter.symptomHandler = {
            AppModel.shared.openSymptomEntry()
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
    /// `tagwerk://gesundheit` (Medikamenten-Widget), `tagwerk://training`, `tagwerk://ernaehrung`,
    /// `tagwerk://mahlzeit`, `tagwerk://wasser`, `tagwerk://symptom`.
    func handle(url: URL) {
        if let callback = ClaudeCallback.parse(url) {
            if let id = callback.requestID, let exchange = InsightsActions.exchange(stableID: id, in: context) {
                handleClaudeCallback(callback, exchange: exchange)
            } else {
                openSystemCheck()
                systemCheck.handleClaudeCallback(callback)
            }
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
        case "training":
            if url.path == "/start" {
                startWorkout()
            } else {
                openTraining()
            }
        case "ernaehrung", "nutrition":
            openNutrition()
        case "mahlzeit", "meal":
            openNutrition()
            logMeal()
        case "wasser", "water":
            addWater(NutritionTargets.glassML)
            openNutrition()
        case "symptom":
            openSymptomEntry()
        case "checkin":
            openCheckIn()
        case "rueckblick", "review":
            openReview(weekStart: nil)
        case "claude":
            openClaudeHub()
        default:
            break
        }
    }

    // MARK: Hintergrundarbeiten

    /// Nach jeder Änderung an Aufgaben: Erinnerungen neu planen (gebündelt).
    func tasksChanged() {
        scheduleRefresh()
    }

    /// Nach Änderungen am Training: Widget-Daten und Erinnerungen an Trainingstage.
    func trainingChanged() {
        writeTrainingSnapshot()
        scheduleRefresh()
    }

    func writeTrainingSnapshot(now: Date = .now) {
        guard !AppInfo.isUITesting else { return }
        TrainingSnapshotWriter.write(context: context, now: now)
    }

    /// Nach Änderungen an Mahlzeiten, Wasser oder Beschwerden: Widget-Daten.
    func nutritionChanged() {
        writeNutritionSnapshot()
    }

    func writeNutritionSnapshot(now: Date = .now) {
        guard !AppInfo.isUITesting else { return }
        NutritionSnapshotWriter.write(context: context, now: now, calendar: Self.calendar)
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
        writeTrainingSnapshot(now: now)
        writeNutritionSnapshot(now: now)
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
        if storeError == nil, !AppInfo.isUITesting {
            TrainingActions.ensureStarterPlan(in: context)
        }
        for command in WorkoutActionCenter.takeQueued() {
            handleWorkoutCommand(command)
        }
        if WorkoutActionCenter.takePendingStart() {
            startWorkout()
        }
        if let session = TrainingActions.activeSession(in: context) {
            workout.updateActivity(session: session, catalog: TrainingActions.catalog(in: context))
        }
        if storeError == nil, NutritionActions.processPendingWater(in: context) > 0 {
            writeNutritionSnapshot()
        }
        if NutritionActionCenter.takePendingSymptomEntry() {
            openSymptomEntry()
        }
        deliverClaudeInbox()
    }

    // MARK: Einblicke

    func openCheckIn() {
        dismissPanels()
        isShowingCheckIn = true
    }

    /// Wochenrückblick öffnen, ohne Angabe für die laufende Woche.
    func openReview(weekStart: Date?) {
        dismissPanels()
        let start = weekStart ?? AgendaBuilder.startOfWeek(containing: .now, calendar: Self.calendar)
        presentedReview = ReviewLink(weekStart: start)
    }

    func openClaudeHub() {
        dismissPanels()
        isShowingClaudeHub = true
    }

    private func dismissPanels() {
        isShowingSearch = false
        isShowingQuickAdd = false
        isShowingSettings = false
        editingTask = nil
    }

    /// Anfrage über den Kurzbefehl „Orbit Claude“ abschicken. Lange Anfragen gehen über die
    /// Zwischenablage, weil sehr lange Links nicht zuverlässig ankommen.
    @discardableResult
    func sendToClaude(_ exchange: ClaudeExchange) async -> Bool {
        _ = ClaudeBridgeInbox.take()
        let input: ShortcutRunRequest.Input
        if exchange.prompt.count <= Self.maxLinkPromptLength {
            input = .text(exchange.prompt)
        } else {
            UIPasteboard.general.string = exchange.prompt
            input = .clipboard
        }
        InsightsActions.markSent(exchange, in: context)
        let request = ShortcutRunRequest(input: input, requestID: exchange.stableID)
        let opened = await UIApplication.shared.open(request.url())
        if !opened {
            InsightsActions.setStatus(.failed, of: exchange, in: context)
        }
        return opened
    }

    static let maxLinkPromptLength = 8_000

    /// Rücksprung aus der Kurzbefehle-App für eine Claude-Anfrage.
    private func handleClaudeCallback(_ callback: ClaudeCallback, exchange: ClaudeExchange) {
        switch callback.outcome {
        case .success:
            let inbox = ClaudeBridgeInbox.take()
            if let result = callback.result?.trimmingCharacters(in: .whitespacesAndNewlines), !result.isEmpty {
                InsightsActions.attach(result, to: exchange, in: context)
            } else if let inbox {
                InsightsActions.attach(inbox, to: exchange, in: context)
            }
        case .cancel:
            if exchange.response.isEmpty { InsightsActions.setStatus(.draft, of: exchange, in: context) }
        case .error:
            if exchange.response.isEmpty { InsightsActions.setStatus(.failed, of: exchange, in: context) }
        }
        present(exchange)
    }

    /// Antwort aus dem Briefkasten (Aktion „Claude-Antwort übernehmen“) zustellen:
    /// an die Anfrage mit passender Kennung, sonst an den wartenden Systemcheck, sonst an die
    /// zuletzt abgeschickte Anfrage.
    private func deliverClaudeInbox() {
        guard let response = ClaudeBridgeInbox.take() else { return }
        if let ref = ClaudeAnswerParser.ref(in: response), let exchange = InsightsActions.exchange(ref: ref, in: context) {
            InsightsActions.attach(response, to: exchange, in: context)
            present(exchange)
        } else if systemCheck.isWaitingForClaude {
            systemCheck.receiveClaude(response)
        } else if let exchange = ClaudeBridgeActions.receive(response, in: context) {
            present(exchange)
        }
    }

    private func present(_ exchange: ClaudeExchange) {
        guard visibleExchangeID != exchange.stableID else { return }
        dismissPanels()
        presentedExchange = ExchangeLink(id: exchange.stableID)
    }

    // MARK: Ernährung

    func openNutrition() {
        isShowingSearch = false
        isShowingQuickAdd = false
        isShowingSettings = false
        editingTask = nil
        selectedTab = .nutrition
    }

    /// Mahlzeit-Editor öffnen, optional mit Rezept (eine Portion) oder Lebensmitteln vorbelegt.
    func logMeal(type: MealType? = nil, date: Date = .now, recipe: RecipeInfo? = nil, items: [MealDraftItem] = []) {
        let calendar = Self.calendar
        var draftItems = items
        if let recipe {
            draftItems += recipe.mealItems(portions: 1).map { MealDraftItem(foodID: $0.foodID, grams: $0.grams) }
        }
        mealDraft = MealDraft(
            type: type ?? MealType.suggested(for: date, calendar: calendar),
            date: date,
            items: draftItems,
            recipeID: recipe?.id
        )
    }

    func addWater(_ milliliters: Int) {
        NutritionActions.addWater(milliliters, in: context)
        nutritionChanged()
    }

    func openSymptomEntry() {
        isShowingSearch = false
        isShowingQuickAdd = false
        isShowingSettings = false
        isAddingSymptom = true
    }

    // MARK: Training

    func openTraining() {
        isShowingSearch = false
        isShowingQuickAdd = false
        isShowingSettings = false
        editingTask = nil
        selectedTab = .training
    }

    /// Startet die nächste (oder gewählte) Einheit. Läuft schon eine, wird sie gezeigt.
    func startWorkout(day: PlanDay? = nil, includeModule: Bool? = nil) {
        openTraining()
        if TrainingActions.activeSession(in: context) != nil {
            isShowingWorkout = true
            return
        }
        guard let plan = TrainingActions.ensureStarterPlan(in: context), let chosen = day ?? plan.nextDay else { return }
        let dayIndex = plan.rotationDays.firstIndex { $0.stableID == chosen.stableID } ?? -1
        let catalog = TrainingActions.catalog(in: context)
        let session = TrainingActions.startSession(
            plan: plan, day: chosen, includeModule: includeModule ?? (plan.moduleDayIndex == dayIndex),
            catalog: catalog, in: context
        )
        workout.updateActivity(session: session, catalog: catalog)
        isShowingWorkout = true
        trainingChanged()
    }

    /// Satz abhaken und die passende Pause starten.
    func completeSet(_ set: SetLog, weight: Double, reps: Int, rir: Int?) {
        guard let session = set.session else { return }
        let catalog = TrainingActions.catalog(in: context)
        TrainingActions.complete(set, weight: weight, reps: reps, rir: rir, in: context)
        let next = TrainingActions.next(after: set, in: session)
        workout.focusSlot = next.set?.slot
        if next.set != nil, next.restSeconds > 0 {
            workout.startRest(seconds: next.restSeconds, session: session, catalog: catalog)
        } else {
            workout.skipRest(session: session, catalog: catalog)
        }
    }

    /// Einheit abschließen. Gibt die Zusammenfassung zurück.
    func finishWorkout(_ session: WorkoutSession) -> SessionSummary {
        let summary = TrainingActions.finish(session, catalog: TrainingActions.catalog(in: context), in: context)
        workout.endActivity()
        trainingChanged()
        return summary
    }

    func discardWorkout(_ session: WorkoutSession) {
        TrainingActions.discard(session, in: context)
        workout.endActivity()
        isShowingWorkout = false
        trainingChanged()
    }

    /// Knöpfe der Live Activity.
    func handleWorkoutCommand(_ command: WorkoutCommand) {
        guard let session = TrainingActions.activeSession(in: context) else {
            workout.endActivity()
            return
        }
        let catalog = TrainingActions.catalog(in: context)
        switch command {
        case .addRest:
            workout.addRest(30, session: session, catalog: catalog)
        case .skipRest:
            workout.skipRest(session: session, catalog: catalog)
        case .completeSet:
            if let set = TrainingActions.nextPendingSet(in: session) {
                completeSet(set, weight: set.weight, reps: set.reps, rir: set.rir ?? set.targetRIR)
            }
        }
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
