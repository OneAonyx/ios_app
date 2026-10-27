import Foundation

public struct HabitRecord: Codable, Sendable, Equatable {
    public var stableID: String
    public var kind: String
    public var name: String
    public var symbol: String
    public var colorName: String
    public var period: String
    public var schedule: HabitSchedule
    public var target: Double
    public var unit: String
    public var steps: [RoutineStep]
    public var reminderMinute: Int
    public var sortIndex: Double
    public var isArchived: Bool
    public var createdAt: Date

    public init(
        stableID: String, kind: String, name: String, symbol: String, colorName: String, period: String, schedule: HabitSchedule,
        target: Double, unit: String, steps: [RoutineStep], reminderMinute: Int, sortIndex: Double, isArchived: Bool, createdAt: Date
    ) {
        self.stableID = stableID
        self.kind = kind
        self.name = name
        self.symbol = symbol
        self.colorName = colorName
        self.period = period
        self.schedule = schedule
        self.target = target
        self.unit = unit
        self.steps = steps
        self.reminderMinute = reminderMinute
        self.sortIndex = sortIndex
        self.isArchived = isArchived
        self.createdAt = createdAt
    }
}

public struct HabitLogRecord: Codable, Sendable, Equatable {
    public var stableID: String
    public var habitID: String
    public var day: Date
    public var value: Double
    public var doneSteps: [String]

    public init(stableID: String, habitID: String, day: Date, value: Double, doneSteps: [String]) {
        self.stableID = stableID
        self.habitID = habitID
        self.day = day
        self.value = value
        self.doneSteps = doneSteps
    }
}

public struct ContractRecord: Codable, Sendable, Equatable {
    public var stableID: String
    public var kind: String
    public var name: String
    public var provider: String
    public var cost: Double?
    public var billing: String
    public var startDate: Date?
    public var endDate: Date?
    public var minimumTermMonths: Int?
    public var renewalMonths: Int?
    public var notice: NoticePeriod
    public var reminderDaysBefore: Int
    public var note: String
    public var isCancelled: Bool
    public var createdAt: Date

    public init(
        stableID: String, kind: String, name: String, provider: String, cost: Double?, billing: String, startDate: Date?, endDate: Date?,
        minimumTermMonths: Int?, renewalMonths: Int?, notice: NoticePeriod, reminderDaysBefore: Int, note: String, isCancelled: Bool, createdAt: Date
    ) {
        self.stableID = stableID
        self.kind = kind
        self.name = name
        self.provider = provider
        self.cost = cost
        self.billing = billing
        self.startDate = startDate
        self.endDate = endDate
        self.minimumTermMonths = minimumTermMonths
        self.renewalMonths = renewalMonths
        self.notice = notice
        self.reminderDaysBefore = reminderDaysBefore
        self.note = note
        self.isCancelled = isCancelled
        self.createdAt = createdAt
    }
}

public struct BirthdayRecord: Codable, Sendable, Equatable {
    public var stableID: String
    public var name: String
    public var day: Int
    public var month: Int
    public var year: Int?
    public var reminderDaysBefore: Int
    public var note: String

    public init(stableID: String, name: String, day: Int, month: Int, year: Int?, reminderDaysBefore: Int, note: String) {
        self.stableID = stableID
        self.name = name
        self.day = day
        self.month = month
        self.year = year
        self.reminderDaysBefore = reminderDaysBefore
        self.note = note
    }
}

public struct JournalRecord: Codable, Sendable, Equatable {
    public var stableID: String
    public var day: Date
    public var prompt: String
    public var answer: String
    public var text: String
    public var updatedAt: Date

    public init(stableID: String, day: Date, prompt: String, answer: String, text: String, updatedAt: Date) {
        self.stableID = stableID
        self.day = day
        self.prompt = prompt
        self.answer = answer
        self.text = text
        self.updatedAt = updatedAt
    }
}

/// Routinen, Gewohnheiten, Verträge, Geburtstage und Tagebuch in der Datensicherung (ab Version 0.7).
public struct LifeBackup: Codable, Sendable, Equatable {
    public var habits: [HabitRecord]
    public var habitLogs: [HabitLogRecord]
    public var contracts: [ContractRecord]
    public var birthdays: [BirthdayRecord]
    public var journal: [JournalRecord]

    public init(
        habits: [HabitRecord] = [], habitLogs: [HabitLogRecord] = [], contracts: [ContractRecord] = [],
        birthdays: [BirthdayRecord] = [], journal: [JournalRecord] = []
    ) {
        self.habits = habits
        self.habitLogs = habitLogs
        self.contracts = contracts
        self.birthdays = birthdays
        self.journal = journal
    }
}
