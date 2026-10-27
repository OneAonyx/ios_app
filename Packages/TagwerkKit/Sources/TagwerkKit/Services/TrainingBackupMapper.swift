import Foundation
import SwiftData
import TagwerkCore

/// Übersetzt die Trainingsdaten zwischen Datenbank und Datensicherung.
@MainActor
enum TrainingBackupMapper {
    static func makeBackup(context: ModelContext) throws -> TrainingBackup {
        let plans = try context.fetch(FetchDescriptor<WorkoutPlan>(sortBy: [SortDescriptor(\.createdAt)]))
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.startedAt)]))
        let custom = try context.fetch(FetchDescriptor<CustomExercise>(sortBy: [SortDescriptor(\.createdAt)]))
        let preferences = try context.fetch(FetchDescriptor<ExercisePreference>())
        let metrics = try context.fetch(FetchDescriptor<BodyMetric>(sortBy: [SortDescriptor(\.date)]))

        return TrainingBackup(
            plans: plans.map { plan in
                WorkoutPlanRecord(
                    stableID: plan.stableID, name: plan.name, summary: plan.summary, templateID: plan.templateID,
                    isActive: plan.isActive, mesoLength: plan.mesoLength, currentWeek: plan.currentWeek,
                    nextDayIndex: plan.nextDayIndex, moduleDayIndex: plan.moduleDayIndex,
                    preferredWeekdays: plan.preferredWeekdays, reminderMinute: plan.reminderMinute, createdAt: plan.createdAt,
                    days: (plan.days ?? []).sorted { $0.order < $1.order }.map { day in
                        PlanDayRecord(
                            stableID: day.stableID, name: day.name, shortName: day.shortName, focus: day.focus,
                            order: day.order, isModule: day.isModule,
                            exercises: day.sortedExercises.map { item in
                                PlanExerciseRecord(
                                    stableID: item.stableID, exerciseID: item.exerciseID, order: item.order, sets: item.sets,
                                    repMin: item.repMin, repMax: item.repMax, rir: item.rir, restSeconds: item.restSeconds,
                                    superset: item.superset, note: item.note, isOptional: item.isOptional
                                )
                            }
                        )
                    }
                )
            },
            sessions: sessions.map { session in
                WorkoutSessionRecord(
                    stableID: session.stableID, planID: session.planID, dayID: session.dayID, dayName: session.dayName,
                    dayShortName: session.dayShortName, dayIndex: session.dayIndex, week: session.week,
                    isDeload: session.isDeload, startedAt: session.startedAt, endedAt: session.endedAt, note: session.note,
                    bodyweight: session.bodyweight, includesModule: session.includesModule,
                    sets: session.sortedSets.map { set in
                        SetLogRecord(
                            stableID: set.stableID, exerciseID: set.exerciseID, slot: set.slot, setIndex: set.setIndex,
                            kind: set.kindRaw, weight: set.weight, reps: set.reps, rir: set.rir, isDone: set.isDone,
                            completedAt: set.completedAt, targetRepMin: set.targetRepMin, targetRepMax: set.targetRepMax,
                            targetRIR: set.targetRIR, restSeconds: set.restSeconds, superset: set.superset, note: set.note
                        )
                    }
                )
            },
            customExercises: custom.map(\.info),
            preferences: preferences.map { ExercisePreferenceRecord(exerciseID: $0.exerciseID, increment: $0.increment, note: $0.note, startWeight: $0.startWeight) },
            bodyMetrics: metrics.map { BodyMetricRecord(stableID: $0.stableID, date: $0.date, type: $0.typeRaw, value: $0.value, note: $0.note) }
        )
    }

    /// Ersetzt alle Trainingsdaten.
    static func restore(_ backup: TrainingBackup, context: ModelContext) throws {
        for set in try context.fetch(FetchDescriptor<SetLog>()) { context.delete(set) }
        for session in try context.fetch(FetchDescriptor<WorkoutSession>()) { context.delete(session) }
        for item in try context.fetch(FetchDescriptor<PlanExercise>()) { context.delete(item) }
        for day in try context.fetch(FetchDescriptor<PlanDay>()) { context.delete(day) }
        for plan in try context.fetch(FetchDescriptor<WorkoutPlan>()) { context.delete(plan) }
        for custom in try context.fetch(FetchDescriptor<CustomExercise>()) { context.delete(custom) }
        for preference in try context.fetch(FetchDescriptor<ExercisePreference>()) { context.delete(preference) }
        for metric in try context.fetch(FetchDescriptor<BodyMetric>()) { context.delete(metric) }
        try context.save()

        for record in backup.plans {
            let plan = WorkoutPlan(name: record.name, summary: record.summary, templateID: record.templateID, mesoLength: record.mesoLength, stableID: record.stableID, createdAt: record.createdAt)
            plan.isActive = record.isActive
            plan.currentWeek = record.currentWeek
            plan.nextDayIndex = record.nextDayIndex
            plan.moduleDayIndex = record.moduleDayIndex
            plan.preferredWeekdays = record.preferredWeekdays
            plan.reminderMinute = record.reminderMinute
            context.insert(plan)
            for dayRecord in record.days {
                let day = PlanDay(name: dayRecord.name, shortName: dayRecord.shortName, focus: dayRecord.focus, order: dayRecord.order, isModule: dayRecord.isModule, stableID: dayRecord.stableID)
                context.insert(day)
                day.plan = plan
                for itemRecord in dayRecord.exercises {
                    let item = PlanExercise(
                        exerciseID: itemRecord.exerciseID, order: itemRecord.order, sets: itemRecord.sets, repMin: itemRecord.repMin,
                        repMax: itemRecord.repMax, rir: itemRecord.rir, restSeconds: itemRecord.restSeconds,
                        superset: itemRecord.superset, note: itemRecord.note, isOptional: itemRecord.isOptional, stableID: itemRecord.stableID
                    )
                    context.insert(item)
                    item.day = day
                }
            }
        }
        for record in backup.sessions {
            let session = WorkoutSession(dayName: record.dayName, dayShortName: record.dayShortName, dayIndex: record.dayIndex, week: record.week, isDeload: record.isDeload, startedAt: record.startedAt, stableID: record.stableID)
            session.planID = record.planID
            session.dayID = record.dayID
            session.endedAt = record.endedAt
            session.note = record.note
            session.bodyweight = record.bodyweight
            session.includesModule = record.includesModule
            context.insert(session)
            for setRecord in record.sets {
                let set = SetLog(
                    exerciseID: setRecord.exerciseID, slot: setRecord.slot, setIndex: setRecord.setIndex,
                    kind: SetKind(rawValue: setRecord.kind) ?? .working, weight: setRecord.weight, reps: setRecord.reps,
                    targetRepMin: setRecord.targetRepMin, targetRepMax: setRecord.targetRepMax, targetRIR: setRecord.targetRIR,
                    restSeconds: setRecord.restSeconds, superset: setRecord.superset, stableID: setRecord.stableID
                )
                set.rir = setRecord.rir
                set.isDone = setRecord.isDone
                set.completedAt = setRecord.completedAt
                set.note = setRecord.note
                context.insert(set)
                set.session = session
            }
        }
        for info in backup.customExercises {
            let custom = CustomExercise(stableID: info.id, name: info.name)
            TrainingActions.apply(info, to: custom)
            context.insert(custom)
        }
        for record in backup.preferences {
            let preference = ExercisePreference(exerciseID: record.exerciseID)
            preference.increment = record.increment
            preference.note = record.note
            preference.startWeight = record.startWeight
            context.insert(preference)
        }
        for record in backup.bodyMetrics {
            context.insert(BodyMetric(date: record.date, type: BodyMetricType(rawValue: record.type) ?? .weight, value: record.value, note: record.note, stableID: record.stableID))
        }
    }
}
