import Foundation
import Testing
@testable import TagwerkCore

@Suite("Training-Coach")
struct PlanCoachTests {
    private let catalog = ExerciseCatalog.bundled()

    private func trend(_ id: String, _ pace: ProgressPace, weeks: Double) -> ExerciseTrend {
        ExerciseTrend(exerciseID: id, sessions: 6, weeks: weeks, first: 100, last: 100, percentPerWeek: 0, pace: pace, message: "")
    }

    @Test("Kurzer Stillstand: anderer Wiederholungsbereich")
    func shortStallChangesRange() {
        let items = [CoachPlanItem(id: "p1", exerciseID: "bench-press-barbell", dayName: "Push", sets: 4, repMin: 6, repMax: 8)]
        let result = PlanCoach.suggestions(items: items, trends: ["bench-press-barbell": trend("bench-press-barbell", .stalled, weeks: 3)], weeklySets: [:], catalog: catalog)
        #expect(result.count == 1)
        #expect(result[0].change == .repRange(min: 8, max: 12))
        #expect(result[0].title.contains("8–12 statt 6–8"))
    }

    @Test("Langer Stillstand: tauschen gegen eine Übung, die noch nicht im Plan ist")
    func longStallSwaps() {
        let items = [
            CoachPlanItem(id: "p1", exerciseID: "hammer-curl", dayName: "Pull", sets: 2, repMin: 10, repMax: 12),
            CoachPlanItem(id: "p2", exerciseID: "cable-curl", dayName: "Arme", sets: 3, repMin: 10, repMax: 12),
        ]
        let result = PlanCoach.suggestions(items: items, trends: ["hammer-curl": trend("hammer-curl", .declining, weeks: 6)], weeklySets: [:], catalog: catalog)
        guard case .swap(let target) = result.first?.change else {
            Issue.record("Kein Tausch: \(result)")
            return
        }
        #expect(target != "cable-curl" && target != "hammer-curl")
        #expect(catalog.exercise(id: target)?.primary.contains(.biceps) == true)
        #expect(result[0].priority == 0)
    }

    @Test("Zu wenig Volumen: Satz dazu bei einer Isolationsübung")
    func lowVolumeAddsSet() {
        let items = [
            CoachPlanItem(id: "p1", exerciseID: "lateral-raise-dumbbell", dayName: "Push", sets: 3, repMin: 12, repMax: 15),
            CoachPlanItem(id: "p2", exerciseID: "bench-press-barbell", dayName: "Push", sets: 4, repMin: 6, repMax: 8),
        ]
        let result = PlanCoach.suggestions(items: items, trends: [:], weeklySets: [.sideDelts: 3, .chest: 12], catalog: catalog)
        #expect(result.map(\.planItemID) == ["p1"])
        #expect(result[0].change == .addSet)
        #expect(result[0].title.contains("3 → 4"))
        #expect(result[0].reason.contains("Seitliche Schulter"))
    }

    @Test("Zu viel Volumen: Satz weniger; ohne Trainingsdaten keine Volumen-Vorschläge")
    func highVolumeRemovesSet() {
        let items = [CoachPlanItem(id: "p2", exerciseID: "bench-press-barbell", dayName: "Push", sets: 5, repMin: 6, repMax: 8)]
        let high = PlanCoach.suggestions(items: items, trends: [:], weeklySets: [.chest: 25], catalog: catalog)
        #expect(high.first?.change == .removeSet)
        #expect(PlanCoach.suggestions(items: items, trends: [:], weeklySets: [:], catalog: catalog).isEmpty)
    }

    @Test("Je Übung höchstens ein Vorschlag, der wichtigste")
    func oneSuggestionPerItem() {
        let items = [CoachPlanItem(id: "p1", exerciseID: "lateral-raise-dumbbell", dayName: "Push", sets: 3, repMin: 12, repMax: 15)]
        let result = PlanCoach.suggestions(
            items: items, trends: ["lateral-raise-dumbbell": trend("lateral-raise-dumbbell", .stalled, weeks: 3)],
            weeklySets: [.sideDelts: 2], catalog: catalog
        )
        #expect(result.count == 1)
        #expect(result[0].change == .repRange(min: 8, max: 12))
    }

    @Test("Wiederholungsbereiche wechseln sinnvoll")
    func repRanges() {
        #expect(PlanCoach.nextRepRange(min: 6, max: 8, isCompound: true) == (8, 12))
        #expect(PlanCoach.nextRepRange(min: 8, max: 12, isCompound: true) == (6, 8))
        #expect(PlanCoach.nextRepRange(min: 10, max: 12, isCompound: false) == (12, 15))
        #expect(PlanCoach.nextRepRange(min: 12, max: 15, isCompound: false) == (8, 12))
    }

    @Test("Wochenlücken: nächste Einheit zuerst, Text verständlich")
    func weeklyGaps() {
        let thisWeek = [
            MuscleVolume(muscle: .biceps, sets: 4, target: MuscleGroup.biceps.weeklyTarget),
            MuscleVolume(muscle: .chest, sets: 12, target: MuscleGroup.chest.weeklyTarget),
        ]
        let gaps = PlanCoach.weeklyGaps(thisWeek: thisWeek, nextSession: ["hammer-curl"], catalog: catalog)
        #expect(gaps.first?.muscle == .biceps)
        #expect(gaps.first?.missing == 4)
        #expect(gaps.first?.inNextSession == true)
        #expect(!gaps.contains { $0.muscle == .chest })
        #expect(gaps.contains { $0.muscle == .lats && !$0.inNextSession })
        let text = PlanCoach.gapText(gaps) ?? ""
        #expect(text.hasPrefix("Die nächste Einheit zählt für Bizeps (noch 4)"))
        #expect(text.contains("außerdem"))
        #expect(PlanCoach.gapText([]) == nil)
    }
}
