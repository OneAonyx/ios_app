import Foundation
import SwiftData
import TagwerkCore

/// Version 3 des Datenmodells (Phase 3): Training.
///
/// Aufgaben (V1) und Medikamente (V2) sind unverändert und werden übernommen.
/// Der Umstieg von V2 ist eine leichte Migration (nur neue Tabellen).
public enum TagwerkSchemaV3: VersionedSchema {
    public static let versionIdentifier = Schema.Version(3, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            TagwerkSchemaV1.TaskItem.self,
            TagwerkSchemaV1.Subtask.self,
            TagwerkSchemaV1.TaskList.self,
            TagwerkSchemaV2.Medication.self,
            TagwerkSchemaV2.DoseLog.self,
            WorkoutPlan.self,
            PlanDay.self,
            PlanExercise.self,
            WorkoutSession.self,
            SetLog.self,
            CustomExercise.self,
            ExercisePreference.self,
            BodyMetric.self,
        ]
    }

    /// Ein Trainingsplan mit Tagen in Rotation (A → B → C → D).
    @Model
    public final class WorkoutPlan {
        public var stableID: String = UUID().uuidString
        public var name: String = ""
        public var summary: String = ""
        /// Vorlage, aus der der Plan entstand (z. B. „upper-4day“).
        public var templateID: String?
        public var isActive: Bool = true
        /// Zykluslänge in Wochen inklusive Deload.
        public var mesoLength: Int = 6
        public var currentWeek: Int = 1
        public var nextDayIndex: Int = 0
        /// An welchen Tag das Zusatzmodul („Beine & Rumpf“) gehängt wird, −1 = aus.
        public var moduleDayIndex: Int = -1
        /// Wunsch-Wochentage (`Calendar`-Wochentag) für Erinnerung und Agenda.
        public var preferredWeekdays: [Int] = []
        /// Erinnerung an Trainingstagen (Minute des Tages), −1 = keine.
        public var reminderMinute: Int = -1
        public var createdAt: Date = Date()

        @Relationship(deleteRule: .cascade, inverse: \PlanDay.plan)
        public var days: [PlanDay]? = []

        public init(name: String, summary: String = "", templateID: String? = nil, mesoLength: Int = 6, stableID: String = UUID().uuidString, createdAt: Date = Date()) {
            self.stableID = stableID
            self.name = name
            self.summary = summary
            self.templateID = templateID
            self.mesoLength = mesoLength
            self.createdAt = createdAt
        }
    }

    @Model
    public final class PlanDay {
        public var stableID: String = UUID().uuidString
        public var name: String = ""
        public var shortName: String = ""
        public var focus: String = ""
        public var order: Int = 0
        /// Zusatzmodul statt Tag in der Rotation.
        public var isModule: Bool = false
        public var plan: WorkoutPlan?

        @Relationship(deleteRule: .cascade, inverse: \PlanExercise.day)
        public var exercises: [PlanExercise]? = []

        public init(name: String, shortName: String = "", focus: String = "", order: Int = 0, isModule: Bool = false, stableID: String = UUID().uuidString) {
            self.stableID = stableID
            self.name = name
            self.shortName = shortName
            self.focus = focus
            self.order = order
            self.isModule = isModule
        }
    }

    @Model
    public final class PlanExercise {
        public var stableID: String = UUID().uuidString
        public var exerciseID: String = ""
        public var order: Int = 0
        public var sets: Int = 3
        public var repMin: Int = 8
        public var repMax: Int = 12
        public var rir: Int = 2
        public var restSeconds: Int = 90
        public var superset: String?
        public var note: String = ""
        public var isOptional: Bool = false
        public var day: PlanDay?

        public init(
            exerciseID: String, order: Int, sets: Int, repMin: Int, repMax: Int, rir: Int, restSeconds: Int,
            superset: String? = nil, note: String = "", isOptional: Bool = false, stableID: String = UUID().uuidString
        ) {
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

    /// Eine Trainingseinheit. Läuft, solange `endedAt` leer ist.
    @Model
    public final class WorkoutSession {
        public var stableID: String = UUID().uuidString
        public var planID: String?
        public var dayID: String?
        public var dayName: String = ""
        public var dayShortName: String = ""
        public var dayIndex: Int = 0
        public var week: Int = 1
        public var isDeload: Bool = false
        public var startedAt: Date = Date()
        public var endedAt: Date?
        public var note: String = ""
        public var bodyweight: Double?
        public var includesModule: Bool = false

        @Relationship(deleteRule: .cascade, inverse: \SetLog.session)
        public var sets: [SetLog]? = []

        public init(dayName: String, dayShortName: String, dayIndex: Int, week: Int, isDeload: Bool, startedAt: Date = Date(), stableID: String = UUID().uuidString) {
            self.stableID = stableID
            self.dayName = dayName
            self.dayShortName = dayShortName
            self.dayIndex = dayIndex
            self.week = week
            self.isDeload = isDeload
            self.startedAt = startedAt
        }
    }

    /// Ein (geplanter oder erledigter) Satz einer Einheit.
    @Model
    public final class SetLog {
        public var stableID: String = UUID().uuidString
        public var exerciseID: String = ""
        /// Position der Übung in der Einheit.
        public var slot: Int = 0
        public var setIndex: Int = 0
        public var kindRaw: String = SetKind.working.rawValue
        public var weight: Double = 0
        public var reps: Int = 0
        public var rir: Int?
        public var isDone: Bool = false
        public var completedAt: Date?
        public var targetRepMin: Int = 8
        public var targetRepMax: Int = 12
        public var targetRIR: Int = 2
        public var restSeconds: Int = 90
        public var superset: String?
        public var note: String = ""
        public var session: WorkoutSession?

        public init(
            exerciseID: String, slot: Int, setIndex: Int, kind: SetKind, weight: Double, reps: Int,
            targetRepMin: Int, targetRepMax: Int, targetRIR: Int, restSeconds: Int, superset: String? = nil,
            stableID: String = UUID().uuidString
        ) {
            self.stableID = stableID
            self.exerciseID = exerciseID
            self.slot = slot
            self.setIndex = setIndex
            self.kindRaw = kind.rawValue
            self.weight = weight
            self.reps = reps
            self.targetRepMin = targetRepMin
            self.targetRepMax = targetRepMax
            self.targetRIR = targetRIR
            self.restSeconds = restSeconds
            self.superset = superset
        }
    }

    /// Selbst angelegte Übung (ergänzt die mitgelieferte Bibliothek).
    @Model
    public final class CustomExercise {
        public var stableID: String = ""
        public var name: String = ""
        public var primaryRaw: [String] = []
        public var secondaryRaw: [String] = []
        public var equipmentRaw: String = Equipment.machine.rawValue
        public var mechanicRaw: String = Mechanic.isolation.rawValue
        public var increment: Double = 2.5
        public var rest: Int = 90
        public var assisted: Bool = false
        public var notes: String = ""
        public var createdAt: Date = Date()

        public init(stableID: String, name: String, createdAt: Date = Date()) {
            self.stableID = stableID
            self.name = name
            self.createdAt = createdAt
        }
    }

    /// Eigene Einstellungen zu einer Übung (z. B. kleinere Steigerung im eigenen Gym).
    @Model
    public final class ExercisePreference {
        public var exerciseID: String = ""
        public var increment: Double?
        public var note: String = ""

        public init(exerciseID: String) {
            self.exerciseID = exerciseID
        }
    }

    @Model
    public final class BodyMetric {
        public var stableID: String = UUID().uuidString
        public var date: Date = Date()
        public var typeRaw: String = BodyMetricType.weight.rawValue
        public var value: Double = 0
        public var note: String = ""

        public init(date: Date, type: BodyMetricType, value: Double, note: String = "", stableID: String = UUID().uuidString) {
            self.stableID = stableID
            self.date = date
            self.typeRaw = type.rawValue
            self.value = value
            self.note = note
        }
    }
}

public typealias WorkoutPlan = TagwerkSchemaV3.WorkoutPlan
public typealias PlanDay = TagwerkSchemaV3.PlanDay
public typealias PlanExercise = TagwerkSchemaV3.PlanExercise
public typealias WorkoutSession = TagwerkSchemaV3.WorkoutSession
public typealias SetLog = TagwerkSchemaV3.SetLog
public typealias CustomExercise = TagwerkSchemaV3.CustomExercise
public typealias ExercisePreference = TagwerkSchemaV3.ExercisePreference
public typealias BodyMetric = TagwerkSchemaV3.BodyMetric

// MARK: - Bequeme Zugriffe

extension TagwerkSchemaV3.WorkoutPlan {
    public var cycle: Mesocycle { Mesocycle(length: mesoLength) }

    /// Tage in der Rotation, sortiert.
    public var rotationDays: [PlanDay] {
        (days ?? []).filter { !$0.isModule }.sorted { $0.order < $1.order }
    }

    /// Zusatzmodul (z. B. „Beine & Rumpf“).
    public var module: PlanDay? {
        (days ?? []).filter(\.isModule).sorted { $0.order < $1.order }.first
    }

    public var progress: PlanProgress {
        get { PlanProgress(nextDayIndex: nextDayIndex, week: currentWeek) }
        set {
            nextDayIndex = newValue.nextDayIndex
            currentWeek = newValue.week
        }
    }

    /// Die nächste Einheit in der Rotation.
    public var nextDay: PlanDay? {
        let days = rotationDays
        guard !days.isEmpty else { return nil }
        return days[min(max(nextDayIndex, 0), days.count - 1)]
    }

    public var isDeloadWeek: Bool { cycle.isDeload(week: currentWeek) }
}

extension TagwerkSchemaV3.PlanDay {
    public var sortedExercises: [PlanExercise] {
        (exercises ?? []).sorted { $0.order < $1.order }
    }

    /// „A · Push“
    public var title: String {
        shortName.isEmpty ? name : "\(shortName) · \(name)"
    }

    /// Ungefähre Dauer in Minuten.
    public func estimatedMinutes(week: Int, cycle: Mesocycle) -> Int {
        WorkoutEstimate.minutes(sortedExercises.filter { !$0.isOptional }.map { (cycle.sets(base: $0.sets, week: week), $0.restSeconds) })
    }
}

extension TagwerkSchemaV3.PlanExercise {
    public var template: ExerciseTemplate {
        ExerciseTemplate(exercise: exerciseID, sets: sets, repMin: repMin, repMax: repMax, rir: rir, restSec: restSeconds, superset: superset, note: note.isEmpty ? nil : note, optional: isOptional)
    }
}

extension TagwerkSchemaV3.WorkoutSession {
    public var isActive: Bool { endedAt == nil }

    /// „A · Push“
    public var title: String {
        dayShortName.isEmpty ? dayName : "\(dayShortName) · \(dayName)"
    }

    public var sortedSets: [SetLog] {
        (sets ?? []).sorted { lhs, rhs in
            if lhs.slot != rhs.slot { return lhs.slot < rhs.slot }
            if lhs.kind != rhs.kind { return lhs.kind == .warmup }
            return lhs.setIndex < rhs.setIndex
        }
    }

    /// Übungs-Positionen der Einheit, in Reihenfolge.
    public var slots: [Int] {
        Array(Set((sets ?? []).map(\.slot))).sorted()
    }

    public func sets(inSlot slot: Int) -> [SetLog] {
        sortedSets.filter { $0.slot == slot }
    }

    public func exerciseID(inSlot slot: Int) -> String? {
        sets(inSlot: slot).first?.exerciseID
    }

    public var doneSets: [SetLog] { (sets ?? []).filter(\.isDone) }

    public var duration: TimeInterval {
        (endedAt ?? .now).timeIntervalSince(startedAt)
    }

    /// Gesamtvolumen der erledigten Arbeits- und Drop-Sätze.
    public var volume: Double {
        doneSets.filter { $0.kind != .warmup }.reduce(0) { $0 + $1.weight * Double($1.reps) }
    }
}

extension TagwerkSchemaV3.SetLog {
    public var kind: SetKind {
        get { SetKind(rawValue: kindRaw) ?? .working }
        set { kindRaw = newValue.rawValue }
    }

    public var logged: LoggedSet {
        LoggedSet(weight: weight, reps: reps, rir: rir, kind: kind)
    }

    /// „6–8“
    public var targetLabel: String {
        targetRepMin == targetRepMax ? "\(targetRepMin)" : "\(targetRepMin)–\(targetRepMax)"
    }
}

extension TagwerkSchemaV3.CustomExercise {
    public var info: ExerciseInfo {
        ExerciseInfo(
            id: stableID,
            name: name,
            primary: primaryRaw.compactMap(MuscleGroup.init(rawValue:)),
            secondary: secondaryRaw.compactMap(MuscleGroup.init(rawValue:)),
            equipment: Equipment(rawValue: equipmentRaw) ?? .other,
            mechanic: Mechanic(rawValue: mechanicRaw) ?? .isolation,
            increment: increment,
            rest: rest,
            assisted: assisted,
            cues: notes.isEmpty ? [] : [notes],
            isCustom: true
        )
    }
}

extension TagwerkSchemaV3.BodyMetric {
    public var type: BodyMetricType {
        get { BodyMetricType(rawValue: typeRaw) ?? .weight }
        set { typeRaw = newValue.rawValue }
    }
}
