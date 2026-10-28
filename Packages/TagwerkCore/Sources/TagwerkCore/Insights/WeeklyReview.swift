import Foundation

/// Eine Trainingseinheit für Rückblick und Bericht.
public struct WorkoutFact: Sendable, Hashable {
    public var date: Date
    public var title: String
    public var workingSets: Int
    public var volume: Double

    public init(date: Date, title: String, workingSets: Int, volume: Double) {
        self.date = date
        self.title = title
        self.workingSets = workingSets
        self.volume = volume
    }
}

/// Alles, was in einen Wochenrückblick einfließt (aus allen Bereichen zusammengetragen).
public struct WeeklyReviewInput: Sendable {
    public var weekStart: Date
    public var tasksCompleted: Int
    public var tasksOverdue: Int
    public var medication: AdherenceSummary?
    public var workouts: [WorkoutFact]
    public var plannedWorkouts: Int?
    public var records: [String]
    /// Nur Tage mit Einträgen.
    public var nutritionDays: [NutritionDay]
    public var symptoms: [SymptomFact]
    public var checkIns: [CheckInFact]
    /// Letztes Gewicht vor der Woche und letztes in der Woche.
    public var weightBefore: Double?
    public var weightAfter: Double?

    public init(
        weekStart: Date, tasksCompleted: Int = 0, tasksOverdue: Int = 0, medication: AdherenceSummary? = nil,
        workouts: [WorkoutFact] = [], plannedWorkouts: Int? = nil, records: [String] = [], nutritionDays: [NutritionDay] = [],
        symptoms: [SymptomFact] = [], checkIns: [CheckInFact] = [], weightBefore: Double? = nil, weightAfter: Double? = nil
    ) {
        self.weekStart = weekStart
        self.tasksCompleted = tasksCompleted
        self.tasksOverdue = tasksOverdue
        self.medication = medication
        self.workouts = workouts
        self.plannedWorkouts = plannedWorkouts
        self.records = records
        self.nutritionDays = nutritionDays
        self.symptoms = symptoms
        self.checkIns = checkIns
        self.weightBefore = weightBefore
        self.weightAfter = weightAfter
    }
}

/// Der fertige Rückblick: Abschnitte mit Kennzahlen und eine Liste von Höhepunkten.
public struct WeeklyReview: Sendable, Hashable {
    public enum Tone: String, Sendable, Hashable {
        case good, neutral, attention
    }

    public struct Line: Sendable, Hashable, Identifiable {
        public var label: String
        public var value: String
        public var detail: String?
        public var tone: Tone
        public var id: String { label }
    }

    public struct Section: Sendable, Hashable, Identifiable {
        public var id: String
        public var title: String
        public var symbol: String
        public var lines: [Line]
    }

    public var weekStart: Date
    public var title: String
    public var sections: [Section]
    public var highlights: [String]
    /// Kurzfassung ohne persönliche Daten, z. B. für Claude.
    public var plainText: String

    public var isEmpty: Bool { sections.isEmpty }

    public static func make(_ input: WeeklyReviewInput, calendar: Calendar) -> WeeklyReview {
        var sections: [Section] = []
        var highlights: [String] = []

        // Aufgaben
        if input.tasksCompleted > 0 || input.tasksOverdue > 0 {
            var lines = [Line(label: "Erledigt", value: "\(input.tasksCompleted)", tone: input.tasksCompleted > 0 ? .good : .neutral)]
            if input.tasksOverdue > 0 {
                lines.append(Line(label: "Überfällig", value: "\(input.tasksOverdue)", tone: .attention))
            }
            sections.append(Section(id: "tasks", title: "Aufgaben", symbol: "checklist", lines: lines))
            if input.tasksCompleted >= 10 { highlights.append("\(input.tasksCompleted) Aufgaben erledigt") }
        }

        // Medikamente
        if let medication = input.medication, medication.expected > 0 {
            let rate = medication.rate ?? 0
            var lines = [Line(
                label: "Einnahmetreue", value: medication.percentLabel,
                detail: "\(medication.taken) von \(medication.expected) genommen",
                tone: rate >= 0.9 ? .good : (rate >= 0.7 ? .neutral : .attention)
            )]
            if medication.missed > 0 {
                lines.append(Line(label: "Verpasst", value: "\(medication.missed)", tone: .attention))
            }
            if medication.skipped > 0 {
                lines.append(Line(label: "Ausgelassen", value: "\(medication.skipped)", tone: .neutral))
            }
            sections.append(Section(id: "medication", title: "Medikamente", symbol: "pills", lines: lines))
            if medication.taken == medication.expected { highlights.append("Alle Einnahmen genommen") }
        }

        // Training
        if !input.workouts.isEmpty || (input.plannedWorkouts ?? 0) > 0 {
            let sets = input.workouts.reduce(0) { $0 + $1.workingSets }
            let volume = input.workouts.reduce(0) { $0 + $1.volume }
            let planned = input.plannedWorkouts ?? 0
            var lines = [Line(
                label: "Einheiten", value: planned > 0 ? "\(input.workouts.count) von \(planned)" : "\(input.workouts.count)",
                detail: input.workouts.isEmpty ? nil : input.workouts.map(\.title).joined(separator: ", "),
                tone: planned > 0 && input.workouts.count < planned ? .attention : .good
            )]
            if sets > 0 {
                lines.append(Line(label: "Arbeitssätze", value: "\(sets)", tone: .neutral))
            }
            if volume > 0 {
                lines.append(Line(label: "Volumen", value: Self.kilograms(volume), tone: .neutral))
            }
            sections.append(Section(id: "training", title: "Training", symbol: "dumbbell", lines: lines))
            highlights += input.records.prefix(3)
            if planned > 0, input.workouts.count >= planned { highlights.append("Alle \(planned) geplanten Einheiten geschafft") }
        }

        // Ernährung
        let days = input.nutritionDays.filter { !$0.meals.isEmpty || $0.waterML > 0 }
        if !days.isEmpty {
            let loads = days.map { $0.load }
            let average = loads.reduce(0) { $0 + $1.points } / Double(loads.count)
            let elevated = loads.filter { $0.level != .calm }.count
            let mealDays = days.filter { !$0.meals.isEmpty }
            let proteinAverage = mealDays.isEmpty ? 0 : mealDays.reduce(0) { $0 + $1.protein } / Double(mealDays.count)
            let proteinHit = mealDays.filter { $0.protein >= $0.proteinTarget * 0.95 }.count
            let target = days.first?.proteinTarget ?? 0
            let waterAverage = days.reduce(0) { $0 + $1.waterML } / days.count
            var lines = [Line(
                label: "Ø Histamin-Tageslast",
                value: HistamineLoad(points: average, contributors: []).level.title,
                detail: elevated == 0 ? "an keinem Tag erhöht" : "\(elevated) von \(days.count) Tagen erhöht oder hoch",
                tone: elevated == 0 ? .good : (elevated <= 2 ? .neutral : .attention)
            )]
            if !mealDays.isEmpty {
                lines.append(Line(
                    label: "Ø Eiweiß", value: "\(Int(proteinAverage.rounded())) g",
                    detail: "Ziel \(Int(target.rounded())) g an \(proteinHit) von \(mealDays.count) Tagen erreicht",
                    tone: proteinHit * 2 >= mealDays.count ? .good : .attention
                ))
            }
            if waterAverage > 0 {
                lines.append(Line(
                    label: "Ø Wasser", value: "\(NutritionDay.liters(waterAverage)) l",
                    tone: waterAverage >= (days.first?.waterTarget ?? 2500) * 8 / 10 ? .good : .neutral
                ))
            }
            sections.append(Section(id: "nutrition", title: "Ernährung", symbol: "fork.knife", lines: lines))
            if !mealDays.isEmpty, proteinHit == mealDays.count, mealDays.count >= 3 {
                highlights.append("Eiweißziel an allen \(mealDays.count) Tagen erreicht")
            }
        }

        // Beschwerden
        let symptomDays = Set(input.symptoms.map { calendar.startOfDay(for: $0.date) })
        if !input.symptoms.isEmpty || !days.isEmpty {
            var lines: [Line] = []
            if input.symptoms.isEmpty {
                lines.append(Line(label: "Beschwerden", value: "keine", tone: .good))
                highlights.append("Eine Woche ohne Beschwerden")
            } else {
                let counts = Dictionary(grouping: input.symptoms, by: \.type).mapValues(\.count)
                let top = counts.sorted { $0.value == $1.value ? $0.key.title < $1.key.title : $0.value > $1.value }
                let severity = Double(input.symptoms.reduce(0) { $0 + $1.severity }) / Double(input.symptoms.count)
                lines.append(Line(
                    label: "Tage mit Beschwerden", value: "\(symptomDays.count) von 7",
                    detail: top.prefix(3).map { "\($0.key.title) \($0.value)×" }.joined(separator: ", "),
                    tone: symptomDays.count <= 1 ? .neutral : .attention
                ))
                lines.append(Line(label: "Ø Stärke", value: CheckInAverages.format(severity), tone: severity >= 3.5 ? .attention : .neutral))
                let free = 7 - symptomDays.count
                if free >= 5 { highlights.append("\(free) Tage ohne Beschwerden") }
            }
            sections.append(Section(id: "symptoms", title: "Beschwerden", symbol: "waveform.path.ecg", lines: lines))
        }

        // Befinden
        if !input.checkIns.isEmpty {
            let averages = CheckInAverages.compute(input.checkIns)
            let lines = CheckInScale.allCases.compactMap { scale -> Line? in
                guard let value = averages.value(scale) else { return nil }
                let good = scale.higherIsBetter ? value >= 3.5 : value <= 2.5
                let bad = scale.higherIsBetter ? value < 2.5 : value >= 3.5
                return Line(
                    label: "Ø \(scale.title)", value: CheckInAverages.format(value),
                    detail: scale.label(Int(value.rounded())), tone: good ? .good : (bad ? .attention : .neutral)
                )
            }
            sections.append(Section(id: "checkins", title: "Befinden", symbol: "face.smiling", lines: lines))
        }

        // Gewicht
        if let after = input.weightAfter {
            var detail: String?
            if let before = input.weightBefore {
                let change = after - before
                let rounded = (change * 10).rounded() / 10
                detail = rounded == 0 ? "unverändert" : (rounded > 0 ? "+" : "−") + "\(WeightFormat.number(abs(rounded))) kg zur Vorwoche"
            }
            sections.append(Section(id: "weight", title: "Körper", symbol: "scalemass", lines: [
                Line(label: "Gewicht", value: "\(WeightFormat.number(after)) kg", detail: detail, tone: .neutral),
            ]))
        }

        let review = WeeklyReview(
            weekStart: input.weekStart,
            title: Self.title(weekStart: input.weekStart, calendar: calendar),
            sections: sections,
            highlights: highlights,
            plainText: ""
        )
        var result = review
        result.plainText = review.makePlainText()
        return result
    }

    /// „KW 44 · 26. Okt. – 1. Nov.“
    public static func title(weekStart: Date, calendar: Calendar) -> String {
        let end = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let week = calendar.component(.weekOfYear, from: weekStart)
        return "KW \(week) · \(Self.dayMonth(weekStart, calendar: calendar)) – \(Self.dayMonth(end, calendar: calendar))"
    }

    public static func dayMonth(_ date: Date, calendar: Calendar) -> String {
        let months = ["Jan.", "Feb.", "März", "Apr.", "Mai", "Juni", "Juli", "Aug.", "Sept.", "Okt.", "Nov.", "Dez."]
        let parts = calendar.dateComponents([.day, .month], from: date)
        return "\(parts.day ?? 1). \(months[((parts.month ?? 1) - 1) % 12])"
    }

    static func kilograms(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "de_DE")
        formatter.groupingSeparator = "."
        formatter.maximumFractionDigits = 0
        return "\(formatter.string(from: NSNumber(value: value.rounded())) ?? String(Int(value))) kg"
    }

    /// Alle Kennzahlen als Text (ohne Namen oder Notizen).
    func makePlainText() -> String {
        var lines = ["Wochenrückblick \(title)"]
        for section in sections {
            lines.append("")
            lines.append("\(section.title):")
            for line in section.lines {
                lines.append("- \(line.label): \(line.value)" + (line.detail.map { " (\($0))" } ?? ""))
            }
        }
        if !highlights.isEmpty {
            lines.append("")
            lines.append("Höhepunkte: " + highlights.joined(separator: "; "))
        }
        return lines.joined(separator: "\n")
    }
}

/// Erinnerung an den Wochenrückblick: sonntags um 18 Uhr.
public enum ReviewReminders {
    public static let hour = 18

    public static func candidate(now: Date, calendar: Calendar) -> ReminderCandidate? {
        let weekStart = AgendaBuilder.startOfWeek(containing: now, calendar: calendar)
        guard let sunday = calendar.date(byAdding: .day, value: 6, to: weekStart),
              var fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: sunday)
        else { return nil }
        var start = weekStart
        if fire <= now {
            // Diese Woche schon vorbei: nächster Sonntag.
            guard let next = calendar.date(byAdding: .day, value: 7, to: fire),
                  let nextStart = calendar.date(byAdding: .day, value: 7, to: weekStart)
            else { return nil }
            fire = next
            start = nextStart
        }
        let parts = calendar.dateComponents([.year, .month, .day], from: fire)
        return ReminderCandidate(
            id: String(format: "%@%04d%02d%02d", NotificationIDs.Prefix.review, parts.year ?? 0, parts.month ?? 0, parts.day ?? 0),
            kind: .review,
            fireDate: fire,
            title: "Dein Wochenrückblick ist da",
            body: "Training, Ernährung, Beschwerden und Befinden der Woche auf einen Blick.",
            referenceID: String(Int(start.timeIntervalSince1970))
        )
    }
}
