import Foundation
import Testing
@testable import TagwerkCore

private let catalog = ExerciseCatalog.bundled()

private func perf(_ day: Int, _ sets: [(Double, Int)], rir: Int? = nil) -> ExercisePerformance {
    ExercisePerformance(date: date(2026, 10, day, 18), sets: sets.map { LoggedSet(weight: $0.0, reps: $0.1, rir: rir) })
}

@Suite("Training: Inhalte")
struct TrainingContentTests {
    @Test func catalogIsCompleteAndClean() throws {
        #expect(catalog.exercises.count >= 90)
        #expect(catalog.validationIssues() == [])
        let bench = try #require(catalog.exercise(id: "bench-press-barbell"))
        #expect(bench.name == "Bankdrücken (Langhantel)")
        #expect(bench.isCompound)
        #expect(bench.increment == 2.5)
        #expect(catalog.exercise(id: "pull-up-assisted")?.assisted == true)
        // Jede Muskelgruppe des Oberkörpers hat Übungen.
        let covered = Set(catalog.exercises.flatMap(\.primary))
        for muscle in [MuscleGroup.chest, .lats, .upperBack, .sideDelts, .rearDelts, .biceps, .triceps, .quads, .hamstrings, .calves, .abs] {
            #expect(covered.contains(muscle), "\(muscle)")
        }
    }

    @Test func starterPlanMatchesLibrary() throws {
        let plan = try #require(PlanTemplate.bundledUpperFourDay())
        #expect(plan.name == "Oberkörper 4er – Hypertrophie")
        #expect(plan.days.map(\.shortName) == ["A", "B", "C", "D"])
        #expect(plan.days.map(\.name) == ["Push", "Pull", "Arme & Schultern", "Brust & Rücken"])
        #expect(plan.modules.first?.name == "Beine & Rumpf")
        #expect(plan.mesoWeeks == 6)
        #expect(plan.validationIssues(catalog: catalog) == [])
        #expect(plan.days[0].exercises[0].prescription == "4 × 6–8 · RIR 2")
        #expect(plan.days[2].exercises.filter { $0.superset == "A" }.count == 2)
    }

    @Test func weeklyVolumeOfStarterPlanIsInRange() throws {
        let plan = try #require(PlanTemplate.bundledUpperFourDay())
        let ids = plan.days.flatMap(\.exercises).filter { !$0.optional }.flatMap { Array(repeating: $0.exercise, count: $0.sets) }
        let volume = Dictionary(uniqueKeysWithValues: VolumeCalculator.volume(exerciseIDs: ids, catalog: catalog).map { ($0.muscle, $0) })
        for muscle in [MuscleGroup.chest, .lats, .upperBack, .sideDelts, .rearDelts, .biceps, .triceps] {
            #expect(volume[muscle]?.status == .inRange, "\(muscle): \(volume[muscle]?.sets ?? -1)")
        }
        #expect(volume[.chest]?.sets == 18.5)
        #expect(volume[.quads] == nil)
        #expect(volume[.chest]?.label == "18,5 Sätze (Ziel 10–20)")
    }

    @Test func searchAndAlternatives() {
        #expect(catalog.search("bankdrück").map(\.id).contains("bench-press-barbell"))
        #expect(catalog.search("Lat Pulldown").map(\.id).contains("lat-pulldown-wide"))
        let alternatives = catalog.alternatives(to: "bench-press-barbell")
        #expect(!alternatives.contains { $0.id == "bench-press-barbell" })
        #expect(alternatives.first?.isCompound == true)
        #expect(alternatives.allSatisfy { $0.primary.contains(.chest) })
        #expect(catalog.grouped.first?.muscle == .chest)
    }
}

@Suite("Training: Progression")
struct ProgressionTests {
    private let bench = catalog.exercise(id: "bench-press-barbell")!

    @Test func mesocycle() {
        let cycle = Mesocycle(length: 6)
        #expect((1...6).map { cycle.targetRIR(base: 2, week: $0, isIsolation: false, isLastSet: false) } == [3, 2, 2, 1, 1, 4])
        #expect(cycle.targetRIR(base: 1, week: 4, isIsolation: true, isLastSet: true) == 0)
        #expect(cycle.targetRIR(base: 1, week: 4, isIsolation: true, isLastSet: false) == 0)
        #expect(cycle.targetRIR(base: 1, week: 2, isIsolation: true, isLastSet: true) == 1)
        #expect(cycle.sets(base: 4, week: 6) == 2)
        #expect(cycle.sets(base: 3, week: 6) == 2)
        #expect(cycle.sets(base: 2, week: 6) == 1)
        #expect(cycle.sets(base: 4, week: 3) == 4)
        #expect(cycle.label(week: 2) == "Woche 2 von 6")
        #expect(cycle.label(week: 6) == "Woche 6 von 6 · Deload")
    }

    @Test func firstTimeAndDeload() {
        let first = ProgressionEngine.suggest(exercise: bench, sets: 4, repMin: 6, repMax: 8, rir: 2, isDeload: false, history: [])
        #expect(first.kind == .firstTime)
        #expect(first.weight == nil)
        #expect(first.message == "Erstes Mal: Wähle ein Gewicht für 6–8 Wdh. mit noch 2 Wdh. im Tank.")
        let deload = ProgressionEngine.suggest(exercise: bench, sets: 2, repMin: 6, repMax: 8, rir: 4, isDeload: true, history: [perf(20, [(80, 8), (80, 7)])])
        #expect(deload.kind == .deload)
        #expect(deload.weight == 80)
        #expect(deload.targetReps == [6, 6])
    }

    @Test func doubleProgression() {
        let allTop = [perf(20, [(80, 8), (80, 8), (80, 8), (80, 8)])]
        let up = ProgressionEngine.suggest(exercise: bench, sets: 4, repMin: 6, repMax: 8, rir: 2, isDeload: false, history: allTop)
        #expect(up.kind == .increase)
        #expect(up.weight == 82.5)
        #expect(up.targetReps == [6, 6, 6, 6])
        #expect(up.message == "Alle Sätze bei 8 Wdh.: +2,5 kg.")

        let partly = [perf(23, [(80, 8), (80, 7), (80, 6)]), perf(20, [(80, 6), (80, 6), (80, 6)])]
        let hold = ProgressionEngine.suggest(exercise: bench, sets: 4, repMin: 6, repMax: 8, rir: 2, isDeload: false, history: partly)
        #expect(hold.kind == .hold)
        #expect(hold.weight == 80)
        #expect(hold.targetReps == [8, 8, 7, 7])
        #expect(hold.message == "Gleiches Gewicht, Ziel: 8 · 8 · 7 · 7 Wdh.")
    }

    @Test func decreaseAfterTwoBadSessions() {
        let bad = [perf(23, [(85, 5), (85, 4), (85, 6)]), perf(20, [(85, 5), (85, 5), (85, 6)])]
        let down = ProgressionEngine.suggest(exercise: bench, sets: 3, repMin: 6, repMax: 8, rir: 2, isDeload: false, history: bad)
        #expect(down.kind == .decrease)
        #expect(down.weight == 77.5)
        // Nur einmal schlecht: halten.
        let once = ProgressionEngine.suggest(exercise: bench, sets: 3, repMin: 6, repMax: 8, rir: 2, isDeload: false, history: [bad[0], perf(20, [(85, 6), (85, 6), (85, 6)])])
        #expect(once.kind == .hold)
    }

    @Test func assistedAndDumbbells() {
        let assisted = catalog.exercise(id: "pull-up-assisted")!
        let up = ProgressionEngine.suggest(exercise: assisted, sets: 3, repMin: 6, repMax: 10, rir: 2, isDeload: false, history: [perf(20, [(25, 10), (25, 10), (25, 10)])])
        #expect(up.weight == 20)
        #expect(up.message == "Alle Sätze bei 10 Wdh.: 5 kg weniger Unterstützung.")
        let dumbbell = catalog.exercise(id: "incline-press-dumbbell")!
        let next = ProgressionEngine.suggest(exercise: dumbbell, sets: 3, repMin: 8, repMax: 10, rir: 2, isDeload: false, history: [perf(20, [(26, 10), (26, 10), (26, 10)])])
        #expect(next.weight == 28)
        let custom = ProgressionEngine.suggest(exercise: dumbbell, sets: 3, repMin: 8, repMax: 10, rir: 2, isDeload: false, history: [perf(20, [(26, 10), (26, 10), (26, 10)])], increment: 1)
        #expect(custom.weight == 27)
    }

    @Test func warmups() {
        let barbell = WarmupCalculator.sets(workingWeight: 80, equipment: .barbell, increment: 2.5)
        #expect(barbell.map(\.weight) == [40, 55, 67.5])
        #expect(barbell.map(\.reps) == [8, 5, 3])
        #expect(barbell.allSatisfy { $0.kind == .warmup })
        let light = WarmupCalculator.sets(workingWeight: 30, equipment: .barbell, increment: 2.5)
        #expect(light.map(\.weight) == [20, 25])
        let dumbbell = WarmupCalculator.sets(workingWeight: 12, equipment: .dumbbell, increment: 2)
        #expect(dumbbell.map(\.weight) == [6, 8, 10])
        #expect(WarmupCalculator.sets(workingWeight: 0, equipment: .bodyweight, increment: 2.5).isEmpty)
    }

    @Test func oneRepMaxAndFormatting() {
        #expect(abs(OneRepMax.epley(weight: 100, reps: 5) - 116.67) < 0.01)
        #expect(OneRepMax.epley(weight: 100, reps: 1) == 100)
        #expect(abs(OneRepMax.epley(weight: 100, reps: 5, rir: 2) - 123.33) < 0.01)
        #expect(OneRepMax.epley(weight: 0, reps: 10) == 0)
        #expect(WeightFormat.number(22.5) == "22,5")
        #expect(WeightFormat.number(80) == "80")
        #expect(WeightFormat.label(0, equipment: .bodyweight) == "Körpergewicht")
        #expect(WeightFormat.label(10, equipment: .bodyweight) == "+10 kg")
        #expect(WeightFormat.label(25, assisted: true) == "−25 kg Hilfe")
        #expect(WeightFormat.round(56, to: 2.5) == 55)
        #expect(WeightFormat.roundDown(78.6, to: 2.5) == 77.5)
        #expect(perf(20, [(80, 8), (80, 7)]).summary == "80 × 8 · 80 × 7")
    }
}

@Suite("Training: Auswertung und Rotation")
struct TrainingStatsTests {
    @Test func records() {
        let history = ["bench-press-barbell": [perf(20, [(80, 8), (80, 8)])]]
        let heavier = RecordFinder.records(session: ["bench-press-barbell": [LoggedSet(weight: 82.5, reps: 6)]], history: history, catalog: catalog)
        #expect(heavier.map(\.kind) == [.weight])
        #expect(heavier.first?.label == "Höchstgewicht 82,5 kg (vorher 80)")
        let moreReps = RecordFinder.records(session: ["bench-press-barbell": [LoggedSet(weight: 80, reps: 10)]], history: history, catalog: catalog)
        #expect(moreReps.map(\.kind) == [.oneRepMax])
        let firstTime = RecordFinder.records(session: ["face-pull": [LoggedSet(weight: 20, reps: 15)]], history: history, catalog: catalog)
        #expect(firstTime.isEmpty)
        let warmupOnly = RecordFinder.records(session: ["bench-press-barbell": [LoggedSet(weight: 100, reps: 1, kind: .warmup)]], history: history, catalog: catalog)
        #expect(warmupOnly.isEmpty)
    }

    @Test func summary() {
        let sets = [LoggedSet(weight: 40, reps: 8, kind: .warmup), LoggedSet(weight: 80, reps: 8), LoggedSet(weight: 80, reps: 7)]
        let summary = SessionSummary.make(start: date(2026, 10, 26, 18), end: date(2026, 10, 26, 19, 12), sets: sets, records: [], previousVolume: 1_100)
        #expect(summary.workingSets == 2)
        #expect(summary.volume == 1_200)
        #expect(summary.durationLabel == "1:12 Std.")
        #expect(summary.volumeLabel == "1.200 kg")
        #expect(abs((summary.volumeChange ?? 0) - 0.0909) < 0.001)
        let short = SessionSummary.make(start: date(2026, 10, 26, 18), end: date(2026, 10, 26, 18, 48), sets: [], records: [], previousVolume: nil)
        #expect(short.durationLabel == "48 Min.")
        #expect(short.volumeChange == nil)
    }

    @Test func stagnationAndEarlyDeload() {
        let flat = [perf(1, [(100, 5)]), perf(5, [(100, 5)]), perf(9, [(100, 5)]), perf(13, [(100, 4)])]
        let rising = [perf(1, [(100, 5)]), perf(5, [(100, 6)]), perf(9, [(102.5, 6)]), perf(13, [(105, 6)])]
        #expect(DeloadAdvisor.isStagnating(flat))
        #expect(!DeloadAdvisor.isStagnating(rising))
        #expect(!DeloadAdvisor.isStagnating(Array(flat.prefix(3))))
        let histories = ["bench-press-barbell": flat, "t-bar-row": flat, "face-pull": flat, "pull-up": rising]
        #expect(DeloadAdvisor.stagnatingCompounds(histories: histories, catalog: catalog) == ["bench-press-barbell", "t-bar-row"])
        #expect(DeloadAdvisor.suggestsEarlyDeload(histories: histories, catalog: catalog))
    }

    @Test func rotationAndWeeks() {
        let cycle = Mesocycle(length: 6)
        let start = PlanProgress(nextDayIndex: 0, week: 1)
        let afterA = start.afterCompleting(dayIndex: 0, dayCount: 4, cycle: cycle)
        #expect(afterA == PlanProgress(nextDayIndex: 1, week: 1))
        let afterD = PlanProgress(nextDayIndex: 3, week: 2).afterCompleting(dayIndex: 3, dayCount: 4, cycle: cycle)
        #expect(afterD == PlanProgress(nextDayIndex: 0, week: 3))
        let afterDeload = PlanProgress(nextDayIndex: 3, week: 6).afterCompleting(dayIndex: 3, dayCount: 4, cycle: cycle)
        #expect(afterDeload == PlanProgress(nextDayIndex: 0, week: 1))
        // Tag übersprungen (B statt A gemacht): danach C, Woche bleibt.
        #expect(PlanProgress(nextDayIndex: 0, week: 2).afterCompleting(dayIndex: 1, dayCount: 4, cycle: cycle) == PlanProgress(nextDayIndex: 2, week: 2))
    }

    @Test func scheduleOnPreferredWeekdays() {
        // Mo, Di, Do, Sa; heute Montag 26.10., als Nächstes B.
        let slots = TrainingSchedule.upcoming(preferredWeekdays: [2, 3, 5, 7], nextDayIndex: 1, dayCount: 4, trainedToday: false, from: date(2026, 10, 26, 8), days: 7, calendar: berlin)
        #expect(slots.map { parts($0.date).d } == [26, 27, 29, 31])
        #expect(slots.map(\.dayIndex) == [1, 2, 3, 0])
        let afterTraining = TrainingSchedule.upcoming(preferredWeekdays: [2, 3, 5, 7], nextDayIndex: 2, dayCount: 4, trainedToday: true, from: date(2026, 10, 26, 20), days: 7, calendar: berlin)
        #expect(afterTraining.first.map { parts($0.date).d } == 27)
        #expect(TrainingSchedule.upcoming(preferredWeekdays: [], nextDayIndex: 0, dayCount: 4, trainedToday: false, from: .now, days: 7, calendar: berlin).isEmpty)
    }

    @Test func snapshotAndEstimate() throws {
        #expect(WorkoutEstimate.minutes([(4, 150), (3, 120), (3, 120), (2, 75), (4, 60), (3, 75)]) == 60)
        let snapshot = TrainingWidgetSnapshot(
            writtenAt: date(2026, 10, 26, 8), planName: "Oberkörper", nextDayName: "Pull", nextDayShort: "B",
            exerciseCount: 7, estimatedMinutes: 70, weekLabel: "Woche 2 von 6", isDeload: false,
            lastTrainingAt: date(2026, 10, 24, 18)
        )
        #expect(snapshot.lastTrainingLabel(now: date(2026, 10, 26, 9), calendar: berlin) == "zuletzt vor 2 Tagen")
        #expect(snapshot.sentence(now: date(2026, 10, 26, 9), calendar: berlin) == "Als Nächstes: B Pull, 7 Übungen, etwa 70 Minuten. Zuletzt trainiert: vor 2 Tagen.")
        #expect(TrainingWidgetSnapshot.decode(try snapshot.encoded()) == snapshot)
        #expect(TrainingWidgetSnapshot.empty.sentence(now: .now, calendar: berlin) == "Es ist noch kein Trainingsplan angelegt.")
    }
}

@Suite("Training: Plan-Import")
struct PlanImportTests {
    private let claudeAnswer = """
    Hier ist dein angepasster Plan:

    ```json
    {"format":"tagwerk.plan.v1","name":"Oberkörper 4er","mesoWeeks":5,"deloadWeek":6,
     "days":[{"name":"Push","exercises":[
       {"name":"Bankdrücken (Langhantel)","sets":4,"repMin":6,"repMax":8,"rir":2,"restSec":150},
       {"name":"Kurzhantel Schrägbankdrücken","sets":3,"reps":"8-10","rir":2},
       {"name":"Lat Pulldown","sets":3,"reps":12},
       {"name":"Zottman Curls","sets":2,"repMin":10,"repMax":12,"rir":1,"note":"langsam ablassen"}]}]}
    ```
    Viel Erfolg!
    """

    @Test func parsesAndResolvesNames() throws {
        let template = try PlanImporter.parse(claudeAnswer)
        #expect(template.name == "Oberkörper 4er")
        #expect(template.mesoWeeks == 6)
        let push = template.days[0].exercises
        #expect(push[1].repMin == 8 && push[1].repMax == 10)
        #expect(push[2].repMin == 12 && push[2].repMax == 12)
        #expect(push[1].restSec == 90)

        let imported = PlanImporter.resolve(template, catalog: catalog)
        let ids = imported.template.days[0].exercises.map(\.exercise)
        #expect(ids == ["bench-press-barbell", "incline-press-dumbbell", "lat-pulldown-wide", "custom-zottman-curls"])
        #expect(imported.unmatched == ["Zottman Curls"])
        #expect(imported.matches.count == 3)
        #expect(imported.template.days[0].exercises[3].name == "Zottman Curls")
    }

    @Test func rejectsOtherContent() {
        #expect(throws: PlanImportError.noPlanFound) { try PlanImporter.parse("Kein JSON hier.") }
        #expect(throws: PlanImportError.wrongFormat("tagwerk.food.v1")) {
            try PlanImporter.parse(#"{"format":"tagwerk.food.v1","name":"Apfel","days":[]}"#)
        }
        #expect(throws: PlanImportError.noDays) { try PlanImporter.parse(#"{"format":"orbit.plan.v1","name":"Leer","days":[]}"#) }
    }

    @Test func roundTripOfBundledPlan() throws {
        let plan = try #require(PlanTemplate.bundledUpperFourDay())
        let data = try JSONEncoder().encode(plan)
        #expect(try PlanTemplate.decode(data) == plan)
    }

    @Test func nameMatching() {
        #expect(NameMatcher.normalize("Schrägbankdrücken (Kurzhantel)") == "schraegbankdruecken kurzhantel")
        #expect(NameMatcher.similarity("Butterfly Maschine", "Butterfly-Maschine") == 1)
        #expect(NameMatcher.bestMatch(for: "Face Pull", in: catalog)?.exercise.id == "face-pull")
        #expect(NameMatcher.bestMatch(for: "Seitheben", in: catalog)?.exercise.id == "lateral-raise-dumbbell")
        #expect(NameMatcher.bestMatch(for: "Nordic Hamstring Curl", in: catalog) == nil)
        #expect(PlanImporter.customID(for: "Zottman Curls") == "custom-zottman-curls")
    }
}

@Suite("Training: Erinnerungen, Körper, Sicherung")
struct TrainingRecordsTests {
    @Test func remindersOnTrainingDays() {
        let slots = TrainingSchedule.upcoming(preferredWeekdays: [2, 5], nextDayIndex: 0, dayCount: 4, trainedToday: false, from: date(2026, 10, 26, 8), days: 7, calendar: berlin)
        let names = ["A · Push", "B · Pull", "C · Arme", "D · Brust & Rücken"]
        let candidates = TrainingReminders.candidates(
            slots: slots, minuteOfDay: 17 * 60 + 30, dayTitle: { names[$0] }, detail: { _ in "6 Übungen · ca. 60 Min." },
            now: date(2026, 10, 26, 8), calendar: berlin
        )
        #expect(candidates.map(\.id) == ["training.20261026", "training.20261029"])
        #expect(candidates.map(\.title) == ["Training heute: A · Push", "Training heute: B · Pull"])
        #expect(candidates[0].fireDate == date(2026, 10, 26, 17, 30))
        #expect(candidates[0].kind == .training)
        // Schon vorbei: keine Erinnerung mehr für heute.
        let late = TrainingReminders.candidates(slots: slots, minuteOfDay: 7 * 60, dayTitle: { names[$0] }, detail: { _ in "" }, now: date(2026, 10, 26, 8), calendar: berlin)
        #expect(late.map(\.id) == ["training.20261029"])
        #expect(TrainingReminders.candidates(slots: slots, minuteOfDay: -1, dayTitle: { _ in "" }, detail: { _ in "" }, now: .now, calendar: berlin).isEmpty)
    }

    @Test func bodyMetrics() {
        #expect(BodyMetricType.weight.label(82.4) == "82,4 kg")
        #expect(BodyMetricType.waist.label(84) == "84 cm")
        #expect(BodyMetricType.bodyFat.unit == "%")
    }

    @Test func backupWithTraining() throws {
        let set = SetLogRecord(stableID: "s1", exerciseID: "bench-press-barbell", slot: 0, setIndex: 0, kind: "working", weight: 80, reps: 8, rir: 2, isDone: true, completedAt: date(2026, 10, 26, 18, 10), targetRepMin: 6, targetRepMax: 8, targetRIR: 2, restSeconds: 150, superset: nil, note: "")
        let training = TrainingBackup(
            plans: [WorkoutPlanRecord(
                stableID: "p1", name: "Oberkörper", summary: "", templateID: "upper-4day", isActive: true, mesoLength: 6,
                currentWeek: 2, nextDayIndex: 1, moduleDayIndex: -1, preferredWeekdays: [2, 3, 5, 7], reminderMinute: 1050,
                createdAt: date(2026, 10, 1),
                days: [PlanDayRecord(stableID: "d1", name: "Push", shortName: "A", focus: "", order: 0, isModule: false, exercises: [
                    PlanExerciseRecord(stableID: "e1", exerciseID: "bench-press-barbell", order: 0, sets: 4, repMin: 6, repMax: 8, rir: 2, restSeconds: 150, superset: nil, note: "", isOptional: false),
                ])]
            )],
            sessions: [WorkoutSessionRecord(stableID: "w1", planID: "p1", dayID: "d1", dayName: "Push", dayShortName: "A", dayIndex: 0, week: 2, isDeload: false, startedAt: date(2026, 10, 26, 18), endedAt: date(2026, 10, 26, 19), note: "", bodyweight: 82, includesModule: false, sets: [set])],
            customExercises: [ExerciseInfo(id: "custom-zottman-curls", name: "Zottman Curls", primary: [.biceps], equipment: .dumbbell, mechanic: .isolation, isCustom: true)],
            preferences: [ExercisePreferenceRecord(exerciseID: "lateral-raise-dumbbell", increment: 1, note: "")],
            bodyMetrics: [BodyMetricRecord(stableID: "b1", date: date(2026, 10, 26, 7), type: "weight", value: 82.4, note: "")]
        )
        let document = BackupDocument(createdAt: date(2026, 10, 26, 20), appVersion: "0.4.0", lists: [], tasks: [], training: training)
        let decoded = try BackupCodec.decode(BackupCodec.encode(document))
        #expect(decoded == document)
        #expect(decoded.training?.customExercises.first?.increment == 2)
    }
}
