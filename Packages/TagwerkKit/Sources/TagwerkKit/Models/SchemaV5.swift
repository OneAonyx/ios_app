import Foundation
import SwiftData
import TagwerkCore

/// Version 5 des Datenmodells (Phase 5): Check-ins und Claude-Verlauf.
///
/// Alle Modelle aus V1–V4 sind unverändert und werden übernommen.
/// Der Umstieg von V4 ist eine leichte Migration (nur neue Tabellen).
public enum TagwerkSchemaV5: VersionedSchema {
    public static let versionIdentifier = Schema.Version(5, 0, 0)

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
            TagwerkSchemaV3.ExercisePreference.self,
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
            DailyCheckIn.self,
            ClaudeExchange.self,
        ]
    }

    /// Check-in eines Tages: morgens Schlaf und Energie, abends Stimmung und Stress.
    @Model
    public final class DailyCheckIn {
        public var stableID: String = UUID().uuidString
        /// Tagesbeginn.
        public var day: Date = Date()
        public var sleep: Int?
        public var sleepHours: Double?
        public var energy: Int?
        public var mood: Int?
        public var stress: Int?
        public var note: String = ""
        public var updatedAt: Date = Date()

        public init(day: Date, stableID: String = UUID().uuidString) {
            self.stableID = stableID
            self.day = day
        }
    }

    /// Eine Anfrage an Claude mit Antwort (Verlauf).
    @Model
    public final class ClaudeExchange {
        public var stableID: String = UUID().uuidString
        public var taskRaw: String = ClaudeTask.weeklyReview.rawValue
        public var ref: String = ""
        public var title: String = ""
        public var prompt: String = ""
        public var response: String = ""
        public var statusRaw: String = ClaudeExchangeStatus.draft.rawValue
        public var createdAt: Date = Date()
        public var answeredAt: Date?

        public init(task: ClaudeTask, ref: String, title: String, prompt: String, stableID: String = UUID().uuidString, createdAt: Date = Date()) {
            self.stableID = stableID
            self.taskRaw = task.rawValue
            self.ref = ref
            self.title = title
            self.prompt = prompt
            self.createdAt = createdAt
        }
    }
}

public typealias DailyCheckIn = TagwerkSchemaV5.DailyCheckIn
public typealias ClaudeExchange = TagwerkSchemaV5.ClaudeExchange

public extension TagwerkSchemaV5.DailyCheckIn {
    var fact: CheckInFact {
        CheckInFact(day: day, sleep: sleep, sleepHours: sleepHours, energy: energy, mood: mood, stress: stress, note: note)
    }

    func value(_ scale: CheckInScale) -> Int? {
        fact.value(scale)
    }

    func set(_ scale: CheckInScale, _ value: Int?) {
        let clamped = value.map { min(max($0, 1), 5) }
        switch scale {
        case .sleep: sleep = clamped
        case .energy: energy = clamped
        case .mood: mood = clamped
        case .stress: stress = clamped
        }
        updatedAt = .now
    }
}

public extension TagwerkSchemaV5.ClaudeExchange {
    var task: ClaudeTask {
        ClaudeTask(rawValue: taskRaw) ?? .weeklyReview
    }

    var status: ClaudeExchangeStatus {
        get { ClaudeExchangeStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }
}
