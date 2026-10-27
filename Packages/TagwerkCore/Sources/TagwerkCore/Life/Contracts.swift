import Foundation

/// Art eines Eintrags unter „Verträge & Fristen“.
public enum ContractKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case subscription
    case contract
    case insurance
    /// Ausweis, Führerschein, TÜV …: nur ein Ablaufdatum.
    case document

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .subscription: "Abo"
        case .contract: "Vertrag"
        case .insurance: "Versicherung"
        case .document: "Dokument / Frist"
        }
    }

    public var symbol: String {
        switch self {
        case .subscription: "repeat.circle"
        case .contract: "doc.text"
        case .insurance: "shield.lefthalf.filled"
        case .document: "person.text.rectangle"
        }
    }

    /// Dokumente haben keine Kosten und keine Kündigung.
    public var hasCost: Bool { self != .document }
}

/// Zahlungsrhythmus.
public enum BillingCycle: String, Codable, Sendable, CaseIterable, Identifiable {
    case monthly, quarterly, halfYearly, yearly, once

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .monthly: "monatlich"
        case .quarterly: "vierteljährlich"
        case .halfYearly: "halbjährlich"
        case .yearly: "jährlich"
        case .once: "einmalig"
        }
    }

    /// Umrechnung auf einen Monat (einmalig zählt nicht zu den Fixkosten).
    public var monthlyFactor: Double {
        switch self {
        case .monthly: 1
        case .quarterly: 1.0 / 3
        case .halfYearly: 1.0 / 6
        case .yearly: 1.0 / 12
        case .once: 0
        }
    }
}

/// Kündigungsfrist, z. B. „3 Monate“.
public struct NoticePeriod: Codable, Sendable, Hashable {
    public enum Unit: String, Codable, Sendable, CaseIterable {
        case days, weeks, months

        public func title(_ value: Int) -> String {
            switch self {
            case .days: value == 1 ? "Tag" : "Tage"
            case .weeks: value == 1 ? "Woche" : "Wochen"
            case .months: value == 1 ? "Monat" : "Monate"
            }
        }
    }

    public var value: Int
    public var unit: Unit

    public init(value: Int, unit: Unit) {
        self.value = max(0, value)
        self.unit = unit
    }

    public static let none = NoticePeriod(value: 0, unit: .days)

    /// „3 Monate“, „keine“
    public var text: String {
        value == 0 ? "keine" : "\(value) \(unit.title(value))"
    }

    /// Datum, bis zu dem spätestens gekündigt werden muss.
    public func deadline(before end: Date, calendar: Calendar) -> Date {
        let component: Calendar.Component = switch unit {
        case .days: .day
        case .weeks: .weekOfYear
        case .months: .month
        }
        return calendar.date(byAdding: component, value: -value, to: end) ?? end
    }
}

/// Ein Vertrag, Abo oder Dokument ohne Datenbank.
public struct ContractFact: Sendable, Hashable {
    public var kind: ContractKind
    public var name: String
    public var cost: Double?
    public var billing: BillingCycle
    /// Vertragsbeginn.
    public var startDate: Date?
    /// Festes Ende bzw. Ablaufdatum (Dokumente).
    public var endDate: Date?
    /// Mindestlaufzeit ab Beginn.
    public var minimumTermMonths: Int?
    /// Verlängerung nach Ablauf (0 oder `nil`: danach jederzeit kündbar).
    public var renewalMonths: Int?
    public var notice: NoticePeriod
    /// So viele Tage vor der Frist erinnern.
    public var reminderDaysBefore: Int
    public var isCancelled: Bool

    public init(
        kind: ContractKind, name: String, cost: Double? = nil, billing: BillingCycle = .monthly,
        startDate: Date? = nil, endDate: Date? = nil, minimumTermMonths: Int? = nil, renewalMonths: Int? = nil,
        notice: NoticePeriod = .none, reminderDaysBefore: Int = 14, isCancelled: Bool = false
    ) {
        self.kind = kind
        self.name = name
        self.cost = cost
        self.billing = billing
        self.startDate = startDate
        self.endDate = endDate
        self.minimumTermMonths = minimumTermMonths
        self.renewalMonths = renewalMonths
        self.notice = notice
        self.reminderDaysBefore = max(0, reminderDaysBefore)
        self.isCancelled = isCancelled
    }
}

/// Zustand eines Vertrags oder Dokuments.
public enum ContractStatus: Sendable, Hashable {
    /// Läuft, Kündigung bis zur Frist möglich (`nil`: jederzeit kündbar bzw. kein Ende bekannt).
    case running(deadline: Date?)
    /// Kündigungsfrist oder Ablauf steht bald an.
    case dueSoon(Date)
    /// Dokument abgelaufen bzw. Vertrag ohne Verlängerung beendet.
    case expired(Date)
    case cancelled

    public var needsAttention: Bool {
        switch self {
        case .dueSoon, .expired: true
        default: false
        }
    }
}

public enum ContractLogic {
    public static func monthlyCost(_ fact: ContractFact) -> Double? {
        guard fact.kind.hasCost, let cost = fact.cost, cost > 0, fact.billing != .once else { return nil }
        return cost * fact.billing.monthlyFactor
    }

    /// Ende der laufenden Vertragsperiode (Dokumente: Ablaufdatum).
    public static func termEnd(_ fact: ContractFact, now: Date, calendar: Calendar) -> Date? {
        if fact.kind == .document { return fact.endDate }
        var end: Date?
        if let start = fact.startDate, let months = fact.minimumTermMonths, months > 0 {
            end = calendar.date(byAdding: .month, value: months, to: start)
        }
        if let fixed = fact.endDate {
            end = end.map { max($0, fixed) } ?? fixed
        }
        guard var current = end else { return nil }
        if let renewal = fact.renewalMonths, renewal > 0 {
            var guardCount = 0
            while current <= now, guardCount < 600 {
                current = calendar.date(byAdding: .month, value: renewal, to: current) ?? now.addingTimeInterval(1)
                guardCount += 1
            }
        }
        return current
    }

    /// Nächster Kündigungstag (bei Verlängerung die nächste noch erreichbare Frist) bzw. Ablauf (Dokumente).
    public static func deadline(_ fact: ContractFact, now: Date, calendar: Calendar) -> Date? {
        guard var end = termEnd(fact, now: now, calendar: calendar) else { return nil }
        if fact.kind == .document { return end }
        let today = calendar.startOfDay(for: now)
        var line = fact.notice.deadline(before: end, calendar: calendar)
        if let renewal = fact.renewalMonths, renewal > 0 {
            var guardCount = 0
            while line < today, guardCount < 600 {
                end = calendar.date(byAdding: .month, value: renewal, to: end) ?? today
                line = fact.notice.deadline(before: end, calendar: calendar)
                guardCount += 1
            }
        }
        return line < today ? nil : line
    }

    public static func status(_ fact: ContractFact, now: Date, calendar: Calendar) -> ContractStatus {
        if fact.isCancelled { return .cancelled }
        let today = calendar.startOfDay(for: now)
        let window = calendar.date(byAdding: .day, value: max(fact.reminderDaysBefore, 14), to: today) ?? today
        if fact.kind == .document {
            guard let end = fact.endDate else { return .running(deadline: nil) }
            if end < today { return .expired(end) }
            return end <= window ? .dueSoon(end) : .running(deadline: end)
        }
        // Ohne erreichbare Frist (kein Ende, Frist verpasst ohne Verlängerung): jederzeit bzw. monatlich kündbar.
        guard let line = deadline(fact, now: now, calendar: calendar) else { return .running(deadline: nil) }
        return line <= window ? .dueSoon(line) : .running(deadline: line)
    }

    /// „kündbar bis 15. Nov.“, „läuft ab am 3. März 2027“, „jederzeit kündbar“
    public static func statusText(_ fact: ContractFact, now: Date, calendar: Calendar) -> String {
        let status = status(fact, now: now, calendar: calendar)
        func date(_ value: Date) -> String { dayMonthYear(value, now: now, calendar: calendar) }
        switch status {
        case .cancelled: return "gekündigt"
        case let .expired(end): return "abgelaufen am \(date(end))"
        case let .dueSoon(deadline), let .running(deadline?):
            if fact.kind == .document { return "läuft ab am \(date(deadline))" }
            return "kündbar bis \(date(deadline))"
        case .running(deadline: nil):
            return fact.kind == .document ? "kein Ablaufdatum" : "jederzeit kündbar"
        }
    }

    /// „15. Nov.“ im laufenden Jahr, sonst „15. Nov. 2027“.
    static func dayMonthYear(_ date: Date, now: Date, calendar: Calendar) -> String {
        let text = WeeklyReview.dayMonth(date, calendar: calendar)
        let year = calendar.component(.year, from: date)
        return year == calendar.component(.year, from: now) ? text : "\(text) \(year)"
    }

    /// Fixkosten aller laufenden Verträge und Abos.
    public static func totals(_ facts: [ContractFact]) -> (monthly: Double, yearly: Double) {
        let monthly = facts.filter { !$0.isCancelled }.compactMap(monthlyCost).reduce(0, +)
        return (monthly, monthly * 12)
    }

    /// „12,99 €“
    public static func euro(_ value: Double) -> String {
        let cents = (value * 100).rounded()
        let euros = Int(cents) / 100
        let rest = abs(Int(cents) % 100)
        return "\(euros),\(rest < 10 ? "0" : "")\(rest) €"
    }

    /// Eintrag für Agenda und Woche am Tag der Frist bzw. des Ablaufs.
    public static func agendaItem(id: String, fact: ContractFact, from start: Date, to end: Date, now: Date, calendar: Calendar) -> AgendaItem? {
        guard !fact.isCancelled, let line = deadline(fact, now: now, calendar: calendar) else { return nil }
        let day = calendar.startOfDay(for: line)
        guard day >= calendar.startOfDay(for: start), day < end else { return nil }
        let title = fact.kind == .document ? "\(fact.name) läuft ab" : "Letzter Kündigungstag: \(fact.name)"
        return AgendaItem(id: "life-\(id)", kind: .deadline, title: title, start: day, isAllDay: true, subtitle: fact.kind.title)
    }

    /// Erinnerung `reminderDaysBefore` Tage vor der Frist um 9 Uhr und am Tag selbst.
    public static func reminderCandidates(id: String, fact: ContractFact, now: Date, calendar: Calendar) -> [ReminderCandidate] {
        guard !fact.isCancelled, let deadline = deadline(fact, now: now, calendar: calendar) else { return [] }
        let isDocument = fact.kind == .document
        var result: [ReminderCandidate] = []
        let dateText = dayMonthYear(deadline, now: now, calendar: calendar)
        let early = calendar.date(byAdding: .day, value: -fact.reminderDaysBefore, to: deadline) ?? deadline
        for (offset, fireDay) in [(fact.reminderDaysBefore, early), (0, deadline)] {
            guard let fire = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: fireDay), fire > now else { continue }
            if offset == 0, fact.reminderDaysBefore == 0, !result.isEmpty { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: fireDay)
            let title: String
            if isDocument {
                title = offset == 0 ? "\(fact.name) läuft heute ab" : "\(fact.name) läuft am \(dateText) ab"
            } else {
                title = offset == 0 ? "Heute letzter Tag zum Kündigen: \(fact.name)" : "\(fact.name): kündbar bis \(dateText)"
            }
            result.append(ReminderCandidate(
                id: String(format: "%@%@.%04d%02d%02d", NotificationIDs.Prefix.life, id, parts.year ?? 0, parts.month ?? 0, parts.day ?? 0),
                kind: .lifeDeadline,
                fireDate: fire,
                title: title,
                body: isDocument ? "Rechtzeitig verlängern oder neu beantragen." : "Kündigen oder bewusst weiterlaufen lassen.",
                referenceID: id
            ))
        }
        return result
    }
}
