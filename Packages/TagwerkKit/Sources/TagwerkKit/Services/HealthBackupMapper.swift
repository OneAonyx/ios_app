import Foundation
import SwiftData
import TagwerkCore

/// Übersetzt die Health-Tageswerte zwischen Datenbank und Datensicherung.
@MainActor
enum HealthBackupMapper {
    static func makeBackup(context: ModelContext) throws -> HealthBackup {
        let days = try context.fetch(FetchDescriptor<HealthDay>(sortBy: [SortDescriptor(\.day)]))
        return HealthBackup(days: days.map {
            HealthDayRecord(
                stableID: $0.stableID, day: $0.day, steps: $0.steps, distanceKm: $0.distanceKm, flights: $0.flights,
                sleepHours: $0.sleepHours, restingHeartRate: $0.restingHeartRate, updatedAt: $0.updatedAt
            )
        })
    }

    static func restore(_ backup: HealthBackup, context: ModelContext) throws {
        for item in try context.fetch(FetchDescriptor<HealthDay>()) { context.delete(item) }
        try context.save()
        for record in backup.days {
            let day = HealthDay(day: record.day, stableID: record.stableID)
            day.steps = record.steps
            day.distanceKm = record.distanceKm
            day.flights = record.flights
            day.sleepHours = record.sleepHours
            day.restingHeartRate = record.restingHeartRate
            day.updatedAt = record.updatedAt
            context.insert(day)
        }
        try context.save()
    }
}
