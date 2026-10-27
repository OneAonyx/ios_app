import Foundation
import SwiftData
import TagwerkCore

/// Version 2 des Datenmodells (Phase 2): Medikamente und Einnahme-Protokoll.
///
/// Aufgaben, Unteraufgaben und Listen sind unverändert und werden aus V1 übernommen.
/// Der Umstieg von V1 ist eine leichte Migration (nur neue Tabellen).
public enum TagwerkSchemaV2: VersionedSchema {
    public static let versionIdentifier = Schema.Version(2, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            TagwerkSchemaV1.TaskItem.self,
            TagwerkSchemaV1.Subtask.self,
            TagwerkSchemaV1.TaskList.self,
            Medication.self,
            DoseLog.self,
        ]
    }

    @Model
    public final class Medication {
        public var stableID: String = UUID().uuidString
        public var name: String = ""
        /// Stärke als Text, z. B. „400 mg“ oder „10.000 HDU“.
        public var dosage: String = ""
        public var formRaw: String = MedicationForm.tablet.rawValue
        public var colorName: String = "teal"
        public var symbol: String = "pills.fill"
        public var timingRaw: String = MealTiming.none.rawValue
        /// `MedicationSchedule` als JSON (siehe `schedule`).
        public var scheduleData: Data?
        public var startDate: Date = Date()
        /// Letzter Einnahmetag (einschließlich), `nil` = dauerhaft.
        public var endDate: Date?
        /// Vorrat in Einheiten der Darreichungsform, `nil` = nicht mitzählen.
        public var stock: Double?
        public var refillThresholdDays: Int = 7
        /// Legt bei knappem Vorrat automatisch eine Aufgabe an.
        public var autoRefillTask: Bool = false
        /// Die automatisch angelegte Nachschub-Aufgabe (bis zum Nachfüllen).
        public var refillTaskID: String?
        public var reminderStyleRaw: String = ReminderStyle.notification.rawValue
        /// `false` = pausiert (keine Erinnerungen, nicht auf „Heute“).
        public var isActive: Bool = true
        public var notes: String = ""
        public var createdAt: Date = Date()
        public var sortIndex: Double = 0

        @Relationship(deleteRule: .cascade, inverse: \DoseLog.medication)
        public var logs: [DoseLog]? = []

        public init(
            name: String,
            dosage: String = "",
            form: MedicationForm = .tablet,
            schedule: MedicationSchedule = .daily([DoseTime(hour: 8)]),
            startDate: Date = Date(),
            sortIndex: Double = 0,
            stableID: String = UUID().uuidString,
            createdAt: Date = Date()
        ) {
            self.stableID = stableID
            self.name = name
            self.dosage = dosage
            self.formRaw = form.rawValue
            self.symbol = form.defaultSymbol
            self.scheduleData = schedule.normalized().encoded()
            self.startDate = startDate
            self.sortIndex = sortIndex
            self.createdAt = createdAt
        }
    }

    @Model
    public final class DoseLog {
        public var stableID: String = UUID().uuidString
        /// Geplanter Zeitpunkt, `nil` bei Bedarfs- oder Zusatz-Einnahmen.
        public var scheduledAt: Date?
        public var takenAt: Date?
        public var statusRaw: String = DoseStatus.taken.rawValue
        public var amount: Double = 1
        public var note: String = ""
        public var createdAt: Date = Date()
        public var medication: Medication?

        public init(
            scheduledAt: Date?,
            takenAt: Date?,
            status: DoseStatus,
            amount: Double,
            note: String = "",
            stableID: String = UUID().uuidString,
            createdAt: Date = Date()
        ) {
            self.stableID = stableID
            self.scheduledAt = scheduledAt
            self.takenAt = takenAt
            self.statusRaw = status.rawValue
            self.amount = amount
            self.note = note
            self.createdAt = createdAt
        }
    }
}

/// Die aktuelle Schema-Version für den Rest der App.
public typealias TaskItem = TagwerkSchemaV1.TaskItem
public typealias Subtask = TagwerkSchemaV1.Subtask
public typealias TaskList = TagwerkSchemaV1.TaskList
public typealias Medication = TagwerkSchemaV2.Medication
public typealias DoseLog = TagwerkSchemaV2.DoseLog

public enum TagwerkMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [TagwerkSchemaV1.self, TagwerkSchemaV2.self, TagwerkSchemaV3.self, TagwerkSchemaV4.self]
    }

    public static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4]
    }

    /// Nur neue Tabellen (Ernährung, Symptome): SwiftData migriert selbst.
    static let migrateV3toV4 = MigrationStage.lightweight(
        fromVersion: TagwerkSchemaV3.self,
        toVersion: TagwerkSchemaV4.self
    )

    /// Nur neue Tabellen (Training): SwiftData migriert selbst.
    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: TagwerkSchemaV2.self,
        toVersion: TagwerkSchemaV3.self
    )

    /// Nur neue Tabellen: SwiftData migriert selbst.
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: TagwerkSchemaV1.self,
        toVersion: TagwerkSchemaV2.self
    )
}

// MARK: - Bequeme Zugriffe

extension TagwerkSchemaV2.Medication {
    public var form: MedicationForm {
        get { MedicationForm(rawValue: formRaw) ?? .other }
        set { formRaw = newValue.rawValue }
    }

    public var timing: MealTiming {
        get { MealTiming(rawValue: timingRaw) ?? .none }
        set { timingRaw = newValue.rawValue }
    }

    public var reminderStyle: ReminderStyle {
        get { ReminderStyle(rawValue: reminderStyleRaw) ?? .notification }
        set { reminderStyleRaw = newValue.rawValue }
    }

    /// Einnahmeplan, gespeichert als JSON in `scheduleData`.
    public var schedule: MedicationSchedule {
        get { MedicationSchedule.decode(scheduleData) ?? .daily([DoseTime(hour: 8)]) }
        set { scheduleData = newValue.normalized().encoded() }
    }

    /// „Ibuprofen 400 mg“
    public var displayName: String {
        let trimmed = dosage.trimmingCharacters(in: .whitespaces)
        let title = name.isEmpty ? "Ohne Namen" : name
        return trimmed.isEmpty ? title : "\(title) \(trimmed)"
    }

    /// Übliche Menge pro Einnahme (für Bei Bedarf und als Rückfall).
    public var defaultAmount: Double {
        let plan = schedule
        switch plan.kind {
        case .asNeeded: return plan.asNeededAmount
        case .interval: return plan.intervalStart.amount
        case .taper: return plan.taperSteps.first?.amount ?? 1
        default: return plan.times.first?.amount ?? 1
        }
    }

    /// „1 Tablette · vor dem Essen“
    public func detail(for amount: Double) -> String {
        [form.amountLabel(amount), timing.hint].compactMap { $0 }.joined(separator: " · ")
    }

    /// „28 Tabletten“, `nil` ohne Vorratszählung.
    public var stockText: String? {
        guard let stock else { return nil }
        return "\(DoseAmount.formatStock(max(0, stock))) \(form.unit(for: max(0, stock) == 1 ? 1 : 2))"
    }

    /// Ab wann Einnahmen gezählt werden: Beginn des Plans, aber nicht weiter zurück als
    /// 2 Stunden vor dem Anlegen (sonst wäre alles davor „verpasst“).
    public func trackFrom(calendar: Calendar) -> Date {
        max(calendar.startOfDay(for: startDate), createdAt.addingTimeInterval(-2 * 3_600))
    }

    /// Läuft der Plan an diesem Tag (aktiv, begonnen, nicht beendet)?
    public func isRunning(on day: Date, calendar: Calendar) -> Bool {
        guard isActive else { return false }
        let start = calendar.startOfDay(for: day)
        if calendar.startOfDay(for: startDate) > start { return false }
        if let endDate, calendar.startOfDay(for: endDate) < start { return false }
        if schedule.kind == .taper,
           let last = calendar.date(byAdding: .day, value: schedule.taperTotalDays, to: calendar.startOfDay(for: startDate)),
           start >= last {
            return false
        }
        return true
    }

    public var logFacts: [DoseLogFact] {
        (logs ?? []).map(\.fact)
    }

    /// Protokoll, neueste zuerst.
    public var sortedLogs: [DoseLog] {
        (logs ?? []).sorted { ($0.takenAt ?? $0.scheduledAt ?? $0.createdAt) > ($1.takenAt ?? $1.scheduledAt ?? $1.createdAt) }
    }

    public func scheduledDoses(from: Date, to: Date, calendar: Calendar) -> [ScheduledDose] {
        DoseCalculator.doses(
            medicationID: stableID,
            schedule: schedule,
            startDate: startDate,
            endDate: endDate,
            trackFrom: trackFrom(calendar: calendar),
            from: from,
            to: to,
            calendar: calendar
        )
    }

    /// Geplante Einnahmen im Zeitraum mit Protokoll und Zustand.
    public func entries(from: Date, to: Date, now: Date = .now, calendar: Calendar) -> [DoseEntry] {
        let doses = scheduledDoses(from: from, to: to, calendar: calendar)
        guard !doses.isEmpty else { return [] }
        let window = DosePlanner.matchWindow
        let relevantLogs = logFacts.filter { fact in
            guard let scheduledAt = fact.scheduledAt else { return false }
            return scheduledAt >= from.addingTimeInterval(-window) && scheduledAt < to.addingTimeInterval(window)
        }
        return DosePlanner.entries(doses: doses, logs: relevantLogs, now: now, calendar: calendar)
    }

    /// Einnahmen eines Tages.
    public func entries(on day: Date, now: Date = .now, calendar: Calendar) -> [DoseEntry] {
        let start = calendar.startOfDay(for: day)
        return entries(from: start, to: calendar.endOfDayDate(for: start), now: now, calendar: calendar)
    }

    /// Bei-Bedarf- und Zusatz-Einnahmen im Zeitraum, neueste zuerst.
    public func extraIntakes(from: Date, to: Date) -> [DoseLog] {
        let ids = Set(DosePlanner.unscheduledIntakes(logFacts, from: from, to: to).map(\.id))
        return sortedLogs.filter { ids.contains($0.stableID) }
    }

    /// Vorrat-Prognose, `nil` ohne Vorratszählung.
    public func forecast(now: Date = .now, calendar: Calendar) -> StockForecast? {
        guard let stock else { return nil }
        if schedule.isScheduled {
            let start = calendar.startOfDay(for: now)
            let horizon = calendar.date(byAdding: .day, value: 120, to: start) ?? start.addingTimeInterval(120 * 86_400)
            let upcoming = entries(from: start, to: horizon, now: now, calendar: calendar)
                .filter(\.isOpen)
                .map(\.dose)
            return StockCalculator.forecast(stock: stock, upcoming: upcoming, refillThresholdDays: refillThresholdDays, now: now, calendar: calendar)
        }
        let taken = (logs ?? [])
            .filter { $0.status == .taken }
            .compactMap { log in log.takenAt.map { (date: $0, amount: log.amount) } }
        let average = StockCalculator.averageDailyUse(takenAmounts: taken, now: now)
        return StockCalculator.forecast(stock: stock, upcoming: [], averageDailyUse: average, refillThresholdDays: refillThresholdDays, now: now, calendar: calendar)
    }

    /// Prüfung für Bei-Bedarf-Einnahmen (Höchstmenge, Abstand).
    public func asNeededCheck(now: Date = .now, calendar: Calendar) -> AsNeededCheck {
        let plan = schedule
        let taken = (logs ?? []).filter { $0.status == .taken }.compactMap(\.takenAt)
        return AsNeededGuard.check(takenAt: taken, maxPerDay: plan.maxPerDay, minGapHours: plan.minGapHours, now: now, calendar: calendar)
    }

    /// Einnahmen als Einträge für Agenda und Woche.
    public func agendaItems(from: Date, to: Date, now: Date = .now, calendar: Calendar) -> [AgendaItem] {
        guard isActive else { return [] }
        return entries(from: from, to: to, now: now, calendar: calendar).map { entry in
            AgendaItem(
                id: "dose-\(entry.id)",
                kind: .medication,
                title: displayName,
                start: entry.dose.date,
                isAllDay: false,
                isDone: entry.isResolved,
                subtitle: entry.state == .skipped ? "Ausgelassen" : form.amountLabel(entry.dose.amount)
            )
        }
    }
}

extension TagwerkSchemaV2.DoseLog {
    public var status: DoseStatus {
        get { DoseStatus(rawValue: statusRaw) ?? .taken }
        set { statusRaw = newValue.rawValue }
    }

    public var fact: DoseLogFact {
        DoseLogFact(id: stableID, scheduledAt: scheduledAt, takenAt: takenAt, status: status, amount: amount)
    }
}

extension Calendar {
    /// Beginn des Folgetags.
    public func endOfDayDate(for date: Date) -> Date {
        let start = startOfDay(for: date)
        return self.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    }
}
