import Foundation

// MARK: - Grundbausteine

public enum SetKind: String, Codable, Sendable, CaseIterable {
    case warmup
    case working
    case drop

    public var title: String {
        switch self {
        case .warmup: "Aufwärmen"
        case .working: "Arbeitssatz"
        case .drop: "Drop-Satz"
        }
    }
}

/// Ein ausgeführter Satz.
public struct LoggedSet: Codable, Sendable, Hashable {
    public var weight: Double
    public var reps: Int
    public var rir: Int?
    public var kind: SetKind

    public init(weight: Double, reps: Int, rir: Int? = nil, kind: SetKind = .working) {
        self.weight = weight
        self.reps = reps
        self.rir = rir
        self.kind = kind
    }

    /// Geschätztes 1-Wiederholungs-Maximum (Epley), mit Wiederholungen im Tank.
    public var estimatedOneRepMax: Double {
        OneRepMax.epley(weight: weight, reps: reps, rir: rir ?? 0)
    }

    /// Gewicht × Wiederholungen.
    public var volume: Double { weight * Double(reps) }
}

/// Alle Sätze einer Übung in einer Einheit.
public struct ExercisePerformance: Sendable, Hashable {
    public var date: Date
    public var sets: [LoggedSet]

    public init(date: Date, sets: [LoggedSet]) {
        self.date = date
        self.sets = sets
    }

    public var workingSets: [LoggedSet] { sets.filter { $0.kind == .working } }

    /// Schwerstes Arbeitsgewicht.
    public var topWeight: Double? { workingSets.map(\.weight).max() }

    public var bestEstimatedOneRepMax: Double? {
        workingSets.filter { $0.weight > 0 }.map(\.estimatedOneRepMax).max()
    }

    /// „80 × 8 · 80 × 8 · 80 × 7“
    public var summary: String {
        workingSets.map { "\(WeightFormat.kg($0.weight)) × \($0.reps)" }.joined(separator: " · ")
    }
}

public enum OneRepMax {
    public static func epley(weight: Double, reps: Int, rir: Int = 0) -> Double {
        guard weight > 0, reps > 0 else { return 0 }
        let effective = Double(reps + max(0, rir))
        return effective <= 1 ? weight : weight * (1 + effective / 30)
    }
}

/// Gewichte deutsch formatiert: „80“, „22,5“, „Körpergewicht“.
public enum WeightFormat {
    public static func number(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        var text = String(format: "%.2f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        return text.replacingOccurrences(of: ".", with: ",")
    }

    /// „80“ – ohne Einheit für Tabellen und Kurzformen.
    public static func kg(_ value: Double) -> String { number(value) }

    /// „80 kg“, bei 0 und Körpergewichtsübungen „KG“ (Körpergewicht).
    public static func label(_ value: Double, equipment: Equipment? = nil, assisted: Bool = false) -> String {
        if assisted { return value > 0 ? "−\(number(value)) kg Hilfe" : "ohne Hilfe" }
        if value == 0, equipment == .bodyweight { return "Körpergewicht" }
        if equipment == .bodyweight { return "+\(number(value)) kg" }
        return "\(number(value)) kg"
    }

    /// Auf den Steigerungsschritt runden.
    public static func round(_ value: Double, to increment: Double) -> Double {
        guard increment > 0 else { return value }
        return (value / increment).rounded() * increment
    }

    public static func roundDown(_ value: Double, to increment: Double) -> Double {
        guard increment > 0 else { return value }
        return (value / increment + 0.0001).rounded(.down) * increment
    }
}

// MARK: - Mesozyklus

/// 6-Wochen-Zyklus: Woche 1 locker (Basis-RIR + 1), Wochen 2–3 wie geplant,
/// Wochen 4–5 härter (−1, Isolation letzter Satz bis 0), letzte Woche Deload.
public struct Mesocycle: Sendable, Hashable {
    public var length: Int

    public init(length: Int = 6) {
        self.length = min(max(length, 3), 12)
    }

    public var deloadWeek: Int { length }

    public func isDeload(week: Int) -> Bool { week >= deloadWeek }

    /// Verschiebung des RIR je Arbeitswoche.
    func offset(week: Int) -> Int {
        let working = length - 1
        guard week >= 1, week <= working else { return 0 }
        if week == 1 { return 1 }
        // Letzte zwei Arbeitswochen härter, der Rest wie geplant.
        return week > working - 2 ? -1 : 0
    }

    public func targetRIR(base: Int, week: Int, isIsolation: Bool, isLastSet: Bool) -> Int {
        if isDeload(week: week) { return 4 }
        let value = base + offset(week: week)
        if isIsolation, isLastSet, offset(week: week) < 0 { return 0 }
        return min(max(value, 0), 5)
    }

    /// Sätze in dieser Woche (Deload: halbiert, aufgerundet).
    public func sets(base: Int, week: Int) -> Int {
        isDeload(week: week) ? max(1, Int((Double(base) / 2).rounded(.up))) : base
    }

    /// „Woche 2 von 6 · RIR 2“ bzw. „Deload-Woche“
    public func label(week: Int) -> String {
        if isDeload(week: week) { return "Woche \(week) von \(length) · Deload" }
        return "Woche \(week) von \(length)"
    }

    /// Kurzer Hinweis zur Woche.
    public func weekHint(week: Int) -> String {
        if isDeload(week: week) { return "Deload: halbe Sätze, gleiches Gewicht, locker (RIR 4)." }
        switch offset(week: week) {
        case 1: return "Einstieg: eine Wiederholung mehr im Tank als geplant."
        case -1: return "Harte Wochen: eine Wiederholung weniger im Tank, Isolation im letzten Satz bis ans Limit."
        default: return "Wie geplant trainieren."
        }
    }
}

// MARK: - Progression

public struct ProgressionSuggestion: Sendable, Hashable {
    public enum Kind: String, Sendable {
        case firstTime, increase, hold, decrease, deload
    }

    public var kind: Kind
    /// Vorgeschlagenes Arbeitsgewicht (`nil` beim ersten Mal).
    public var weight: Double?
    /// Ziel-Wiederholungen je Satz.
    public var targetReps: [Int]
    public var message: String
}

/// Doppelte Progression: Gewicht bleibt, bis alle Arbeitssätze das obere Ende erreichen,
/// dann geht es um einen Schritt hoch. Zweimal unter dem unteren Ende: etwa 7,5 % runter.
public enum ProgressionEngine {
    public static func suggest(
        exercise: ExerciseInfo,
        sets: Int,
        repMin: Int,
        repMax: Int,
        rir: Int,
        isDeload: Bool,
        history: [ExercisePerformance],
        increment: Double? = nil
    ) -> ProgressionSuggestion {
        let step = increment ?? exercise.increment
        let recent = history.filter { !$0.workingSets.isEmpty }.sorted { $0.date > $1.date }
        let repRange = repMin == repMax ? "\(repMin)" : "\(repMin)–\(repMax)"
        guard let last = recent.first, let lastWeight = last.topWeight else {
            return ProgressionSuggestion(
                kind: .firstTime, weight: nil, targetReps: Array(repeating: repMin, count: sets),
                message: "Erstes Mal: Wähle ein Gewicht für \(repRange) Wdh. mit noch \(rir) Wdh. im Tank."
            )
        }

        if isDeload {
            return ProgressionSuggestion(
                kind: .deload, weight: lastWeight, targetReps: Array(repeating: repMin, count: sets),
                message: "Deload: gleiches Gewicht, halbe Sätze, \(repMin) Wdh. locker."
            )
        }

        // Zweimal hintereinander die Mehrheit der Sätze unter dem unteren Ende.
        let struggled = recent.prefix(2).filter { performance in
            let below = performance.workingSets.filter { $0.reps < repMin }.count
            return below * 2 >= performance.workingSets.count && below > 0
        }
        if recent.count >= 2, struggled.count == 2 {
            let lowered = exercise.assisted
                ? WeightFormat.round(lastWeight * 1.075 + step / 2, to: step)
                : min(WeightFormat.roundDown(lastWeight * 0.925, to: step), lastWeight - step)
            return ProgressionSuggestion(
                kind: .decrease, weight: max(0, lowered), targetReps: Array(repeating: repMin, count: sets),
                message: "Zweimal unter \(repMin) Wdh.: etwas leichter und sauber wieder aufbauen."
            )
        }

        let working = last.workingSets
        if !working.isEmpty, working.allSatisfy({ $0.reps >= repMax }) {
            let next = exercise.assisted ? max(0, lastWeight - step) : lastWeight + step
            let stepText = WeightFormat.number(step)
            return ProgressionSuggestion(
                kind: .increase, weight: next, targetReps: Array(repeating: repMin, count: sets),
                message: exercise.assisted
                    ? "Alle Sätze bei \(repMax) Wdh.: \(stepText) kg weniger Unterstützung."
                    : "Alle Sätze bei \(repMax) Wdh.: +\(stepText) kg."
            )
        }

        // Gleiches Gewicht, je Satz eine Wiederholung mehr als zuletzt (bis zum oberen Ende).
        let targets = (0..<sets).map { index -> Int in
            let previous = index < working.count ? working[index].reps : (working.last?.reps ?? repMin)
            return min(repMax, max(repMin, previous + 1))
        }
        return ProgressionSuggestion(
            kind: .hold, weight: lastWeight, targetReps: targets,
            message: "Gleiches Gewicht, Ziel: \(targets.map(String.init).joined(separator: " · ")) Wdh."
        )
    }
}

// MARK: - Aufwärmen

public enum WarmupCalculator {
    /// 50 % × 8, 70 % × 5, 85 % × 3 – gerundet, ohne doppelte und zu leichte Sätze.
    public static func sets(workingWeight: Double, equipment: Equipment, increment: Double) -> [LoggedSet] {
        guard workingWeight > 0 else { return [] }
        let minimum = max(equipment.minimumLoad, increment)
        let steps: [(Double, Int)] = [(0.5, 8), (0.7, 5), (0.85, 3)]
        var result: [LoggedSet] = []
        for (factor, reps) in steps {
            let weight = max(minimum, WeightFormat.round(workingWeight * factor, to: increment))
            guard weight < workingWeight else { continue }
            if let last = result.last, last.weight >= weight { continue }
            result.append(LoggedSet(weight: weight, reps: reps, kind: .warmup))
        }
        return result
    }
}

// MARK: - Volumen

public struct MuscleVolume: Sendable, Hashable, Identifiable {
    public enum Status: String, Sendable {
        case low, inRange, high, optional
    }

    public var muscle: MuscleGroup
    /// Sätze (Hauptmuskel 1, Nebenmuskel 0,5).
    public var sets: Double
    public var target: ClosedRange<Int>

    public var id: MuscleGroup { muscle }

    public var status: Status {
        if sets > Double(target.upperBound) { return .high }
        if target.lowerBound == 0 { return sets > 0 ? .inRange : .optional }
        return sets < Double(target.lowerBound) ? .low : .inRange
    }

    /// „14 Sätze (Ziel 10–20)“
    public var label: String {
        "\(WeightFormat.number(sets)) Sätze (Ziel \(target.lowerBound)–\(target.upperBound))"
    }
}

public enum VolumeCalculator {
    /// Arbeitssätze je Muskel. `exerciseIDs`: je erledigtem Arbeitssatz eine ID.
    public static func volume(exerciseIDs: [String], catalog: ExerciseCatalog, includeOptional: Bool = false) -> [MuscleVolume] {
        var sets: [MuscleGroup: Double] = [:]
        for id in exerciseIDs {
            guard let exercise = catalog.exercise(id: id) else { continue }
            for muscle in exercise.primary { sets[muscle, default: 0] += 1 }
            for muscle in exercise.secondary { sets[muscle, default: 0] += 0.5 }
        }
        return MuscleGroup.allCases.compactMap { muscle in
            let value = sets[muscle] ?? 0
            let item = MuscleVolume(muscle: muscle, sets: value, target: muscle.weeklyTarget)
            if !includeOptional, value == 0, muscle.weeklyTarget.lowerBound == 0 { return nil }
            return item
        }
    }
}

// MARK: - Rekorde und Zusammenfassung

public struct PersonalRecord: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable {
        case weight, oneRepMax
    }

    public var exerciseID: String
    public var kind: Kind
    public var value: Double
    public var previous: Double

    public var id: String { "\(exerciseID)-\(kind.rawValue)" }

    /// „Neues Höchstgewicht: 85 kg (vorher 82,5)“
    public var label: String {
        switch kind {
        case .weight: "Höchstgewicht \(WeightFormat.number(value)) kg (vorher \(WeightFormat.number(previous)))"
        case .oneRepMax: "Geschätztes Maximum \(WeightFormat.number(value.rounded())) kg (vorher \(WeightFormat.number(previous.rounded())))"
        }
    }
}

public enum RecordFinder {
    /// Neue Rekorde einer Einheit gegenüber der Vorgeschichte (erstes Mal zählt nicht).
    public static func records(
        session: [String: [LoggedSet]],
        history: [String: [ExercisePerformance]],
        catalog: ExerciseCatalog
    ) -> [PersonalRecord] {
        var result: [PersonalRecord] = []
        for (exerciseID, sets) in session.sorted(by: { $0.key < $1.key }) {
            if catalog.exercise(id: exerciseID)?.assisted == true { continue }
            let working = sets.filter { $0.kind == .working && $0.weight > 0 && $0.reps > 0 }
            let past = (history[exerciseID] ?? []).flatMap(\.workingSets).filter { $0.weight > 0 && $0.reps > 0 }
            guard !working.isEmpty, !past.isEmpty else { continue }
            if let best = working.map(\.weight).max(), let before = past.map(\.weight).max(), best > before {
                result.append(PersonalRecord(exerciseID: exerciseID, kind: .weight, value: best, previous: before))
            }
            if let best = working.map(\.estimatedOneRepMax).max(), let before = past.map(\.estimatedOneRepMax).max(), best > before + 0.5 {
                result.append(PersonalRecord(exerciseID: exerciseID, kind: .oneRepMax, value: best, previous: before))
            }
        }
        return result
    }
}

public struct SessionSummary: Sendable, Hashable {
    public var duration: TimeInterval
    public var workingSets: Int
    public var volume: Double
    public var records: [PersonalRecord]
    /// Veränderung des Volumens gegenüber der letzten Einheit desselben Tages (z. B. 0,05 = +5 %).
    public var volumeChange: Double?

    public static func make(
        start: Date,
        end: Date,
        sets: [LoggedSet],
        records: [PersonalRecord],
        previousVolume: Double?
    ) -> SessionSummary {
        let working = sets.filter { $0.kind != .warmup }
        let volume = working.reduce(0) { $0 + $1.volume }
        let change = previousVolume.flatMap { $0 > 0 ? (volume - $0) / $0 : nil }
        return SessionSummary(
            duration: max(0, end.timeIntervalSince(start)),
            workingSets: working.count,
            volume: volume,
            records: records,
            volumeChange: change
        )
    }

    /// „1:12 Std.“ bzw. „48 Min.“
    public var durationLabel: String {
        let minutes = Int(duration / 60)
        if minutes < 60 { return "\(minutes) Min." }
        return String(format: "%d:%02d Std.", minutes / 60, minutes % 60)
    }

    /// „8.450 kg“
    public var volumeLabel: String {
        let value = Int(volume.rounded())
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "de_DE")
        formatter.groupingSeparator = "."
        return "\(formatter.string(from: NSNumber(value: value)) ?? String(value)) kg"
    }
}

// MARK: - Deload-Empfehlung

public enum DeloadAdvisor {
    /// Stagniert, wenn das beste geschätzte Maximum der letzten zwei Einheiten nicht über
    /// dem besten davor liegt (mindestens vier Einheiten Verlauf).
    public static func isStagnating(_ history: [ExercisePerformance]) -> Bool {
        let sessions = history.filter { $0.bestEstimatedOneRepMax != nil }.sorted { $0.date > $1.date }
        guard sessions.count >= 4 else { return false }
        let recent = sessions.prefix(2).compactMap(\.bestEstimatedOneRepMax).max() ?? 0
        let before = sessions.dropFirst(2).compactMap(\.bestEstimatedOneRepMax).max() ?? 0
        return recent <= before
    }

    /// Früherer Deload, wenn mindestens zwei Grundübungen stagnieren. Gibt deren IDs zurück.
    public static func stagnatingCompounds(histories: [String: [ExercisePerformance]], catalog: ExerciseCatalog) -> [String] {
        histories
            .filter { catalog.exercise(id: $0.key)?.isCompound == true && isStagnating($0.value) }
            .map(\.key)
            .sorted()
    }

    public static func suggestsEarlyDeload(histories: [String: [ExercisePerformance]], catalog: ExerciseCatalog) -> Bool {
        stagnatingCompounds(histories: histories, catalog: catalog).count >= 2
    }
}

// MARK: - Rotation

/// Fortschritt im Plan: nächste Einheit (A → B → C → D) und Woche im Zyklus.
public struct PlanProgress: Codable, Sendable, Hashable {
    public var nextDayIndex: Int
    public var week: Int

    public init(nextDayIndex: Int = 0, week: Int = 1) {
        self.nextDayIndex = nextDayIndex
        self.week = week
    }

    /// Nach einer Einheit: nächster Tag; nach dem letzten Tag beginnt die nächste Woche.
    public func afterCompleting(dayIndex: Int, dayCount: Int, cycle: Mesocycle) -> PlanProgress {
        guard dayCount > 0 else { return self }
        let next = (dayIndex + 1) % dayCount
        var week = self.week
        if dayIndex == dayCount - 1 {
            week = week >= cycle.length ? 1 : week + 1
        }
        return PlanProgress(nextDayIndex: next, week: week)
    }
}

/// Geplante Trainingstage an Wunsch-Wochentagen (für Agenda und Erinnerungen).
public enum TrainingSchedule {
    public struct Slot: Sendable, Hashable {
        public var date: Date
        public var dayIndex: Int
    }

    /// - Parameter trainedToday: heute schon trainiert, dann beginnt die Vorschau morgen.
    public static func upcoming(
        preferredWeekdays: [Int],
        nextDayIndex: Int,
        dayCount: Int,
        trainedToday: Bool,
        from now: Date,
        days: Int,
        calendar: Calendar
    ) -> [Slot] {
        guard dayCount > 0, !preferredWeekdays.isEmpty else { return [] }
        let preferred = Set(preferredWeekdays)
        var index = nextDayIndex % dayCount
        var result: [Slot] = []
        let today = calendar.startOfDay(for: now)
        for offset in (trainedToday ? 1 : 0)..<max(1, days) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            guard preferred.contains(calendar.component(.weekday, from: day)) else { continue }
            result.append(Slot(date: day, dayIndex: index))
            index = (index + 1) % dayCount
        }
        return result
    }
}
