import Foundation

/// Körpermaße.
public enum BodyMetricType: String, Codable, Sendable, CaseIterable, Identifiable {
    case weight, height, bodyFat, waist, chest, upperArm, shoulders, thigh

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .weight: "Gewicht"
        case .height: "Größe"
        case .bodyFat: "Körperfett"
        case .waist: "Taille"
        case .chest: "Brust"
        case .upperArm: "Oberarm"
        case .shoulders: "Schultern"
        case .thigh: "Oberschenkel"
        }
    }

    public var unit: String {
        switch self {
        case .weight: "kg"
        case .bodyFat: "%"
        default: "cm"
        }
    }

    public var symbol: String {
        switch self {
        case .weight: "scalemass"
        case .height: "figure.stand"
        case .bodyFat: "percent"
        default: "ruler"
        }
    }

    /// Schrittweite beim Eintragen.
    public var step: Double {
        switch self {
        case .weight, .bodyFat, .upperArm: 0.1
        default: 0.5
        }
    }

    /// „82,4 kg“
    public func label(_ value: Double) -> String {
        "\(WeightFormat.number(value)) \(unit)"
    }

    /// Sinnvoller Bereich beim Eintragen.
    public var range: ClosedRange<Double> {
        switch self {
        case .weight: 30...250
        case .height: 120...230
        case .bodyFat: 3...60
        default: 10...200
        }
    }
}

/// Body-Mass-Index aus Gewicht (kg) und Größe (cm).
public enum BodyIndex {
    public static func bmi(weight: Double, heightCM: Double) -> Double? {
        guard weight > 0, heightCM > 50 else { return nil }
        let meters = heightCM / 100
        return weight / (meters * meters)
    }

    /// „24,3“
    public static func format(_ bmi: Double) -> String {
        WeightFormat.number((bmi * 10).rounded() / 10)
    }

    /// „1,83 m“
    public static func heightText(_ heightCM: Double) -> String {
        let meters = (heightCM).rounded() / 100
        return WeightFormat.number(meters) + " m"
    }
}

/// Erinnerungen an Trainingstage (Wunsch-Wochentage).
public enum TrainingReminders {
    public static func candidates(
        slots: [TrainingSchedule.Slot],
        minuteOfDay: Int,
        dayTitle: (Int) -> String,
        detail: (Int) -> String,
        now: Date,
        calendar: Calendar
    ) -> [ReminderCandidate] {
        guard minuteOfDay >= 0 else { return [] }
        return slots.compactMap { slot in
            guard let fire = calendar.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: slot.date),
                  fire > now
            else { return nil }
            let parts = calendar.dateComponents([.year, .month, .day], from: slot.date)
            let id = String(format: "%@%04d%02d%02d", NotificationIDs.Prefix.training, parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
            return ReminderCandidate(
                id: id,
                kind: .training,
                fireDate: fire,
                title: "Training heute: \(dayTitle(slot.dayIndex))",
                body: detail(slot.dayIndex),
                referenceID: "\(slot.dayIndex)"
            )
        }
    }
}

// MARK: - Datensicherung

public struct PlanExerciseRecord: Codable, Sendable, Equatable {
    public var stableID: String
    public var exerciseID: String
    public var order: Int
    public var sets: Int
    public var repMin: Int
    public var repMax: Int
    public var rir: Int
    public var restSeconds: Int
    public var superset: String?
    public var note: String
    public var isOptional: Bool

    public init(stableID: String, exerciseID: String, order: Int, sets: Int, repMin: Int, repMax: Int, rir: Int, restSeconds: Int, superset: String?, note: String, isOptional: Bool) {
        self.stableID = stableID
        self.exerciseID = exerciseID
        self.order = order
        self.sets = sets
        self.repMin = repMin
        self.repMax = repMax
        self.rir = rir
        self.restSeconds = restSeconds
        self.superset = superset
        self.note = note
        self.isOptional = isOptional
    }
}

public struct PlanDayRecord: Codable, Sendable, Equatable {
    public var stableID: String
    public var name: String
    public var shortName: String
    public var focus: String
    public var order: Int
    public var isModule: Bool
    public var exercises: [PlanExerciseRecord]

    public init(stableID: String, name: String, shortName: String, focus: String, order: Int, isModule: Bool, exercises: [PlanExerciseRecord]) {
        self.stableID = stableID
        self.name = name
        self.shortName = shortName
        self.focus = focus
        self.order = order
        self.isModule = isModule
        self.exercises = exercises
    }
}

public struct WorkoutPlanRecord: Codable, Sendable, Equatable {
    public var stableID: String
    public var name: String
    public var summary: String
    public var templateID: String?
    public var isActive: Bool
    public var mesoLength: Int
    public var currentWeek: Int
    public var nextDayIndex: Int
    public var moduleDayIndex: Int
    public var preferredWeekdays: [Int]
    public var reminderMinute: Int
    public var createdAt: Date
    public var days: [PlanDayRecord]

    public init(
        stableID: String, name: String, summary: String, templateID: String?, isActive: Bool, mesoLength: Int,
        currentWeek: Int, nextDayIndex: Int, moduleDayIndex: Int, preferredWeekdays: [Int], reminderMinute: Int,
        createdAt: Date, days: [PlanDayRecord]
    ) {
        self.stableID = stableID
        self.name = name
        self.summary = summary
        self.templateID = templateID
        self.isActive = isActive
        self.mesoLength = mesoLength
        self.currentWeek = currentWeek
        self.nextDayIndex = nextDayIndex
        self.moduleDayIndex = moduleDayIndex
        self.preferredWeekdays = preferredWeekdays
        self.reminderMinute = reminderMinute
        self.createdAt = createdAt
        self.days = days
    }
}

public struct SetLogRecord: Codable, Sendable, Equatable {
    public var stableID: String
    public var exerciseID: String
    public var slot: Int
    public var setIndex: Int
    public var kind: String
    public var weight: Double
    public var reps: Int
    public var rir: Int?
    public var isDone: Bool
    public var completedAt: Date?
    public var targetRepMin: Int
    public var targetRepMax: Int
    public var targetRIR: Int
    public var restSeconds: Int
    public var superset: String?
    public var note: String

    public init(
        stableID: String, exerciseID: String, slot: Int, setIndex: Int, kind: String, weight: Double, reps: Int,
        rir: Int?, isDone: Bool, completedAt: Date?, targetRepMin: Int, targetRepMax: Int, targetRIR: Int,
        restSeconds: Int, superset: String?, note: String
    ) {
        self.stableID = stableID
        self.exerciseID = exerciseID
        self.slot = slot
        self.setIndex = setIndex
        self.kind = kind
        self.weight = weight
        self.reps = reps
        self.rir = rir
        self.isDone = isDone
        self.completedAt = completedAt
        self.targetRepMin = targetRepMin
        self.targetRepMax = targetRepMax
        self.targetRIR = targetRIR
        self.restSeconds = restSeconds
        self.superset = superset
        self.note = note
    }
}

public struct WorkoutSessionRecord: Codable, Sendable, Equatable {
    public var stableID: String
    public var planID: String?
    public var dayID: String?
    public var dayName: String
    public var dayShortName: String
    public var dayIndex: Int
    public var week: Int
    public var isDeload: Bool
    public var startedAt: Date
    public var endedAt: Date?
    public var note: String
    public var bodyweight: Double?
    public var includesModule: Bool
    public var sets: [SetLogRecord]

    public init(
        stableID: String, planID: String?, dayID: String?, dayName: String, dayShortName: String, dayIndex: Int,
        week: Int, isDeload: Bool, startedAt: Date, endedAt: Date?, note: String, bodyweight: Double?,
        includesModule: Bool, sets: [SetLogRecord]
    ) {
        self.stableID = stableID
        self.planID = planID
        self.dayID = dayID
        self.dayName = dayName
        self.dayShortName = dayShortName
        self.dayIndex = dayIndex
        self.week = week
        self.isDeload = isDeload
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.note = note
        self.bodyweight = bodyweight
        self.includesModule = includesModule
        self.sets = sets
    }
}

public struct ExercisePreferenceRecord: Codable, Sendable, Equatable {
    public var exerciseID: String
    public var increment: Double?
    public var note: String
    /// Ab Version 0.7: Gewicht für die erste Einheit ohne Verlauf.
    public var startWeight: Double?

    public init(exerciseID: String, increment: Double?, note: String, startWeight: Double? = nil) {
        self.exerciseID = exerciseID
        self.increment = increment
        self.note = note
        self.startWeight = startWeight
    }
}

public struct BodyMetricRecord: Codable, Sendable, Equatable {
    public var stableID: String
    public var date: Date
    public var type: String
    public var value: Double
    public var note: String

    public init(stableID: String, date: Date, type: String, value: Double, note: String) {
        self.stableID = stableID
        self.date = date
        self.type = type
        self.value = value
        self.note = note
    }
}

/// Alles rund ums Training in der Datensicherung (ab Version 0.4).
public struct TrainingBackup: Codable, Sendable, Equatable {
    public var plans: [WorkoutPlanRecord]
    public var sessions: [WorkoutSessionRecord]
    public var customExercises: [ExerciseInfo]
    public var preferences: [ExercisePreferenceRecord]
    public var bodyMetrics: [BodyMetricRecord]

    public init(
        plans: [WorkoutPlanRecord] = [], sessions: [WorkoutSessionRecord] = [], customExercises: [ExerciseInfo] = [],
        preferences: [ExercisePreferenceRecord] = [], bodyMetrics: [BodyMetricRecord] = []
    ) {
        self.plans = plans
        self.sessions = sessions
        self.customExercises = customExercises
        self.preferences = preferences
        self.bodyMetrics = bodyMetrics
    }
}
