import Foundation

/// Eine Übung im aktiven Plan, so wie der Coach sie sieht.
public struct CoachPlanItem: Sendable, Hashable {
    /// `stableID` der Plan-Übung.
    public var id: String
    public var exerciseID: String
    public var dayName: String
    public var sets: Int
    public var repMin: Int
    public var repMax: Int

    public init(id: String, exerciseID: String, dayName: String, sets: Int, repMin: Int, repMax: Int) {
        self.id = id
        self.exerciseID = exerciseID
        self.dayName = dayName
        self.sets = sets
        self.repMin = repMin
        self.repMax = repMax
    }
}

/// Ein Vorschlag für den Plan, mit einem Tipp übernehmbar.
public struct CoachSuggestion: Sendable, Hashable, Identifiable {
    public enum Change: Sendable, Hashable {
        case addSet
        case removeSet
        case repRange(min: Int, max: Int)
        case swap(to: String)
    }

    public var planItemID: String
    public var exerciseID: String
    public var change: Change
    /// „Hammercurls: 1 Satz mehr (2 → 3)“
    public var title: String
    /// Warum, in einem Satz.
    public var reason: String
    /// Kleiner = wichtiger.
    public var priority: Int

    public var id: String { "\(planItemID)-\(change)" }

    public var symbol: String {
        switch change {
        case .addSet: "plus.circle"
        case .removeSet: "minus.circle"
        case .repRange: "arrow.left.and.right.circle"
        case .swap: "arrow.triangle.2.circlepath"
        }
    }
}

/// Muskel, dem diese Woche noch Sätze fehlen.
public struct WeeklyGap: Sendable, Hashable, Identifiable {
    public var muscle: MuscleGroup
    public var done: Double
    public var target: Int
    /// Trainiert die nächste Einheit diesen Muskel direkt?
    public var inNextSession: Bool

    public var id: MuscleGroup { muscle }
    public var missing: Int { max(0, Int((Double(target) - done).rounded(.up))) }
}

/// Plan-Check: Vorschläge je Übung aus Kraftverlauf und Wochenvolumen.
public enum PlanCoach {
    /// Ab so vielen Wochen Stillstand wird Tauschen vorgeschlagen statt nur den Bereich zu wechseln.
    static let swapAfterWeeks = 5.0
    static let maxSets = 5

    /// - Parameters:
    ///   - trends: Kraftverlauf je Übung (`ProgressAssessment.exercise`).
    ///   - weeklySets: Durchschnittliche Arbeitssätze je Muskel der letzten Wochen; leer = noch kein Training.
    public static func suggestions(
        items: [CoachPlanItem],
        trends: [String: ExerciseTrend],
        weeklySets: [MuscleGroup: Double],
        catalog: ExerciseCatalog,
        limit: Int = 6
    ) -> [CoachSuggestion] {
        var byItem: [String: CoachSuggestion] = [:]
        func offer(_ suggestion: CoachSuggestion) {
            if let existing = byItem[suggestion.planItemID], existing.priority <= suggestion.priority { return }
            byItem[suggestion.planItemID] = suggestion
        }
        let planExercises = Set(items.map(\.exerciseID))

        // 1. Stillstand oder Rückgang je Übung.
        for item in items {
            guard let trend = trends[item.exerciseID], trend.pace == .stalled || trend.pace == .declining,
                  let info = catalog.exercise(id: item.exerciseID)
            else { continue }
            let name = info.name
            let weeksText = "\(Int(trend.weeks.rounded())) Wochen"
            if trend.weeks >= swapAfterWeeks,
               let alternative = catalog.alternatives(to: item.exerciseID).first(where: { !planExercises.contains($0.id) }) {
                offer(CoachSuggestion(
                    planItemID: item.id, exerciseID: item.exerciseID, change: .swap(to: alternative.id),
                    title: "\(name) gegen \(alternative.name) tauschen",
                    reason: "\(trend.pace == .declining ? "Rückläufig" : "Kein Fortschritt") seit etwa \(weeksText). Ein neuer Reiz für dieselben Muskeln hilft oft.",
                    priority: trend.pace == .declining ? 0 : 1
                ))
            } else {
                let range = nextRepRange(min: item.repMin, max: item.repMax, isCompound: info.isCompound)
                offer(CoachSuggestion(
                    planItemID: item.id, exerciseID: item.exerciseID, change: .repRange(min: range.min, max: range.max),
                    title: "\(name): \(range.min)–\(range.max) statt \(item.repMin)–\(item.repMax) Wiederholungen",
                    reason: "\(trend.pace == .declining ? "Kraft sinkt" : "Stillstand") seit etwa \(weeksText). Ein anderer Wiederholungsbereich bringt oft wieder Bewegung rein.",
                    priority: trend.pace == .declining ? 1 : 2
                ))
            }
        }

        // 2. Wochenvolumen je Muskel gegen den Zielbereich (nur mit Trainingsdaten).
        if !weeklySets.isEmpty {
            for muscle in MuscleGroup.allCases {
                let target = muscle.weeklyTarget
                let average = weeklySets[muscle] ?? 0
                let candidates = items.filter { catalog.exercise(id: $0.exerciseID)?.primary.first == muscle }
                if target.lowerBound > 0, average < Double(target.lowerBound) {
                    // Lieber eine Isolationsübung mit wenigen Sätzen aufstocken.
                    let pick = candidates
                        .filter { $0.sets < maxSets }
                        .sorted { lhs, rhs in
                            let lc = catalog.exercise(id: lhs.exerciseID)?.isCompound == true
                            let rc = catalog.exercise(id: rhs.exerciseID)?.isCompound == true
                            if lc != rc { return !lc }
                            return lhs.sets < rhs.sets
                        }
                        .first
                    if let pick {
                        offer(CoachSuggestion(
                            planItemID: pick.id, exerciseID: pick.exerciseID, change: .addSet,
                            title: "\(catalog.name(for: pick.exerciseID)): 1 Satz mehr (\(pick.sets) → \(pick.sets + 1))",
                            reason: "\(muscle.title): Ø \(WeightFormat.number((average * 10).rounded() / 10)) Sätze pro Woche, Ziel \(target.lowerBound)–\(target.upperBound).",
                            priority: 3
                        ))
                    }
                } else if average > Double(target.upperBound + 2) {
                    if let pick = candidates.filter({ $0.sets > 2 }).max(by: { $0.sets < $1.sets }) {
                        offer(CoachSuggestion(
                            planItemID: pick.id, exerciseID: pick.exerciseID, change: .removeSet,
                            title: "\(catalog.name(for: pick.exerciseID)): 1 Satz weniger (\(pick.sets) → \(pick.sets - 1))",
                            reason: "\(muscle.title): Ø \(WeightFormat.number((average * 10).rounded() / 10)) Sätze pro Woche, mehr als die \(target.upperBound) für gute Erholung.",
                            priority: 4
                        ))
                    }
                }
            }
        }

        return byItem.values
            .sorted { $0.priority != $1.priority ? $0.priority < $1.priority : $0.title < $1.title }
            .prefix(limit)
            .map { $0 }
    }

    /// Wechselt zwischen schwer (≤ 8), mittel (8–12) und leicht (12–15).
    static func nextRepRange(min: Int, max: Int, isCompound: Bool) -> (min: Int, max: Int) {
        if max <= 8 { return (8, 12) }
        if min >= 12 { return (8, 12) }
        return isCompound ? (6, 8) : (12, 15)
    }

    /// Muskeln unter dem Wochenziel; die, die die nächste Einheit trainiert, zuerst.
    public static func weeklyGaps(thisWeek: [MuscleVolume], nextSession exerciseIDs: [String], catalog: ExerciseCatalog) -> [WeeklyGap] {
        let next = Set(exerciseIDs.compactMap { catalog.exercise(id: $0)?.primary }.flatMap { $0 })
        return MuscleGroup.allCases.compactMap { muscle -> WeeklyGap? in
            let target = muscle.weeklyTarget.lowerBound
            guard target > 0 else { return nil }
            let done = thisWeek.first { $0.muscle == muscle }?.sets ?? 0
            guard done < Double(target) else { return nil }
            return WeeklyGap(muscle: muscle, done: done, target: target, inNextSession: next.contains(muscle))
        }
        .sorted { lhs, rhs in
            if lhs.inNextSession != rhs.inNextSession { return lhs.inNextSession }
            return lhs.missing > rhs.missing
        }
    }

    /// „Heute trainierst du Bizeps (noch 4 Sätze) und Trizeps (noch 6). Diese Woche fehlen außerdem: Brust 10.“
    public static func gapText(_ gaps: [WeeklyGap]) -> String? {
        guard !gaps.isEmpty else { return nil }
        let next = gaps.filter(\.inNextSession).map { "\($0.muscle.title) (noch \($0.missing))" }
        let other = gaps.filter { !$0.inNextSession }.map { "\($0.muscle.title) \($0.missing)" }
        var parts: [String] = []
        if !next.isEmpty { parts.append("Die nächste Einheit zählt für \(next.joined(separator: ", ")).") }
        if !other.isEmpty { parts.append("Diese Woche fehlen \(next.isEmpty ? "" : "außerdem ")Sätze für \(other.joined(separator: ", ")).") }
        return parts.joined(separator: " ")
    }
}
