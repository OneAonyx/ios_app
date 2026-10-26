import Foundation

/// Eine Einnahme-Uhrzeit in Ortszeit mit Menge. Ortszeit statt Zeitpunkt, damit
/// „08:00“ auch nach der Zeitumstellung 08:00 bleibt.
public struct DoseTime: Codable, Sendable, Hashable, Comparable {
    public var hour: Int
    public var minute: Int
    /// Menge in Einheiten der Darreichungsform (z. B. 0,5 Tabletten).
    public var amount: Double

    public init(hour: Int, minute: Int = 0, amount: Double = 1) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
        self.amount = amount
    }

    public var minuteOfDay: Int { hour * 60 + minute }

    /// „08:00“
    public var label: String { String(format: "%02d:%02d", hour, minute) }

    public static func < (lhs: DoseTime, rhs: DoseTime) -> Bool {
        lhs.minuteOfDay < rhs.minuteOfDay
    }
}

/// Eine Stufe beim Ausschleichen: `days` Tage lang `amount` pro Einnahme.
public struct TaperStep: Codable, Sendable, Hashable {
    public var days: Int
    public var amount: Double

    public init(days: Int, amount: Double) {
        self.days = days
        self.amount = amount
    }
}

/// Einnahmeplan eines Medikaments.
///
/// Bewusst ein Struct mit allen Feldern statt eines Enums mit Werten: Beim Wechsel der Art
/// im Editor bleiben die Eingaben erhalten, und neue Felder lassen sich ohne Bruch ergänzen.
public struct MedicationSchedule: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable, CaseIterable, Identifiable {
        /// Jeden Tag zu festen Uhrzeiten.
        case daily
        /// An bestimmten Wochentagen.
        case weekdays
        /// Alle N Tage, gezählt ab Beginn.
        case everyNDays
        /// Im Stundentakt ab einer Startzeit, jeden Tag gleich (z. B. alle 8 Std. ab 06:00).
        case interval
        /// Nur bei Bedarf, mit Höchstmenge und Mindestabstand.
        case asNeeded
        /// Einnahme- und Pausentage im Wechsel (z. B. 21 / 7).
        case cycle
        /// Ausschleichen in Stufen, danach Ende.
        case taper

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .daily: "Täglich"
            case .weekdays: "An Wochentagen"
            case .everyNDays: "Alle paar Tage"
            case .interval: "Im Stundentakt"
            case .asNeeded: "Bei Bedarf"
            case .cycle: "Einnahme und Pause"
            case .taper: "Ausschleichen"
            }
        }
    }

    public var kind: Kind
    /// Uhrzeiten (alle Arten außer Stundentakt und Bei Bedarf).
    public var times: [DoseTime]
    /// `Calendar`-Wochentage (1 = So … 7 = Sa).
    public var weekdays: [Int]
    /// Abstand in Tagen bei „alle N Tage“.
    public var dayInterval: Int
    /// Abstand in Stunden beim Stundentakt.
    public var intervalHours: Int
    /// Erste Einnahme des Tages beim Stundentakt (mit Menge).
    public var intervalStart: DoseTime
    /// Bei Bedarf: höchstens so oft in 24 Stunden.
    public var maxPerDay: Int?
    /// Bei Bedarf: mindestens so viele Stunden Abstand.
    public var minGapHours: Double?
    /// Bei Bedarf: übliche Menge pro Einnahme.
    public var asNeededAmount: Double
    public var cycleOnDays: Int
    public var cycleOffDays: Int
    public var taperSteps: [TaperStep]

    public init(
        kind: Kind,
        times: [DoseTime] = [DoseTime(hour: 8)],
        weekdays: [Int] = [2, 3, 4, 5, 6],
        dayInterval: Int = 2,
        intervalHours: Int = 8,
        intervalStart: DoseTime = DoseTime(hour: 6),
        maxPerDay: Int? = nil,
        minGapHours: Double? = nil,
        asNeededAmount: Double = 1,
        cycleOnDays: Int = 21,
        cycleOffDays: Int = 7,
        taperSteps: [TaperStep] = []
    ) {
        self.kind = kind
        self.times = times
        self.weekdays = weekdays
        self.dayInterval = dayInterval
        self.intervalHours = intervalHours
        self.intervalStart = intervalStart
        self.maxPerDay = maxPerDay
        self.minGapHours = minGapHours
        self.asNeededAmount = asNeededAmount
        self.cycleOnDays = cycleOnDays
        self.cycleOffDays = cycleOffDays
        self.taperSteps = taperSteps
    }

    // MARK: Vorlagen

    public static func daily(_ times: [DoseTime]) -> MedicationSchedule {
        MedicationSchedule(kind: .daily, times: times)
    }

    public static func weekdays(_ days: [Int], times: [DoseTime]) -> MedicationSchedule {
        MedicationSchedule(kind: .weekdays, times: times, weekdays: days)
    }

    public static func everyNDays(_ interval: Int, times: [DoseTime]) -> MedicationSchedule {
        MedicationSchedule(kind: .everyNDays, times: times, dayInterval: interval)
    }

    public static func interval(hours: Int, start: DoseTime) -> MedicationSchedule {
        MedicationSchedule(kind: .interval, intervalHours: hours, intervalStart: start)
    }

    public static func asNeeded(maxPerDay: Int?, minGapHours: Double?, amount: Double = 1) -> MedicationSchedule {
        MedicationSchedule(kind: .asNeeded, times: [], maxPerDay: maxPerDay, minGapHours: minGapHours, asNeededAmount: amount)
    }

    public static func cycle(on: Int, off: Int, times: [DoseTime]) -> MedicationSchedule {
        MedicationSchedule(kind: .cycle, times: times, cycleOnDays: on, cycleOffDays: off)
    }

    public static func taper(_ steps: [TaperStep], times: [DoseTime]) -> MedicationSchedule {
        MedicationSchedule(kind: .taper, times: times, taperSteps: steps)
    }

    // MARK: Abfragen

    /// Feste Einnahmezeiten? (Bei Bedarf hat keine.)
    public var isScheduled: Bool { kind != .asNeeded }

    /// Gesamtdauer beim Ausschleichen in Tagen.
    public var taperTotalDays: Int {
        taperSteps.reduce(0) { $0 + max(0, $1.days) }
    }

    /// Bereinigte Kopie: sortierte, eindeutige Uhrzeiten, Werte in sinnvollen Grenzen.
    public func normalized() -> MedicationSchedule {
        var copy = self
        var seen = Set<Int>()
        copy.times = times.sorted().filter { seen.insert($0.minuteOfDay).inserted }
        copy.weekdays = Array(Set(weekdays.filter { (1...7).contains($0) }))
            .sorted { GermanCalendar.mondayIndex(ofWeekday: $0) < GermanCalendar.mondayIndex(ofWeekday: $1) }
        copy.dayInterval = min(max(dayInterval, 1), 365)
        copy.intervalHours = min(max(intervalHours, 1), 24)
        copy.cycleOnDays = min(max(cycleOnDays, 1), 365)
        copy.cycleOffDays = min(max(cycleOffDays, 0), 365)
        copy.taperSteps = taperSteps.filter { $0.days > 0 }
        if let maxPerDay { copy.maxPerDay = maxPerDay > 0 ? maxPerDay : nil }
        if let minGapHours { copy.minGapHours = minGapHours > 0 ? minGapHours : nil }
        return copy
    }

    /// Fehlt etwas, damit der Plan Einnahmen erzeugt? `nil` = alles gut.
    public var validationMessage: String? {
        switch kind {
        case .daily, .everyNDays, .cycle:
            return times.isEmpty ? "Mindestens eine Uhrzeit hinzufügen." : nil
        case .weekdays:
            if weekdays.isEmpty { return "Mindestens einen Wochentag wählen." }
            return times.isEmpty ? "Mindestens eine Uhrzeit hinzufügen." : nil
        case .taper:
            if taperSteps.filter({ $0.days > 0 }).isEmpty { return "Mindestens eine Stufe hinzufügen." }
            return times.isEmpty ? "Mindestens eine Uhrzeit hinzufügen." : nil
        case .interval, .asNeeded:
            return nil
        }
    }

    /// Uhrzeiten beim Stundentakt: von der Startzeit in Schritten bis Mitternacht.
    public var intervalTimes: [DoseTime] {
        let step = min(max(intervalHours, 1), 24) * 60
        var result: [DoseTime] = []
        var minute = intervalStart.minuteOfDay
        while minute < 24 * 60 {
            result.append(DoseTime(hour: minute / 60, minute: minute % 60, amount: intervalStart.amount))
            minute += step
        }
        return result
    }

    /// Einnahmen an einem Tag (mit Menge). `anchor` ist der Beginn des Plans; davon
    /// hängen „alle N Tage“, Zyklus und Ausschleichen ab.
    public func doseTimes(on day: Date, anchor: Date, calendar: Calendar) -> [DoseTime] {
        let plan = normalized()
        let dayIndex = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: anchor), to: calendar.startOfDay(for: day)
        ).day ?? 0
        guard dayIndex >= 0 else { return [] }

        switch plan.kind {
        case .daily:
            return plan.times
        case .weekdays:
            return plan.weekdays.contains(calendar.component(.weekday, from: day)) ? plan.times : []
        case .everyNDays:
            return dayIndex % plan.dayInterval == 0 ? plan.times : []
        case .interval:
            return plan.intervalTimes
        case .asNeeded:
            return []
        case .cycle:
            let period = plan.cycleOnDays + plan.cycleOffDays
            return dayIndex % period < plan.cycleOnDays ? plan.times : []
        case .taper:
            var start = 0
            for step in plan.taperSteps {
                if dayIndex < start + step.days {
                    guard step.amount > 0 else { return [] }
                    return plan.times.map { DoseTime(hour: $0.hour, minute: $0.minute, amount: step.amount) }
                }
                start += step.days
            }
            return []
        }
    }

    // MARK: Text

    /// „08:00, 20:00“
    public var timesLabel: String {
        let source = kind == .interval ? intervalTimes : normalized().times
        return source.map(\.label).joined(separator: ", ")
    }

    /// Kurze Beschreibung, z. B. „Täglich um 08:00, 20:00“ oder „Bei Bedarf · max. 3× in 24 Std.“
    public var summary: String {
        let plan = normalized()
        let times = plan.timesLabel
        switch plan.kind {
        case .daily:
            return "Täglich um \(times)"
        case .weekdays:
            let days = plan.weekdays.map { GermanCalendar.shortWeekdays[$0 - 1] }
            let dayText = plan.weekdays == [2, 3, 4, 5, 6] ? "Werktags" : days.joined(separator: ", ")
            return "\(dayText) um \(times)"
        case .everyNDays:
            return plan.dayInterval == 1 ? "Täglich um \(times)" : "Alle \(plan.dayInterval) Tage um \(times)"
        case .interval:
            return "Alle \(plan.intervalHours) Std. ab \(plan.intervalStart.label)"
        case .asNeeded:
            var parts = ["Bei Bedarf"]
            if let max = plan.maxPerDay { parts.append("max. \(max)× in 24 Std.") }
            if let gap = plan.minGapHours { parts.append("mind. \(Self.hoursLabel(gap)) Abstand") }
            return parts.joined(separator: " · ")
        case .cycle:
            return "\(plan.cycleOnDays) Tage Einnahme, \(plan.cycleOffDays) Tage Pause · \(times)"
        case .taper:
            let count = plan.taperSteps.count
            return "Ausschleichen in \(count) \(count == 1 ? "Stufe" : "Stufen") (\(plan.taperTotalDays) Tage) · \(times)"
        }
    }

    /// „6 Std.“, „1,5 Std.“
    public static func hoursLabel(_ hours: Double) -> String {
        "\(DoseAmount.formatStock(hours)) Std."
    }

    // MARK: Codable mit Standardwerten (ältere Daten bleiben lesbar)

    private enum CodingKeys: String, CodingKey {
        case kind, times, weekdays, dayInterval, intervalHours, intervalStart
        case maxPerDay, minGapHours, asNeededAmount, cycleOnDays, cycleOffDays, taperSteps
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = MedicationSchedule(kind: .daily)
        kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .daily
        times = try c.decodeIfPresent([DoseTime].self, forKey: .times) ?? defaults.times
        weekdays = try c.decodeIfPresent([Int].self, forKey: .weekdays) ?? defaults.weekdays
        dayInterval = try c.decodeIfPresent(Int.self, forKey: .dayInterval) ?? defaults.dayInterval
        intervalHours = try c.decodeIfPresent(Int.self, forKey: .intervalHours) ?? defaults.intervalHours
        intervalStart = try c.decodeIfPresent(DoseTime.self, forKey: .intervalStart) ?? defaults.intervalStart
        maxPerDay = try c.decodeIfPresent(Int.self, forKey: .maxPerDay)
        minGapHours = try c.decodeIfPresent(Double.self, forKey: .minGapHours)
        asNeededAmount = try c.decodeIfPresent(Double.self, forKey: .asNeededAmount) ?? 1
        cycleOnDays = try c.decodeIfPresent(Int.self, forKey: .cycleOnDays) ?? defaults.cycleOnDays
        cycleOffDays = try c.decodeIfPresent(Int.self, forKey: .cycleOffDays) ?? defaults.cycleOffDays
        taperSteps = try c.decodeIfPresent([TaperStep].self, forKey: .taperSteps) ?? []
    }

    public func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(self)
    }

    public static func decode(_ data: Data?) -> MedicationSchedule? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(MedicationSchedule.self, from: data)
    }
}
