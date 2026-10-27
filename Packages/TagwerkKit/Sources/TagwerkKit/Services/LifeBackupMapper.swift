import Foundation
import SwiftData
import TagwerkCore

/// Übersetzt Routinen, Gewohnheiten, Verträge, Geburtstage und Tagebuch zwischen Datenbank und Datensicherung.
@MainActor
enum LifeBackupMapper {
    static func makeBackup(context: ModelContext) throws -> LifeBackup {
        let habits = try context.fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortIndex)]))
        let logs = try context.fetch(FetchDescriptor<HabitLog>(sortBy: [SortDescriptor(\.day)]))
        let contracts = try context.fetch(FetchDescriptor<Contract>(sortBy: [SortDescriptor(\.createdAt)]))
        let birthdays = try context.fetch(FetchDescriptor<Birthday>(sortBy: [SortDescriptor(\.name)]))
        let journal = try context.fetch(FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\.day)]))
        return LifeBackup(
            habits: habits.map {
                HabitRecord(
                    stableID: $0.stableID, kind: $0.kindRaw, name: $0.name, symbol: $0.symbol, colorName: $0.colorName,
                    period: $0.periodRaw, schedule: $0.schedule, target: $0.target, unit: $0.unit, steps: $0.steps,
                    reminderMinute: $0.reminderMinute, sortIndex: $0.sortIndex, isArchived: $0.isArchived, createdAt: $0.createdAt
                )
            },
            habitLogs: logs.map {
                HabitLogRecord(stableID: $0.stableID, habitID: $0.habitID, day: $0.day, value: $0.value, doneSteps: $0.doneSteps)
            },
            contracts: contracts.map {
                ContractRecord(
                    stableID: $0.stableID, kind: $0.kindRaw, name: $0.name, provider: $0.provider, cost: $0.cost, billing: $0.billingRaw,
                    startDate: $0.startDate, endDate: $0.endDate, minimumTermMonths: $0.minimumTermMonths, renewalMonths: $0.renewalMonths,
                    notice: $0.notice, reminderDaysBefore: $0.reminderDaysBefore, note: $0.note, isCancelled: $0.isCancelled, createdAt: $0.createdAt
                )
            },
            birthdays: birthdays.map {
                BirthdayRecord(stableID: $0.stableID, name: $0.name, day: $0.day, month: $0.month, year: $0.year, reminderDaysBefore: $0.reminderDaysBefore, note: $0.note)
            },
            journal: journal.map {
                JournalRecord(stableID: $0.stableID, day: $0.day, prompt: $0.prompt, answer: $0.answer, text: $0.text, updatedAt: $0.updatedAt)
            }
        )
    }

    static func restore(_ backup: LifeBackup, context: ModelContext) throws {
        for item in try context.fetch(FetchDescriptor<HabitLog>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<Habit>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<Contract>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<Birthday>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<JournalEntry>()) { context.delete(item) }
        try context.save()

        for record in backup.habits {
            let habit = Habit(name: record.name, kind: HabitKind(rawValue: record.kind) ?? .habit, stableID: record.stableID, createdAt: record.createdAt)
            habit.symbol = record.symbol
            habit.colorName = record.colorName
            habit.periodRaw = record.period
            habit.schedule = record.schedule
            habit.target = record.target
            habit.unit = record.unit
            habit.steps = record.steps
            habit.reminderMinute = record.reminderMinute
            habit.sortIndex = record.sortIndex
            habit.isArchived = record.isArchived
            context.insert(habit)
        }
        for record in backup.habitLogs {
            let log = HabitLog(habitID: record.habitID, day: record.day, stableID: record.stableID)
            log.value = record.value
            log.doneSteps = record.doneSteps
            context.insert(log)
        }
        for record in backup.contracts {
            let contract = Contract(name: record.name, kind: ContractKind(rawValue: record.kind) ?? .contract, stableID: record.stableID, createdAt: record.createdAt)
            contract.provider = record.provider
            contract.cost = record.cost
            contract.billingRaw = record.billing
            contract.startDate = record.startDate
            contract.endDate = record.endDate
            contract.minimumTermMonths = record.minimumTermMonths
            contract.renewalMonths = record.renewalMonths
            contract.notice = record.notice
            contract.reminderDaysBefore = record.reminderDaysBefore
            contract.note = record.note
            contract.isCancelled = record.isCancelled
            context.insert(contract)
        }
        for record in backup.birthdays {
            let birthday = Birthday(name: record.name, day: record.day, month: record.month, year: record.year, stableID: record.stableID)
            birthday.reminderDaysBefore = record.reminderDaysBefore
            birthday.note = record.note
            context.insert(birthday)
        }
        for record in backup.journal {
            let entry = JournalEntry(day: record.day, prompt: record.prompt, stableID: record.stableID)
            entry.answer = record.answer
            entry.text = record.text
            entry.updatedAt = record.updatedAt
            context.insert(entry)
        }
    }
}
