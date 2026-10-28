import Foundation
import SwiftData
import TagwerkCore

/// Übersetzt Schmerzen, Bewegung und Tages-Vermerke zwischen Datenbank und Datensicherung.
@MainActor
enum DiaryBackupMapper {
    static func makeBackup(context: ModelContext) throws -> DiaryBackup {
        let pains = try context.fetch(FetchDescriptor<PainEntry>(sortBy: [SortDescriptor(\.date)]))
        let activities = try context.fetch(FetchDescriptor<ActivityEntry>(sortBy: [SortDescriptor(\.date)]))
        let days = try context.fetch(FetchDescriptor<DiaryDay>(sortBy: [SortDescriptor(\.day)]))
        return DiaryBackup(
            pains: pains.map {
                PainRecord(
                    stableID: $0.stableID, date: $0.date, regions: $0.regionsRaw, intensity: $0.intensity, qualities: $0.qualitiesRaw,
                    durationMinutes: $0.durationMinutes, triggers: $0.triggersRaw, reliefs: $0.reliefsRaw, note: $0.note, createdAt: $0.createdAt
                )
            },
            activities: activities.map {
                ActivityRecord(stableID: $0.stableID, date: $0.date, kind: $0.kindRaw, minutes: $0.minutes, intensity: $0.intensityRaw, note: $0.note, createdAt: $0.createdAt)
            },
            days: days.map {
                DiaryDayRecord(stableID: $0.stableID, day: $0.day, symptomFree: $0.symptomFree, restDay: $0.restDay)
            }
        )
    }

    static func restore(_ backup: DiaryBackup, context: ModelContext) throws {
        for item in try context.fetch(FetchDescriptor<PainEntry>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<ActivityEntry>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<DiaryDay>()) { context.delete(item) }
        try context.save()

        for record in backup.pains {
            let entry = PainEntry(date: record.date, intensity: record.intensity, stableID: record.stableID, createdAt: record.createdAt)
            entry.regionsRaw = record.regions
            entry.qualitiesRaw = record.qualities
            entry.durationMinutes = record.durationMinutes
            entry.triggersRaw = record.triggers
            entry.reliefsRaw = record.reliefs
            entry.note = record.note
            context.insert(entry)
        }
        for record in backup.activities {
            let entry = ActivityEntry(
                date: record.date, kind: ActivityKind(rawValue: record.kind) ?? .other, minutes: record.minutes,
                intensity: ActivityIntensity(rawValue: record.intensity) ?? .moderate, stableID: record.stableID, createdAt: record.createdAt
            )
            entry.kindRaw = record.kind
            entry.note = record.note
            context.insert(entry)
        }
        for record in backup.days {
            let day = DiaryDay(day: record.day, stableID: record.stableID)
            day.symptomFree = record.symptomFree
            day.restDay = record.restDay
            context.insert(day)
        }
        try context.save()
    }
}
