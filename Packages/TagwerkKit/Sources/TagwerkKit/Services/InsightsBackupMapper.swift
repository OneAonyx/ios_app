import Foundation
import SwiftData
import TagwerkCore

/// Übersetzt Check-ins und Claude-Verlauf zwischen Datenbank und Datensicherung.
@MainActor
enum InsightsBackupMapper {
    nonisolated static func makeBackup(context: ModelContext) throws -> InsightsBackup {
        let checkIns = try context.fetch(FetchDescriptor<DailyCheckIn>(sortBy: [SortDescriptor(\.day)]))
        let exchanges = try context.fetch(FetchDescriptor<ClaudeExchange>(sortBy: [SortDescriptor(\.createdAt)]))
        return InsightsBackup(
            checkIns: checkIns.map {
                CheckInRecord(
                    stableID: $0.stableID, day: $0.day, sleep: $0.sleep, sleepHours: $0.sleepHours, energy: $0.energy,
                    mood: $0.mood, stress: $0.stress, note: $0.note, updatedAt: $0.updatedAt
                )
            },
            claudeExchanges: exchanges.map {
                ClaudeExchangeRecord(
                    stableID: $0.stableID, task: $0.taskRaw, ref: $0.ref, title: $0.title, prompt: $0.prompt,
                    response: $0.response, status: $0.statusRaw, createdAt: $0.createdAt, answeredAt: $0.answeredAt
                )
            }
        )
    }

    static func restore(_ backup: InsightsBackup, context: ModelContext) throws {
        for entry in try context.fetch(FetchDescriptor<DailyCheckIn>()) { context.delete(entry) }
        for entry in try context.fetch(FetchDescriptor<ClaudeExchange>()) { context.delete(entry) }
        try context.save()

        for record in backup.checkIns {
            let entry = DailyCheckIn(day: record.day, stableID: record.stableID)
            entry.sleep = record.sleep
            entry.sleepHours = record.sleepHours
            entry.energy = record.energy
            entry.mood = record.mood
            entry.stress = record.stress
            entry.note = record.note
            entry.updatedAt = record.updatedAt
            context.insert(entry)
        }
        for record in backup.claudeExchanges {
            let task = ClaudeTask(rawValue: record.task) ?? .weeklyReview
            let entry = ClaudeExchange(task: task, ref: record.ref, title: record.title, prompt: record.prompt, stableID: record.stableID, createdAt: record.createdAt)
            entry.response = record.response
            entry.statusRaw = record.status
            entry.answeredAt = record.answeredAt
            context.insert(entry)
        }
    }
}
