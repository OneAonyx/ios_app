import Foundation

/// Ein Ereignis für die Tag-für-Tag-Tabelle des Arztberichts.
public struct DiaryEvent: Sendable, Hashable {
    public var date: Date
    public var text: String

    public init(date: Date, text: String) {
        self.date = date
        self.text = text
    }
}

/// Eine Zeile der Tag-für-Tag-Tabelle.
public struct DiaryRow: Sendable, Hashable, Identifiable {
    public var day: Date
    public var meals: [String]
    /// Beschwerden und Schmerzen.
    public var complaints: [String]
    public var medications: [String]
    public var activities: [String]
    /// „Schlaf 7,5 Std. · Stimmung 4 · Stress 2“
    public var wellbeing: String?
    public var id: Date { day }

    public var isEmpty: Bool {
        meals.isEmpty && complaints.isEmpty && medications.isEmpty && activities.isEmpty && wellbeing == nil
    }

    /// Befinden zeilenweise („Schlaf 7,5 Std.“, „Stimmung 4/5“ …).
    public var wellbeingLines: [String] {
        wellbeing.map { $0.components(separatedBy: " · ") } ?? []
    }
}

/// Alles fürs Arzt-Tagebuch im Bericht.
public struct DiaryReportInput: Sendable {
    public var pains: [PainFact]
    public var activities: [ActivityFact]
    public var days: [DiaryDayFacts]
    public var meals: [DiaryEvent]
    public var medications: [DiaryEvent]
    public var checkIns: [CheckInFact]
    public var questions: String
    /// Tageswerte aus Apple Health (Schritte, Schlaf …).
    public var health: [HealthDayFact]

    public init(
        pains: [PainFact] = [], activities: [ActivityFact] = [], days: [DiaryDayFacts] = [], meals: [DiaryEvent] = [],
        medications: [DiaryEvent] = [], checkIns: [CheckInFact] = [], questions: String = "", health: [HealthDayFact] = []
    ) {
        self.pains = pains
        self.activities = activities
        self.days = days
        self.meals = meals
        self.medications = medications
        self.checkIns = checkIns
        self.questions = questions
        self.health = health
    }
}

/// Teile des Arztberichts, einzeln abwählbar.
public enum ReportSection: String, Codable, Sendable, CaseIterable, Identifiable {
    case medications, symptoms, pain, nutrition, activity, wellbeing, weight, diary, log

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .medications: "Medikamente"
        case .symptoms: "Beschwerden"
        case .pain: "Schmerzen"
        case .nutrition: "Ernährung und Muster"
        case .activity: "Bewegung und Sport"
        case .wellbeing: "Befinden und Schlaf"
        case .weight: "Gewicht"
        case .diary: "Tag-für-Tag-Tabelle"
        case .log: "Protokoll aller Einträge"
        }
    }
}

extension DoctorReport {
    /// Ergänzt den Bericht um Schmerzen, Bewegung, Vollständigkeit und die Tag-für-Tag-Tabelle.
    public func withDiary(_ input: DiaryReportInput, calendar: Calendar) -> DoctorReport {
        var report = self
        let start = calendar.startOfDay(for: from)
        let pains = input.pains.filter { $0.date >= start && $0.date < to }.sorted { $0.date < $1.date }
        let activities = input.activities.filter { $0.date >= start && $0.date < to }.sorted { $0.date < $1.date }
        report.pains = pains
        report.painSummary = PainSummary.compute(pains, activities: activities, from: start, to: to, calendar: calendar)
        report.activities = activities
        report.activityWeeks = ActivityStats.weeks(activities, from: start, to: to, calendar: calendar)
        report.activityKinds = ActivityStats.byKind(activities)
        let days = input.days.filter { $0.day >= start && $0.day < to }
        report.completeness = DiaryCompleteness.compute(days)
        report.questions = input.questions.trimmingCharacters(in: .whitespacesAndNewlines)
        let hours = input.checkIns.filter { $0.day >= start && $0.day < to }.compactMap(\.sleepHours)
        report.averageSleepHours = hours.isEmpty ? nil : hours.reduce(0, +) / Double(hours.count)
        report.health = HealthSummary.compute(input.health, from: start, to: to)
        report.diary = Self.diaryRows(input: input, pains: pains, activities: activities, days: days, symptoms: symptomLog, from: start, to: to, calendar: calendar)
        return report
    }

    static func diaryRows(
        input: DiaryReportInput, pains: [PainFact], activities: [ActivityFact], days: [DiaryDayFacts],
        symptoms: [SymptomLogRow], from: Date, to: Date, calendar: Calendar
    ) -> [DiaryRow] {
        func time(_ date: Date) -> String { GermanCalendar.time(date, calendar: calendar) }
        func grouped<T>(_ items: [T], date: (T) -> Date) -> [Date: [T]] {
            Dictionary(grouping: items) { calendar.startOfDay(for: date($0)) }
        }
        let meals = grouped(input.meals.sorted { $0.date < $1.date }) { $0.date }
        let meds = grouped(input.medications.sorted { $0.date < $1.date }) { $0.date }
        let symptomsByDay = grouped(symptoms) { $0.date }
        let painsByDay = grouped(pains) { $0.date }
        let activitiesByDay = grouped(activities) { $0.date }
        let checkIns = Dictionary(input.checkIns.map { (calendar.startOfDay(for: $0.day), $0) }, uniquingKeysWith: { first, _ in first })
        let flags = Dictionary(days.map { (calendar.startOfDay(for: $0.day), $0) }, uniquingKeysWith: { first, _ in first })
        let health = Dictionary(input.health.map { (calendar.startOfDay(for: $0.day), $0) }, uniquingKeysWith: { first, _ in first })

        var rows: [DiaryRow] = []
        var day = calendar.startOfDay(for: from)
        while day < to {
            var complaints: [(Date, String)] = (symptomsByDay[day] ?? []).map { row in
                let duration = row.durationMinutes.map { ", " + DurationText.short($0) } ?? ""
                return (row.date, "\(time(row.date)) \(row.type.title) \(row.severity)/5\(duration)")
            }
            complaints += (painsByDay[day] ?? []).map { fact in
                (fact.date, "\(time(fact.date)) Schmerz: \(fact.summary)")
            }
            complaints.sort { $0.0 < $1.0 }
            var complaintTexts = complaints.map(\.1)
            if complaintTexts.isEmpty, flags[day]?.symptomFree == true {
                complaintTexts = ["keine"]
            }
            var activityTexts = (activitiesByDay[day] ?? []).map { "\(time($0.date)) \($0.summary)" }
            if activityTexts.isEmpty, flags[day]?.restDay == true {
                activityTexts = ["Ruhetag"]
            }
            if let steps = health[day]?.stepsText {
                activityTexts.append(steps)
            }
            rows.append(DiaryRow(
                day: day,
                meals: (meals[day] ?? []).map { "\(time($0.date)) \($0.text)" },
                complaints: complaintTexts,
                medications: groupedMedications(meds[day] ?? [], time: time),
                activities: activityTexts,
                wellbeing: checkIns[day].flatMap(wellbeingText)
            ))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return rows
    }

    /// Einnahmen eines Tages je Medikament: „DAO-Enzym: 07:45, 12:15, 18:45“.
    static func groupedMedications(_ events: [DiaryEvent], time: (Date) -> String) -> [String] {
        var order: [String] = []
        var times: [String: [String]] = [:]
        for event in events.sorted(by: { $0.date < $1.date }) {
            if times[event.text] == nil { order.append(event.text) }
            times[event.text, default: []].append(time(event.date))
        }
        return order.map { "\($0): \(times[$0, default: []].joined(separator: ", "))" }
    }

    /// „Schlaf 7,5 Std. · Stimmung 4 · Stress 2“
    static func wellbeingText(_ fact: CheckInFact) -> String? {
        var parts: [String] = []
        if let hours = fact.sleepHours { parts.append("Schlaf \(WeightFormat.number(hours)) Std.") } else if let sleep = fact.sleep { parts.append("Schlaf \(sleep)/5") }
        if let mood = fact.mood { parts.append("Stimmung \(mood)/5") }
        if let stress = fact.stress { parts.append("Stress \(stress)/5") }
        if let energy = fact.energy { parts.append("Energie \(energy)/5") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Verteilt die Tag-für-Tag-Tabelle auf Seiten. Geschätzt wird über Textlänge je Spalte.
public enum DiaryPagination {
    /// Zeichen pro Zeile je Spalte (Essen, Beschwerden, Medikamente, Bewegung, Befinden).
    public static let charsPerLine = [34, 28, 25, 15, 14]

    public static func lines(_ row: DiaryRow) -> Int {
        let columns = [row.meals, row.complaints, row.medications, row.activities, row.wellbeingLines]
        let perColumn = zip(columns, charsPerLine).map { items, width in
            items.reduce(0) { $0 + max(1, Int((Double($1.count) / Double(width)).rounded(.up))) }
        }
        return max(1, perColumn.max() ?? 1)
    }

    public static func pages(_ rows: [DiaryRow], linesPerPage: Int) -> [[DiaryRow]] {
        var pages: [[DiaryRow]] = []
        var current: [DiaryRow] = []
        var used = 0
        for row in rows {
            let needed = lines(row) + 1
            if used + needed > linesPerPage, !current.isEmpty {
                pages.append(current)
                current = []
                used = 0
            }
            current.append(row)
            used += needed
        }
        if !current.isEmpty { pages.append(current) }
        return pages
    }
}
