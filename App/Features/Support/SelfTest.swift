import Foundation
import PDFKit
import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Selbsttest für den Simulator im CI (Startoption `-selfTest`): prüft, was sich unter Linux
/// nicht testen lässt – Migration der Datenbank, Medikamenten-Aktionen, Datensicherung.
/// Läuft nur mit Wegwerf-Speichern in einem temporären Ordner.
@MainActor
enum SelfTest {
    struct Result: Identifiable {
        let name: String
        let passed: Bool
        let detail: String
        var id: String { name }
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func runAll() -> [Result] {
        [
            run("Migration V1 → V8", migrationKeepsTasks),
            run("Migration V2 → V8", migrationKeepsMedications),
            run("Migration V3 → V8", migrationKeepsTraining),
            run("Migration V4 → V8", migrationKeepsNutrition),
            run("Migration V5 → V8", migrationKeepsInsights),
            run("Migration V6 → V8", migrationKeepsLife),
            run("Migration V7 → V8", migrationKeepsDiary),
            run("Training: Einheit und Progression", trainingFlow),
            run("Training: eigener Plan mit Startgewichten", ownPlanFlow),
            run("Leben: Routine, Vertrag, Geburtstag, Tagebuch", lifeFlow),
            run("Arzt-Tagebuch: Schmerz, Bewegung, Bericht", diaryFlow),
            run("Apple Health über Kurzbefehle", healthFlow),
            run("Ernährung: Tageslast, Muster, Einkauf", nutritionFlow),
            run("Einblicke: Check-in, Rückblick, Bericht", insightsFlow),
            run("Claude: Anfrage, Antwort, Übernahme", claudeFlow),
            run("Einnahmen und Vorrat", doseActionsAdjustStock),
            run("Nachschub-Aufgabe", refillTaskOnlyOnce),
            run("Datensicherung mit Medikamenten", backupRoundTrip),
            run("Datensicherung mit Training", trainingBackupRoundTrip),
            run("Datensicherung mit Ernährung", nutritionBackupRoundTrip),
            run("Datensicherung mit Einblicken", insightsBackupRoundTrip),
            run("Datensicherung mit Leben", lifeBackupRoundTrip),
            run("Datensicherung mit Arzt-Tagebuch", diaryBackupRoundTrip),
            run("Datensicherung mit Health-Werten", healthBackupRoundTrip),
            run("Widget-Daten", snapshotContainsTodayAndTomorrow),
            run("Import aus Apple Erinnerungen", reminderImportFlow),
            run("Sicherung in zweitem Ordner", externalBackupFlow),
            run("Jede Funktion im Verzeichnis führt irgendwohin", featureDirectoryRoutes),
            run("Startseite: Anordnung speichern und laden", todayLayoutStorage),
            run("Training-Coach: Vorschlag, übernehmen, später", coachFlow),
            run("Rückblick und Export: Monat, Tabellen, ZIP", reviewAndExportFlow),
            run("Tag planen: Briefing, Tag abschließen", planningFlow),
        ]
    }

    private static func run(_ name: String, _ body: () throws -> String) -> Result {
        do {
            return Result(name: name, passed: true, detail: try body())
        } catch {
            return Result(name: name, passed: false, detail: "\(error)")
        }
    }

    private static func check(_ condition: Bool, _ message: @autoclosure () -> String) throws {
        if !condition { throw Failure(description: message()) }
    }

    private static func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static var calendar: Calendar { AppModel.calendar }

    // MARK: Tests

    /// Eine Datenbank aus Version 0.2 (Schema 1) wird geöffnet, migriert und kopiert.
    private static func migrationKeepsTasks() throws -> String {
        let folder = try temporaryFolder()
        let url = folder.appendingPathComponent("Test.store")
        let defaults = UserDefaults(suiteName: "tagwerk.selftest.\(UUID().uuidString)")!

        do {
            let schemaV1 = Schema(versionedSchema: TagwerkSchemaV1.self)
            let container = try ModelContainer(for: schemaV1, configurations: [ModelConfiguration(schema: schemaV1, url: url)])
            let context = ModelContext(container)
            let list = TaskList(name: "Alt")
            context.insert(list)
            for index in 0..<3 {
                context.insert(TaskItem(title: "Aufgabe \(index)", list: list))
            }
            try context.save()
        }

        let container = try TagwerkStore.makeContainer(at: url, defaults: defaults)
        let context = ModelContext(container)
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        try check(tasks.count == 3, "Nach der Migration \(tasks.count) statt 3 Aufgaben")
        try check(tasks.allSatisfy { $0.list?.name == "Alt" }, "Liste ging verloren")
        context.insert(Medication(name: "Test"))
        try context.save()
        try check(try context.fetchCount(FetchDescriptor<Medication>()) == 1, "Medikament nicht gespeichert")
        let copy = folder.appendingPathComponent("Test-vor-v8.store")
        try check(FileManager.default.fileExists(atPath: copy.path), "Keine Kopie vor der Migration")
        try check(defaults.integer(forKey: "tagwerk.store.schemaVersion") == 8, "Schema-Version nicht gemerkt")
        return "3 Aufgaben übernommen, Kopie angelegt"
    }

    /// Eine Datenbank aus Version 0.3 (Schema 2) mit Medikamenten wird auf Schema 8 gebracht.
    private static func migrationKeepsMedications() throws -> String {
        let folder = try temporaryFolder()
        let url = folder.appendingPathComponent("Meds.store")
        let defaults = UserDefaults(suiteName: "tagwerk.selftest.\(UUID().uuidString)")!
        defaults.set(2, forKey: "tagwerk.store.schemaVersion")

        do {
            let schemaV2 = Schema(versionedSchema: TagwerkSchemaV2.self)
            let container = try ModelContainer(for: schemaV2, configurations: [ModelConfiguration(schema: schemaV2, url: url)])
            let context = ModelContext(container)
            let medication = Medication(name: "Vitamin D", schedule: .daily([DoseTime(hour: 8)]))
            medication.stock = 30
            context.insert(medication)
            let log = DoseLog(scheduledAt: .now, takenAt: .now, status: .taken, amount: 1)
            context.insert(log)
            log.medication = medication
            context.insert(TaskItem(title: "Aufgabe"))
            try context.save()
        }

        let container = try TagwerkStore.makeContainer(at: url, defaults: defaults)
        let context = ModelContext(container)
        let medications = try context.fetch(FetchDescriptor<Medication>())
        try check(medications.count == 1, "\(medications.count) statt 1 Medikament")
        try check(medications.first?.stock == 30, "Vorrat verloren")
        try check((medications.first?.logs ?? []).count == 1, "Protokoll verloren")
        try check(try context.fetchCount(FetchDescriptor<TaskItem>()) == 1, "Aufgabe verloren")
        let plan = TrainingActions.ensureStarterPlan(in: context)
        try check(plan?.rotationDays.count == 4, "Startplan nicht angelegt")
        try check(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Meds-vor-v8.store").path), "Keine Kopie vor der Migration")
        return "Medikament, Protokoll und Aufgabe übernommen, Startplan angelegt"
    }

    /// Eine Datenbank aus Version 0.4 (Schema 3) mit Training wird auf Schema 8 gebracht.
    private static func migrationKeepsTraining() throws -> String {
        let folder = try temporaryFolder()
        let url = folder.appendingPathComponent("Training.store")
        let defaults = UserDefaults(suiteName: "tagwerk.selftest.\(UUID().uuidString)")!
        defaults.set(3, forKey: "tagwerk.store.schemaVersion")

        do {
            let schemaV3 = Schema(versionedSchema: TagwerkSchemaV3.self)
            let container = try ModelContainer(for: schemaV3, configurations: [ModelConfiguration(schema: schemaV3, url: url)])
            let context = ModelContext(container)
            context.insert(WorkoutPlan(name: "Alter Plan"))
            context.insert(BodyMetric(date: .now, type: .weight, value: 81.5))
            context.insert(Medication(name: "DAO", schedule: .daily([DoseTime(hour: 12)])))
            try context.save()
        }

        let container = try TagwerkStore.makeContainer(at: url, defaults: defaults)
        let context = ModelContext(container)
        try check(try context.fetch(FetchDescriptor<WorkoutPlan>()).first?.name == "Alter Plan", "Trainingsplan verloren")
        try check(try context.fetchCount(FetchDescriptor<BodyMetric>()) == 1, "Körpergewicht verloren")
        try check(try context.fetchCount(FetchDescriptor<Medication>()) == 1, "Medikament verloren")
        NutritionActions.addMeal(type: .lunch, date: .now, items: [(foodID: "reis", grams: 70)], catalog: NutritionActions.bundledFoods, in: context)
        try check(try context.fetchCount(FetchDescriptor<MealEntry>()) == 1, "Mahlzeit nicht gespeichert")
        try check(NutritionActions.proteinTarget(in: context) == 147, "Eiweißziel aus Körpergewicht: \(NutritionActions.proteinTarget(in: context))")
        try check(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Training-vor-v8.store").path), "Keine Kopie vor der Migration")
        try check(defaults.integer(forKey: "tagwerk.store.schemaVersion") == 8, "Schema-Version nicht gemerkt")
        return "Plan, Gewicht und Medikament übernommen, Mahlzeit gespeichert"
    }

    /// Eine Datenbank aus Version 0.5 (Schema 4) mit Ernährung wird auf Schema 8 gebracht.
    private static func migrationKeepsNutrition() throws -> String {
        let folder = try temporaryFolder()
        let url = folder.appendingPathComponent("Food.store")
        let defaults = UserDefaults(suiteName: "tagwerk.selftest.\(UUID().uuidString)")!
        defaults.set(4, forKey: "tagwerk.store.schemaVersion")

        do {
            let schemaV4 = Schema(versionedSchema: TagwerkSchemaV4.self)
            let container = try ModelContainer(for: schemaV4, configurations: [ModelConfiguration(schema: schemaV4, url: url)])
            let context = ModelContext(container)
            let meal = MealEntry(date: .now, type: .lunch)
            context.insert(meal)
            let item = MealItem(foodID: "reis", name: "Reis", grams: 70, position: 0)
            context.insert(item)
            item.meal = meal
            context.insert(SymptomEntry(date: .now, type: .headache, severity: 3))
            context.insert(CustomRecipe(title: "Eigenes Rezept"))
            try context.save()
        }

        let container = try TagwerkStore.makeContainer(at: url, defaults: defaults)
        let context = ModelContext(container)
        try check(try context.fetch(FetchDescriptor<MealEntry>()).first?.sortedItems.count == 1, "Mahlzeit verloren")
        try check(try context.fetchCount(FetchDescriptor<SymptomEntry>()) == 1, "Beschwerde verloren")
        try check(try context.fetchCount(FetchDescriptor<CustomRecipe>()) == 1, "Rezept verloren")
        InsightsActions.set(.mood, 4, calendar: calendar, in: context)
        try check(try context.fetchCount(FetchDescriptor<DailyCheckIn>()) == 1, "Check-in nicht gespeichert")
        try check(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Food-vor-v8.store").path), "Keine Kopie vor der Migration")
        try check(defaults.integer(forKey: "tagwerk.store.schemaVersion") == 8, "Schema-Version nicht gemerkt")
        return "Mahlzeit, Beschwerde und Rezept übernommen, Check-in gespeichert"
    }

    /// Eine Datenbank aus Version 0.6 (Schema 5) wird auf Schema 8 gebracht. Die Einstellungen
    /// je Übung bekommen das neue Feld „Startgewicht“.
    private static func migrationKeepsInsights() throws -> String {
        let folder = try temporaryFolder()
        let url = folder.appendingPathComponent("Insights.store")
        let defaults = UserDefaults(suiteName: "tagwerk.selftest.\(UUID().uuidString)")!
        defaults.set(5, forKey: "tagwerk.store.schemaVersion")

        do {
            let schemaV5 = Schema(versionedSchema: TagwerkSchemaV5.self)
            let container = try ModelContainer(for: schemaV5, configurations: [ModelConfiguration(schema: schemaV5, url: url)])
            let context = ModelContext(container)
            let preference = TagwerkSchemaV3.ExercisePreference(exerciseID: "pec-deck")
            preference.increment = 2.5
            context.insert(preference)
            InsightsActions.set(.mood, 4, calendar: calendar, in: context)
            context.insert(TaskItem(title: "Aufgabe"))
            try context.save()
        }

        let container = try TagwerkStore.makeContainer(at: url, defaults: defaults)
        let context = ModelContext(container)
        let preferences = try context.fetch(FetchDescriptor<ExercisePreference>())
        try check(preferences.count == 1 && preferences[0].increment == 2.5, "Steigerung verloren")
        try check(preferences[0].startWeight == nil, "Startgewicht sollte leer sein")
        try check(try context.fetchCount(FetchDescriptor<DailyCheckIn>()) == 1, "Check-in verloren")
        try check(try context.fetchCount(FetchDescriptor<TaskItem>()) == 1, "Aufgabe verloren")
        LifeActions.createHabit(from: LifeTemplates.habits[0], in: context)
        try check(LifeActions.habits(in: context).count == 1, "Routine nicht gespeichert")
        TrainingActions.setStartWeight(80, for: "pec-deck", in: context)
        try check(TrainingActions.startWeight(for: "pec-deck", in: context) == 80, "Startgewicht nicht gespeichert")
        try check(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Insights-vor-v8.store").path), "Keine Kopie vor der Migration")
        try check(defaults.integer(forKey: "tagwerk.store.schemaVersion") == 8, "Schema-Version nicht gemerkt")
        return "Steigerung, Check-in und Aufgabe übernommen, Routine und Startgewicht gespeichert"
    }

    /// Eigener Plan wird einmal angelegt, die erste Einheit startet mit den bisherigen Gewichten.
    private static func ownPlanFlow() throws -> String {
        let context = ModelContext(try TagwerkStore.makeContainer(at: nil))
        let defaults = UserDefaults(suiteName: "tagwerk.selftest.\(UUID().uuidString)")!
        let catalog = TrainingActions.catalog(in: context)
        guard let plan = TrainingActions.ensureOwnPlan(in: context, defaults: defaults), let push = plan.nextDay else {
            throw Failure(description: "Eigener Plan nicht angelegt")
        }
        try check(TrainingActions.ensureOwnPlan(in: context, defaults: defaults) == nil, "Plan doppelt angelegt")
        try check(plan.rotationDays.count == 4 && plan.isActive, "Plan: \(plan.rotationDays.count) Tage")
        try check(TrainingActions.startWeight(for: "pec-deck", in: context) == 93, "Startgewicht Butterfly fehlt")
        let session = TrainingActions.startSession(plan: plan, day: push, includeModule: false, catalog: catalog, in: context)
        let working = session.sortedSets.filter { $0.kind == .working }
        let pecDeck = working.filter { $0.exerciseID == "pec-deck" }
        let chestPress = working.filter { $0.exerciseID == "chest-press-lying" }
        try check(pecDeck.count == 3 && pecDeck.first?.weight == 93, "Butterfly: \(pecDeck.count) Sätze, \(pecDeck.first?.weight ?? -1) kg")
        try check(chestPress.first?.weight == 35, "Brustpresse: \(chestPress.first?.weight ?? -1) kg statt 35")
        try check(working.allSatisfy { $0.targetRepMin == 7 && $0.targetRepMax == 10 }, "Wiederholungen nicht 7–10")
        TrainingActions.discard(session, in: context)
        TrainingActions.addMetric(.height, value: 183, in: context)
        TrainingActions.addMetric(.weight, value: 82, in: context)
        let body = TrainingActions.bodySummary(in: context)
        try check(body == "1,83 m, 82 kg", "Körper: \(body)")
        return "4 Tage, Butterfly 93 kg, Brustpresse 35 kg je Seite, Körper „\(body)“"
    }

    /// Routine abhaken, Kündigungsfrist erkennen, Geburtstag in der Agenda, Tagebuch und Top 3.
    private static func lifeFlow() throws -> String {
        let context = ModelContext(try TagwerkStore.makeContainer(at: nil))
        let now = Date.now
        let today = calendar.startOfDay(for: now)
        let routine = LifeActions.createHabit(from: LifeTemplates.habits[0], now: now, in: context)
        for step in routine.steps {
            LifeActions.toggleStep(step.id, of: routine, on: now, calendar: calendar, in: context)
        }
        try check(LifeActions.isDone(routine, on: now, calendar: calendar, in: context), "Routine nicht erledigt")
        try check(LifeActions.stats(for: routine, now: now, calendar: calendar, in: context).current == 1, "Serie nicht 1")

        let gym = LifeActions.createContract(from: LifeTemplates.contracts[0], now: now, in: context)
        gym.cost = 29.9
        gym.minimumTermMonths = 12
        gym.renewalMonths = 1
        gym.startDate = calendar.date(byAdding: .month, value: -11, to: today).flatMap { calendar.date(byAdding: .day, value: 10, to: $0) }
        guard case .dueSoon = ContractLogic.status(gym.fact, now: now, calendar: calendar) else {
            throw Failure(description: "Vertrag: \(ContractLogic.statusText(gym.fact, now: now, calendar: calendar))")
        }

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        LifeActions.addBirthday(name: "Lena", day: calendar.component(.day, from: tomorrow), month: calendar.component(.month, from: tomorrow), year: 1996, in: context)
        let end = calendar.date(byAdding: .day, value: 60, to: today) ?? today
        let items = LifeActions.agendaItems(from: today, to: end, now: now, calendar: calendar, in: context)
        try check(items.contains { $0.kind == .birthday } && items.contains { $0.kind == .deadline }, "Agenda: \(items.map(\.title))")
        let reminders = LifeActions.reminderCandidates(now: now, calendar: calendar, in: context)
        try check(reminders.contains { $0.kind == .birthday } && reminders.contains { $0.kind == .lifeDeadline }, "Erinnerungen fehlen")

        LifeActions.saveJournal(answer: "Gutes Training", text: "Notiz", on: now, calendar: calendar, in: context)
        try check(LifeActions.journal(on: now, calendar: calendar, in: context)?.answer == "Gutes Training", "Tagebuch nicht gespeichert")
        let planned = LifeActions.planTomorrow(["Einkaufen", "Steuer"], now: now, calendar: calendar, in: context)
        try check(planned.count == 2 && planned.allSatisfy { $0.facts.isFocus(on: tomorrow, calendar: calendar) }, "Top 3 nicht im Fokus von morgen")
        return "Serie 1, Frist erkannt, Geburtstag und Frist in Agenda und Erinnerungen"
    }

    /// Eine Datenbank aus Version 0.7 (Schema 6) mit Routinen wird auf Schema 8 gebracht.
    private static func migrationKeepsLife() throws -> String {
        let folder = try temporaryFolder()
        let url = folder.appendingPathComponent("Life.store")
        let defaults = UserDefaults(suiteName: "tagwerk.selftest.\(UUID().uuidString)")!
        defaults.set(6, forKey: "tagwerk.store.schemaVersion")

        do {
            let schemaV6 = Schema(versionedSchema: TagwerkSchemaV6.self)
            let container = try ModelContainer(for: schemaV6, configurations: [ModelConfiguration(schema: schemaV6, url: url)])
            let context = ModelContext(container)
            LifeActions.createHabit(from: LifeTemplates.habits[0], in: context)
            NutritionActions.addSymptom(.headache, severity: 3, date: .now, in: context)
            try context.save()
        }

        let container = try TagwerkStore.makeContainer(at: url, defaults: defaults)
        let context = ModelContext(container)
        try check(LifeActions.habits(in: context).count == 1, "Routine verloren")
        try check(try context.fetchCount(FetchDescriptor<SymptomEntry>()) == 1, "Beschwerde verloren")
        DiaryActions.addPain(PainFact(date: .now, regions: [.lowerBack], intensity: 5), in: context)
        DiaryActions.setSymptomFree(true, calendar: calendar, in: context)
        try check(try context.fetchCount(FetchDescriptor<PainEntry>()) == 1, "Schmerz nicht gespeichert")
        try check(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Life-vor-v8.store").path), "Keine Kopie vor der Migration")
        try check(defaults.integer(forKey: "tagwerk.store.schemaVersion") == 8, "Schema-Version nicht gemerkt")
        return "Routine und Beschwerde übernommen, Schmerz gespeichert"
    }

    /// Eine Datenbank aus Version 0.8 (Schema 7) mit Arzt-Tagebuch wird auf Schema 8 gebracht.
    private static func migrationKeepsDiary() throws -> String {
        let folder = try temporaryFolder()
        let url = folder.appendingPathComponent("Diary.store")
        let defaults = UserDefaults(suiteName: "tagwerk.selftest.\(UUID().uuidString)")!
        defaults.set(7, forKey: "tagwerk.store.schemaVersion")

        do {
            let schemaV7 = Schema(versionedSchema: TagwerkSchemaV7.self)
            let container = try ModelContainer(for: schemaV7, configurations: [ModelConfiguration(schema: schemaV7, url: url)])
            let context = ModelContext(container)
            DiaryActions.addPain(PainFact(date: .now, regions: [.kneeLeft], intensity: 4), in: context)
            DiaryActions.addActivity(ActivityFact(date: .now, kind: .cycling, minutes: 40, intensity: .moderate), in: context)
            try context.save()
        }

        let container = try TagwerkStore.makeContainer(at: url, defaults: defaults)
        let context = ModelContext(container)
        try check(try context.fetchCount(FetchDescriptor<PainEntry>()) == 1, "Schmerz verloren")
        try check(try context.fetchCount(FetchDescriptor<ActivityEntry>()) == 1, "Bewegung verloren")
        HealthActions.importValues(HealthValues(steps: 5_000), calendar: calendar, in: context)
        try check(try context.fetchCount(FetchDescriptor<HealthDay>()) == 1, "Health-Werte nicht gespeichert")
        try check(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Diary-vor-v8.store").path), "Keine Kopie vor der Migration")
        try check(defaults.integer(forKey: "tagwerk.store.schemaVersion") == 8, "Schema-Version nicht gemerkt")
        return "Schmerz und Bewegung übernommen, Schritte gespeichert"
    }

    /// Werte übernehmen, zusammenführen, Gewicht und Schlaf weitergeben, Wasser ohne Doppelte zurück.
    private static func healthFlow() throws -> String {
        let context = ModelContext(try TagwerkStore.makeContainer(at: nil))
        let now = Date.now
        let defaults = UserDefaults.standard
        let savedMarker = defaults.data(forKey: SettingsKeys.healthWaterMarker)
        let savedWeight = defaults.object(forKey: SettingsKeys.healthWeightExportedAt)
        let savedImport = defaults.object(forKey: SettingsKeys.healthLastImport)
        defer {
            defaults.set(savedMarker, forKey: SettingsKeys.healthWaterMarker)
            defaults.set(savedWeight, forKey: SettingsKeys.healthWeightExportedAt)
            defaults.set(savedImport, forKey: SettingsKeys.healthLastImport)
        }
        defaults.removeObject(forKey: SettingsKeys.healthWaterMarker)
        defaults.removeObject(forKey: SettingsKeys.healthWeightExportedAt)

        let first = HealthActions.importValues(HealthValues(steps: 3_000, sleepHours: 450, weightKg: 81.6), now: now, calendar: calendar, in: context)
        try check(first.stored.sleepHours == 7.5, "Schlaf in Minuten nicht umgerechnet")
        HealthActions.importValues(HealthValues(steps: 8_200, distanceKm: 5.9, weightKg: 81.6), now: now, calendar: calendar, in: context)
        let day = HealthActions.healthDay(on: now, calendar: calendar, in: context)?.fact
        try check(day?.steps == 8_200 && day?.sleepHours == 7.5 && day?.distanceKm == 5.9, "Zusammenführen: \(String(describing: day))")
        try check(try context.fetchCount(FetchDescriptor<HealthDay>()) == 1, "Ein Tag erwartet")
        let weights = TrainingActions.metrics(.weight, in: context)
        try check(weights.count == 1 && weights[0].note == HealthActions.healthNote, "Gewicht doppelt oder fehlt: \(weights.count)")
        try check(InsightsActions.checkIn(on: now, calendar: calendar, in: context)?.sleepHours == 7.5, "Schlaf nicht im Check-in")
        try check(DiaryActions.today(now: now, calendar: calendar, in: context).steps == 8_200, "Schritte nicht im Tagebuch")

        NutritionActions.addWater(500, at: now, in: context)
        try check(HealthActions.waterForHealth(now: now, calendar: calendar, in: context) == 500, "Wasser 1")
        try check(HealthActions.waterForHealth(now: now, calendar: calendar, in: context) == 0, "Wasser doppelt")
        NutritionActions.addWater(250, at: now, in: context)
        try check(HealthActions.waterForHealth(now: now, calendar: calendar, in: context) == 250, "Wasser 2")

        try check(HealthActions.weightForHealth(now: now, in: context) == nil, "Gewicht aus Health darf nicht zurück")
        TrainingActions.addMetric(.weight, value: 82.1, date: now.addingTimeInterval(60), in: context)
        try check(HealthActions.weightForHealth(now: now, in: context) == 82.1, "Neues Gewicht fehlt")
        try check(HealthActions.weightForHealth(now: now, in: context) == nil, "Gewicht doppelt")

        let rejected = HealthActions.importValues(HealthValues(steps: 500_000), now: now, calendar: calendar, in: context)
        try check(rejected.rejected == ["Schritte"] && HealthActions.healthDay(on: now, calendar: calendar, in: context)?.steps == 8_200, "Unplausible Schritte übernommen")
        return "8.200 Schritte, Schlaf 7,5 Std. im Check-in, Wasser und Gewicht ohne Doppelte"
    }

    /// Schmerz, Bewegung, Gym-Einheit, beschwerdefreier Tag, Vollständigkeit, Bericht mit Tabelle.
    private static func diaryFlow() throws -> String {
        let context = ModelContext(try TagwerkStore.makeContainer(at: nil))
        let now = Date.now
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let noonYesterday = yesterday.addingTimeInterval(12 * 3_600)

        DiaryActions.addPain(PainFact(date: noonYesterday, regions: [.shoulderRight], intensity: 6, qualities: [.stabbing], triggers: [.training]), in: context)
        DiaryActions.addActivity(ActivityFact(date: noonYesterday.addingTimeInterval(-3_600), kind: .running, minutes: 30, intensity: .vigorous), in: context)
        NutritionActions.addMeal(type: .lunch, date: noonYesterday, items: [(foodID: "reis", grams: 70)], catalog: NutritionActions.catalog(in: context), in: context)
        let catalog = TrainingActions.catalog(in: context)
        if let plan = TrainingActions.ensureStarterPlan(in: context), let day = plan.nextDay {
            // Heute, aber nicht in der Zukunft (der Test kann kurz nach Mitternacht laufen).
            let start = max(today, now.addingTimeInterval(-2 * 3_600))
            let session = TrainingActions.startSession(plan: plan, day: day, includeModule: false, catalog: catalog, now: start, in: context)
            TrainingActions.finish(session, catalog: catalog, now: start.addingTimeInterval(3_600), in: context)
        }
        DiaryActions.setSymptomFree(true, on: now, calendar: calendar, in: context)

        let facts = DiaryActions.today(now: now, calendar: calendar, in: context)
        try check(facts.symptomFree && facts.gymSessions == 1 && facts.hasActivityInfo, "Heute: frei \(facts.symptomFree), Gym \(facts.gymSessions)")
        let activities = DiaryActions.activityFacts(from: yesterday, to: now.addingTimeInterval(1), in: context)
        try check(activities.map(\.kind) == [.running, .gym], "Bewegung: \(activities.map(\.kind.rawValue))")
        let factors = InsightsActions.dayFactors(from: yesterday, to: now.addingTimeInterval(1), calendar: calendar, in: context)
        try check(factors.filter { $0.key == "activity" }.count == 2, "Sport als Umstand fehlt")

        let report = InsightsActions.doctorReport(from: yesterday, to: now, name: "", questions: "Frage?", calendar: calendar, in: context)
        try check(report.painSummary.count == 1 && report.painSummary.afterActivity == 1, "Schmerzen im Bericht: \(report.painSummary.count)")
        try check(report.activities.count == 2 && report.diary.count == 2, "Bewegung \(report.activities.count), Tage \(report.diary.count)")
        try check(report.diary.first?.meals.count == 1 && report.diary.last?.complaints == ["keine"], "Tabelle: \(report.diary.map(\.complaints))")
        try check(report.completeness.days == 2 && report.questions == "Frage?", "Vollständigkeit: \(report.completeness.summary)")
        guard let url = DoctorReportPDF.render(report, calendar: calendar), let document = PDFDocument(url: url) else {
            throw Failure(description: "PDF nicht erstellt")
        }
        try check(document.pageCount == DoctorReportPages.make(report, calendar: calendar).count, "PDF: \(document.pageCount) Seiten")
        let reduced = DoctorReportPages.make(report, sections: [.medications], calendar: calendar).count
        try check(reduced == 1, "Nur Medikamente: \(reduced) Seiten")
        let reminder = DiaryCheck.reminder(DiaryDayFacts(day: today), minuteOfDay: 23 * 60 + 59, now: today, calendar: calendar)
        try check(reminder?.kind == .diary, "Erinnerung fehlt")
        return "Schmerz nach Sport erkannt, Tabelle mit 2 Tagen, PDF mit \(document.pageCount) Seiten"
    }

    /// Check-ins als Umstände, Wochenrückblick, Arztbericht mit PDF.
    private static func insightsFlow() throws -> String {
        let context = ModelContext(try TagwerkStore.makeContainer(at: nil))
        let now = Date.now
        let today = calendar.startOfDay(for: now)
        for offset in 1...6 {
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            InsightsActions.set(.sleep, offset <= 3 ? 1 : 4, on: day, calendar: calendar, in: context)
            InsightsActions.set(.mood, 3, on: day, calendar: calendar, in: context)
        }
        InsightsActions.set(.stress, 9, on: now, calendar: calendar, in: context)
        InsightsActions.setNote("Test", on: now, calendar: calendar, in: context)
        try check(InsightsActions.checkIn(on: now, calendar: calendar, in: context)?.stress == 5, "Wert nicht auf 1–5 begrenzt")
        try check(try context.fetchCount(FetchDescriptor<DailyCheckIn>()) == 7, "Ein Check-in je Tag erwartet")
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        let factors = InsightsActions.dayFactors(from: weekAgo, to: now.addingTimeInterval(1), calendar: calendar, in: context)
        try check(factors.filter { $0.key == "factor.sleep" }.count == 3 && factors.filter { $0.key == "factor.stress" }.count == 1, "Umstände: \(factors.map(\.key))")

        let medication = Medication(name: "DAO", schedule: .daily([DoseTime(hour: 12)]), startDate: now.addingTimeInterval(-10 * 86_400), createdAt: now.addingTimeInterval(-10 * 86_400))
        context.insert(medication)
        NutritionActions.addMeal(type: .lunch, date: now.addingTimeInterval(-3_600), items: [(foodID: "tomate", grams: 150)], catalog: NutritionActions.catalog(in: context), in: context)
        NutritionActions.addSymptom(.headache, severity: 3, date: now.addingTimeInterval(-1_800), durationMinutes: 90, note: "nach dem Essen", in: context)
        TrainingActions.addMetric(.weight, value: 82, date: now.addingTimeInterval(-20 * 86_400), in: context)
        TrainingActions.addMetric(.weight, value: 81.2, date: now.addingTimeInterval(-86_400), in: context)
        try context.save()

        let review = InsightsActions.weeklyReview(weekStart: AgendaBuilder.startOfWeek(containing: now, calendar: calendar), calendar: calendar, in: context)
        try check(!review.isEmpty && !review.plainText.contains("DAO"), "Rückblick leer oder mit Namen")

        let from = calendar.date(byAdding: .day, value: -27, to: today) ?? today
        let report = InsightsActions.doctorReport(from: from, to: now, name: "Test", calendar: calendar, in: context)
        try check(report.medications.count == 1 && report.symptomLog.count == 1 && report.checkIns.days == 7, "Bericht: \(report.medications.count) Medikamente, \(report.symptomLog.count) Beschwerden, \(report.checkIns.days) Check-ins")
        try check(report.weightChangeText?.contains("82") == true, "Gewicht: \(report.weightChangeText ?? "–")")
        guard let url = DoctorReportPDF.render(report, calendar: calendar), let document = PDFDocument(url: url) else {
            throw Failure(description: "PDF nicht erstellt")
        }
        let expectedPages = DoctorReportPages.make(report, calendar: calendar).count
        try check(document.pageCount == expectedPages && document.pageCount >= 4, "PDF: \(document.pageCount) statt \(expectedPages) Seiten")
        let candidates = InsightsActions.reminderCandidates(now: now, calendar: calendar)
        try check(candidates.count == (InsightsActions.reviewReminderEnabled ? 1 : 0), "Erinnerung an den Rückblick fehlt")
        return "3 Tage wenig Schlaf als Umstand, Rückblick, PDF mit \(document.pageCount) Seiten"
    }

    /// Anfragen bauen, Antworten zuordnen und übernehmen (Lebensmittel, Plan, Rezepte).
    private static func claudeFlow() throws -> String {
        let context = ModelContext(try TagwerkStore.makeContainer(at: nil))
        _ = TrainingActions.ensureStarterPlan(in: context)

        // Lebensmittel: Antwort mit Codeblock, Zuordnung über die Kennung.
        let foodPrompt = ClaudeBridgeActions.foodPrompt(name: "Testriegel", ingredients: "Hafer, Kakao")
        let food = InsightsActions.createExchange(foodPrompt, title: "Lebensmittel: Testriegel", in: context)
        InsightsActions.markSent(food, in: context)
        let other = InsightsActions.createExchange(ClaudeBridgeActions.foodPrompt(name: "Anderes"), title: "Anderes", in: context)
        InsightsActions.markSent(other, in: context)
        let response = "Gern!\n```json\n{\"format\":\"orbit.food.v1\",\"ref\":\"\(foodPrompt.ref)\",\"name\":\"Testriegel\",\"category\":\"sweets\",\"score\":2,\"flags\":[\"L\"],\"hint\":\"Kakao setzt Histamin frei.\",\"protein\":8}\n```"
        let received = ClaudeBridgeActions.receive(response, in: context)
        try check(received?.stableID == food.stableID && food.status == .answered, "Antwort falsch zugeordnet")
        guard case .food(let info) = try ClaudeBridgeActions.parse(food, in: context) else {
            throw Failure(description: "Lebensmittel nicht erkannt")
        }
        ClaudeBridgeActions.applyFood(info, from: food, in: context)
        let saved = NutritionActions.catalog(in: context).foods.first { $0.name == "Testriegel" }
        try check(saved?.score == .poor && food.status == .applied, "Lebensmittel nicht gespeichert")

        // Trainingsplan: Anfrage mit Plan und Übungsnamen, Antwort wird neuer aktiver Plan.
        guard let planPrompt = ClaudeBridgeActions.trainingPrompt(wish: "Mehr Rücken", calendar: calendar, in: context) else {
            throw Failure(description: "Keine Plan-Anfrage ohne Plan")
        }
        try check(planPrompt.text.contains("Bankdrücken (Langhantel)") && planPrompt.text.contains("Mehr Rücken"), "Plan-Anfrage unvollständig")
        let planExchange = InsightsActions.createExchange(planPrompt, title: "Plan", in: context)
        InsightsActions.attach(#"{"format":"orbit.plan.v1","name":"Claude-Plan","mesoWeeks":5,"days":[{"name":"Oberkörper","exercises":[{"name":"Bankdrücken (Langhantel)","sets":3,"repMin":6,"repMax":8,"rir":2,"restSec":150},{"name":"Xylofon-Übung","sets":2,"repMin":10,"repMax":12,"rir":1,"restSec":60}]}]}"#, to: planExchange, in: context)
        guard case .plan(let template) = try ClaudeBridgeActions.parse(planExchange, in: context) else {
            throw Failure(description: "Plan nicht erkannt")
        }
        let plan = ClaudeBridgeActions.applyPlan(template, from: planExchange, in: context)
        try check(TrainingActions.activePlan(in: context)?.stableID == plan.stableID && plan.rotationDays.count == 1, "Plan nicht aktiv")
        try check(TrainingActions.catalog(in: context).exercise(id: PlanImporter.customID(for: "Xylofon-Übung")) != nil, "Unbekannte Übung nicht angelegt")

        // Rezepte: unbekannte Zutat wird eigenes Lebensmittel.
        let recipesPrompt = ClaudeBridgeActions.recipesPrompt(wish: "Frühstück", in: context)
        let recipes = InsightsActions.createExchange(recipesPrompt, title: "Rezepte", in: context)
        InsightsActions.attach(#"{"format":"orbit.recipes.v1","recipes":[{"title":"Quark-Bowl","servings":1,"minutes":5,"ingredients":[{"name":"Magerquark","grams":250},{"name":"Xylofrucht","grams":80}],"steps":["Alles mischen."]}]}"#, to: recipes, in: context)
        guard case .recipes(let list, let newFoods) = try ClaudeBridgeActions.parse(recipes, in: context) else {
            throw Failure(description: "Rezepte nicht erkannt")
        }
        ClaudeBridgeActions.applyRecipes(list, newFoods: newFoods, from: recipes, in: context)
        try check(NutritionActions.recipes(in: context).recipes.contains { $0.title == "Quark-Bowl" }, "Rezept nicht gespeichert")
        try check(newFoods.count == 1 && NutritionActions.catalog(in: context).food(id: newFoods[0].id) != nil, "Neue Zutat fehlt")

        let waiting = InsightsActions.waitingExchange(in: context)
        try check(waiting?.stableID == other.stableID, "Wartende Anfrage: \(waiting?.title ?? "keine")")
        return "Lebensmittel, Plan und Rezept übernommen"
    }

    /// Mahlzeiten mit Tomate vor Kopfschmerz: Tageslast, Muster, Einkauf aus dem Wochenplan.
    private static func nutritionFlow() throws -> String {
        let context = ModelContext(try TagwerkStore.makeContainer(at: nil))
        let catalog = NutritionActions.catalog(in: context)
        try check(catalog.foods.count >= 300, "Lexikon fehlt (\(catalog.foods.count))")
        try check(NutritionActions.bundledRecipes.recipes.count >= 30, "Rezepte fehlen")
        let now = Date.now
        for day in 1...12 {
            let noon = now.addingTimeInterval(-Double(day) * 86_400)
            let tomato = day <= 5
            NutritionActions.addMeal(
                type: .lunch, date: noon,
                items: tomato ? [(foodID: "tomate", grams: 150), (foodID: "nudeln", grams: 100)] : [(foodID: "haehnchenbrust", grams: 150), (foodID: "reis", grams: 70)],
                catalog: catalog, in: context
            )
            if tomato { NutritionActions.addSymptom(.headache, severity: 3, date: noon.addingTimeInterval(3_600), in: context) }
        }
        let report = NutritionActions.triggerReport(days: 30, now: now, in: context)
        let keys = report.findings.map(\.key)
        try check(keys.contains("tomate") && !keys.contains("haehnchenbrust"), "Muster: \(keys)")

        // Eigene Einschätzung „ok“ senkt die Tageslast auf null.
        NutritionActions.addMeal(type: .dinner, date: now.addingTimeInterval(-60), items: [(foodID: "tomate", grams: 100)], catalog: catalog, in: context)
        let before = NutritionActions.day(now, calendar: calendar, in: context).load.points
        NutritionActions.setTolerance(.ok, for: "tomate", in: context)
        let after = NutritionActions.day(now, calendar: calendar, in: context).load.points
        try check(before == 3 && after == 0, "Tageslast \(before) → \(after)")

        NutritionActions.addWater(in: context)
        NutritionActions.addWater(500, in: context)
        try check(NutritionActions.water(on: now, calendar: calendar, in: context) == 750, "Wasser")
        let snapshot = NutritionActions.snapshot(now: now, calendar: calendar, in: context)
        try check(snapshot.waterML == 750 && snapshot.mealCount >= 1, "Widget-Daten: \(snapshot.waterML) ml")

        let monday = AgendaBuilder.startOfWeek(containing: now, calendar: calendar)
        NutritionActions.plan("haehnchen-reis-zucchini", servings: 2, on: monday, mealType: .dinner, calendar: calendar, in: context)
        NutritionActions.plan("kurkuma-haehnchen-kokos", servings: 4, on: monday.addingTimeInterval(86_400), mealType: .dinner, calendar: calendar, in: context)
        let end = calendar.date(byAdding: .day, value: 7, to: monday) ?? monday
        let added = NutritionActions.addToShopping(NutritionActions.planNeeds(from: monday, to: end, in: context), source: "plan", catalog: catalog, in: context)
        let chicken = try context.fetch(FetchDescriptor<ShoppingItem>()).first { $0.foodID == "haehnchenbrust" }
        try check(added >= 8 && chicken?.amount == "900 g", "Einkauf: \(added) Artikel, Hähnchen \(chicken?.amount ?? "-")")
        let again = NutritionActions.addToShopping(NutritionActions.planNeeds(from: monday, to: end, in: context), source: "plan", catalog: catalog, in: context)
        try check(again == 0, "Doppelt auf der Liste: \(again)")
        return "Muster Tomate, Tageslast 3 → 0, \(added) Artikel aus dem Wochenplan"
    }

    /// Einheit starten, Sätze abhaken, abschließen: Rotation geht weiter, beim nächsten Mal mehr Gewicht.
    private static func trainingFlow() throws -> String {
        let context = ModelContext(try TagwerkStore.makeContainer(at: nil))
        let catalog = TrainingActions.catalog(in: context)
        try check(catalog.exercises.count >= 90, "Bibliothek fehlt (\(catalog.exercises.count))")
        guard let plan = TrainingActions.ensureStarterPlan(in: context), let push = plan.nextDay else {
            throw Failure(description: "Kein Startplan")
        }
        try check(push.name == "Push", "Erster Tag: \(push.name)")
        let first = TrainingActions.startSession(plan: plan, day: push, includeModule: false, catalog: catalog, now: .now.addingTimeInterval(-7_200), in: context)
        let benchSets = first.sets(inSlot: 0)
        try check(benchSets.count == 4, "Bankdrücken: \(benchSets.count) Sätze statt 4")
        try check(benchSets.allSatisfy { $0.kind == .working }, "Beim ersten Mal keine Aufwärmsätze erwartet")
        for set in first.sortedSets {
            TrainingActions.complete(set, weight: set.exerciseID == "bench-press-barbell" ? 80 : 20, reps: set.targetRepMax, rir: 2, in: context)
        }
        let summary = TrainingActions.finish(first, catalog: catalog, now: .now.addingTimeInterval(-3_600), in: context)
        try check(summary.workingSets == (first.sets ?? []).count, "Zusammenfassung: \(summary.workingSets) Sätze")
        try check(plan.nextDayIndex == 1, "Rotation: nächster Tag \(plan.nextDayIndex) statt 1")
        try check(TrainingActions.activeSession(in: context) == nil, "Einheit läuft noch")

        let second = TrainingActions.startSession(plan: plan, day: push, includeModule: false, catalog: catalog, in: context)
        let warmups = second.sets(inSlot: 0).filter { $0.kind == .warmup }
        let working = second.sets(inSlot: 0).filter { $0.kind == .working }
        try check(working.first?.weight == 82.5, "Vorschlag: \(working.first?.weight ?? -1) kg statt 82,5")
        try check(warmups.map(\.weight) == [42.5, 57.5, 70], "Aufwärmen: \(warmups.map(\.weight))")
        // Wie in der App: erst abhaken, dann den nächsten Satz holen.
        TrainingActions.complete(working[0], weight: 82.5, reps: 8, rir: 2, in: context)
        let next = TrainingActions.next(after: working[0], in: second)
        let nextLabel = next.set.map { "\($0.kind.rawValue) \($0.setIndex) in \($0.slot)" } ?? "keiner"
        try check(
            next.set?.stableID == working[1].stableID && next.restSeconds == 150,
            "Nächster Satz \(nextLabel), Pause \(next.restSeconds) s statt Satz 2, 150 s"
        )
        TrainingActions.discard(second, in: context)
        try check(TrainingActions.activeSession(in: context) == nil, "Verworfene Einheit läuft noch")

        let snapshot = TrainingActions.snapshot(in: context)
        try check(snapshot.nextDayName == "Pull" && snapshot.lastTrainingAt != nil, "Widget-Daten: \(snapshot.nextDayName)")
        return "Rotation weiter, nächstes Mal 82,5 kg mit Aufwärmen"
    }

    private static func doseActionsAdjustStock() throws -> String {
        let container = try TagwerkStore.makeContainer(at: nil)
        let context = ModelContext(container)
        let now = Date.now
        let medication = Medication(
            name: "Test", form: .tablet,
            schedule: .daily([DoseTime(hour: 8), DoseTime(hour: 20, amount: 0.5)]),
            startDate: now.addingTimeInterval(-5 * 86_400), createdAt: now.addingTimeInterval(-5 * 86_400)
        )
        medication.stock = 10
        context.insert(medication)
        try context.save()

        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let entries = medication.entries(on: yesterday, now: now, calendar: calendar)
        try check(entries.count == 2, "\(entries.count) statt 2 Einnahmen gestern")
        let morning = entries[0]
        MedicationActions.take(morning, medication: medication, in: context)
        try check(medication.stock == 9, "Vorrat nach Einnahme \(medication.stock ?? -1)")
        MedicationActions.take(morning, medication: medication, in: context)
        try check(medication.stock == 9, "Doppeltes Abhaken zählte doppelt")
        let taken = medication.entries(on: yesterday, now: now, calendar: calendar)[0]
        try check(taken.state == .taken, "Zustand \(taken.state.rawValue) statt taken")
        MedicationActions.skip(taken, medication: medication, in: context)
        try check(medication.stock == 10, "Auslassen gab Vorrat nicht zurück")
        let skipped = medication.entries(on: yesterday, now: now, calendar: calendar)[0]
        MedicationActions.undo(skipped, medication: medication, in: context)
        try check((medication.logs ?? []).isEmpty, "Rückgängig ließ Einträge übrig")

        MedicationActions.record(doseID: entries[1].id, status: .taken, in: context, calendar: calendar)
        try check(medication.stock == 9.5, "Einnahme per DoseID: Vorrat \(medication.stock ?? -1)")
        MedicationActions.takeExtra(medication, amount: 2, in: context)
        try check(medication.stock == 7.5, "Zusätzliche Einnahme: Vorrat \(medication.stock ?? -1)")
        MedicationActions.refill(medication, adding: 20, in: context)
        try check(medication.stock == 27.5, "Nachfüllen: Vorrat \(medication.stock ?? -1)")
        let summary = Adherence.summarize(medication.entries(from: calendar.startOfDay(for: yesterday), to: calendar.startOfDay(for: now), now: now, calendar: calendar))
        try check(summary.taken == 1 && summary.missed == 1, "Treue: \(summary)")
        return "Vorrat 10 → 27,5 wie erwartet"
    }

    private static func refillTaskOnlyOnce() throws -> String {
        let container = try TagwerkStore.makeContainer(at: nil)
        let context = ModelContext(container)
        let medication = Medication(name: "Knapp", schedule: .daily([DoseTime(hour: 9)]), createdAt: .now.addingTimeInterval(-86_400))
        medication.stock = 2
        medication.autoRefillTask = true
        context.insert(medication)
        try context.save()
        let first = MedicationActions.ensureRefillTasks(in: context, calendar: calendar)
        let second = MedicationActions.ensureRefillTasks(in: context, calendar: calendar)
        try check(first == 1 && second == 0, "Aufgaben: \(first), dann \(second)")
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        try check(tasks.first?.title == "Nachschub besorgen: Knapp", "Titel: \(tasks.first?.title ?? "–")")
        MedicationActions.refill(medication, adding: 30, in: context)
        try check(tasks.first?.isDone == true, "Aufgabe nach dem Nachfüllen nicht erledigt")
        return "Eine Aufgabe, nach Nachfüllen erledigt"
    }

    private static func backupRoundTrip() throws -> String {
        let source = ModelContext(try TagwerkStore.makeContainer(at: nil))
        let medication = Medication(name: "Sicherung", dosage: "5 mg", schedule: .asNeeded(maxPerDay: 2, minGapHours: 4))
        medication.stock = 12
        source.insert(medication)
        MedicationActions.takeExtra(medication, amount: 1, in: source)
        source.insert(TaskItem(title: "Aufgabe"))
        try source.save()

        let document = try BackupService.makeDocument(context: source)
        let folder = try temporaryFolder()
        let file = folder.appendingPathComponent("backup.json")
        try BackupCodec.encode(document).write(to: file)

        let target = ModelContext(try TagwerkStore.makeContainer(at: nil))
        let summary = try BackupService.restore(from: file, context: target, calendar: calendar)
        let restored = try target.fetch(FetchDescriptor<Medication>())
        try check(summary.medications == 1 && restored.count == 1, "Medikamente: \(restored.count)")
        try check(restored[0].schedule.maxPerDay == 2, "Zeitplan verloren")
        try check(restored[0].stock == 11, "Vorrat: \(restored[0].stock ?? -1)")
        try check((restored[0].logs ?? []).count == 1, "Protokoll: \((restored[0].logs ?? []).count)")
        try check(try target.fetchCount(FetchDescriptor<TaskItem>()) == 1, "Aufgaben fehlen")
        return "1 Medikament, 1 Eintrag, 1 Aufgabe"
    }

    private static func trainingBackupRoundTrip() throws -> String {
        let source = ModelContext(try TagwerkStore.makeContainer(at: nil))
        let catalog = TrainingActions.catalog(in: source)
        guard let plan = TrainingActions.ensureStarterPlan(in: source), let day = plan.nextDay else {
            throw Failure(description: "Kein Startplan")
        }
        let session = TrainingActions.startSession(plan: plan, day: day, includeModule: false, catalog: catalog, in: source)
        for set in session.sortedSets.prefix(3) {
            TrainingActions.complete(set, weight: 50, reps: 8, rir: 2, in: source)
        }
        TrainingActions.finish(session, catalog: catalog, in: source)
        TrainingActions.addMetric(.weight, value: 82.4, in: source)
        TrainingActions.createCustomExercise(ExerciseInfo(id: "custom-zottman-curls", name: "Zottman Curls", primary: [.biceps], equipment: .dumbbell, mechanic: .isolation, isCustom: true), in: source)

        let document = try BackupService.makeDocument(context: source)
        let file = try temporaryFolder().appendingPathComponent("training.json")
        try BackupCodec.encode(document).write(to: file)
        let target = ModelContext(try TagwerkStore.makeContainer(at: nil))
        let summary = try BackupService.restore(from: file, context: target, calendar: calendar)
        try check(summary.workouts == 1, "Einheiten: \(summary.workouts)")
        let restoredPlan = try target.fetch(FetchDescriptor<WorkoutPlan>()).first
        try check(restoredPlan?.rotationDays.count == 4 && restoredPlan?.nextDayIndex == 1, "Plan oder Rotation verloren")
        let sets = try target.fetch(FetchDescriptor<SetLog>())
        try check(sets.count == 3 && sets.allSatisfy(\.isDone), "Sätze: \(sets.count)")
        try check(try target.fetchCount(FetchDescriptor<BodyMetric>()) == 1, "Körpermaße fehlen")
        try check(TrainingActions.catalog(in: target).exercise(id: "custom-zottman-curls") != nil, "Eigene Übung fehlt")
        return "Plan, 1 Einheit, 3 Sätze, Körpermaß, eigene Übung"
    }

    private static func nutritionBackupRoundTrip() throws -> String {
        let source = ModelContext(try TagwerkStore.makeContainer(at: nil))
        let catalog = NutritionActions.catalog(in: source)
        NutritionActions.addMeal(type: .lunch, date: .now, freshness: .leftover, items: [(foodID: "tomate", grams: 100), (foodID: "reis", grams: 70)], catalog: catalog, in: source)
        NutritionActions.addSymptom(.flush, severity: 2, in: source)
        NutritionActions.addWater(in: source)
        NutritionActions.setTolerance(.caution, for: "banane", in: source)
        NutritionActions.saveCustomFood(FoodInfo(id: "barcode-4006381333931", name: "Testprodukt", category: .sauces, score: .poor, isCustom: true, barcode: "4006381333931"), in: source)
        NutritionActions.addShoppingItem("Quark", amount: "500 g", catalog: catalog, in: source)
        NutritionActions.plan("frikadellen", servings: 3, on: .now, mealType: .dinner, calendar: calendar, in: source)

        let document = try BackupService.makeDocument(context: source)
        let file = try temporaryFolder().appendingPathComponent("nutrition.json")
        try BackupCodec.encode(document).write(to: file)
        let target = ModelContext(try TagwerkStore.makeContainer(at: nil))
        let summary = try BackupService.restore(from: file, context: target, calendar: calendar)
        try check(summary.meals == 1, "Mahlzeiten: \(summary.meals)")
        let meal = try target.fetch(FetchDescriptor<MealEntry>()).first
        try check(meal?.sortedItems.count == 2 && meal?.freshness == .leftover, "Mahlzeit unvollständig")
        try check(try target.fetchCount(FetchDescriptor<SymptomEntry>()) == 1, "Beschwerden fehlen")
        try check(NutritionActions.water(on: .now, calendar: calendar, in: target) == 250, "Wasser fehlt")
        try check(NutritionActions.tolerance(for: "banane", in: target) == .caution, "Einschätzung fehlt")
        try check(NutritionActions.catalog(in: target).food(barcode: "4006381333931") != nil, "Gescanntes Produkt fehlt")
        try check(try target.fetchCount(FetchDescriptor<ShoppingItem>()) == 1, "Einkaufsliste fehlt")
        try check(try target.fetchCount(FetchDescriptor<MealPlanEntry>()) == 1, "Wochenplan fehlt")
        return "Mahlzeit, Beschwerde, Wasser, Einschätzung, Produkt, Einkauf, Plan"
    }

    private static func insightsBackupRoundTrip() throws -> String {
        let source = ModelContext(try TagwerkStore.makeContainer(at: nil))
        InsightsActions.set(.mood, 4, calendar: calendar, in: source)
        InsightsActions.setSleepHours(7.5, calendar: calendar, in: source)
        InsightsActions.setNote("Gut geschlafen", calendar: calendar, in: source)
        let prompt = ClaudeBridgeActions.foodPrompt(name: "Sicherung")
        let exchange = InsightsActions.createExchange(prompt, title: "Lebensmittel: Sicherung", in: source)
        InsightsActions.attach("Antwort", to: exchange, in: source)

        let document = try BackupService.makeDocument(context: source)
        let file = try temporaryFolder().appendingPathComponent("insights.json")
        try BackupCodec.encode(document).write(to: file)
        let target = ModelContext(try TagwerkStore.makeContainer(at: nil))
        let summary = try BackupService.restore(from: file, context: target, calendar: calendar)
        try check(summary.checkIns == 1, "Check-ins: \(summary.checkIns)")
        let checkIn = try target.fetch(FetchDescriptor<DailyCheckIn>()).first
        try check(checkIn?.mood == 4 && checkIn?.sleepHours == 7.5 && checkIn?.note == "Gut geschlafen", "Check-in unvollständig")
        let restored = try target.fetch(FetchDescriptor<ClaudeExchange>())
        try check(restored.count == 1 && restored[0].ref == prompt.ref && restored[0].response == "Antwort" && restored[0].status == .answered, "Claude-Verlauf unvollständig")
        return "Check-in und Claude-Verlauf"
    }

    private static func lifeBackupRoundTrip() throws -> String {
        let source = ModelContext(try TagwerkStore.makeContainer(at: nil))
        let routine = LifeActions.createHabit(from: LifeTemplates.habits[0], in: source)
        if let step = routine.steps.first {
            LifeActions.toggleStep(step.id, of: routine, calendar: calendar, in: source)
        }
        let contract = LifeActions.createContract(from: LifeTemplates.contracts[1], in: source)
        contract.cost = 17.99
        contract.provider = "Telekom"
        LifeActions.addBirthday(name: "Papa", day: 3, month: 4, year: 1965, in: source)
        LifeActions.saveJournal(answer: "Ruhig", text: "", calendar: calendar, in: source)
        LifeActions.save(source)

        let document = try BackupService.makeDocument(context: source)
        let file = try temporaryFolder().appendingPathComponent("life.json")
        try BackupCodec.encode(document).write(to: file)
        let target = ModelContext(try TagwerkStore.makeContainer(at: nil))
        let summary = try BackupService.restore(from: file, context: target, calendar: calendar)
        try check(summary.lifeEntries == 3, "Leben: \(summary.lifeEntries) statt 3")
        let habits = LifeActions.habits(in: target)
        try check(habits.count == 1 && habits[0].steps.count == routine.steps.count, "Routine unvollständig")
        try check(LifeActions.logs(for: habits[0], in: target).first?.doneSteps.count == 1, "Abgehakter Schritt fehlt")
        let contracts = LifeActions.contracts(in: target)
        try check(contracts.first?.cost == 17.99 && contracts.first?.provider == "Telekom", "Vertrag unvollständig")
        try check(LifeActions.birthdays(in: target).first?.year == 1965, "Geburtstag unvollständig")
        try check(LifeActions.journalEntries(in: target).count == 1, "Tagebuch fehlt")
        return "Routine mit Verlauf, Vertrag, Geburtstag und Tagebuch"
    }

    private static func diaryBackupRoundTrip() throws -> String {
        let source = ModelContext(try TagwerkStore.makeContainer(at: nil))
        DiaryActions.addPain(PainFact(date: .now, regions: [.kneeLeft, .kneeRight], intensity: 4, qualities: [.dull], durationMinutes: 60, triggers: [.training], reliefs: [.cold], note: "Treppe"), in: source)
        DiaryActions.addActivity(ActivityFact(date: .now, kind: .swimming, minutes: 40, intensity: .moderate, note: "Hallenbad"), in: source)
        DiaryActions.setRestDay(true, calendar: calendar, in: source)

        let document = try BackupService.makeDocument(context: source)
        let file = try temporaryFolder().appendingPathComponent("diary.json")
        try BackupCodec.encode(document).write(to: file)
        let target = ModelContext(try TagwerkStore.makeContainer(at: nil))
        let summary = try BackupService.restore(from: file, context: target, calendar: calendar)
        try check(summary.diaryEntries == 2, "Tagebuch: \(summary.diaryEntries) statt 2")
        let pain = DiaryActions.allPains(in: target).first?.fact
        try check(pain?.regions == [.kneeLeft, .kneeRight] && pain?.reliefs == [.cold] && pain?.note == "Treppe", "Schmerz unvollständig")
        let activity = DiaryActions.activities(from: .distantPast, to: .distantFuture, in: target).first
        try check(activity?.kind == .swimming && activity?.minutes == 40 && activity?.note == "Hallenbad", "Bewegung unvollständig")
        try check(DiaryActions.diaryDay(on: .now, calendar: calendar, in: target)?.restDay == true, "Ruhetag fehlt")
        return "Schmerz, Bewegung und Ruhetag"
    }

    private static func healthBackupRoundTrip() throws -> String {
        let source = ModelContext(try TagwerkStore.makeContainer(at: nil))
        let yesterday = calendar.date(byAdding: .day, value: -1, to: .now) ?? .now
        HealthActions.importValues(HealthValues(steps: 9_100, distanceKm: 6.4, flights: 5, restingHeartRate: 58), day: yesterday, calendar: calendar, in: source)
        HealthActions.importValues(HealthValues(steps: 4_000), calendar: calendar, in: source)

        let document = try BackupService.makeDocument(context: source)
        let file = try temporaryFolder().appendingPathComponent("health.json")
        try BackupCodec.encode(document).write(to: file)
        let target = ModelContext(try TagwerkStore.makeContainer(at: nil))
        let summary = try BackupService.restore(from: file, context: target, calendar: calendar)
        try check(summary.healthDays == 2, "Health-Tage: \(summary.healthDays) statt 2")
        let restored = HealthActions.healthDay(on: yesterday, calendar: calendar, in: target)?.fact
        try check(restored?.steps == 9_100 && restored?.flights == 5 && restored?.restingHeartRate == 58, "Werte unvollständig")
        return "2 Tage mit Schritten und Ruhepuls"
    }

    private static func snapshotContainsTodayAndTomorrow() throws -> String {
        let context = ModelContext(try TagwerkStore.makeContainer(at: nil))
        let medication = Medication(name: "Widget", schedule: .daily([DoseTime(hour: 8), DoseTime(hour: 20)]), createdAt: .now.addingTimeInterval(-3 * 86_400))
        medication.startDate = .now.addingTimeInterval(-3 * 86_400)
        context.insert(medication)
        try context.save()
        let snapshot = MedicationSnapshotWriter.makeSnapshot(medications: [medication], calendar: calendar)
        try check(snapshot.doses.count == 4, "\(snapshot.doses.count) statt 4 Einnahmen")
        // Nur die Einnahmen vergleichen: Der Zeitstempel `writtenAt` verliert beim Kodieren
        // Sekundenbruchteile, die Einnahme-Zeiten sind ganze Minuten.
        let decoded = MedicationWidgetSnapshot.decode(try snapshot.encoded())
        try check(decoded?.doses == snapshot.doses, "Kodierung: Einnahmen weichen ab")
        return "4 Einnahmen (heute und morgen)"
    }

    /// Zwei Wochen nur Bankdrücken: Der Coach schlägt mehr Sätze vor, Übernehmen ändert den Plan,
    /// „Später“ blendet den Vorschlag aus.
    private static func coachFlow() throws -> String {
        let defaults = UserDefaults.standard
        let savedDismissals = defaults.object(forKey: "tagwerk.coach.dismissed")
        defer { defaults.set(savedDismissals, forKey: "tagwerk.coach.dismissed") }
        defaults.removeObject(forKey: "tagwerk.coach.dismissed")

        let context = ModelContext(try TagwerkStore.makeContainer(at: nil))
        guard TrainingActions.ensureStarterPlan(in: context) != nil else { throw Failure(description: "Kein Startplan") }
        let now = Date.now
        for weeksBack in 1...2 {
            guard let start = calendar.date(byAdding: .day, value: -7 * weeksBack, to: now) else { continue }
            let session = WorkoutSession(dayName: "Test", dayShortName: "T", dayIndex: 0, week: 1, isDeload: false, startedAt: start)
            session.endedAt = start.addingTimeInterval(3_600)
            context.insert(session)
            for index in 0..<4 {
                let set = SetLog(exerciseID: "bench-press-barbell", slot: 0, setIndex: index, kind: .working, weight: 80, reps: 8, targetRepMin: 6, targetRepMax: 8, targetRIR: 2, restSeconds: 120)
                set.isDone = true
                set.completedAt = start
                context.insert(set)
                set.session = session
            }
        }
        try context.save()

        let suggestions = CoachActions.suggestions(now: now, calendar: calendar, limit: 30, in: context)
        guard let add = suggestions.first(where: { $0.change == .addSet }) else {
            throw Failure(description: "Kein „Satz dazu“: \(suggestions.map(\.title))")
        }
        let id = add.planItemID
        let before = try context.fetch(FetchDescriptor<PlanExercise>(predicate: #Predicate { $0.stableID == id })).first?.sets ?? 0
        try check(CoachActions.apply(add, in: context), "Übernehmen fehlgeschlagen")
        let after = try context.fetch(FetchDescriptor<PlanExercise>(predicate: #Predicate { $0.stableID == id })).first?.sets ?? 0
        try check(after == before + 1, "Sätze \(before) → \(after)")

        let remaining = CoachActions.suggestions(now: now, calendar: calendar, limit: 30, in: context)
        guard let other = remaining.first else { return "Satz dazu übernommen, keine weiteren Vorschläge" }
        CoachActions.dismiss(other, now: now)
        let afterDismiss = CoachActions.suggestions(now: now, calendar: calendar, limit: 30, in: context)
        try check(!afterDismiss.contains { $0.id == other.id }, "„Später“ wirkt nicht")
        return "\(suggestions.count) Vorschläge, „\(add.title)“ übernommen"
    }

    /// Ein paar Einträge in diesem Monat: Rückblick zählt sie, Tabellen enthalten sie, ZIP entsteht.
    private static func reviewAndExportFlow() throws -> String {
        let context = ModelContext(try TagwerkStore.makeContainer(at: nil))
        let now = Date.now
        let noon = calendar.startOfDay(for: now).addingTimeInterval(12 * 3_600)
        let moment = min(noon, now.addingTimeInterval(-60))
        NutritionActions.addMeal(type: .lunch, date: moment, items: [(foodID: "reis", grams: 70)], catalog: NutritionActions.catalog(in: context), in: context)
        NutritionActions.addSymptom(.headache, severity: 2, date: moment, in: context)
        DiaryActions.addPain(PainFact(date: moment, regions: [.kneeLeft], intensity: 5, triggers: [.training]), in: context)
        DiaryActions.addActivity(ActivityFact(date: moment, kind: .cycling, minutes: 45, intensity: .moderate, note: "Arbeitsweg; zurück"), in: context)
        InsightsActions.set(.mood, 4, on: now, calendar: calendar, in: context)
        try context.save()

        let start = ReviewPeriod.month.interval(containing: now, calendar: calendar).start
        let review = ReviewActions.review(.month, start: start, now: now, calendar: calendar, in: context)
        let ids = Set(review.lines.map(\.id))
        try check(ids.isSuperset(of: ["activity", "symptoms", "pain", "mood"]), "Rückblick-Zeilen: \(ids.sorted())")

        let tables = ExportActions.doctorTables(from: start, to: now.addingTimeInterval(60), calendar: calendar, in: context)
        let counts = Dictionary(uniqueKeysWithValues: tables.map { ($0.name, $0.rows.count) })
        try check(counts["Mahlzeiten"] == 1 && counts["Beschwerden"] == 1 && counts["Schmerzen"] == 1 && counts["Bewegung"] == 1, "Zeilen: \(counts)")
        let activity = String(decoding: tables.first { $0.name == "Bewegung" }?.data ?? Data(), as: UTF8.self)
        try check(activity.contains("\"Arbeitsweg; zurück\""), "Semikolon in der Notiz nicht geschützt")
        try check(ExportActions.allTables(calendar: calendar, in: context).count == 10, "Nicht alle Tabellen")

        let zip = try ExportActions.zip(files: tables.map { (name: $0.fileName, data: $0.data) }, folderName: "Orbit-Test")
        let data = try Data(contentsOf: zip)
        try check(data.count > 100 && data.prefix(2) == Data([0x50, 0x4B]), "Kein ZIP (\(data.count) Bytes)")
        return "\(review.lines.count) Rückblick-Zeilen, \(tables.count) Tabellen, ZIP \(data.count / 1_024 + 1) KB"
    }

    /// Morgen-Briefing aus Aufgaben und Einnahmen von morgen, offene Aufgaben wandern auf morgen.
    private static func planningFlow() throws -> String {
        let context = ModelContext(try TagwerkStore.makeContainer(at: nil))
        let now = Date.now
        let today = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { throw Failure(description: "Kein Morgen") }
        let medication = Medication(name: "Briefing", schedule: .daily([DoseTime(hour: 8)]), startDate: today.addingTimeInterval(-86_400), createdAt: today.addingTimeInterval(-86_400))
        context.insert(medication)
        context.insert(TaskItem(title: "Heute offen", dueDate: today, hasDueTime: false))
        context.insert(TaskItem(title: "Morgen fällig", dueDate: tomorrow, hasDueTime: false))
        try context.save()

        let facts = PlanningActions.briefingFacts(for: tomorrow, calendar: calendar, in: context)
        try check(facts.doses == 1 && facts.dueTasks >= 1, "Briefing: \(facts.doses) Einnahmen, \(facts.dueTasks) Aufgaben")
        let body = MorningBriefing.body(facts, calendar: calendar)
        try check(body.contains("Einnahme ab 08:00"), "Briefing-Text: \(body)")

        let open = PlanningActions.openToday(now: now, calendar: calendar, in: context)
        try check(open.map(\.title) == ["Heute offen"], "Offen heute: \(open.map(\.title))")
        try check(PlanningActions.moveAllToTomorrow(now: now, calendar: calendar, in: context) == 1, "Nicht verschoben")
        try check(PlanningActions.openToday(now: now, calendar: calendar, in: context).isEmpty, "Noch offen nach dem Verschieben")
        return body
    }

    /// Kein Eintrag im Verzeichnis ohne Ziel (sonst täte das Antippen nichts).
    private static func featureDirectoryRoutes() throws -> String {
        let missing = FeatureIndex.all.filter { FeatureDestination.of($0.id) == nil }.map(\.id)
        try check(missing.isEmpty, "Ohne Ziel: \(missing.joined(separator: ", "))")
        return "\(FeatureIndex.all.count) Funktionen in \(FeatureIndex.grouped.count) Bereichen"
    }

    /// Die Anordnung auf „Heute“ übersteht Speichern und Laden (wie über @AppStorage).
    private static func todayLayoutStorage() throws -> String {
        let defaults = UserDefaults(suiteName: "tagwerk.selftest.\(UUID().uuidString)")!
        var layout = TodayLayout.standard
        layout.setVisible(.nutrition, false)
        layout.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        defaults.set(layout.encoded, forKey: SettingsKeys.todayLayout)
        let loaded = TodayLayout.decode(defaults.string(forKey: SettingsKeys.todayLayout) ?? "")
        try check(loaded == layout, "Anordnung nach dem Laden anders")
        try check(SettingsKeys.backedUp.contains(SettingsKeys.todayLayout), "Anordnung nicht in der Sicherung")
        return "\(loaded.visibleCards.count) von \(TodayCard.allCases.count) Karten sichtbar"
    }

    /// Erinnerungen werden zu Aufgaben in gleichnamigen Listen, ein zweiter Import legt nichts doppelt an.
    private static func reminderImportFlow() throws -> String {
        let context = ModelContext(try TagwerkStore.makeContainer(at: nil))
        let reminders = [
            ExternalReminder(id: "a", title: "Zahnarzt anrufen", listName: "Privat", due: DateComponents(year: 2026, month: 11, day: 2, hour: 9), priority: 1),
            ExternalReminder(id: "b", title: "Müll rausbringen", listName: "Haushalt", frequency: .weekly, weekdays: [2]),
            ExternalReminder(id: "c", title: "Alt", listName: "Haushalt", isCompleted: true, completedAt: .now.addingTimeInterval(-86_400)),
        ]
        let importer = ReminderImporter()
        let first = importer.importReminders(reminders, includeCompleted: false, calendar: calendar, in: context)
        try check(first.imported == 2 && first.lists == 2 && first.skipped == 1, "Erster Import: \(first)")
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        let dentist = tasks.first { $0.title == "Zahnarzt anrufen" }
        try check(dentist?.list?.name == "Privat" && dentist?.priority == 3 && dentist?.hasDueTime == true, "Zahnarzt falsch übernommen")
        try check(tasks.first { $0.title == "Müll rausbringen" }?.recurrence?.frequency == .weekly, "Wiederholung fehlt")
        let second = importer.importReminders(reminders, includeCompleted: true, calendar: calendar, in: context)
        try check(second.imported == 1 && second.skipped == 2, "Zweiter Import: \(second)")
        try check(try context.fetchCount(FetchDescriptor<TaskItem>()) == 3, "Doppelte Aufgaben")
        try check(try context.fetchCount(FetchDescriptor<TaskList>()) == 2, "Doppelte Listen")
        return "2 Listen, 3 Aufgaben, nichts doppelt"
    }

    /// Ordner merken, Sicherung hineinkopieren, alte Stände aufräumen. Stellt die echten Einstellungen wieder her.
    private static func externalBackupFlow() throws -> String {
        let defaults = UserDefaults.standard
        let keys = ["tagwerk.backup.externalBookmark", "tagwerk.backup.externalName", "tagwerk.backup.externalLastAt", "tagwerk.backup.externalError"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) }
        }

        let source = try temporaryFolder()
        let target = try temporaryFolder()
        try ExternalBackup.setFolder(target)
        try check(ExternalBackup.isConfigured && ExternalBackup.folderName == target.lastPathComponent, "Ordner nicht gemerkt")
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        for index in 0..<16 {
            let date = start.addingTimeInterval(Double(index) * 86_400)
            let file = source.appendingPathComponent(BackupCodec.fileName(for: date, calendar: calendar))
            try Data("{}".utf8).write(to: file)
            try check(ExternalBackup.copy(file, now: date), "Kopie \(index + 1): \(ExternalBackup.lastError ?? "?")")
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: target.path).filter(BackupCodec.isBackupFileName)
        try check(names.count == BackupService.keepCount, "\(names.count) statt \(BackupService.keepCount) Sicherungen im Ordner")
        try check(ExternalBackup.lastCopy != nil && ExternalBackup.lastError == nil, "Letzte Kopie nicht gemerkt")
        ExternalBackup.remove()
        try check(!ExternalBackup.isConfigured, "Ordner nicht entfernt")
        return "16 Kopien, 14 behalten"
    }
}

/// Zeigt die Ergebnisse des Selbsttests (nur im CI).
struct SelfTestView: View {
    @State private var results: [SelfTest.Result] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(summary)
                        .font(.headline)
                        .accessibilityIdentifier("selftest.summary")
                }
                ForEach(results) { result in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(result.name, systemImage: result.passed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(result.passed ? Color.green : Color.red)
                        Text(result.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Selbsttest")
        }
        .onAppear {
            if results.isEmpty { results = SelfTest.runAll() }
        }
    }

    private var summary: String {
        if results.isEmpty { return "Läuft …" }
        let failed = results.filter { !$0.passed }
        return failed.isEmpty
            ? "Alle \(results.count) Prüfungen bestanden"
            : "Fehlgeschlagen: \(failed.map { "\($0.name) (\($0.detail))" }.joined(separator: ", "))"
    }
}
