import Foundation

public struct PainRecord: Codable, Sendable, Equatable {
    public var stableID: String
    public var date: Date
    public var regions: [String]
    public var intensity: Int
    public var qualities: [String]
    public var durationMinutes: Int?
    public var triggers: [String]
    public var reliefs: [String]
    public var note: String
    public var createdAt: Date

    public init(
        stableID: String, date: Date, regions: [String], intensity: Int, qualities: [String], durationMinutes: Int?,
        triggers: [String], reliefs: [String], note: String, createdAt: Date
    ) {
        self.stableID = stableID
        self.date = date
        self.regions = regions
        self.intensity = intensity
        self.qualities = qualities
        self.durationMinutes = durationMinutes
        self.triggers = triggers
        self.reliefs = reliefs
        self.note = note
        self.createdAt = createdAt
    }
}

public struct ActivityRecord: Codable, Sendable, Equatable {
    public var stableID: String
    public var date: Date
    public var kind: String
    public var minutes: Int
    public var intensity: Int
    public var note: String
    public var createdAt: Date

    public init(stableID: String, date: Date, kind: String, minutes: Int, intensity: Int, note: String, createdAt: Date) {
        self.stableID = stableID
        self.date = date
        self.kind = kind
        self.minutes = minutes
        self.intensity = intensity
        self.note = note
        self.createdAt = createdAt
    }
}

public struct DiaryDayRecord: Codable, Sendable, Equatable {
    public var stableID: String
    public var day: Date
    public var symptomFree: Bool
    public var restDay: Bool

    public init(stableID: String, day: Date, symptomFree: Bool, restDay: Bool) {
        self.stableID = stableID
        self.day = day
        self.symptomFree = symptomFree
        self.restDay = restDay
    }
}

/// Arzt-Tagebuch in der Datensicherung (ab 0.8).
public struct DiaryBackup: Codable, Sendable, Equatable {
    public var pains: [PainRecord]
    public var activities: [ActivityRecord]
    public var days: [DiaryDayRecord]

    public init(pains: [PainRecord] = [], activities: [ActivityRecord] = [], days: [DiaryDayRecord] = []) {
        self.pains = pains
        self.activities = activities
        self.days = days
    }

    public var isEmpty: Bool { pains.isEmpty && activities.isEmpty && days.isEmpty }
}
