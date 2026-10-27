import Foundation

/// Inhalt des Arztberichts (PDF). Die App sammelt die Daten, hier wird gerechnet und sortiert.
public struct DoctorReport: Sendable {
    public struct MedicationLine: Sendable, Hashable, Identifiable {
        public var name: String
        public var schedule: String
        public var hint: String?
        public var adherence: AdherenceSummary?
        public var extraIntakes: Int
        public var isActive: Bool
        public var id: String { name + schedule }

        public init(name: String, schedule: String, hint: String?, adherence: AdherenceSummary?, extraIntakes: Int, isActive: Bool) {
            self.name = name
            self.schedule = schedule
            self.hint = hint
            self.adherence = adherence
            self.extraIntakes = extraIntakes
            self.isActive = isActive
        }

        /// „92 % (23 von 25)“, bei Bei-Bedarf „6× genommen“.
        public var adherenceText: String {
            if let adherence, adherence.expected > 0 {
                return "\(adherence.percentLabel) (\(adherence.taken) von \(adherence.expected))"
            }
            return extraIntakes > 0 ? "\(extraIntakes)× genommen" : "–"
        }
    }

    public struct SymptomWeek: Sendable, Hashable, Identifiable {
        public var weekStart: Date
        public var count: Int
        public var averageSeverity: Double?
        public var id: Date { weekStart }
    }

    public struct SymptomTypeLine: Sendable, Hashable, Identifiable {
        public var type: SymptomType
        public var count: Int
        public var averageSeverity: Double
        public var id: String { type.rawValue }
    }

    public struct SymptomLogRow: Sendable, Hashable, Identifiable {
        public var date: Date
        public var type: SymptomType
        public var severity: Int
        public var durationMinutes: Int?
        public var note: String
        public var id: String { "\(date.timeIntervalSince1970)-\(type.rawValue)" }

        public init(date: Date, type: SymptomType, severity: Int, durationMinutes: Int?, note: String) {
            self.date = date
            self.type = type
            self.severity = severity
            self.durationMinutes = durationMinutes
            self.note = note
        }
    }

    public struct WeightPoint: Sendable, Hashable, Identifiable {
        public var date: Date
        public var value: Double
        public var id: Date { date }

        public init(date: Date, value: Double) {
            self.date = date
            self.value = value
        }
    }

    public var from: Date
    public var to: Date
    public var createdAt: Date
    public var name: String
    public var medications: [MedicationLine]
    public var symptomWeeks: [SymptomWeek]
    public var symptomTypes: [SymptomTypeLine]
    public var symptomLog: [SymptomLogRow]
    public var findings: [TriggerFinding]
    public var mealCount: Int
    public var avoidedFoods: [String]
    public var cautionFoods: [String]
    public var loadDays: Int
    public var elevatedLoadDays: Int
    public var weights: [WeightPoint]
    public var checkIns: CheckInAverages

    public static func make(
        from: Date,
        to: Date,
        createdAt: Date,
        name: String,
        medications: [MedicationLine],
        symptoms: [SymptomLogRow],
        findings: [TriggerFinding],
        mealCount: Int,
        avoidedFoods: [String],
        cautionFoods: [String],
        loads: [HistamineLoad],
        weights: [WeightPoint],
        checkIns: [CheckInFact],
        calendar: Calendar
    ) -> DoctorReport {
        let inRange = symptoms.filter { $0.date >= from && $0.date < to }.sorted { $0.date < $1.date }
        return DoctorReport(
            from: from,
            to: to,
            createdAt: createdAt,
            name: name,
            medications: medications.sorted { ($0.isActive ? 0 : 1, $0.name) < ($1.isActive ? 0 : 1, $1.name) },
            symptomWeeks: weeks(inRange, from: from, to: to, calendar: calendar),
            symptomTypes: types(inRange),
            symptomLog: inRange,
            findings: findings,
            mealCount: mealCount,
            avoidedFoods: avoidedFoods.sorted(),
            cautionFoods: cautionFoods.sorted(),
            loadDays: loads.count,
            elevatedLoadDays: loads.filter { $0.level != .calm }.count,
            weights: weights.filter { $0.date >= from && $0.date < to }.sorted { $0.date < $1.date },
            checkIns: CheckInAverages.compute(checkIns.filter { $0.day >= calendar.startOfDay(for: from) && $0.day < to })
        )
    }

    /// Beschwerden je Kalenderwoche, auch Wochen ohne Beschwerden.
    static func weeks(_ symptoms: [SymptomLogRow], from: Date, to: Date, calendar: Calendar) -> [SymptomWeek] {
        var result: [SymptomWeek] = []
        var start = AgendaBuilder.startOfWeek(containing: from, calendar: calendar)
        while start < to {
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 86_400)
            let week = symptoms.filter { $0.date >= start && $0.date < end }
            let average = week.isEmpty ? nil : Double(week.reduce(0) { $0 + $1.severity }) / Double(week.count)
            result.append(SymptomWeek(weekStart: start, count: week.count, averageSeverity: average))
            start = end
        }
        return result
    }

    /// Häufigste Beschwerden zuerst.
    static func types(_ symptoms: [SymptomLogRow]) -> [SymptomTypeLine] {
        Dictionary(grouping: symptoms, by: \.type)
            .map { type, rows in
                SymptomTypeLine(type: type, count: rows.count, averageSeverity: Double(rows.reduce(0) { $0 + $1.severity }) / Double(rows.count))
            }
            .sorted { $0.count == $1.count ? $0.type.title < $1.type.title : $0.count > $1.count }
    }

    /// „1. Sept. – 27. Okt. 2026“
    public func periodLabel(calendar: Calendar) -> String {
        let end = to.addingTimeInterval(-1)
        let year = calendar.component(.year, from: end)
        return "\(WeeklyReview.dayMonth(from, calendar: calendar)) – \(WeeklyReview.dayMonth(end, calendar: calendar)) \(year)"
    }

    /// Gewicht am Anfang und Ende des Zeitraums.
    public var weightChangeText: String? {
        guard let first = weights.first, let last = weights.last, weights.count >= 2 else {
            return weights.last.map { "\(WeightFormat.number($0.value)) kg" }
        }
        let change = ((last.value - first.value) * 10).rounded() / 10
        let sign = change > 0 ? "+" : (change < 0 ? "−" : "±")
        return "\(WeightFormat.number(first.value)) → \(WeightFormat.number(last.value)) kg (\(sign)\(WeightFormat.number(abs(change))) kg)"
    }

    /// Tage mit mindestens einer Beschwerde.
    public func symptomDayCount(calendar: Calendar) -> Int {
        Set(symptomLog.map { calendar.startOfDay(for: $0.date) }).count
    }
}
