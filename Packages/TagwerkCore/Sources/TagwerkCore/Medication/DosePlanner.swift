import Foundation

/// Eine geplante Einnahme.
public struct ScheduledDose: Sendable, Hashable, Identifiable {
    public var medicationID: String
    public var date: Date
    public var amount: Double

    public init(medicationID: String, date: Date, amount: Double) {
        self.medicationID = medicationID
        self.date = date
        self.amount = amount
    }

    public var id: String { DoseID.make(medicationID: medicationID, date: date) }
}

/// Kennung einer geplanten Einnahme: „<Medikament>|<Unix-Sekunden>“. Damit finden
/// Widget, Mitteilung und Wecker dieselbe Einnahme wieder, ohne die Datenbank zu kennen.
public enum DoseID {
    public static func make(medicationID: String, date: Date) -> String {
        "\(medicationID)|\(Int(date.timeIntervalSince1970.rounded()))"
    }

    public static func parse(_ id: String) -> (medicationID: String, date: Date)? {
        guard let separator = id.lastIndex(of: "|") else { return nil }
        let medicationID = String(id[..<separator])
        guard !medicationID.isEmpty, let seconds = Int(id[id.index(after: separator)...]) else { return nil }
        return (medicationID, Date(timeIntervalSince1970: TimeInterval(seconds)))
    }
}

/// Ein Eintrag im Einnahme-Protokoll, unabhängig von SwiftData.
public struct DoseLogFact: Sendable, Hashable, Identifiable {
    public var id: String
    /// Geplanter Zeitpunkt, `nil` bei Bedarfs- oder Zusatz-Einnahmen.
    public var scheduledAt: Date?
    public var takenAt: Date?
    public var status: DoseStatus
    public var amount: Double

    public init(id: String, scheduledAt: Date?, takenAt: Date?, status: DoseStatus, amount: Double = 1) {
        self.id = id
        self.scheduledAt = scheduledAt
        self.takenAt = takenAt
        self.status = status
        self.amount = amount
    }
}

/// Eine geplante Einnahme mit Protokoll und Zustand.
public struct DoseEntry: Sendable, Hashable, Identifiable {
    public enum State: String, Sendable, Hashable {
        /// Noch nicht dran.
        case upcoming
        /// Jetzt dran (ab 30 Min. vorher bis 60 Min. danach).
        case due
        /// Überfällig, aber noch nachholbar.
        case late
        /// Nicht genommen und vorbei.
        case missed
        case taken
        case skipped
    }

    public var dose: ScheduledDose
    public var log: DoseLogFact?
    public var state: State

    public init(dose: ScheduledDose, log: DoseLogFact?, state: State) {
        self.dose = dose
        self.log = log
        self.state = state
    }

    public var id: String { dose.id }

    /// Noch offen und abhakbar.
    public var isOpen: Bool { state == .upcoming || state == .due || state == .late }

    /// Genommen oder bewusst ausgelassen.
    public var isResolved: Bool { state == .taken || state == .skipped }
}

/// Zeitfenster für den Zustand einer Einnahme.
public enum DoseTiming {
    /// Ab so viel vorher gilt eine Einnahme als „jetzt dran“.
    public static let dueBefore: TimeInterval = 30 * 60
    /// Ab so viel danach gilt sie als überfällig.
    public static let lateAfter: TimeInterval = 60 * 60
    /// Ab so viel danach gilt sie als verpasst.
    public static let missedAfter: TimeInterval = 12 * 3_600

    public static func state(for scheduled: Date, now: Date) -> DoseEntry.State {
        let delta = now.timeIntervalSince(scheduled)
        if delta < -dueBefore { return .upcoming }
        if delta <= lateAfter { return .due }
        if delta < missedAfter { return .late }
        return .missed
    }
}

/// Erzeugt geplante Einnahmen aus einem Plan.
public enum DoseCalculator {
    /// Einnahmen im Zeitraum `[from, to)`.
    /// - Parameters:
    ///   - startDate: Beginn des Plans (Tag zählt, Uhrzeit egal)
    ///   - endDate: letzter Tag (einschließlich), `nil` = ohne Ende
    ///   - trackFrom: frühere Einnahmen werden nicht erzeugt (z. B. vor dem Anlegen)
    public static func doses(
        medicationID: String,
        schedule: MedicationSchedule,
        startDate: Date,
        endDate: Date?,
        trackFrom: Date? = nil,
        from: Date,
        to: Date,
        calendar: Calendar
    ) -> [ScheduledDose] {
        guard schedule.isScheduled, from < to else { return [] }
        let planStart = calendar.startOfDay(for: startDate)
        let lowerBound = max(from, planStart, trackFrom ?? .distantPast)
        let endLimit = endDate.map { calendar.endOfDay(for: $0) } ?? .distantFuture
        let upperBound = min(to, endLimit)
        guard lowerBound < upperBound else { return [] }

        var result: [ScheduledDose] = []
        var day = calendar.startOfDay(for: lowerBound)
        var guardCounter = 0
        while day < upperBound, guardCounter < 1_500 {
            guardCounter += 1
            for time in schedule.doseTimes(on: day, anchor: planStart, calendar: calendar) {
                guard let moment = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day),
                      calendar.isDate(moment, inSameDayAs: day),
                      moment >= lowerBound, moment < upperBound
                else { continue }
                result.append(ScheduledDose(medicationID: medicationID, date: moment, amount: time.amount))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        // Zeitumstellung kann zwei Uhrzeiten auf denselben Moment legen.
        var seen = Set<Date>()
        return result.sorted { $0.date < $1.date }.filter { seen.insert($0.date).inserted }
    }
}

/// Ordnet Protokolleinträge den geplanten Einnahmen zu und bestimmt den Zustand.
public enum DosePlanner {
    /// Wie weit ein Protokolleintrag von „seiner“ Einnahme entfernt sein darf, wenn die
    /// Uhrzeit im Plan später geändert wurde.
    public static let matchWindow: TimeInterval = 4 * 3_600

    public static func entries(doses: [ScheduledDose], logs: [DoseLogFact], now: Date, calendar: Calendar) -> [DoseEntry] {
        let sortedDoses = doses.sorted { $0.date < $1.date }
        var assigned: [Int: DoseLogFact] = [:]
        var usedLogs = Set<String>()

        // 1. Genaue Treffer (gleicher geplanter Zeitpunkt). Bei Doppelten zählt „genommen“.
        let scheduledLogs = logs.filter { $0.scheduledAt != nil }
        var bySecond: [Int: [DoseLogFact]] = [:]
        for log in scheduledLogs {
            bySecond[Int(log.scheduledAt!.timeIntervalSince1970.rounded()), default: []].append(log)
        }
        for (index, dose) in sortedDoses.enumerated() {
            let key = Int(dose.date.timeIntervalSince1970.rounded())
            guard let candidates = bySecond[key], !candidates.isEmpty else { continue }
            let best = candidates.first { $0.status == .taken } ?? candidates[0]
            assigned[index] = best
            usedLogs.formUnion(candidates.map(\.id))
        }

        // 2. Übrige Einträge zur nächstgelegenen freien Einnahme am selben Tag.
        let leftovers = scheduledLogs
            .filter { !usedLogs.contains($0.id) }
            .sorted { $0.scheduledAt! < $1.scheduledAt! }
        for log in leftovers {
            let scheduledAt = log.scheduledAt!
            let candidate = sortedDoses.indices
                .filter { assigned[$0] == nil }
                .filter { calendar.isDate(sortedDoses[$0].date, inSameDayAs: scheduledAt) }
                .filter { abs(sortedDoses[$0].date.timeIntervalSince(scheduledAt)) <= matchWindow }
                .min { abs(sortedDoses[$0].date.timeIntervalSince(scheduledAt)) < abs(sortedDoses[$1].date.timeIntervalSince(scheduledAt)) }
            if let candidate {
                assigned[candidate] = log
            }
        }

        return sortedDoses.enumerated().map { index, dose in
            let log = assigned[index]
            let state: DoseEntry.State
            switch log?.status {
            case .taken: state = .taken
            case .skipped: state = .skipped
            case nil: state = DoseTiming.state(for: dose.date, now: now)
            }
            return DoseEntry(dose: dose, log: log, state: state)
        }
    }

    /// Einnahmen ohne festen Termin (Bei Bedarf, zusätzlich) im Zeitraum, neueste zuerst.
    public static func unscheduledIntakes(_ logs: [DoseLogFact], from: Date, to: Date) -> [DoseLogFact] {
        logs
            .filter { $0.scheduledAt == nil && $0.status == .taken }
            .filter { guard let takenAt = $0.takenAt else { return false }; return takenAt >= from && takenAt < to }
            .sorted { ($0.takenAt ?? .distantPast) > ($1.takenAt ?? .distantPast) }
    }
}
