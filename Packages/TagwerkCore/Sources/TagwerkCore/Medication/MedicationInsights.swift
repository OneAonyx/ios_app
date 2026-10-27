import Foundation

// MARK: - Einnahmetreue

public struct AdherenceSummary: Sendable, Hashable {
    public var taken: Int
    public var skipped: Int
    public var missed: Int
    /// Noch offen (zählen nicht in die Quote).
    public var open: Int

    public init(taken: Int = 0, skipped: Int = 0, missed: Int = 0, open: Int = 0) {
        self.taken = taken
        self.skipped = skipped
        self.missed = missed
        self.open = open
    }

    /// Einnahmen, die schon entschieden sind.
    public var expected: Int { taken + skipped + missed }

    /// Anteil genommener Einnahmen, `nil` solange nichts fällig war.
    public var rate: Double? {
        expected == 0 ? nil : Double(taken) / Double(expected)
    }

    /// „92 %“ oder „–“.
    public var percentLabel: String {
        guard let rate else { return "–" }
        return "\(Int((rate * 100).rounded())) %"
    }
}

public enum DayAdherenceStatus: String, Sendable, Equatable {
    /// Keine Einnahme geplant.
    case none
    /// Alles genommen.
    case complete
    /// Teilweise genommen.
    case partial
    /// Nichts genommen.
    case missed
    /// Läuft noch (offene Einnahmen, nichts verpasst).
    case pending
}

public struct DayAdherence: Sendable, Equatable, Identifiable {
    public var date: Date
    public var status: DayAdherenceStatus
    public var taken: Int
    public var total: Int

    public init(date: Date, status: DayAdherenceStatus, taken: Int, total: Int) {
        self.date = date
        self.status = status
        self.taken = taken
        self.total = total
    }

    public var id: Date { date }
}

public enum Adherence {
    public static func summarize(_ entries: [DoseEntry]) -> AdherenceSummary {
        var summary = AdherenceSummary()
        for entry in entries {
            switch entry.state {
            case .taken: summary.taken += 1
            case .skipped: summary.skipped += 1
            case .missed: summary.missed += 1
            case .upcoming, .due, .late: summary.open += 1
            }
        }
        return summary
    }

    /// Status je Tag für den Einnahme-Kalender.
    public static func days(_ entries: [DoseEntry], from startDay: Date, days: Int, calendar: Calendar) -> [DayAdherence] {
        let first = calendar.startOfDay(for: startDay)
        var byDay: [Date: [DoseEntry]] = [:]
        for entry in entries {
            byDay[calendar.startOfDay(for: entry.dose.date), default: []].append(entry)
        }
        return (0..<max(0, days)).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: first) else { return nil }
            let dayEntries = byDay[day] ?? []
            return DayAdherence(date: day, status: status(of: dayEntries), taken: dayEntries.filter { $0.state == .taken }.count, total: dayEntries.count)
        }
    }

    static func status(of entries: [DoseEntry]) -> DayAdherenceStatus {
        guard !entries.isEmpty else { return .none }
        let summary = summarize(entries)
        if summary.taken == entries.count { return .complete }
        if summary.missed + summary.skipped == 0 { return .pending }
        if summary.taken == 0 && summary.open == 0 { return .missed }
        return .partial
    }
}

// MARK: - Vorrat

public struct StockForecast: Sendable, Equatable {
    public var stock: Double
    /// Tage bis der Vorrat nicht mehr reicht. `nil` = reicht über den betrachteten Zeitraum hinaus
    /// oder es gibt keinen Verbrauch.
    public var daysLeft: Int?
    /// Tag, an dem die erste Einnahme nicht mehr gedeckt ist.
    public var runOutDate: Date?
    public var needsRefill: Bool

    public init(stock: Double, daysLeft: Int?, runOutDate: Date?, needsRefill: Bool) {
        self.stock = stock
        self.daysLeft = daysLeft
        self.runOutDate = runOutDate
        self.needsRefill = needsRefill
    }

    public var isEmpty: Bool { stock <= 0.0001 }

    /// „reicht bis Mo, 24. Nov.“, „reicht noch 2 Tage“, „Vorrat leer“.
    public func rangeLabel(calendar: Calendar) -> String? {
        if isEmpty { return "Vorrat leer" }
        guard let daysLeft, let runOutDate else { return nil }
        // `runOutDate` ist der erste Tag, der nicht mehr gedeckt ist.
        switch daysLeft {
        case ..<1: return "reicht nicht für die nächste Einnahme"
        case 1: return "reicht nur noch heute"
        case 2: return "reicht bis morgen"
        case 3...7: return "reicht noch \(daysLeft) Tage"
        default:
            let lastDay = calendar.date(byAdding: .day, value: -1, to: runOutDate) ?? runOutDate
            return "reicht bis \(GermanCalendar.shortDate(lastDay, calendar: calendar))"
        }
    }
}

public enum StockCalculator {
    /// - Parameters:
    ///   - upcoming: noch nicht protokollierte Einnahmen ab jetzt (inkl. heute offener)
    ///   - averageDailyUse: für „bei Bedarf“: Verbrauch pro Tag im Mittel
    public static func forecast(
        stock: Double,
        upcoming: [ScheduledDose],
        averageDailyUse: Double? = nil,
        refillThresholdDays: Int,
        now: Date,
        calendar: Calendar
    ) -> StockForecast {
        let today = calendar.startOfDay(for: now)
        var runOut: Date?
        if !upcoming.isEmpty {
            var remaining = stock
            for dose in upcoming.sorted(by: { $0.date < $1.date }) {
                if remaining + 0.0001 < dose.amount {
                    runOut = calendar.startOfDay(for: dose.date)
                    break
                }
                remaining -= dose.amount
            }
        } else if let averageDailyUse, averageDailyUse > 0 {
            let days = Int((max(stock, 0) / averageDailyUse).rounded(.down))
            runOut = calendar.date(byAdding: .day, value: days, to: today)
        }

        guard let runOut else {
            return StockForecast(stock: stock, daysLeft: nil, runOutDate: nil, needsRefill: false)
        }
        let daysLeft = max(0, calendar.dateComponents([.day], from: today, to: runOut).day ?? 0)
        return StockForecast(stock: stock, daysLeft: daysLeft, runOutDate: runOut, needsRefill: daysLeft <= max(0, refillThresholdDays))
    }

    /// Durchschnittlicher Verbrauch pro Tag aus den letzten `days` Tagen (für Bei-Bedarf-Medikamente).
    public static func averageDailyUse(takenAmounts: [(date: Date, amount: Double)], now: Date, days: Int = 28) -> Double? {
        let start = now.addingTimeInterval(-Double(days) * 86_400)
        let total = takenAmounts.filter { $0.date >= start && $0.date <= now }.reduce(0) { $0 + $1.amount }
        return total > 0 ? total / Double(days) : nil
    }
}

// MARK: - Bei Bedarf

public struct AsNeededCheck: Sendable, Equatable {
    /// Einnahmen in den letzten 24 Stunden.
    public var countInWindow: Int
    public var maxPerDay: Int?
    public var lastTaken: Date?
    /// Ab wann die Regeln wieder eine Einnahme erlauben (`nil` = jetzt).
    public var nextAllowed: Date?
    /// Hinweise, warum gerade Vorsicht gilt.
    public var warnings: [String]
    /// Kurze Zusammenfassung, z. B. „1 von max. 3 in 24 Std. · zuletzt 10:15“.
    public var statusLine: String

    public var isAllowed: Bool { warnings.isEmpty }
}

public enum AsNeededGuard {
    public static func check(takenAt: [Date], maxPerDay: Int?, minGapHours: Double?, now: Date, calendar: Calendar) -> AsNeededCheck {
        let windowStart = now.addingTimeInterval(-24 * 3_600)
        let recent = takenAt.filter { $0 > windowStart && $0 <= now }.sorted()
        let lastTaken = takenAt.filter { $0 <= now }.max()
        var warnings: [String] = []
        var nextAllowed: Date?

        if let maxPerDay, maxPerDay > 0, recent.count >= maxPerDay {
            warnings.append("Schon \(recent.count)× in den letzten 24 Std. genommen (max. \(maxPerDay)×).")
            // Erst wenn die älteste der letzten `maxPerDay` Einnahmen 24 Std. her ist.
            let blocking = recent[recent.count - maxPerDay]
            nextAllowed = blocking.addingTimeInterval(24 * 3_600)
        }
        if let minGapHours, minGapHours > 0, let lastTaken {
            let gapEnd = lastTaken.addingTimeInterval(minGapHours * 3_600)
            if gapEnd > now {
                warnings.append("Letzte Einnahme um \(GermanCalendar.time(lastTaken, calendar: calendar)) – empfohlen sind mind. \(MedicationSchedule.hoursLabel(minGapHours)) Abstand.")
                nextAllowed = max(nextAllowed ?? gapEnd, gapEnd)
            }
        }

        var status: String
        if let maxPerDay {
            status = "\(recent.count) von max. \(maxPerDay) in 24 Std."
        } else if recent.isEmpty {
            status = "In den letzten 24 Std. nicht genommen"
        } else {
            status = "\(recent.count)× in 24 Std."
        }
        if let lastTaken {
            status += " · zuletzt \(relativeTime(lastTaken, now: now, calendar: calendar))"
        }

        return AsNeededCheck(
            countInWindow: recent.count,
            maxPerDay: maxPerDay,
            lastTaken: lastTaken,
            nextAllowed: nextAllowed,
            warnings: warnings,
            statusLine: status
        )
    }

    /// „Wieder ab 16:15“ bzw. „Wieder ab Di, 16:15“.
    public static func nextAllowedLabel(_ date: Date, now: Date, calendar: Calendar) -> String {
        "Wieder ab \(relativeTime(date, now: now, calendar: calendar))"
    }

    /// „10:15“ heute, „gestern 22:10“, sonst „Di, 3. Nov., 10:15“.
    static func relativeTime(_ date: Date, now: Date, calendar: Calendar) -> String {
        let time = GermanCalendar.time(date, calendar: calendar)
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "gestern \(time)"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "morgen \(time)"
        }
        return "\(GermanCalendar.shortDate(date, calendar: calendar)), \(time)"
    }
}
