import Foundation
import SwiftData
import TagwerkCore

/// Fortschritt: Tempo je Übung, Körpergewicht, Maße, Fotos und Daten für Claude.
@MainActor
public enum ProgressActions {
    /// Tempo aller Übungen des aktiven Plans (mit Verlauf), Handlungsbedarf zuerst.
    public static func trends(now: Date = .now, in context: ModelContext) -> [ExerciseTrend] {
        guard let plan = TrainingActions.activePlan(in: context) else { return [] }
        let catalog = TrainingActions.catalog(in: context)
        var seen = Set<String>()
        let ids = plan.rotationDays.flatMap(\.sortedExercises).map(\.exerciseID).filter { seen.insert($0).inserted }
        return ids.map { trend(for: $0, catalog: catalog, now: now, in: context) }
            .sorted { $0.pace.sortRank == $1.pace.sortRank ? catalog.name(for: $0.exerciseID) < catalog.name(for: $1.exerciseID) : $0.pace.sortRank < $1.pace.sortRank }
    }

    public static func trend(for exerciseID: String, catalog: ExerciseCatalog, now: Date = .now, in context: ModelContext) -> ExerciseTrend {
        let compound = catalog.exercise(id: exerciseID)?.isCompound ?? false
        return ProgressAssessment.exercise(
            exerciseID, history: TrainingActions.history(for: exerciseID, limit: 40, in: context), isCompound: compound, now: now
        )
    }

    public static func bodyweightTrend(now: Date = .now, in context: ModelContext) -> BodyweightTrend? {
        let points = TrainingActions.metrics(.weight, in: context).map { (date: $0.date, value: $0.value) }
        return ProgressAssessment.bodyweight(points, now: now)
    }

    /// „Oberarm 36 → 37 cm“ für Maße mit mindestens zwei Einträgen in den letzten `weeks` Wochen.
    public static func measurementChanges(weeks: Int = 12, now: Date = .now, in context: ModelContext) -> [String] {
        let from = now.addingTimeInterval(-Double(weeks) * 7 * 86_400)
        return [BodyMetricType.upperArm, .chest, .shoulders, .waist, .thigh, .bodyFat].compactMap { type in
            let values = TrainingActions.metrics(type, in: context).filter { $0.date >= from }
            guard let first = values.first, let last = values.last, values.count >= 2 else { return nil }
            return "\(type.title) \(WeightFormat.number(first.value)) → \(type.label(last.value))"
        }
    }

    /// Einheiten pro Woche im Schnitt der letzten 4 Wochen.
    public static func frequencyText(now: Date = .now, in context: ModelContext) -> String {
        let from = now.addingTimeInterval(-28 * 86_400)
        let count = TrainingActions.sessions(from: from, to: now, in: context).filter { !$0.isActive && !$0.doneSets.isEmpty }.count
        guard count > 0 else { return "" }
        return "Ø \(WeightFormat.number((Double(count) / 4 * 10).rounded() / 10)) Einheiten pro Woche (letzte 4 Wochen)"
    }

    /// Daten für „Fortschritt bewerten“ und „Fotos bewerten“.
    public static func claudeContext(now: Date = .now, in context: ModelContext) -> ClaudePromptBuilder.ProgressContext {
        let catalog = TrainingActions.catalog(in: context)
        let trendLines = trends(now: now, in: context).filter { $0.pace != .notEnoughData }.map { trend in
            let weeks = Int(trend.weeks.rounded())
            return "\(catalog.name(for: trend.exerciseID)): \(WeightFormat.number(trend.first.rounded())) → \(WeightFormat.number(trend.last.rounded())) kg in \(weeks) Wochen (\(trend.rateText), \(trend.pace.title))"
        }
        let bodyweight = bodyweightTrend(now: now, in: context).map {
            "\(WeightFormat.number($0.first)) → \(WeightFormat.number($0.last)) kg in \(Int($0.weeks.rounded())) Wochen (\($0.rateText))"
        }
        return ClaudePromptBuilder.ProgressContext(
            goal: ClaudeBridgeActions.trainingGoal,
            experience: ClaudeBridgeActions.trainingExperience,
            body: TrainingActions.bodySummary(in: context),
            exerciseTrends: trendLines,
            bodyweight: bodyweight,
            measurements: measurementChanges(now: now, in: context),
            frequency: frequencyText(now: now, in: context)
        )
    }

    // MARK: Fotos

    public static func photos(in context: ModelContext) -> [ProgressPhoto] {
        (try? context.fetch(FetchDescriptor<ProgressPhoto>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
    }

    /// Foto speichern (Bild und Vorschau schon verkleinert). Übernimmt das letzte Körpergewicht.
    @discardableResult
    public static func addPhoto(imageData: Data, thumbnailData: Data, date: Date = .now, pose: PhotoPose, note: String = "", in context: ModelContext) -> ProgressPhoto {
        let photo = ProgressPhoto(date: date, pose: pose)
        photo.imageData = imageData
        photo.thumbnailData = thumbnailData
        photo.note = note
        photo.weight = TrainingActions.metrics(.weight, in: context).last { $0.date <= date.addingTimeInterval(86_400) }?.value
        context.insert(photo)
        save(context)
        return photo
    }

    public static func delete(_ photo: ProgressPhoto, in context: ModelContext) {
        context.delete(photo)
        save(context)
    }

    /// „Mo, 12. Okt. 2026, vorne, 80,5 kg“
    public static func label(for photo: ProgressPhoto, calendar: Calendar) -> String {
        var parts = [GermanCalendar.shortDate(photo.date, calendar: calendar, includeYear: true), photo.pose.title.lowercased()]
        if let weight = photo.weight { parts.append("\(WeightFormat.number(weight)) kg") }
        return parts.joined(separator: ", ")
    }

    public static func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            print("Orbit: Speichern fehlgeschlagen: \(error)")
        }
    }
}
