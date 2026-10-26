import Foundation
import SwiftData
import TagwerkCore

/// Alle Änderungen an Medikamenten und am Einnahme-Protokoll an einer Stelle,
/// damit App, Mitteilungen, Wecker, Widgets und Siri dieselben Regeln nutzen.
///
/// Der Vorrat zählt automatisch mit: „genommen“ zieht ab, Rückgängig gibt zurück.
@MainActor
public enum MedicationActions {
    // MARK: Lesen

    public static func fetchAll(in context: ModelContext) -> [Medication] {
        let descriptor = FetchDescriptor<Medication>(sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.name)])
        return (try? context.fetch(descriptor)) ?? []
    }

    public static func fetch(stableID: String, in context: ModelContext) -> Medication? {
        var descriptor = FetchDescriptor<Medication>(predicate: #Predicate { $0.stableID == stableID })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    public static func nextSortIndex(in context: ModelContext) -> Double {
        (fetchAll(in: context).map(\.sortIndex).max() ?? 0) + 1
    }

    // MARK: Geplante Einnahmen

    /// Setzt den Status einer geplanten Einnahme. Mehrfaches Abhaken ändert nichts.
    public static func set(_ status: DoseStatus, for dose: ScheduledDose, medication: Medication, at moment: Date = .now, in context: ModelContext) {
        let existing = (medication.logs ?? []).first { $0.scheduledAt == dose.date }
        if let existing {
            guard existing.status != status else { return }
            if existing.status == .taken { adjustStock(medication, by: existing.amount) }
            existing.status = status
            existing.takenAt = status == .taken ? moment : nil
            existing.amount = dose.amount
        } else {
            let log = DoseLog(scheduledAt: dose.date, takenAt: status == .taken ? moment : nil, status: status, amount: dose.amount, createdAt: moment)
            context.insert(log)
            log.medication = medication
        }
        if status == .taken { adjustStock(medication, by: -dose.amount) }
        save(context)
        // Schon angezeigte Mitteilungen dieser Einnahme aus der Mitteilungszentrale nehmen.
        MedicationNotifications.removeNotifications(forDose: dose.id)
    }

    public static func take(_ entry: DoseEntry, medication: Medication, at moment: Date = .now, in context: ModelContext) {
        if let log = log(for: entry, in: medication), log.scheduledAt != entry.dose.date {
            // Eintrag stammt von einer früheren Uhrzeit: auf die aktuelle umziehen.
            log.scheduledAt = entry.dose.date
        }
        set(.taken, for: entry.dose, medication: medication, at: moment, in: context)
    }

    public static func skip(_ entry: DoseEntry, medication: Medication, in context: ModelContext) {
        if let log = log(for: entry, in: medication), log.scheduledAt != entry.dose.date {
            log.scheduledAt = entry.dose.date
        }
        set(.skipped, for: entry.dose, medication: medication, in: context)
    }

    /// Macht „genommen“ oder „ausgelassen“ rückgängig.
    public static func undo(_ entry: DoseEntry, medication: Medication, in context: ModelContext) {
        guard let log = log(for: entry, in: medication) else { return }
        delete(log, in: context)
    }

    /// Für Widget, Kontrollzentrum, Siri, Mitteilung und Wecker: Einnahme per `DoseID`.
    @discardableResult
    public static func record(doseID: String, status: DoseStatus, at moment: Date = .now, in context: ModelContext, calendar: Calendar) -> Bool {
        guard let parsed = DoseID.parse(doseID), let medication = fetch(stableID: parsed.medicationID, in: context) else {
            return false
        }
        let planned = medication.scheduledDoses(from: parsed.date, to: parsed.date.addingTimeInterval(1), calendar: calendar).first
        let dose = planned ?? ScheduledDose(medicationID: medication.stableID, date: parsed.date, amount: medication.defaultAmount)
        set(status, for: dose, medication: medication, at: moment, in: context)
        return true
    }

    /// Abhaken im Wechsel (Agenda, Woche): offen → genommen, sonst zurück auf offen.
    public static func toggleTaken(doseID: String, in context: ModelContext, calendar: Calendar) {
        guard let parsed = DoseID.parse(doseID), let medication = fetch(stableID: parsed.medicationID, in: context) else { return }
        let entry = medication.entries(from: parsed.date, to: parsed.date.addingTimeInterval(1), calendar: calendar).first
        if let entry, entry.isResolved {
            undo(entry, medication: medication, in: context)
        } else if let entry {
            take(entry, medication: medication, in: context)
        } else {
            record(doseID: doseID, status: .taken, in: context, calendar: calendar)
        }
    }

    // MARK: Bei Bedarf und Protokoll

    /// Einnahme ohne festen Termin (Bei Bedarf oder zusätzlich).
    @discardableResult
    public static func takeExtra(_ medication: Medication, amount: Double, at moment: Date = .now, note: String = "", in context: ModelContext) -> DoseLog {
        let log = DoseLog(scheduledAt: nil, takenAt: moment, status: .taken, amount: amount, note: note, createdAt: moment)
        context.insert(log)
        log.medication = medication
        adjustStock(medication, by: -amount)
        save(context)
        return log
    }

    /// Löscht einen Protokolleintrag. War er „genommen“, kommt die Menge zurück in den Vorrat.
    public static func delete(_ log: DoseLog, in context: ModelContext) {
        if log.status == .taken, let medication = log.medication {
            adjustStock(medication, by: log.amount)
        }
        context.delete(log)
        save(context)
    }

    // MARK: Vorrat

    /// Nachgefüllt: Vorrat erhöhen. Eine automatische Nachschub-Aufgabe gilt damit als erledigt.
    public static func refill(_ medication: Medication, adding amount: Double, in context: ModelContext) {
        medication.stock = max(0, (medication.stock ?? 0) + amount)
        if let taskID = medication.refillTaskID, let task = TaskActions.fetchTask(stableID: taskID, in: context), !task.isDone {
            task.isDone = true
            task.completedAt = .now
        }
        medication.refillTaskID = nil
        save(context)
    }

    static func adjustStock(_ medication: Medication, by delta: Double) {
        guard let stock = medication.stock else { return }
        medication.stock = max(0, stock + delta)
    }

    /// Legt für knappe Medikamente mit „Aufgabe anlegen“ eine Nachschub-Aufgabe an.
    /// Gibt die Anzahl neuer Aufgaben zurück.
    @discardableResult
    public static func ensureRefillTasks(in context: ModelContext, now: Date = .now, calendar: Calendar) -> Int {
        var created = 0
        for medication in fetchAll(in: context) where medication.isActive && medication.autoRefillTask && medication.refillTaskID == nil {
            guard let forecast = medication.forecast(now: now, calendar: calendar), forecast.needsRefill else { continue }
            let task = TaskItem(
                title: "Nachschub besorgen: \(medication.displayName)",
                notes: [medication.stockText.map { "Vorrat: \($0)" }, forecast.rangeLabel(calendar: calendar)]
                    .compactMap { $0 }
                    .joined(separator: " · "),
                dueDate: calendar.startOfDay(for: now),
                priority: 2,
                sortIndex: TaskActions.nextSortIndex(in: context),
                createdAt: now
            )
            context.insert(task)
            medication.refillTaskID = task.stableID
            created += 1
        }
        if created > 0 { save(context) }
        return created
    }

    // MARK: Verwalten

    public static func delete(_ medication: Medication, in context: ModelContext) {
        context.delete(medication)
        save(context)
    }

    public static func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            print("Tagwerk: Speichern fehlgeschlagen: \(error)")
        }
    }

    // MARK: Warteschlange (Widget, Kontrollzentrum)

    /// Übernimmt Einnahmen, die außerhalb der App abgehakt wurden. Gibt die Anzahl zurück.
    @discardableResult
    public static func processPendingActions(in context: ModelContext, calendar: Calendar) -> Int {
        let actions = DoseActionCenter.takeQueued()
        for action in actions {
            record(doseID: action.doseID, status: action.kind == .taken ? .taken : .skipped, at: action.at, in: context, calendar: calendar)
        }
        return actions.count
    }

    // MARK: Hilfen

    static func log(for entry: DoseEntry, in medication: Medication) -> DoseLog? {
        guard let id = entry.log?.id else { return nil }
        return (medication.logs ?? []).first { $0.stableID == id }
    }
}
