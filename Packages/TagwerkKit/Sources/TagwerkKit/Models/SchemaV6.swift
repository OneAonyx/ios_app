import Foundation
import SwiftData
import TagwerkCore

/// Version 6 des Datenmodells (Phase 6): Routinen, Gewohnheiten, Verträge und Fristen,
/// Geburtstage, Tagebuch, dazu ein Startgewicht je Übung.
///
/// `ExercisePreference` bekommt das Feld `startWeight`, alle anderen Modelle aus V1–V5 bleiben.
/// Der Umstieg von V5 ist eine leichte Migration (neue Tabellen, ein neues optionales Feld).
public enum TagwerkSchemaV6: VersionedSchema {
    public static let versionIdentifier = Schema.Version(6, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            TagwerkSchemaV1.TaskItem.self,
            TagwerkSchemaV1.Subtask.self,
            TagwerkSchemaV1.TaskList.self,
            TagwerkSchemaV2.Medication.self,
            TagwerkSchemaV2.DoseLog.self,
            TagwerkSchemaV3.WorkoutPlan.self,
            TagwerkSchemaV3.PlanDay.self,
            TagwerkSchemaV3.PlanExercise.self,
            TagwerkSchemaV3.WorkoutSession.self,
            TagwerkSchemaV3.SetLog.self,
            TagwerkSchemaV3.CustomExercise.self,
            ExercisePreference.self,
            TagwerkSchemaV3.BodyMetric.self,
            TagwerkSchemaV4.FoodPreference.self,
            TagwerkSchemaV4.CustomFood.self,
            TagwerkSchemaV4.MealEntry.self,
            TagwerkSchemaV4.MealItem.self,
            TagwerkSchemaV4.SymptomEntry.self,
            TagwerkSchemaV4.WaterLog.self,
            TagwerkSchemaV4.ShoppingItem.self,
            TagwerkSchemaV4.MealPlanEntry.self,
            TagwerkSchemaV4.CustomRecipe.self,
            TagwerkSchemaV5.DailyCheckIn.self,
            TagwerkSchemaV5.ClaudeExchange.self,
            Habit.self,
            HabitLog.self,
            Contract.self,
            Birthday.self,
            JournalEntry.self,
        ]
    }

    /// Eigene Einstellungen je Übung (wie V3, dazu das Startgewicht).
    @Model
    public final class ExercisePreference {
        public var exerciseID: String = ""
        public var increment: Double?
        public var note: String = ""
        /// Gewicht für die erste Einheit, solange es keinen Verlauf gibt.
        public var startWeight: Double?

        public init(exerciseID: String) {
            self.exerciseID = exerciseID
        }
    }

    /// Routine (abhakbare Schritte) oder Gewohnheit (Zielwert je Tag).
    @Model
    public final class Habit {
        public var stableID: String = UUID().uuidString
        public var kindRaw: String = HabitKind.habit.rawValue
        public var name: String = ""
        public var symbol: String = "checkmark.circle"
        public var colorName: String = "orange"
        public var periodRaw: String = HabitPeriod.anytime.rawValue
        /// `HabitSchedule` als JSON.
        public var scheduleData: Data?
        public var target: Double = 1
        /// Einheit des Zielwerts, z. B. „Min.“ (leer = Anzahl).
        public var unit: String = ""
        /// `[RoutineStep]` als JSON.
        public var stepsData: Data?
        /// Minute des Tages für die Erinnerung, −1 = keine.
        public var reminderMinute: Int = -1
        public var sortIndex: Double = 0
        public var isArchived: Bool = false
        public var createdAt: Date = Date()

        public init(name: String, kind: HabitKind, stableID: String = UUID().uuidString, createdAt: Date = Date()) {
            self.stableID = stableID
            self.name = name
            self.kindRaw = kind.rawValue
            self.createdAt = createdAt
        }
    }

    /// Was an einem Tag für eine Routine oder Gewohnheit erledigt wurde.
    @Model
    public final class HabitLog {
        public var stableID: String = UUID().uuidString
        public var habitID: String = ""
        /// Tagesbeginn.
        public var day: Date = Date()
        public var value: Double = 0
        public var doneSteps: [String] = []
        public var updatedAt: Date = Date()

        public init(habitID: String, day: Date, stableID: String = UUID().uuidString) {
            self.stableID = stableID
            self.habitID = habitID
            self.day = day
        }
    }

    /// Vertrag, Abo, Versicherung oder Dokument mit Ablaufdatum.
    @Model
    public final class Contract {
        public var stableID: String = UUID().uuidString
        public var kindRaw: String = ContractKind.contract.rawValue
        public var name: String = ""
        public var provider: String = ""
        public var cost: Double?
        public var billingRaw: String = BillingCycle.monthly.rawValue
        public var startDate: Date?
        public var endDate: Date?
        public var minimumTermMonths: Int?
        public var renewalMonths: Int?
        public var noticeValue: Int = 0
        public var noticeUnitRaw: String = NoticePeriod.Unit.months.rawValue
        public var reminderDaysBefore: Int = 14
        public var note: String = ""
        public var isCancelled: Bool = false
        public var createdAt: Date = Date()

        public init(name: String, kind: ContractKind, stableID: String = UUID().uuidString, createdAt: Date = Date()) {
            self.stableID = stableID
            self.name = name
            self.kindRaw = kind.rawValue
            self.createdAt = createdAt
        }
    }

    @Model
    public final class Birthday {
        public var stableID: String = UUID().uuidString
        public var name: String = ""
        public var day: Int = 1
        public var month: Int = 1
        public var year: Int?
        public var reminderDaysBefore: Int = 3
        /// z. B. Geschenkideen.
        public var note: String = ""
        public var createdAt: Date = Date()

        public init(name: String, day: Int, month: Int, year: Int? = nil, stableID: String = UUID().uuidString, createdAt: Date = Date()) {
            self.stableID = stableID
            self.name = name
            self.day = day
            self.month = month
            self.year = year
            self.createdAt = createdAt
        }
    }

    /// Tagebuch: Antwort auf die Frage des Tages und freie Notiz.
    @Model
    public final class JournalEntry {
        public var stableID: String = UUID().uuidString
        /// Tagesbeginn.
        public var day: Date = Date()
        public var prompt: String = ""
        public var answer: String = ""
        public var text: String = ""
        public var updatedAt: Date = Date()

        public init(day: Date, prompt: String, stableID: String = UUID().uuidString) {
            self.stableID = stableID
            self.day = day
            self.prompt = prompt
        }
    }
}

public typealias ExercisePreference = TagwerkSchemaV6.ExercisePreference
public typealias Habit = TagwerkSchemaV6.Habit
public typealias HabitLog = TagwerkSchemaV6.HabitLog
public typealias Contract = TagwerkSchemaV6.Contract
public typealias Birthday = TagwerkSchemaV6.Birthday
public typealias JournalEntry = TagwerkSchemaV6.JournalEntry

// MARK: - Bequeme Zugriffe

public extension TagwerkSchemaV6.Habit {
    var kind: HabitKind {
        get { HabitKind(rawValue: kindRaw) ?? .habit }
        set { kindRaw = newValue.rawValue }
    }

    var period: HabitPeriod {
        get { HabitPeriod(rawValue: periodRaw) ?? .anytime }
        set { periodRaw = newValue.rawValue }
    }

    var schedule: HabitSchedule {
        get { HabitSchedule.decode(scheduleData) ?? .daily }
        set { scheduleData = newValue.encoded() }
    }

    var steps: [RoutineStep] {
        get { RoutineStep.decode(stepsData) }
        set { stepsData = RoutineStep.encode(newValue) }
    }

    var fact: HabitFact {
        HabitFact(kind: kind, schedule: schedule, target: target, steps: steps, createdAt: createdAt)
    }

    /// „10 Min.“, „1×“
    var targetText: String {
        let value = WeightFormat.number(target)
        return unit.isEmpty ? "\(value)×" : "\(value) \(unit)"
    }
}

public extension TagwerkSchemaV6.HabitLog {
    var habitDay: HabitDay {
        HabitDay(day: day, value: value, doneSteps: Set(doneSteps))
    }
}

public extension TagwerkSchemaV6.Contract {
    var kind: ContractKind {
        get { ContractKind(rawValue: kindRaw) ?? .contract }
        set { kindRaw = newValue.rawValue }
    }

    var billing: BillingCycle {
        get { BillingCycle(rawValue: billingRaw) ?? .monthly }
        set { billingRaw = newValue.rawValue }
    }

    var notice: NoticePeriod {
        get { NoticePeriod(value: noticeValue, unit: NoticePeriod.Unit(rawValue: noticeUnitRaw) ?? .months) }
        set {
            noticeValue = newValue.value
            noticeUnitRaw = newValue.unit.rawValue
        }
    }

    var fact: ContractFact {
        ContractFact(
            kind: kind, name: name, cost: cost, billing: billing, startDate: startDate, endDate: endDate,
            minimumTermMonths: minimumTermMonths, renewalMonths: renewalMonths, notice: notice,
            reminderDaysBefore: reminderDaysBefore, isCancelled: isCancelled
        )
    }
}

public extension TagwerkSchemaV6.Birthday {
    var fact: BirthdayFact {
        BirthdayFact(name: name, day: day, month: month, year: year, reminderDaysBefore: reminderDaysBefore)
    }
}
