import Foundation
import SwiftData
import SwiftUI
import TagwerkCore

/// Alle Änderungen rund ums Training an einer Stelle (App, Live Activity, Siri, Widgets).
@MainActor
public enum TrainingActions {
    // MARK: Bibliothek

    /// Mitgelieferte Übungen (einmal geladen).
    public static let bundledCatalog = ExerciseCatalog.bundled()

    /// Mitgelieferte plus eigene Übungen.
    public static func catalog(in context: ModelContext) -> ExerciseCatalog {
        let custom = (try? context.fetch(FetchDescriptor<CustomExercise>())) ?? []
        return bundledCatalog.adding(custom.map(\.info))
    }

    /// Übung oder ein Platzhalter, falls sie (z. B. nach dem Löschen) fehlt.
    public static func info(for exerciseID: String, catalog: ExerciseCatalog) -> ExerciseInfo {
        catalog.exercise(id: exerciseID)
            ?? ExerciseInfo(id: exerciseID, name: exerciseID, primary: [], equipment: .other, mechanic: .isolation, isCustom: true)
    }

    public static func preference(for exerciseID: String, in context: ModelContext) -> ExercisePreference? {
        var descriptor = FetchDescriptor<ExercisePreference>(predicate: #Predicate { $0.exerciseID == exerciseID })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// Steigerungsschritt: eigene Einstellung oder Standard der Übung.
    public static func increment(for exercise: ExerciseInfo, in context: ModelContext) -> Double {
        preference(for: exercise.id, in: context)?.increment ?? exercise.increment
    }

    public static func setIncrement(_ value: Double?, for exerciseID: String, in context: ModelContext) {
        let preference = preference(for: exerciseID, in: context) ?? {
            let created = ExercisePreference(exerciseID: exerciseID)
            context.insert(created)
            return created
        }()
        preference.increment = value
        save(context)
    }

    /// Gewicht für die erste Einheit ohne Verlauf (z. B. aus dem bisherigen Training).
    public static func startWeight(for exerciseID: String, in context: ModelContext) -> Double? {
        preference(for: exerciseID, in: context)?.startWeight
    }

    public static func setStartWeight(_ value: Double?, for exerciseID: String, in context: ModelContext) {
        let record = preference(for: exerciseID, in: context) ?? {
            let created = ExercisePreference(exerciseID: exerciseID)
            context.insert(created)
            return created
        }()
        record.startWeight = value.flatMap { $0 > 0 ? $0 : nil }
        save(context)
    }

    @discardableResult
    public static func createCustomExercise(_ info: ExerciseInfo, in context: ModelContext) -> CustomExercise {
        let exercise = CustomExercise(stableID: info.id, name: info.name)
        apply(info, to: exercise)
        context.insert(exercise)
        save(context)
        return exercise
    }

    public static func apply(_ info: ExerciseInfo, to exercise: CustomExercise) {
        exercise.name = info.name
        exercise.primaryRaw = info.primary.map(\.rawValue)
        exercise.secondaryRaw = info.secondary.map(\.rawValue)
        exercise.equipmentRaw = info.equipment.rawValue
        exercise.mechanicRaw = info.mechanic.rawValue
        exercise.increment = info.increment
        exercise.rest = info.rest
        exercise.assisted = info.assisted
        exercise.notes = info.cues.first ?? ""
    }

    // MARK: Pläne

    public static func plans(in context: ModelContext) -> [WorkoutPlan] {
        (try? context.fetch(FetchDescriptor<WorkoutPlan>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    public static func activePlan(in context: ModelContext) -> WorkoutPlan? {
        let all = plans(in: context)
        return all.last(where: \.isActive) ?? all.last
    }

    /// Legt beim ersten Start den Startplan an. Gibt den aktiven Plan zurück.
    @discardableResult
    public static func ensureStarterPlan(in context: ModelContext, now: Date = .now) -> WorkoutPlan? {
        if let plan = activePlan(in: context) { return plan }
        guard let template = PlanTemplate.bundledUpperFourDay() else { return nil }
        return createPlan(from: template, in: context, now: now)
    }

    /// Neuer Plan aus einer Vorlage; wird der aktive Plan.
    @discardableResult
    public static func createPlan(from template: PlanTemplate, in context: ModelContext, now: Date = .now) -> WorkoutPlan {
        for existing in plans(in: context) { existing.isActive = false }
        let plan = WorkoutPlan(name: template.name, summary: template.summary ?? "", templateID: template.id, mesoLength: template.mesoWeeks, createdAt: now)
        plan.preferredWeekdays = [2, 3, 5, 7]
        context.insert(plan)
        for (index, dayTemplate) in template.days.enumerated() {
            insertDay(dayTemplate, order: index, isModule: false, into: plan, context: context)
        }
        for (index, moduleTemplate) in template.modules.enumerated() {
            insertDay(moduleTemplate, order: 100 + index, isModule: true, into: plan, context: context)
        }
        // Startgewichte aus der Vorlage (gelten nur, solange es zur Übung keinen Verlauf gibt).
        for (exerciseID, weight) in template.startWeights {
            let record = preference(for: exerciseID, in: context) ?? {
                let created = ExercisePreference(exerciseID: exerciseID)
                context.insert(created)
                return created
            }()
            record.startWeight = weight
        }
        save(context)
        return plan
    }

    /// Einmalig: „Oberkörper 4er – meine Übungen“ anlegen und aktiv setzen (Version 0.7).
    /// Gibt den neuen Plan zurück, wenn er gerade angelegt wurde.
    @discardableResult
    public static func ensureOwnPlan(in context: ModelContext, defaults: UserDefaults = .standard, now: Date = .now) -> WorkoutPlan? {
        let key = "tagwerk.training.ownPlanApplied"
        guard !defaults.bool(forKey: key), let template = PlanTemplate.bundledOwnFourDay() else { return nil }
        defaults.set(true, forKey: key)
        if plans(in: context).contains(where: { $0.templateID == template.id }) { return nil }
        let plan = createPlan(from: template, in: context, now: now)
        // Fünfmal pro Woche: Mo, Di, Mi, Fr, Sa.
        plan.preferredWeekdays = [2, 3, 4, 6, 7]
        save(context)
        return plan
    }

    /// „1,83 m, 82,4 kg“ für Claude, leer ohne Angaben.
    public static func bodySummary(in context: ModelContext) -> String {
        let height = metrics(.height, in: context).last?.value
        let weight = metrics(.weight, in: context).last?.value
        return [height.map(BodyIndex.heightText), weight.map { "\(WeightFormat.number($0)) kg" }].compactMap { $0 }.joined(separator: ", ")
    }

    private static func insertDay(_ template: DayTemplate, order: Int, isModule: Bool, into plan: WorkoutPlan, context: ModelContext) {
        let fallbackShort = isModule ? "+" : letter(order)
        let day = PlanDay(name: template.name, shortName: template.shortName ?? fallbackShort, focus: template.focus ?? "", order: order, isModule: isModule)
        context.insert(day)
        day.plan = plan
        for (index, item) in template.exercises.enumerated() {
            let exercise = PlanExercise(
                exerciseID: item.exercise, order: index, sets: item.sets, repMin: item.repMin, repMax: item.repMax,
                rir: item.rir, restSeconds: item.restSec, superset: item.superset, note: item.note ?? "", isOptional: item.optional
            )
            context.insert(exercise)
            exercise.day = day
        }
    }

    /// „A“, „B“, … für Tage in der Rotation.
    static func letter(_ index: Int) -> String {
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return String(letters[min(max(index, 0), letters.count - 1)])
    }

    /// Übernimmt einen importierten Plan und legt unbekannte Übungen als eigene an.
    @discardableResult
    public static func importPlan(_ imported: ImportedPlan, in context: ModelContext, now: Date = .now) -> WorkoutPlan {
        let existing = Set(((try? context.fetch(FetchDescriptor<CustomExercise>())) ?? []).map(\.stableID))
        for name in imported.unmatched {
            let id = PlanImporter.customID(for: name)
            guard !existing.contains(id) else { continue }
            let custom = CustomExercise(stableID: id, name: name, createdAt: now)
            context.insert(custom)
        }
        return createPlan(from: imported.template, in: context, now: now)
    }

    public static func activate(_ plan: WorkoutPlan, in context: ModelContext) {
        for other in plans(in: context) { other.isActive = other.stableID == plan.stableID }
        save(context)
    }

    public static func delete(_ plan: WorkoutPlan, in context: ModelContext) {
        context.delete(plan)
        save(context)
    }

    /// Plan als Vorlage (zum Teilen oder für die Claude-Brücke).
    public static func template(of plan: WorkoutPlan) -> PlanTemplate {
        func day(_ day: PlanDay) -> DayTemplate {
            DayTemplate(name: day.name, shortName: day.shortName, focus: day.focus.isEmpty ? nil : day.focus, exercises: day.sortedExercises.map(\.template))
        }
        return PlanTemplate(
            id: plan.templateID, name: plan.name, summary: plan.summary.isEmpty ? nil : plan.summary,
            mesoWeeks: plan.mesoLength, days: plan.rotationDays.map(day), modules: plan.module.map { [day($0)] } ?? []
        )
    }

    /// Setzt den Plan auf Woche 1, Tag A.
    public static func restartCycle(_ plan: WorkoutPlan, in context: ModelContext) {
        plan.progress = PlanProgress()
        save(context)
    }

    @discardableResult
    public static func addDay(to plan: WorkoutPlan, name: String, in context: ModelContext) -> PlanDay {
        let order = (plan.rotationDays.map(\.order).max() ?? -1) + 1
        let short = letter(plan.rotationDays.count)
        let day = PlanDay(name: name, shortName: short, order: order)
        context.insert(day)
        day.plan = plan
        save(context)
        return day
    }

    public static func delete(_ day: PlanDay, in context: ModelContext) {
        let plan = day.plan
        context.delete(day)
        if let plan {
            for (index, remaining) in plan.rotationDays.filter({ $0.stableID != day.stableID }).enumerated() {
                remaining.order = index
            }
            plan.nextDayIndex = 0
        }
        save(context)
    }

    public static func moveDays(in plan: WorkoutPlan, from source: IndexSet, to destination: Int, in context: ModelContext) {
        var days = plan.rotationDays
        days.move(fromOffsets: source, toOffset: destination)
        for (index, day) in days.enumerated() { day.order = index }
        save(context)
    }

    /// Übung an einen Tag anhängen, mit sinnvollen Standardwerten.
    @discardableResult
    public static func addExercise(_ exercise: ExerciseInfo, to day: PlanDay, in context: ModelContext) -> PlanExercise {
        let order = (day.sortedExercises.map(\.order).max() ?? -1) + 1
        let compound = exercise.isCompound
        let item = PlanExercise(
            exerciseID: exercise.id, order: order, sets: 3,
            repMin: compound ? 6 : 10, repMax: compound ? 10 : 15, rir: compound ? 2 : 1, restSeconds: exercise.rest
        )
        context.insert(item)
        item.day = day
        save(context)
        return item
    }

    public static func moveExercises(in day: PlanDay, from source: IndexSet, to destination: Int, in context: ModelContext) {
        var items = day.sortedExercises
        items.move(fromOffsets: source, toOffset: destination)
        for (index, item) in items.enumerated() { item.order = index }
        save(context)
    }

    public static func delete(_ item: PlanExercise, in context: ModelContext) {
        let day = item.day
        context.delete(item)
        if let day {
            for (index, remaining) in day.sortedExercises.filter({ $0.stableID != item.stableID }).enumerated() {
                remaining.order = index
            }
        }
        save(context)
    }

    // MARK: Einheiten

    public static func activeSession(in context: ModelContext) -> WorkoutSession? {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    public static func finishedSessions(in context: ModelContext, limit: Int? = nil) -> [WorkoutSession] {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        if let limit { descriptor.fetchLimit = limit }
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Verlauf einer Übung aus abgeschlossenen Einheiten, neueste zuerst.
    public static func history(for exerciseID: String, excluding sessionID: String? = nil, limit: Int = 12, in context: ModelContext) -> [ExercisePerformance] {
        let descriptor = FetchDescriptor<SetLog>(predicate: #Predicate { $0.exerciseID == exerciseID && $0.isDone })
        let logs = (try? context.fetch(descriptor)) ?? []
        var bySession: [String: (date: Date, sets: [SetLog])] = [:]
        for log in logs {
            guard let session = log.session, session.endedAt != nil, session.stableID != sessionID else { continue }
            bySession[session.stableID, default: (session.startedAt, [])].sets.append(log)
        }
        return bySession.values
            .map { entry in
                let sorted = entry.sets.sorted { lhs, rhs in
                    if lhs.kind != rhs.kind { return lhs.kind == .warmup }
                    return lhs.setIndex < rhs.setIndex
                }
                return ExercisePerformance(date: entry.date, sets: sorted.map(\.logged))
            }
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map { $0 }
    }

    /// Startet eine Einheit mit vorausgefüllten Sätzen (Vorschlag aus dem Verlauf,
    /// Aufwärmsätze vor der ersten Grundübung, Sätze und RIR nach der Zykluswoche).
    @discardableResult
    public static func startSession(
        plan: WorkoutPlan,
        day: PlanDay,
        includeModule: Bool,
        catalog: ExerciseCatalog,
        now: Date = .now,
        in context: ModelContext
    ) -> WorkoutSession {
        let cycle = plan.cycle
        let week = plan.currentWeek
        let deload = cycle.isDeload(week: week)
        let dayIndex = plan.rotationDays.firstIndex { $0.stableID == day.stableID } ?? plan.nextDayIndex
        let session = WorkoutSession(dayName: day.name, dayShortName: day.shortName, dayIndex: dayIndex, week: week, isDeload: deload, startedAt: now)
        session.planID = plan.stableID
        session.dayID = day.stableID
        session.includesModule = includeModule && plan.module != nil
        context.insert(session)

        var items = day.sortedExercises
        if session.includesModule, let module = plan.module {
            items += module.sortedExercises
        }
        var warmupDone = false
        for (slot, item) in items.enumerated() {
            let exercise = info(for: item.exerciseID, catalog: catalog)
            let sets = cycle.sets(base: item.sets, week: week)
            let suggestion = ProgressionEngine.suggest(
                exercise: exercise, sets: sets, repMin: item.repMin, repMax: item.repMax, rir: item.rir,
                isDeload: deload, history: history(for: item.exerciseID, in: context),
                increment: increment(for: exercise, in: context),
                startWeight: startWeight(for: item.exerciseID, in: context)
            )
            // Aufwärmen nur vor der ersten Grundübung des Tages (und nur mit bekanntem Gewicht).
            if !warmupDone, exercise.isCompound {
                warmupDone = true
                if let weight = suggestion.weight, weight > 0, !exercise.assisted {
                    let warmups = WarmupCalculator.sets(workingWeight: weight, equipment: exercise.equipment, increment: increment(for: exercise, in: context))
                    for (index, warmup) in warmups.enumerated() {
                        let log = SetLog(
                            exerciseID: item.exerciseID, slot: slot, setIndex: index, kind: .warmup, weight: warmup.weight, reps: warmup.reps,
                            targetRepMin: warmup.reps, targetRepMax: warmup.reps, targetRIR: 5, restSeconds: 60, superset: item.superset
                        )
                        context.insert(log)
                        log.session = session
                    }
                }
            }
            for index in 0..<sets {
                let rir = cycle.targetRIR(base: item.rir, week: week, isIsolation: !exercise.isCompound, isLastSet: index == sets - 1)
                let log = SetLog(
                    exerciseID: item.exerciseID, slot: slot, setIndex: index, kind: .working,
                    weight: suggestion.weight ?? 0, reps: index < suggestion.targetReps.count ? suggestion.targetReps[index] : item.repMin,
                    targetRepMin: item.repMin, targetRepMax: item.repMax, targetRIR: rir, restSeconds: item.restSeconds, superset: item.superset
                )
                log.note = item.note
                context.insert(log)
                log.session = session
            }
        }
        save(context)
        return session
    }

    /// Satz abhaken. Ändert sich das Gewicht, übernehmen die folgenden offenen Sätze es.
    public static func complete(_ set: SetLog, weight: Double, reps: Int, rir: Int?, now: Date = .now, in context: ModelContext) {
        let previousWeight = set.weight
        set.weight = max(0, weight)
        set.reps = max(0, reps)
        set.rir = rir
        set.isDone = true
        set.completedAt = now
        if let session = set.session, previousWeight != weight, set.kind == .working {
            for later in session.sets(inSlot: set.slot) where !later.isDone && later.kind == .working && later.setIndex > set.setIndex && later.weight == previousWeight {
                later.weight = set.weight
            }
        }
        save(context)
    }

    public static func reopen(_ set: SetLog, in context: ModelContext) {
        set.isDone = false
        set.completedAt = nil
        save(context)
    }

    /// Weiterer Satz wie der letzte der Übung.
    @discardableResult
    public static func addSet(toSlot slot: Int, of session: WorkoutSession, kind: SetKind = .working, in context: ModelContext) -> SetLog? {
        let existing = session.sets(inSlot: slot).filter { $0.kind != .warmup }
        guard let last = existing.last ?? session.sets(inSlot: slot).last else { return nil }
        let log = SetLog(
            exerciseID: last.exerciseID, slot: slot, setIndex: (existing.map(\.setIndex).max() ?? -1) + 1, kind: kind,
            weight: kind == .drop ? WeightFormat.round(last.weight * 0.75, to: 2.5) : last.weight, reps: last.reps,
            targetRepMin: last.targetRepMin, targetRepMax: last.targetRepMax, targetRIR: last.targetRIR,
            restSeconds: kind == .drop ? 0 : last.restSeconds, superset: last.superset
        )
        context.insert(log)
        log.session = session
        save(context)
        return log
    }

    public static func delete(_ set: SetLog, in context: ModelContext) {
        context.delete(set)
        save(context)
    }

    /// Übung tauschen: offene Sätze bekommen die neue Übung und einen neuen Vorschlag.
    public static func swapExercise(inSlot slot: Int, of session: WorkoutSession, to exerciseID: String, catalog: ExerciseCatalog, in context: ModelContext) {
        let exercise = info(for: exerciseID, catalog: catalog)
        let open = session.sets(inSlot: slot).filter { !$0.isDone }
        guard let template = open.first(where: { $0.kind == .working }) ?? open.first else { return }
        let working = open.filter { $0.kind == .working }
        let suggestion = ProgressionEngine.suggest(
            exercise: exercise, sets: max(1, working.count), repMin: template.targetRepMin, repMax: template.targetRepMax,
            rir: template.targetRIR, isDeload: session.isDeload, history: history(for: exerciseID, in: context),
            increment: increment(for: exercise, in: context)
        )
        for log in open where log.kind == .warmup {
            context.delete(log)
        }
        for (index, log) in working.enumerated() {
            log.exerciseID = exerciseID
            log.weight = suggestion.weight ?? 0
            log.reps = index < suggestion.targetReps.count ? suggestion.targetReps[index] : template.targetRepMin
            log.restSeconds = exercise.rest
        }
        for log in open where log.kind == .drop {
            log.exerciseID = exerciseID
        }
        save(context)
    }

    /// Übung am Ende der Einheit ergänzen (3 Sätze).
    public static func addExercise(_ exercise: ExerciseInfo, to session: WorkoutSession, in context: ModelContext) {
        let slot = (session.slots.max() ?? -1) + 1
        let compound = exercise.isCompound
        let repMin = compound ? 6 : 10, repMax = compound ? 10 : 15, rir = compound ? 2 : 1
        let suggestion = ProgressionEngine.suggest(
            exercise: exercise, sets: 3, repMin: repMin, repMax: repMax, rir: rir, isDeload: session.isDeload,
            history: history(for: exercise.id, in: context), increment: increment(for: exercise, in: context)
        )
        for index in 0..<3 {
            let log = SetLog(
                exerciseID: exercise.id, slot: slot, setIndex: index, kind: .working, weight: suggestion.weight ?? 0,
                reps: suggestion.targetReps[index], targetRepMin: repMin, targetRepMax: repMax, targetRIR: rir, restSeconds: exercise.rest
            )
            context.insert(log)
            log.session = session
        }
        save(context)
    }

    /// Nächster offener Satz (für „Satz fertig“ in der Live Activity).
    public static func nextPendingSet(in session: WorkoutSession) -> SetLog? {
        session.sortedSets.first { !$0.isDone }
    }

    /// Was nach einem erledigten Satz kommt und wie lange die Pause ist.
    /// Bei Supersätzen geht es nach kurzer Pause (15 s) mit der Partnerübung weiter,
    /// die volle Pause folgt erst nach der Runde.
    public static func next(after set: SetLog, in session: WorkoutSession) -> (set: SetLog?, restSeconds: Int) {
        let pending = session.sortedSets.filter { !$0.isDone && $0.stableID != set.stableID }
        if let group = set.superset, !group.isEmpty {
            let groupSlots = session.slots.filter { slot in session.sets(inSlot: slot).contains { $0.superset == group } }
            if let position = groupSlots.firstIndex(of: set.slot), groupSlots.count > 1 {
                let order = Array(groupSlots[(position + 1)...]) + Array(groupSlots[...position])
                for slot in order {
                    if let candidate = pending.first(where: { $0.slot == slot }) {
                        let wrapped = slot <= set.slot
                        return (candidate, wrapped ? set.restSeconds : 15)
                    }
                }
            }
        }
        // Nach dem Aufwärmen geht es in derselben Übung weiter; nach einem Arbeitssatz zum
        // nächsten Arbeitssatz (übersprungene Aufwärmsätze werden nicht mehr angeboten).
        let sameSlot = pending.filter { $0.slot == set.slot }
        let inSlot = set.kind == .warmup ? sameSlot.first : sameSlot.first { $0.kind != .warmup }
        let later = pending.first { $0.slot > set.slot }
        let next = inSlot ?? later ?? pending.first { $0.kind != .warmup } ?? pending.first
        let rest = set.kind == .warmup ? 60 : (set.kind == .drop ? 0 : set.restSeconds)
        return (next, next == nil ? 0 : rest)
    }

    /// Einheit abschließen: offene Sätze entfernen, Rekorde suchen, Plan weiterdrehen.
    @discardableResult
    public static func finish(_ session: WorkoutSession, catalog: ExerciseCatalog, now: Date = .now, in context: ModelContext) -> SessionSummary {
        let done = session.doneSets
        var bySlotExercise: [String: [LoggedSet]] = [:]
        for set in done { bySlotExercise[set.exerciseID, default: []].append(set.logged) }
        var histories: [String: [ExercisePerformance]] = [:]
        for exerciseID in bySlotExercise.keys {
            histories[exerciseID] = history(for: exerciseID, excluding: session.stableID, limit: 50, in: context)
        }
        let records = RecordFinder.records(session: bySlotExercise, history: histories, catalog: catalog)
        let previousVolume = finishedSessions(in: context, limit: 30)
            .first { $0.stableID != session.stableID && $0.dayID == session.dayID }?
            .volume

        for set in session.sets ?? [] where !set.isDone {
            context.delete(set)
        }
        session.endedAt = now

        if let planID = session.planID, let plan = plans(in: context).first(where: { $0.stableID == planID }), !done.isEmpty {
            plan.progress = plan.progress.afterCompleting(dayIndex: session.dayIndex, dayCount: plan.rotationDays.count, cycle: plan.cycle)
        }
        save(context)
        return SessionSummary.make(start: session.startedAt, end: now, sets: done.map(\.logged), records: records, previousVolume: previousVolume)
    }

    public static func discard(_ session: WorkoutSession, in context: ModelContext) {
        context.delete(session)
        save(context)
    }

    // MARK: Auswertung

    /// Erledigte Arbeitssätze je Muskel in der Kalenderwoche von `date`.
    public static func weeklyVolume(containing date: Date, catalog: ExerciseCatalog, calendar: Calendar, in context: ModelContext) -> [MuscleVolume] {
        let start = AgendaBuilder.startOfWeek(containing: date, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        let ids = sessions(from: start, to: end, in: context)
            .flatMap(\.doneSets)
            .filter { $0.kind != .warmup }
            .map(\.exerciseID)
        return VolumeCalculator.volume(exerciseIDs: ids, catalog: catalog)
    }

    /// Höchstes Gewicht eines erledigten Arbeitssatzes vor einem Zeitpunkt (eine Zeile aus der Datenbank).
    public static func heaviestWorkingSet(for exerciseID: String, before date: Date, in context: ModelContext) -> Double? {
        let working = SetKind.working.rawValue
        let future = Date.distantFuture
        var descriptor = FetchDescriptor<SetLog>(
            predicate: #Predicate { $0.exerciseID == exerciseID && $0.isDone && $0.kindRaw == working && ($0.completedAt ?? future) < date },
            sortBy: [SortDescriptor(\.weight, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.weight
    }

    public static func sessions(from start: Date, to end: Date, in context: ModelContext) -> [WorkoutSession] {
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.startedAt >= start && $0.startedAt < end },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Grundübungen des Plans, die seit mehreren Einheiten stagnieren.
    public static func stagnatingExercises(in plan: WorkoutPlan, catalog: ExerciseCatalog, in context: ModelContext) -> [String] {
        let ids = Set(plan.rotationDays.flatMap(\.sortedExercises).map(\.exerciseID))
        var histories: [String: [ExercisePerformance]] = [:]
        for id in ids where catalog.exercise(id: id)?.isCompound == true {
            histories[id] = history(for: id, limit: 6, in: context)
        }
        return DeloadAdvisor.stagnatingCompounds(histories: histories, catalog: catalog)
    }

    // MARK: Körper

    @discardableResult
    public static func addMetric(_ type: BodyMetricType, value: Double, date: Date = .now, note: String = "", in context: ModelContext) -> BodyMetric {
        let metric = BodyMetric(date: date, type: type, value: value, note: note)
        context.insert(metric)
        save(context)
        return metric
    }

    public static func metrics(_ type: BodyMetricType, in context: ModelContext) -> [BodyMetric] {
        let raw = type.rawValue
        let descriptor = FetchDescriptor<BodyMetric>(predicate: #Predicate { $0.typeRaw == raw }, sortBy: [SortDescriptor(\.date)])
        return (try? context.fetch(descriptor)) ?? []
    }

    public static func delete(_ metric: BodyMetric, in context: ModelContext) {
        context.delete(metric)
        save(context)
    }

    // MARK: Planung, Agenda, Widget

    /// Kommende Trainingstage an den Wunsch-Wochentagen.
    public static func upcomingSlots(for plan: WorkoutPlan, now: Date = .now, days: Int, calendar: Calendar, in context: ModelContext) -> [TrainingSchedule.Slot] {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let trainedToday = sessions(from: today, to: tomorrow, in: context).contains { $0.endedAt != nil }
        return upcomingSlots(for: plan, trainedToday: trainedToday, now: now, days: days, calendar: calendar)
    }

    public static func upcomingSlots(for plan: WorkoutPlan, trainedToday: Bool, now: Date, days: Int, calendar: Calendar) -> [TrainingSchedule.Slot] {
        TrainingSchedule.upcoming(
            preferredWeekdays: plan.preferredWeekdays, nextDayIndex: plan.nextDayIndex, dayCount: plan.rotationDays.count,
            trainedToday: trainedToday, from: now, days: days, calendar: calendar
        )
    }

    /// Geplante Trainingstage und erledigte Einheiten für Agenda und Woche (aus der Datenbank).
    public static func agendaItems(from start: Date, to end: Date, now: Date = .now, calendar: Calendar, in context: ModelContext) -> [AgendaItem] {
        agendaItems(plan: activePlan(in: context), sessions: sessions(from: min(start, calendar.startOfDay(for: now)), to: end, in: context), from: start, to: end, now: now, calendar: calendar)
    }

    /// Geplante Trainingstage und erledigte Einheiten für Agenda und Woche.
    /// - Parameter sessions: Einheiten im Zeitraum (und von heute, für „heute schon trainiert“).
    public static func agendaItems(plan: WorkoutPlan?, sessions: [WorkoutSession], from start: Date, to end: Date, now: Date, calendar: Calendar) -> [AgendaItem] {
        var items: [AgendaItem] = sessions.compactMap { session in
            guard let endedAt = session.endedAt, session.startedAt >= start, session.startedAt < end else { return nil }
            return AgendaItem(
                id: "workout-\(session.stableID)", kind: .training, title: "Training: \(session.title)",
                start: session.startedAt, end: endedAt, isAllDay: false, isDone: true,
                subtitle: "\(session.doneSets.filter { $0.kind != .warmup }.count) Sätze"
            )
        }
        guard let plan else { return items }
        let days = plan.rotationDays
        guard !days.isEmpty else { return items }
        let trainedToday = sessions.contains { $0.endedAt != nil && calendar.isDate($0.startedAt, inSameDayAs: now) }
        let horizon = max(1, calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: end).day ?? 0)
        for slot in upcomingSlots(for: plan, trainedToday: trainedToday, now: now, days: horizon, calendar: calendar)
        where slot.date >= calendar.startOfDay(for: start) && slot.date < end && slot.dayIndex < days.count {
            let day = days[slot.dayIndex]
            items.append(AgendaItem(
                id: "training-\(Int(slot.date.timeIntervalSince1970))", kind: .training, title: "Training: \(day.title)",
                start: slot.date, isAllDay: true,
                subtitle: "\(day.sortedExercises.filter { !$0.isOptional }.count) Übungen · ca. \(day.estimatedMinutes(week: plan.currentWeek, cycle: plan.cycle)) Min."
            ))
        }
        return items
    }

    /// Erinnerungen an den Wunsch-Wochentagen (nächste 7 Tage).
    public static func reminderCandidates(now: Date = .now, calendar: Calendar, in context: ModelContext) -> [ReminderCandidate] {
        guard let plan = activePlan(in: context), plan.reminderMinute >= 0 else { return [] }
        let days = plan.rotationDays
        guard !days.isEmpty else { return [] }
        return TrainingReminders.candidates(
            slots: upcomingSlots(for: plan, now: now, days: 7, calendar: calendar, in: context),
            minuteOfDay: plan.reminderMinute,
            dayTitle: { days[min($0, days.count - 1)].title },
            detail: { index in
                let day = days[min(index, days.count - 1)]
                return "\(day.sortedExercises.filter { !$0.isOptional }.count) Übungen · ca. \(day.estimatedMinutes(week: plan.currentWeek, cycle: plan.cycle)) Min."
            },
            now: now,
            calendar: calendar
        )
    }

    public static func snapshot(now: Date = .now, in context: ModelContext) -> TrainingWidgetSnapshot {
        let last = finishedSessions(in: context, limit: 1).first?.startedAt
        let active = activeSession(in: context)
        guard let plan = activePlan(in: context), let day = plan.nextDay else {
            var empty = TrainingWidgetSnapshot.empty
            empty.writtenAt = now
            empty.lastTrainingAt = last
            return empty
        }
        return TrainingWidgetSnapshot(
            writtenAt: now, planName: plan.name, nextDayName: day.name, nextDayShort: day.shortName,
            exerciseCount: day.sortedExercises.filter { !$0.isOptional }.count,
            estimatedMinutes: day.estimatedMinutes(week: plan.currentWeek, cycle: plan.cycle),
            weekLabel: plan.cycle.label(week: plan.currentWeek), isDeload: plan.isDeloadWeek,
            lastTrainingAt: last, activeSessionStart: active?.startedAt, activeDayName: active?.title
        )
    }

    public static func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            print("Orbit: Speichern fehlgeschlagen: \(error)")
        }
    }
}
