import Foundation
import SwiftData
import TagwerkCore

/// Apple Health über Kurzbefehle: Werte übernehmen, Tageswerte lesen, Wasser und Gewicht zurückgeben.
@MainActor
public enum HealthActions {
    /// Markiert Gewichtswerte, die aus Health kamen (gehen nicht zurück nach Health).
    public static let healthNote = "Apple Health"

    /// Ergebnis einer Übergabe.
    public struct ImportResult: Sendable, Equatable {
        public var stored: HealthValues
        public var rejected: [String]
        public var day: Date
    }

    // MARK: Übernehmen

    /// Speichert die Werte für einen Tag. Gewicht landet unter Körper, Schlaf im Check-in
    /// (nur wenn dort noch nichts steht).
    @discardableResult
    public static func importValues(_ raw: HealthValues, day: Date = .now, now: Date = .now, calendar: Calendar, in context: ModelContext) -> ImportResult {
        let (values, rejected) = raw.sanitized()
        let start = calendar.startOfDay(for: day)
        let record = healthDay(on: start, calendar: calendar, in: context) ?? {
            let created = HealthDay(day: start)
            context.insert(created)
            return created
        }()
        record.apply(record.fact.merging(values))
        record.updatedAt = now

        if let weight = values.weightKg {
            let sameDay = TrainingActions.metrics(.weight, in: context).contains {
                calendar.isDate($0.date, inSameDayAs: start) && abs($0.value - weight) < 0.05
            }
            if !sameDay {
                let date = calendar.isDate(now, inSameDayAs: start) ? now : start.addingTimeInterval(8 * 3_600)
                TrainingActions.addMetric(.weight, value: weight, date: date, note: healthNote, in: context)
            }
        }
        if let sleep = values.sleepHours, InsightsActions.checkIn(on: start, calendar: calendar, in: context)?.sleepHours == nil {
            InsightsActions.setSleepHours(sleep, on: start, calendar: calendar, in: context)
        }
        save(context)
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: SettingsKeys.healthLastImport)
        return ImportResult(stored: values, rejected: rejected, day: start)
    }

    public static var lastImport: Date? {
        let value = UserDefaults.standard.double(forKey: SettingsKeys.healthLastImport)
        return value > 0 ? Date(timeIntervalSince1970: value) : nil
    }

    // MARK: Lesen

    public static func healthDay(on day: Date, calendar: Calendar, in context: ModelContext) -> HealthDay? {
        let start = calendar.startOfDay(for: day)
        let end = calendar.endOfDayDate(for: start)
        var descriptor = FetchDescriptor<HealthDay>(predicate: #Predicate { $0.day >= start && $0.day < end })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    public static func days(from start: Date, to end: Date, in context: ModelContext) -> [HealthDay] {
        let descriptor = FetchDescriptor<HealthDay>(
            predicate: #Predicate { $0.day >= start && $0.day < end },
            sortBy: [SortDescriptor(\.day)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    public static func facts(from start: Date, to end: Date, in context: ModelContext) -> [HealthDayFact] {
        days(from: start, to: end, in: context).map(\.fact)
    }

    // MARK: Zurück nach Health

    /// Wasser seit dem letzten Abruf (heute). Merkt sich den Stand, damit nichts doppelt ankommt.
    public static func waterForHealth(now: Date = .now, calendar: Calendar, in context: ModelContext) -> Int {
        let defaults = UserDefaults.standard
        let marker = defaults.data(forKey: SettingsKeys.healthWaterMarker).flatMap { try? JSONDecoder().decode(HealthExport.WaterMarker.self, from: $0) }
        let total = NutritionActions.water(on: now, calendar: calendar, in: context)
        let result = HealthExport.water(todayTotal: total, marker: marker, now: now, calendar: calendar)
        if let data = try? JSONEncoder().encode(result.marker) {
            defaults.set(data, forKey: SettingsKeys.healthWaterMarker)
        }
        return result.milliliters
    }

    /// Neuestes Gewicht aus Orbit, das noch nicht in Health ist, sonst `nil`.
    public static func weightForHealth(now: Date = .now, in context: ModelContext) -> Double? {
        let defaults = UserDefaults.standard
        let exported = defaults.double(forKey: SettingsKeys.healthWeightExportedAt)
        let weights = TrainingActions.metrics(.weight, in: context)
            .filter { $0.note != healthNote }
            .map { (date: $0.date, value: $0.value) }
        guard let pending = HealthExport.weight(weights, lastExported: exported > 0 ? Date(timeIntervalSince1970: exported) : nil) else { return nil }
        defaults.set(max(pending.date, now).timeIntervalSince1970, forKey: SettingsKeys.healthWeightExportedAt)
        return pending.value
    }

    public static func save(_ context: ModelContext) {
        try? context.save()
    }
}
