import Foundation
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
            run("Migration V1 → V2", migrationKeepsTasks),
            run("Einnahmen und Vorrat", doseActionsAdjustStock),
            run("Nachschub-Aufgabe", refillTaskOnlyOnce),
            run("Datensicherung mit Medikamenten", backupRoundTrip),
            run("Widget-Daten", snapshotContainsTodayAndTomorrow),
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
        let copy = folder.appendingPathComponent("Test-vor-v2.store")
        try check(FileManager.default.fileExists(atPath: copy.path), "Keine Kopie vor der Migration")
        try check(defaults.integer(forKey: "tagwerk.store.schemaVersion") == 2, "Schema-Version nicht gemerkt")
        return "3 Aufgaben übernommen, Kopie angelegt"
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

    private static func snapshotContainsTodayAndTomorrow() throws -> String {
        let context = ModelContext(try TagwerkStore.makeContainer(at: nil))
        let medication = Medication(name: "Widget", schedule: .daily([DoseTime(hour: 8), DoseTime(hour: 20)]), createdAt: .now.addingTimeInterval(-3 * 86_400))
        medication.startDate = .now.addingTimeInterval(-3 * 86_400)
        context.insert(medication)
        try context.save()
        let snapshot = MedicationSnapshotWriter.makeSnapshot(medications: [medication], calendar: calendar)
        try check(snapshot.doses.count == 4, "\(snapshot.doses.count) statt 4 Einnahmen")
        try check(MedicationWidgetSnapshot.decode(try snapshot.encoded()) == snapshot, "Kodierung")
        return "4 Einnahmen (heute und morgen)"
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
        return failed.isEmpty ? "Alle \(results.count) Prüfungen bestanden" : "Fehlgeschlagen: \(failed.map(\.name).joined(separator: ", "))"
    }
}
