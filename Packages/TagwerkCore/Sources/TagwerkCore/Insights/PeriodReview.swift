import Foundation

/// Monats- oder Jahresrückblick.
public enum ReviewPeriod: String, CaseIterable, Sendable, Identifiable {
    case month, year

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .month: "Monat"
        case .year: "Jahr"
        }
    }

    /// „zum Vormonat“, „zum Vorjahr“
    public var comparison: String {
        switch self {
        case .month: "zum Vormonat"
        case .year: "zum Vorjahr"
        }
    }

    /// Beginn und Ende (exklusiv) des Zeitraums, der `date` enthält.
    public func interval(containing date: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let component: Calendar.Component = self == .month ? .month : .year
        let start = calendar.dateInterval(of: component, for: date)?.start ?? calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: component, value: 1, to: start) ?? start
        return (start, end)
    }

    /// Beginn des Zeitraums davor bzw. danach.
    public func shifted(_ start: Date, by offset: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: self == .month ? .month : .year, value: offset, to: start) ?? start
    }

    /// „Oktober 2026“ bzw. „2026“
    public func label(_ start: Date, calendar: Calendar) -> String {
        let year = calendar.component(.year, from: start)
        switch self {
        case .month: return "\(GermanCalendar.longMonths[calendar.component(.month, from: start) - 1]) \(year)"
        case .year: return "\(year)"
        }
    }
}

/// Kennzahlen eines Zeitraums. `days` = erfasste Tage (beim laufenden Zeitraum bis heute).
public struct PeriodMetrics: Sendable, Equatable {
    public var days: Int
    public var workouts: Int
    public var workingSets: Int
    public var activityMinutes: Int
    public var symptomDays: Int
    public var painDays: Int
    public var averagePain: Double?
    /// Einnahmetreue 0…1, `nil` ohne geplante Einnahmen.
    public var adherence: Double?
    public var averageSleepHours: Double?
    /// Stimmung 1…5.
    public var averageMood: Double?
    public var averageSteps: Int?
    public var weightStart: Double?
    public var weightEnd: Double?
    public var diaryCompleteDays: Int
    public var tasksDone: Int

    public init(
        days: Int, workouts: Int = 0, workingSets: Int = 0, activityMinutes: Int = 0, symptomDays: Int = 0, painDays: Int = 0,
        averagePain: Double? = nil, adherence: Double? = nil, averageSleepHours: Double? = nil, averageMood: Double? = nil,
        averageSteps: Int? = nil, weightStart: Double? = nil, weightEnd: Double? = nil, diaryCompleteDays: Int = 0, tasksDone: Int = 0
    ) {
        self.days = days
        self.workouts = workouts
        self.workingSets = workingSets
        self.activityMinutes = activityMinutes
        self.symptomDays = symptomDays
        self.painDays = painDays
        self.averagePain = averagePain
        self.adherence = adherence
        self.averageSleepHours = averageSleepHours
        self.averageMood = averageMood
        self.averageSteps = averageSteps
        self.weightStart = weightStart
        self.weightEnd = weightEnd
        self.diaryCompleteDays = diaryCompleteDays
        self.tasksDone = tasksDone
    }

    var weeks: Double { max(Double(days) / 7, 1.0 / 7) }

    /// Nichts erfasst, was sich auswerten ließe.
    public var isEmpty: Bool {
        workouts == 0 && activityMinutes == 0 && symptomDays == 0 && painDays == 0 && adherence == nil
            && averageSleepHours == nil && averageMood == nil && averageSteps == nil && weightEnd == nil
            && diaryCompleteDays == 0 && tasksDone == 0
    }
}

/// Eine Zeile im Rückblick: Wert und Vergleich zum Zeitraum davor.
public struct PeriodReviewLine: Sendable, Hashable, Identifiable {
    public enum Direction: String, Sendable {
        case better, worse, same, none
    }

    public var id: String
    public var title: String
    public var value: String
    /// „+0,8 zum Vormonat“, `nil` ohne Vergleich.
    public var change: String?
    public var direction: Direction
    public var symbol: String
}

public struct PeriodReview: Sendable {
    public var title: String
    public var lines: [PeriodReviewLine]
    public var highlights: [String]
    /// Erster Tag mit Einträgen, wenn er im Zeitraum liegt (davor zählt nichts mit).
    public var since: Date?

    public var isEmpty: Bool { lines.isEmpty }

    /// Zeilen nur, wo es Daten gibt. Vergleiche je Woche bzw. als Anteil der Tage,
    /// damit ein laufender Monat fair gegen einen ganzen steht.
    public static func make(period: ReviewPeriod, start: Date, current: PeriodMetrics, previous: PeriodMetrics?, calendar: Calendar) -> PeriodReview {
        var lines: [PeriodReviewLine] = []
        var highlights: [String] = []
        let prev = previous.flatMap { $0.isEmpty ? nil : $0 }
        let versus = period.comparison

        func add(_ id: String, _ title: String, _ symbol: String, value: String, now: Double?, before: Double?, higherIsBetter: Bool?, format: (Double) -> String, highlight: ((Double) -> String)? = nil) {
            guard let now else { return }
            var change: String?
            var direction = PeriodReviewLine.Direction.none
            if let before {
                let delta = now - before
                change = (delta >= 0 ? "+" : "−") + format(abs(delta)) + " " + versus
                let tolerance = max(abs(before) * 0.05, 0.0001)
                if abs(delta) <= tolerance {
                    direction = .same
                    change = "wie \(period == .month ? "im Vormonat" : "im Vorjahr")"
                } else if let higherIsBetter {
                    direction = (delta > 0) == higherIsBetter ? .better : .worse
                    if direction == .better, let highlight { highlights.append(highlight(delta)) }
                }
            }
            lines.append(PeriodReviewLine(id: id, title: title, value: value, change: change, direction: direction, symbol: symbol))
        }

        func perWeek(_ value: Int, _ metrics: PeriodMetrics) -> Double { Double(value) / metrics.weeks }
        func share(_ value: Int, _ metrics: PeriodMetrics) -> Double { Double(value) / Double(max(metrics.days, 1)) * 100 }
        let one = { (value: Double) in WeightFormat.number((value * 10).rounded() / 10) }

        if current.workouts > 0 || (prev?.workouts ?? 0) > 0 {
            let rate = perWeek(current.workouts, current)
            add("workouts", "Training", "dumbbell", value: "\(current.workouts) Einheiten · \(one(rate)) pro Woche",
                now: rate, before: prev.map { perWeek($0.workouts, $0) }, higherIsBetter: true, format: one,
                highlight: { "Öfter trainiert als \(period == .month ? "im Vormonat" : "im Vorjahr") (+\(one($0)) pro Woche)" })
        }
        if current.workingSets > 0 {
            let rate = perWeek(current.workingSets, current)
            add("sets", "Arbeitssätze", "square.stack.3d.up", value: "\(one(rate.rounded())) pro Woche",
                now: rate.rounded(), before: prev.map { perWeek($0.workingSets, $0).rounded() }, higherIsBetter: nil, format: one)
        }
        if current.activityMinutes > 0 {
            let rate = perWeek(current.activityMinutes, current)
            add("activity", "Bewegung", "figure.walk", value: "Ø \(Int(rate.rounded())) Min. pro Woche",
                now: rate.rounded(), before: prev.map { perWeek($0.activityMinutes, $0).rounded() }, higherIsBetter: true,
                format: { "\(Int($0.rounded())) Min." })
        }
        if let steps = current.averageSteps {
            add("steps", "Schritte", "shoeprints.fill", value: "Ø \(GermanNumber.grouped(steps)) am Tag",
                now: Double(steps), before: prev?.averageSteps.map(Double.init), higherIsBetter: true,
                format: { GermanNumber.grouped(Int($0.rounded())) })
        }
        if current.symptomDays > 0 || (prev?.symptomDays ?? 0) > 0 {
            add("symptoms", "Beschwerden", "bandage", value: "an \(current.symptomDays) von \(current.days) Tagen",
                now: share(current.symptomDays, current), before: prev.map { share($0.symptomDays, $0) }, higherIsBetter: false,
                format: { "\(Int($0.rounded())) % der Tage" })
            if let prev, share(current.symptomDays, current) + 5 < share(prev.symptomDays, prev) {
                highlights.append("Weniger Tage mit Beschwerden als \(period == .month ? "im Vormonat" : "im Vorjahr")")
            }
        }
        if current.painDays > 0 || (prev?.painDays ?? 0) > 0 {
            let strength = current.averagePain.map { ", Ø Stärke \(one($0))" } ?? ""
            add("pain", "Schmerzen", "figure.stand", value: "an \(current.painDays) Tagen\(strength)",
                now: share(current.painDays, current), before: prev.map { share($0.painDays, $0) }, higherIsBetter: false,
                format: { "\(Int($0.rounded())) % der Tage" })
        }
        if let adherence = current.adherence {
            add("adherence", "Einnahmetreue", "pills", value: "\(Int((adherence * 100).rounded())) %",
                now: adherence * 100, before: prev?.adherence.map { $0 * 100 }, higherIsBetter: true,
                format: { "\(Int($0.rounded())) Punkte" })
            if adherence >= 0.95 { highlights.append("Medikamente zuverlässig genommen (\(Int((adherence * 100).rounded())) %)") }
        }
        if let sleep = current.averageSleepHours {
            add("sleep", "Schlaf", "bed.double.fill", value: "Ø \(one(sleep)) Std.",
                now: sleep, before: prev?.averageSleepHours, higherIsBetter: sleep < 9 ? true : nil, format: { "\(one($0)) Std." })
        }
        if let mood = current.averageMood {
            add("mood", "Stimmung", "face.smiling", value: "Ø \(one(mood)) von 5",
                now: mood, before: prev?.averageMood, higherIsBetter: true, format: one)
        }
        if let end = current.weightEnd {
            let start = current.weightStart ?? end
            let delta = end - start
            let sign = delta > 0.05 ? "+" : (delta < -0.05 ? "−" : "±")
            lines.append(PeriodReviewLine(
                id: "weight", title: "Gewicht", value: "\(WeightFormat.number(end)) kg",
                change: "\(sign)\(one(abs(delta))) kg im \(period == .month ? "Monat" : "Jahr")", direction: .none, symbol: "scalemass"
            ))
        }
        if current.diaryCompleteDays > 0 {
            add("diary", "Tagebuch vollständig", "checkmark.seal", value: "an \(current.diaryCompleteDays) von \(current.days) Tagen",
                now: share(current.diaryCompleteDays, current), before: prev.map { share($0.diaryCompleteDays, $0) }, higherIsBetter: true,
                format: { "\(Int($0.rounded())) % der Tage" })
        }
        if current.tasksDone > 0 {
            let rate = perWeek(current.tasksDone, current)
            add("tasks", "Aufgaben erledigt", "checklist", value: "\(current.tasksDone) · \(one(rate)) pro Woche",
                now: rate, before: prev.map { perWeek($0.tasksDone, $0) }, higherIsBetter: true, format: one)
        }
        return PeriodReview(title: period.label(start, calendar: calendar), lines: lines, highlights: Array(highlights.prefix(3)))
    }
}
