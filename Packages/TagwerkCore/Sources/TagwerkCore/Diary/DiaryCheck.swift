import Foundation

/// Was an einem Tag fürs Arzt-Tagebuch erfasst ist.
public struct DiaryDayFacts: Sendable, Hashable {
    public var day: Date
    public var meals: Int
    public var symptoms: Int
    public var pains: Int
    /// „Heute keine Beschwerden“ angetippt.
    public var symptomFree: Bool
    /// Bewegung von Hand eingetragen (ohne Gym).
    public var activities: Int
    /// Gym-Einheiten an dem Tag.
    public var gymSessions: Int
    /// „Heute keine Bewegung“ angetippt.
    public var restDay: Bool
    public var dosesDue: Int
    public var dosesResolved: Int
    public var checkIn: Bool
    /// Schritte aus Apple Health (über den Kurzbefehl), 0 = keine.
    public var steps: Int

    public init(
        day: Date, meals: Int = 0, symptoms: Int = 0, pains: Int = 0, symptomFree: Bool = false, activities: Int = 0,
        gymSessions: Int = 0, restDay: Bool = false, dosesDue: Int = 0, dosesResolved: Int = 0, checkIn: Bool = false, steps: Int = 0
    ) {
        self.day = day
        self.meals = meals
        self.symptoms = symptoms
        self.pains = pains
        self.symptomFree = symptomFree
        self.activities = activities
        self.gymSessions = gymSessions
        self.restDay = restDay
        self.dosesDue = dosesDue
        self.dosesResolved = dosesResolved
        self.checkIn = checkIn
        self.steps = steps
    }

    public var hasMeals: Bool { meals > 0 }
    /// Beschwerden oder Schmerzen eingetragen, oder ausdrücklich „keine“.
    public var hasSymptomInfo: Bool { symptoms + pains > 0 || symptomFree }
    public var hasActivityInfo: Bool { activities + gymSessions > 0 || restDay || steps > 0 }
    public var medicationsDone: Bool { dosesResolved >= dosesDue }
    /// Für den Bericht reicht: Essen und Beschwerden.
    public var isComplete: Bool { hasMeals && hasSymptomInfo }
}

/// Ein Punkt der Tages-Checkliste.
public struct DiaryItem: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        case meals, symptoms, activity, medications, checkIn

        public var title: String {
            switch self {
            case .meals: "Essen"
            case .symptoms: "Beschwerden"
            case .activity: "Bewegung"
            case .medications: "Medikamente"
            case .checkIn: "Check-in"
            }
        }

        public var symbol: String {
            switch self {
            case .meals: "fork.knife"
            case .symptoms: "waveform.path.ecg"
            case .activity: "figure.walk"
            case .medications: "pills.fill"
            case .checkIn: "face.smiling"
            }
        }
    }

    public var kind: Kind
    public var isDone: Bool
    /// „2 Mahlzeiten“, „keine“, „noch offen“
    public var detail: String
    public var id: String { kind.rawValue }
}

public enum DiaryCheck {
    /// Checkliste für einen Tag. Medikamente nur, wenn welche geplant sind.
    public static func items(_ facts: DiaryDayFacts) -> [DiaryItem] {
        var items: [DiaryItem] = [
            DiaryItem(kind: .meals, isDone: facts.hasMeals, detail: facts.meals == 0 ? "noch offen" : (facts.meals == 1 ? "1 Mahlzeit" : "\(facts.meals) Mahlzeiten")),
            DiaryItem(kind: .symptoms, isDone: facts.hasSymptomInfo, detail: symptomDetail(facts)),
            DiaryItem(kind: .activity, isDone: facts.hasActivityInfo, detail: activityDetail(facts)),
        ]
        if facts.dosesDue > 0 {
            items.append(DiaryItem(kind: .medications, isDone: facts.medicationsDone, detail: "\(facts.dosesResolved) von \(facts.dosesDue)"))
        }
        items.append(DiaryItem(kind: .checkIn, isDone: facts.checkIn, detail: facts.checkIn ? "erledigt" : "noch offen"))
        return items
    }

    static func symptomDetail(_ facts: DiaryDayFacts) -> String {
        let count = facts.symptoms + facts.pains
        if count > 0 { return count == 1 ? "1 Eintrag" : "\(count) Einträge" }
        return facts.symptomFree ? "keine" : "noch offen"
    }

    static func activityDetail(_ facts: DiaryDayFacts) -> String {
        let count = facts.activities + facts.gymSessions
        if count > 0 { return facts.gymSessions > 0 && facts.activities == 0 ? "Gym" : (count == 1 ? "1 Eintrag" : "\(count) Einträge") }
        if facts.restDay { return "Ruhetag" }
        return facts.steps > 0 ? "\(GermanNumber.grouped(facts.steps)) Schritte" : "noch offen"
    }

    /// Erinnerung am Abend, nur wenn Essen oder Beschwerden noch fehlen.
    public static func reminder(_ facts: DiaryDayFacts, minuteOfDay: Int, now: Date, calendar: Calendar) -> ReminderCandidate? {
        guard minuteOfDay >= 0, calendar.isDate(facts.day, inSameDayAs: now) else { return nil }
        let missing = items(facts).filter { !$0.isDone && ($0.kind == .meals || $0.kind == .symptoms || $0.kind == .activity) }
        guard !missing.isEmpty,
              let fire = calendar.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: facts.day),
              fire > now
        else { return nil }
        let parts = calendar.dateComponents([.year, .month, .day], from: facts.day)
        return ReminderCandidate(
            id: String(format: "%@%04d%02d%02d", NotificationIDs.Prefix.diary, parts.year ?? 0, parts.month ?? 0, parts.day ?? 0),
            kind: .diary,
            fireDate: fire,
            title: "Tagebuch für heute",
            body: "Noch offen: " + missing.map(\.kind.title).joined(separator: ", ") + ". Auch „keine Beschwerden“ zählt.",
            referenceID: "diary"
        )
    }
}

/// Wie lückenlos das Tagebuch im Zeitraum ist.
public struct DiaryCompleteness: Sendable, Hashable {
    public var days: Int
    public var withMeals: Int
    public var withSymptomInfo: Int
    public var withActivityInfo: Int
    public var complete: Int
    public var symptomFreeDays: Int

    public static func compute(_ days: [DiaryDayFacts]) -> DiaryCompleteness {
        DiaryCompleteness(
            days: days.count,
            withMeals: days.filter(\.hasMeals).count,
            withSymptomInfo: days.filter(\.hasSymptomInfo).count,
            withActivityInfo: days.filter(\.hasActivityInfo).count,
            complete: days.filter(\.isComplete).count,
            symptomFreeDays: days.filter { $0.symptomFree && $0.symptoms + $0.pains == 0 }.count
        )
    }

    public static let empty = DiaryCompleteness(days: 0, withMeals: 0, withSymptomInfo: 0, withActivityInfo: 0, complete: 0, symptomFreeDays: 0)

    /// 0…1
    public var fraction: Double { days == 0 ? 0 : Double(complete) / Double(days) }

    /// „Vollständig an 24 von 28 Tagen (86 %)“
    public var summary: String {
        guard days > 0 else { return "Keine Tage im Zeitraum" }
        return "Vollständig an \(complete) von \(days) Tagen (\(Int((fraction * 100).rounded())) %)"
    }
}
