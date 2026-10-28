import Foundation
import SwiftData
import TagwerkCore

/// Tabellen (CSV) für das Arzt-Paket und den Export aller Daten.
@MainActor
public enum ExportActions {
    /// Was der Arzt Tag für Tag sehen will: Essen, Beschwerden, Schmerzen, Einnahmen, Bewegung, Tageswerte.
    public static func doctorTables(from start: Date, to end: Date, calendar: Calendar, in context: ModelContext) -> [CSVTable] {
        [
            meals(from: start, to: end, calendar: calendar, in: context),
            symptoms(from: start, to: end, calendar: calendar, in: context),
            pains(from: start, to: end, calendar: calendar, in: context),
            doses(from: start, to: end, calendar: calendar, in: context),
            activities(from: start, to: end, calendar: calendar, in: context),
            dailyValues(from: start, to: end, calendar: calendar, in: context),
        ]
    }

    /// Alle Daten als Tabellen (zusätzlich Aufgaben, Training, Körperwerte, Routinen).
    public static func allTables(calendar: Calendar, in context: ModelContext) -> [CSVTable] {
        let start = Date.distantPast
        let end = Date.distantFuture
        return doctorTables(from: start, to: end, calendar: calendar, in: context) + [
            tasks(calendar: calendar, in: context),
            trainingSets(calendar: calendar, in: context),
            bodyMetrics(calendar: calendar, in: context),
            habitLogs(calendar: calendar, in: context),
        ]
    }

    // MARK: Tabellen

    static func meals(from start: Date, to end: Date, calendar: Calendar, in context: ModelContext) -> CSVTable {
        let rows = NutritionActions.meals(from: start, to: end, in: context).sorted { $0.date < $1.date }.map { meal -> [String] in
            let items = meal.sortedItems.map { "\($0.name) \(CSVFormat.number($0.grams)) g" }.joined(separator: ", ")
            return [
                CSVFormat.date(meal.date, calendar: calendar), CSVFormat.time(meal.date, calendar: calendar),
                meal.type.title, items, meal.freshness.title, meal.place.title, meal.note,
            ]
        }
        return CSVTable(name: "Mahlzeiten", header: ["Datum", "Uhrzeit", "Mahlzeit", "Lebensmittel", "Frische", "Ort", "Notiz"], rows: rows)
    }

    static func symptoms(from start: Date, to end: Date, calendar: Calendar, in context: ModelContext) -> CSVTable {
        let rows = NutritionActions.symptoms(from: start, to: end, in: context).sorted { $0.date < $1.date }.map { entry -> [String] in
            [
                CSVFormat.date(entry.date, calendar: calendar), CSVFormat.time(entry.date, calendar: calendar),
                entry.type.title, String(entry.severity), CSVFormat.int(entry.durationMinutes), entry.note,
            ]
        }
        return CSVTable(name: "Beschwerden", header: ["Datum", "Uhrzeit", "Beschwerde", "Stärke (1–5)", "Dauer (Min.)", "Notiz"], rows: rows)
    }

    static func pains(from start: Date, to end: Date, calendar: Calendar, in context: ModelContext) -> CSVTable {
        let rows = DiaryActions.pains(from: start, to: end, in: context).map(\.fact).sorted { $0.date < $1.date }.map { fact -> [String] in
            [
                CSVFormat.date(fact.date, calendar: calendar), CSVFormat.time(fact.date, calendar: calendar),
                fact.regions.map(\.title).joined(separator: ", "), String(fact.intensity),
                fact.qualities.map(\.title).joined(separator: ", "), CSVFormat.int(fact.durationMinutes),
                fact.triggers.map(\.title).joined(separator: ", "), fact.reliefs.map(\.title).joined(separator: ", "), fact.note,
            ]
        }
        return CSVTable(
            name: "Schmerzen",
            header: ["Datum", "Uhrzeit", "Stelle", "Stärke (0–10)", "Art", "Dauer (Min.)", "Möglicher Auslöser", "Was half", "Notiz"],
            rows: rows
        )
    }

    static func doses(from start: Date, to end: Date, calendar: Calendar, in context: ModelContext) -> CSVTable {
        var rows: [(Date, [String])] = []
        for medication in MedicationActions.fetchAll(in: context) {
            for log in medication.logsInRange(from: start, to: end) {
                let sortDate = log.takenAt ?? log.scheduledAt ?? log.createdAt
                rows.append((sortDate, [
                    CSVFormat.date(sortDate, calendar: calendar), CSVFormat.optionalTime(log.scheduledAt, calendar: calendar),
                    CSVFormat.optionalTime(log.takenAt, calendar: calendar), medication.displayName,
                    log.status == .taken ? (log.scheduledAt == nil ? "bei Bedarf genommen" : "genommen") : "ausgelassen",
                    CSVFormat.number(log.amount), log.note,
                ]))
            }
        }
        return CSVTable(
            name: "Einnahmen",
            header: ["Datum", "Geplant", "Genommen", "Medikament", "Status", "Menge", "Notiz"],
            rows: rows.sorted { $0.0 < $1.0 }.map(\.1)
        )
    }

    static func activities(from start: Date, to end: Date, calendar: Calendar, in context: ModelContext) -> CSVTable {
        let rows = DiaryActions.activityFacts(from: start, to: end, in: context).map { fact -> [String] in
            [
                CSVFormat.date(fact.date, calendar: calendar), CSVFormat.time(fact.date, calendar: calendar),
                fact.kind.title, String(fact.minutes), fact.intensity.title, fact.note,
            ]
        }
        return CSVTable(name: "Bewegung", header: ["Datum", "Uhrzeit", "Art", "Minuten", "Anstrengung", "Notiz"], rows: rows)
    }

    /// Ein Tag je Zeile: Schritte und Ruhepuls aus Health, Schlaf und Befinden aus dem Check-in.
    static func dailyValues(from start: Date, to end: Date, calendar: Calendar, in context: ModelContext) -> CSVTable {
        let health = Dictionary(HealthActions.facts(from: start, to: end, in: context).map { (calendar.startOfDay(for: $0.day), $0) }, uniquingKeysWith: { lhs, _ in lhs })
        let checkIns = Dictionary(InsightsActions.checkIns(from: start, to: end, in: context).map { (calendar.startOfDay(for: $0.day), $0.fact) }, uniquingKeysWith: { lhs, _ in lhs })
        let days = Set(health.keys).union(checkIns.keys).sorted()
        let rows = days.map { day -> [String] in
            let h = health[day]
            let c = checkIns[day]
            return [
                CSVFormat.date(day, calendar: calendar), CSVFormat.int(h?.steps), CSVFormat.number(c?.sleepHours ?? h?.sleepHours),
                CSVFormat.int(c?.sleep), CSVFormat.int(c?.energy), CSVFormat.int(c?.mood), CSVFormat.int(c?.stress),
                CSVFormat.int(h?.restingHeartRate), c?.note ?? "",
            ]
        }
        return CSVTable(
            name: "Tageswerte",
            header: ["Datum", "Schritte", "Schlaf (Std.)", "Schlafgefühl (1–5)", "Energie (1–5)", "Stimmung (1–5)", "Stress (1–5)", "Ruhepuls", "Notiz"],
            rows: rows
        )
    }

    static func tasks(calendar: Calendar, in context: ModelContext) -> CSVTable {
        let all = ((try? context.fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.createdAt)]))) ?? [])
        let rows = all.map { task -> [String] in
            [
                task.title, task.list?.name ?? "Eingang", CSVFormat.optionalDate(task.dueDate, calendar: calendar),
                task.hasDueTime ? CSVFormat.optionalTime(task.dueDate, calendar: calendar) : "",
                CSVFormat.bool(task.isDone), CSVFormat.optionalDate(task.completedAt, calendar: calendar),
                String(task.priority), task.notes,
            ]
        }
        return CSVTable(name: "Aufgaben", header: ["Titel", "Liste", "Fällig", "Uhrzeit", "Erledigt", "Erledigt am", "Priorität (0–3)", "Notizen"], rows: rows)
    }

    static func trainingSets(calendar: Calendar, in context: ModelContext) -> CSVTable {
        let catalog = TrainingActions.catalog(in: context)
        let sessions = TrainingActions.finishedSessions(in: context).sorted { $0.startedAt < $1.startedAt }
        let rows = sessions.flatMap { session in
            session.sortedSets.filter(\.isDone).map { set -> [String] in
                [
                    CSVFormat.date(session.startedAt, calendar: calendar), session.dayName, catalog.name(for: set.exerciseID),
                    String(set.setIndex + 1), set.kind == .warmup ? "Aufwärmen" : "Arbeit",
                    CSVFormat.number(set.weight), String(set.reps), CSVFormat.int(set.rir),
                ]
            }
        }
        return CSVTable(name: "Training", header: ["Datum", "Einheit", "Übung", "Satz", "Art", "Gewicht (kg)", "Wiederholungen", "RIR"], rows: rows)
    }

    static func bodyMetrics(calendar: Calendar, in context: ModelContext) -> CSVTable {
        let all = ((try? context.fetch(FetchDescriptor<BodyMetric>(sortBy: [SortDescriptor(\.date)]))) ?? [])
        let rows = all.map { metric -> [String] in
            [CSVFormat.date(metric.date, calendar: calendar), metric.type.title, CSVFormat.number(metric.value), metric.note]
        }
        return CSVTable(name: "Koerperwerte", header: ["Datum", "Art", "Wert", "Notiz"], rows: rows)
    }

    static func habitLogs(calendar: Calendar, in context: ModelContext) -> CSVTable {
        let names = Dictionary(LifeActions.habits(includeArchived: true, in: context).map { ($0.stableID, $0.name) }, uniquingKeysWith: { lhs, _ in lhs })
        let logs = ((try? context.fetch(FetchDescriptor<HabitLog>(sortBy: [SortDescriptor(\.day)]))) ?? [])
        let rows = logs.map { log -> [String] in
            [CSVFormat.date(log.day, calendar: calendar), names[log.habitID] ?? "gelöscht", CSVFormat.number(log.value)]
        }
        return CSVTable(name: "Routinen", header: ["Datum", "Routine", "Wert"], rows: rows)
    }

    // MARK: Paket

    /// Legt die Dateien in einen Ordner und packt ihn als ZIP (Bordmittel: `NSFileCoordinator` mit `.forUploading`).
    nonisolated public static func zip(files: [(name: String, data: Data)], folderName: String) throws -> URL {
        let manager = FileManager.default
        let base = manager.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)", isDirectory: true)
        let folder = base.appendingPathComponent(folderName, isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        for file in files {
            try file.data.write(to: folder.appendingPathComponent(file.name))
        }
        var coordinationError: NSError?
        var copyError: Error?
        var result: URL?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: [.forUploading], error: &coordinationError) { zipped in
            let target = base.appendingPathComponent("\(folderName).zip")
            do {
                try manager.copyItem(at: zipped, to: target)
                result = target
            } catch {
                copyError = error
            }
        }
        if let error = coordinationError ?? copyError { throw error }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        return result
    }
}
