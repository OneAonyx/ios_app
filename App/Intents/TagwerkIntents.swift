import AppIntents
import SwiftData
import TagwerkCore
import TagwerkKit

/// „Neue Aufgabe in Orbit“ – Datum und Uhrzeit im Text werden erkannt.
struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Aufgabe hinzufügen"
    static let description = IntentDescription(
        "Legt eine Aufgabe in Orbit an. Datum und Uhrzeit im Text werden erkannt, z. B. „morgen 10 Uhr Zahnarzt“."
    )
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Aufgabe", requestValueDialog: "Was soll ich eintragen?")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        let entry = QuickEntryParser(calendar: AppModel.calendar).parse(text, now: .now)
        guard !entry.title.isEmpty else {
            return .result(dialog: IntentDialog(stringLiteral: "Ich habe keinen Titel erkannt."))
        }
        let offset = UserDefaults.standard.object(forKey: SettingsKeys.defaultReminderOffset) as? Int ?? 0
        let task = TaskActions.create(
            from: entry,
            presetList: nil,
            defaultReminderOffset: offset >= 0 ? offset : nil,
            in: model.context
        )
        model.tasksChanged()
        var message = "„\(task.title)“ ist eingetragen"
        if let due = task.dueDate {
            message += " für " + DueFormatter.label(due: due, hasTime: task.hasDueTime, now: .now, calendar: AppModel.calendar)
        }
        return .result(dialog: IntentDialog(stringLiteral: message + "."))
    }
}

/// „Was steht heute an?“ – liest offene Aufgaben für heute vor.
struct TodaySummaryIntent: AppIntent {
    static let title: LocalizedStringResource = "Was steht heute an?"
    static let description = IntentDescription("Nennt die offenen Aufgaben für heute, zuerst die im Fokus.")
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date.now
        let calendar = AppModel.calendar
        let tasks = ((try? AppModel.shared.context.fetch(FetchDescriptor<TaskItem>())) ?? []).filter { !$0.isDone }
        let today = TaskOrdering.sorted(
            tasks.filter { SmartList.today.includes($0.facts, now: now, calendar: calendar) },
            facts: \.facts, now: now, calendar: calendar
        )
        let focus = today.filter { $0.facts.isFocus(on: now, calendar: calendar) }
        let ordered = focus + today.filter { !$0.facts.isFocus(on: now, calendar: calendar) }

        let message: String
        switch ordered.count {
        case 0:
            message = "Für heute ist nichts mehr offen."
        case 1:
            message = "Heute steht noch eine Aufgabe an: \(ordered[0].title)."
        default:
            let names = ordered.prefix(5).map(\.title)
            let list = names.dropLast().joined(separator: ", ") + " und " + (names.last ?? "")
            let more = ordered.count > 5 ? " und \(ordered.count - 5) weitere" : ""
            message = "Heute stehen \(ordered.count) Aufgaben an: \(list)\(more)."
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

/// „Habe ich heute meine Tabletten genommen?“
struct MedicationStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Medikamente heute"
    static let description = IntentDescription("Sagt, welche Einnahmen heute erledigt und welche noch offen sind.")
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = DoseActionCenter.currentSnapshot()
        return .result(dialog: IntentDialog(stringLiteral: snapshot.statusSentence(now: .now, calendar: AppModel.calendar)))
    }
}

/// „Was trainiere ich als Nächstes?“
struct NextWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Nächstes Training"
    static let description = IntentDescription("Nennt die nächste Einheit deines Trainingsplans.")
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = TrainingActions.snapshot(in: AppModel.shared.context)
        return .result(dialog: IntentDialog(stringLiteral: snapshot.sentence(now: .now, calendar: AppModel.calendar)))
    }
}

/// „Ist Avocado histaminarm?“ – Antwort offline aus dem Lexikon, mit eigener Einschätzung.
struct CheckFoodIntent: AppIntent {
    static let title: LocalizedStringResource = "Histamin-Check"
    static let description = IntentDescription("Sagt, wie gut ein Lebensmittel bei Histaminintoleranz verträglich ist.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Lebensmittel", requestValueDialog: IntentDialog("Welches Lebensmittel?"))
    var food: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = AppModel.shared.context
        let catalog = NutritionActions.catalog(in: context)
        guard let match = catalog.bestMatch(for: food) else {
            return .result(dialog: IntentDialog(stringLiteral: "„\(food)“ steht nicht im Lexikon. Du kannst es in Orbit als eigenes Lebensmittel anlegen."))
        }
        let tolerance = NutritionActions.tolerance(for: match.id, in: context)
        return .result(dialog: IntentDialog(stringLiteral: FoodAnswer.sentence(for: match, tolerance: tolerance)))
    }
}

/// „Wie ist meine Histamin-Last heute?“
struct NutritionTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Ernährung heute"
    static let description = IntentDescription("Nennt Histamin-Tageslast, Eiweiß und Wasser von heute.")
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = NutritionActions.snapshot(calendar: AppModel.calendar, in: AppModel.shared.context)
        return .result(dialog: IntentDialog(stringLiteral: snapshot.sentence(now: .now, calendar: AppModel.calendar)))
    }
}

/// Letzte Aktion im Kurzbefehl „Orbit Claude“: übergibt Claudes Antwort an Orbit.
struct ImportClaudeResponseIntent: AppIntent {
    static let title: LocalizedStringResource = "Claude-Antwort übernehmen"
    static let description = IntentDescription(
        "Übergibt eine Antwort von Claude an Orbit. Wird im Kurzbefehl „Orbit Claude“ benutzt."
    )
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Antwort")
    var response: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        ClaudeBridgeInbox.store(response)
        return .result(dialog: "Antwort an Orbit übergeben.")
    }
}

/// Öffnet den Systemcheck, z. B. per Siri: „Orbit Systemcheck“.
struct OpenSystemCheckIntent: AppIntent {
    static let title: LocalizedStringResource = "Systemcheck öffnen"
    static let description = IntentDescription("Öffnet den Systemcheck in Orbit.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.openSystemCheck()
        return .result()
    }
}

struct TagwerkShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Neue Aufgabe in \(.applicationName)",
                "Füge eine Aufgabe zu \(.applicationName) hinzu",
                "Trag etwas in \(.applicationName) ein",
            ],
            shortTitle: "Aufgabe hinzufügen",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: TodaySummaryIntent(),
            phrases: [
                "Was steht heute in \(.applicationName) an",
                "\(.applicationName) Tagesüberblick",
            ],
            shortTitle: "Heute",
            systemImageName: "sun.max"
        )
        AppShortcut(
            intent: TakeNextDoseIntent(),
            phrases: [
                "Medikament in \(.applicationName) abhaken",
                "Tablette in \(.applicationName) genommen",
                "\(.applicationName) Medikament genommen",
            ],
            shortTitle: "Medikament genommen",
            systemImageName: "pills.fill"
        )
        AppShortcut(
            intent: MedicationStatusIntent(),
            phrases: [
                "Habe ich heute meine Tabletten in \(.applicationName) genommen",
                "\(.applicationName) Medikamente heute",
            ],
            shortTitle: "Medikamente heute",
            systemImageName: "pills"
        )
        AppShortcut(
            intent: StartWorkoutIntent(),
            phrases: [
                "Starte mein Training in \(.applicationName)",
                "\(.applicationName) Training starten",
            ],
            shortTitle: "Training starten",
            systemImageName: "figure.strengthtraining.traditional"
        )
        AppShortcut(
            intent: NextWorkoutIntent(),
            phrases: [
                "Was trainiere ich als Nächstes in \(.applicationName)",
                "\(.applicationName) nächstes Training",
            ],
            shortTitle: "Nächstes Training",
            systemImageName: "dumbbell"
        )
        AppShortcut(
            intent: AddWaterIntent(),
            phrases: [
                "Wasser trinken in \(.applicationName)",
                "\(.applicationName) Glas Wasser",
                "Trag ein Glas Wasser in \(.applicationName) ein",
            ],
            shortTitle: "Wasser trinken",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: LogSymptomIntent(),
            phrases: [
                "Symptom in \(.applicationName) erfassen",
                "Beschwerden in \(.applicationName) eintragen",
                "\(.applicationName) Symptom erfassen",
            ],
            shortTitle: "Beschwerden eintragen",
            systemImageName: "waveform.path.ecg"
        )
        AppShortcut(
            intent: CheckFoodIntent(),
            phrases: [
                "Histamin-Check in \(.applicationName)",
                "Ist das histaminarm in \(.applicationName)",
                "\(.applicationName) Histamin-Check",
            ],
            shortTitle: "Histamin-Check",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: OpenSystemCheckIntent(),
            phrases: [
                "Öffne den Systemcheck in \(.applicationName)",
                "\(.applicationName) Systemcheck",
            ],
            shortTitle: "Systemcheck",
            systemImageName: "checkmark.seal"
        )
    }
}
