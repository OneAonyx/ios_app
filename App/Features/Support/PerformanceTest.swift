import Foundation
import PDFKit
import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Tempo-Test für das CI (Startoption `-perfTest`): legt zwei Jahre typische Daten an
/// (Mahlzeiten, Einnahmen, Training, Tagebuch, Aufgaben) und misst die wichtigsten Auswertungen.
/// Läuft nur mit einem Wegwerf-Speicher in einem temporären Ordner.
@MainActor
enum PerformanceTest {
    struct Measurement: Identifiable {
        let name: String
        let milliseconds: Int
        /// Obergrenze im Simulator, `nil` = nur messen.
        let budget: Int?
        let detail: String
        var id: String { name }

        var passed: Bool { budget.map { milliseconds <= $0 } ?? true }

        /// Eine Zeile fürs CI-Log.
        var line: String {
            let limit = budget.map { " (Grenze \($0) ms)" } ?? ""
            return "TEMPO: \(name): \(milliseconds) ms\(limit) – \(detail)"
        }
    }

    struct Step {
        let name: String
        let budget: Int?
        let body: () throws -> String
    }

    static let days = 730
    private static var calendar: Calendar { AppModel.calendar }

    /// Misst einen Schritt. Fehler zählen als nicht bestanden.
    static func measure(_ step: Step) -> Measurement {
        let clock = ContinuousClock()
        var detail = ""
        var failed = false
        let duration = clock.measure {
            do {
                detail = try step.body()
            } catch {
                detail = "Fehler: \(error)"
                failed = true
            }
        }
        let milliseconds = Int(duration.components.seconds * 1_000) + Int(duration.components.attoseconds / 1_000_000_000_000_000)
        return Measurement(name: step.name, milliseconds: milliseconds, budget: failed ? -1 : step.budget, detail: detail)
    }

    /// Alle Schritte in fester Reihenfolge. Der erste legt die Daten an.
    static func steps(now: Date = .now) throws -> [Step] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("perftest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "tagwerk.perftest.\(UUID().uuidString)")!
        let context = ModelContext(try TagwerkStore.makeContainer(at: folder.appendingPathComponent("Tempo.store"), defaults: defaults))
        context.autosaveEnabled = false
        let today = calendar.startOfDay(for: now)
        let from90 = calendar.date(byAdding: .day, value: -89, to: today) ?? today
        var report: DoctorReport?
        var backupFile: URL?

        return [
            Step(name: "Zwei Jahre Daten anlegen", budget: nil) {
                try seed(context, now: now)
            },
            Step(name: "Tagebuch heute", budget: 400) {
                let facts = DiaryActions.today(now: now, calendar: calendar, in: context)
                return "\(facts.meals) Mahlzeiten, \(facts.dosesDue) Einnahmen fällig"
            },
            Step(name: "Tagebuch 90 Tage", budget: 2_500) {
                let facts = DiaryActions.dayFacts(from: from90, to: now, now: now, calendar: calendar, in: context)
                let complete = facts.filter { DiaryCheck.items($0).allSatisfy(\.isDone) }.count
                return "\(facts.count) Tage, \(complete) vollständig"
            },
            Step(name: "Arztbericht 90 Tage", budget: 5_000) {
                let made = InsightsActions.doctorReport(from: from90, to: now, name: "Tempo", now: now, calendar: calendar, in: context)
                report = made
                return "\(made.symptomLog.count) Beschwerden, \(made.diary.count) Tageszeilen"
            },
            Step(name: "Arztbericht als PDF", budget: 8_000) {
                guard let report, let url = DoctorReportPDF.render(report, calendar: calendar), let document = PDFDocument(url: url) else {
                    throw SelfTest.Failure(description: "PDF nicht erstellt")
                }
                return "\(document.pageCount) Seiten"
            },
            Step(name: "Wochenrückblick", budget: 1_500) {
                let review = InsightsActions.weeklyReview(weekStart: AgendaBuilder.startOfWeek(containing: now, calendar: calendar), now: now, calendar: calendar, in: context)
                return review.isEmpty ? "leer" : "\(review.plainText.count) Zeichen"
            },
            Step(name: "Auslöser-Analyse 90 Tage", budget: 3_000) {
                let analysis = NutritionActions.triggerReport(days: 90, now: now, in: context)
                return "\(analysis.findings.count) Auffälligkeiten"
            },
            Step(name: "Ernährung heute", budget: 400) {
                let day = NutritionActions.day(now, calendar: calendar, in: context)
                return "Tageslast \(day.load.points)"
            },
            Step(name: "Wochenvolumen Training", budget: 800) {
                let volume = TrainingActions.weeklyVolume(containing: now, catalog: TrainingActions.catalog(in: context), calendar: calendar, in: context)
                return "\(volume.count) Muskeln"
            },
            Step(name: "Kraftverlauf einer Übung", budget: 800) {
                let id = exerciseIDs(context).first ?? ""
                return "\(TrainingActions.history(for: id, limit: 30, in: context).count) Einheiten"
            },
            Step(name: "Aufgaben: Liste „Heute“", budget: 800) {
                let tasks = try context.fetch(FetchDescriptor<TaskItem>())
                let today = tasks.filter { SmartList.today.includes($0.facts, now: now, calendar: calendar) }
                return "\(today.count) von \(tasks.count)"
            },
            Step(name: "Einnahmen heute", budget: 600) {
                let entries = MedicationActions.fetchAll(in: context).flatMap { $0.entries(on: now, now: now, calendar: calendar) }
                return "\(entries.count) Einnahmen"
            },
            Step(name: "Erinnerungen planen", budget: 2_000) {
                let candidates = ReminderScheduler.taskCandidates(context: context, calendar: calendar)
                    + ReminderScheduler.medicationCandidates(context: context, now: now, calendar: calendar, alarmsActive: false)
                    + TrainingActions.reminderCandidates(now: now, calendar: calendar, in: context)
                    + LifeActions.reminderCandidates(now: now, calendar: calendar, in: context)
                    + DiaryActions.reminderCandidates(now: now, calendar: calendar, in: context)
                let planned = ReminderPlanner.plan(candidates, now: now, horizon: ReminderScheduler.horizon)
                return "\(planned.count) von \(candidates.count) geplant"
            },
            Step(name: "Sicherung schreiben (Hintergrund)", budget: 12_000) {
                // Wie die tägliche Sicherung: eigener Kontext auf einem anderen Thread.
                let container = context.container
                let file = folder.appendingPathComponent("tempo-backup.json")
                let outcome = BackgroundOutcome()
                let done = DispatchSemaphore(value: 0)
                DispatchQueue.global(qos: .utility).async {
                    do {
                        let background = ModelContext(container)
                        let data = try BackupCodec.encode(try BackupService.makeDocument(context: background, now: now))
                        try data.write(to: file)
                        outcome.text = "\(data.count / 1_024) KB, nicht auf dem Hauptthread"
                    } catch {
                        outcome.failure = "\(error)"
                    }
                    done.signal()
                }
                done.wait()
                if let failure = outcome.failure { throw SelfTest.Failure(description: failure) }
                backupFile = file
                return outcome.text
            },
            Step(name: "Sicherung wiederherstellen", budget: 40_000) {
                guard let backupFile else { throw SelfTest.Failure(description: "Keine Sicherung") }
                let target = ModelContext(try TagwerkStore.makeContainer(at: nil))
                let summary = try BackupService.restore(from: backupFile, context: target, now: now, calendar: calendar)
                return "\(summary.tasks) Aufgaben, \(summary.meals) Mahlzeiten, \(summary.workouts) Einheiten"
            },
        ]
    }

    /// Ergebnis aus dem Hintergrund-Thread.
    private final class BackgroundOutcome: @unchecked Sendable {
        var text = ""
        var failure: String?
    }

    private static func exerciseIDs(_ context: ModelContext) -> [String] {
        TrainingActions.catalog(in: context).exercises.filter(\.isCompound).prefix(6).map(\.id)
    }

    /// Zwei Jahre Alltag: 3 Mahlzeiten, 4 Gläser Wasser, 3 Einnahmen, Check-in und Schritte am Tag,
    /// Gym 5× die Woche, Beschwerden, Schmerzen und Bewegung in festen Abständen, 1.500 Aufgaben.
    private static func seed(_ context: ModelContext, now: Date) throws -> String {
        let today = calendar.startOfDay(for: now)
        let foods = NutritionActions.catalog(in: context)
        let foodIDs = ["haehnchenbrust", "reis", "nudeln", "tomate", "kartoffel", "brokkoli", "haferflocken", "apfel", "ei", "zucchini"]
        let exercises = exerciseIDs(context)
        var objects = 0

        let lists = (0..<6).map { TaskList(name: "Liste \($0 + 1)", sortIndex: Double($0)) }
        lists.forEach { context.insert($0) }
        for index in 0..<1_500 {
            let created = today.addingTimeInterval(-Double(index % days) * 86_400)
            let task = TaskItem(title: "Aufgabe \(index)", dueDate: created.addingTimeInterval(2 * 86_400), priority: index % 4, sortIndex: Double(index), createdAt: created)
            context.insert(task)
            task.list = lists[index % lists.count]
            if index >= 300 {
                task.isDone = true
                task.completedAt = created.addingTimeInterval(86_400)
            }
            objects += 1
        }

        let start = today.addingTimeInterval(-Double(days + 1) * 86_400)
        let twice = Medication(name: "Tablette", schedule: .daily([DoseTime(hour: 8), DoseTime(hour: 20)]), startDate: start, createdAt: start)
        let noon = Medication(name: "DAO", schedule: .daily([DoseTime(hour: 12)]), startDate: start, sortIndex: 1, createdAt: start)
        let asNeeded = Medication(name: "Bei Bedarf", schedule: .asNeeded(maxPerDay: 3, minGapHours: 4), startDate: start, sortIndex: 2, createdAt: start)
        [twice, noon, asNeeded].forEach { context.insert($0) }
        try context.save()

        for offset in 1...days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            func at(_ hour: Double) -> Date { day.addingTimeInterval(hour * 3_600) }

            for (medication, hour) in [(twice, 8.0), (twice, 20.0), (noon, 12.0)] {
                let skipped = offset % 20 == 0
                let log = DoseLog(scheduledAt: at(hour), takenAt: skipped ? nil : at(hour + 0.1), status: skipped ? .skipped : .taken, amount: 1, createdAt: at(hour + 0.1))
                context.insert(log)
                log.medication = medication
                objects += 1
            }
            if offset % 5 == 0 {
                let log = DoseLog(scheduledAt: nil, takenAt: at(15), status: .taken, amount: 1, createdAt: at(15))
                context.insert(log)
                log.medication = asNeeded
                objects += 1
            }

            for (slot, type) in [(8.0, MealType.breakfast), (13.0, .lunch), (19.0, .dinner)] {
                let meal = MealEntry(date: at(slot), type: type)
                context.insert(meal)
                for position in 0..<3 {
                    let id = foodIDs[(offset + position * 3 + Int(slot)) % foodIDs.count]
                    let item = MealItem(foodID: id, name: foods.name(for: id), grams: 120, position: position)
                    context.insert(item)
                    item.meal = meal
                }
                objects += 4
            }
            for glass in 0..<4 {
                context.insert(WaterLog(date: at(9 + Double(glass) * 3), milliliters: 250))
                objects += 1
            }
            if offset % 3 == 0 {
                context.insert(SymptomEntry(date: at(15), type: .headache, severity: 2))
                objects += 1
            }
            if offset % 4 == 0 {
                context.insert(PainEntry(date: at(18), regions: [.kneeLeft], intensity: 4))
                objects += 1
            }
            if offset % 7 == 1 || offset % 7 == 3 {
                context.insert(ActivityEntry(date: at(10), kind: .walking, minutes: 40, intensity: .moderate))
                objects += 1
            }

            let checkIn = DailyCheckIn(day: day)
            checkIn.sleep = 3
            checkIn.sleepHours = 7.2
            checkIn.mood = 4
            checkIn.energy = 3
            checkIn.stress = 2
            context.insert(checkIn)
            let health = HealthDay(day: day)
            health.steps = 6_000 + (offset * 137) % 5_000
            context.insert(health)
            objects += 2

            if offset % 3 == 0 {
                context.insert(BodyMetric(date: at(7), type: .weight, value: 82 + Double(offset % 10) / 10))
                objects += 1
            }

            if offset % 7 != 3 && offset % 7 != 6, !exercises.isEmpty {
                let session = WorkoutSession(dayName: "Tag \(offset % 4 + 1)", dayShortName: "T\(offset % 4 + 1)", dayIndex: offset % 4, week: 1, isDeload: false, startedAt: at(17))
                session.endedAt = at(18.2)
                context.insert(session)
                for (slot, exercise) in exercises.enumerated() {
                    for setIndex in 0..<4 {
                        let set = SetLog(exerciseID: exercise, slot: slot, setIndex: setIndex, kind: .working, weight: 60 + Double(slot * 5), reps: 8, targetRepMin: 6, targetRepMax: 10, targetRIR: 2, restSeconds: 120)
                        set.isDone = true
                        set.rir = 2
                        set.completedAt = at(17 + Double(slot) * 0.2)
                        context.insert(set)
                        set.session = session
                    }
                }
                objects += 1 + exercises.count * 4
            }

            if offset % 30 == 0 { try context.save() }
        }
        try context.save()
        return "\(GermanNumber.grouped(objects)) Einträge über \(days) Tage"
    }
}

/// Zeigt die Messwerte des Tempo-Tests (nur im CI).
struct PerformanceTestView: View {
    @State private var results: [PerformanceTest.Measurement] = []
    @State private var finished = false
    @State private var setupError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(summary)
                        .font(.headline)
                        .accessibilityIdentifier("perftest.summary")
                        // Alle Zeilen fürs CI-Log, auch die außerhalb des Bildschirms.
                        .accessibilityValue(results.map(\.line).joined(separator: "\n"))
                }
                ForEach(results) { result in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Label(result.name, systemImage: result.passed ? "checkmark.circle.fill" : "tortoise.fill")
                                .foregroundStyle(result.passed ? Color.green : Color.red)
                            Spacer()
                            Text("\(result.milliseconds) ms")
                                .font(.subheadline.monospacedDigit())
                        }
                        Text(result.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(result.line)
                    .accessibilityIdentifier("perftest.result")
                }
            }
            .navigationTitle("Tempo-Test")
        }
        .task {
            guard results.isEmpty else { return }
            do {
                for step in try PerformanceTest.steps() {
                    // Kurz Luft holen, damit die Liste zwischendurch zeichnet.
                    try? await Task.sleep(for: .milliseconds(50))
                    results.append(PerformanceTest.measure(step))
                }
            } catch {
                setupError = "\(error)"
            }
            finished = true
        }
    }

    private var summary: String {
        if let setupError { return "Fehlgeschlagen: \(setupError)" }
        guard finished else { return "Läuft … (\(results.count) Messungen)" }
        let slow = results.filter { !$0.passed }
        return slow.isEmpty
            ? "Alle \(results.count) Messungen im Rahmen"
            : "Fehlgeschlagen: \(slow.map { "\($0.name) \($0.milliseconds) ms" }.joined(separator: ", "))"
    }
}
