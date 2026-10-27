import Foundation

public struct CheckInRecord: Codable, Sendable, Equatable {
    public var stableID: String
    public var day: Date
    public var sleep: Int?
    public var sleepHours: Double?
    public var energy: Int?
    public var mood: Int?
    public var stress: Int?
    public var note: String
    public var updatedAt: Date

    public init(stableID: String, day: Date, sleep: Int?, sleepHours: Double?, energy: Int?, mood: Int?, stress: Int?, note: String, updatedAt: Date) {
        self.stableID = stableID
        self.day = day
        self.sleep = sleep
        self.sleepHours = sleepHours
        self.energy = energy
        self.mood = mood
        self.stress = stress
        self.note = note
        self.updatedAt = updatedAt
    }
}

/// Status einer Anfrage an Claude.
public enum ClaudeExchangeStatus: String, Codable, Sendable, CaseIterable {
    /// Anfrage gebaut, noch nicht abgeschickt.
    case draft
    /// Über den Kurzbefehl oder die Zwischenablage abgeschickt, Antwort steht aus.
    case sent
    /// Antwort da, noch nicht übernommen.
    case answered
    /// Ergebnis übernommen (Plan, Lebensmittel, Rezepte) bzw. gelesen.
    case applied
    case discarded
    case failed

    public var title: String {
        switch self {
        case .draft: "Entwurf"
        case .sent: "Wartet auf Antwort"
        case .answered: "Antwort da"
        case .applied: "Übernommen"
        case .discarded: "Verworfen"
        case .failed: "Fehlgeschlagen"
        }
    }
}

public struct ClaudeExchangeRecord: Codable, Sendable, Equatable {
    public var stableID: String
    public var task: String
    public var ref: String
    public var title: String
    public var prompt: String
    public var response: String
    public var status: String
    public var createdAt: Date
    public var answeredAt: Date?

    public init(stableID: String, task: String, ref: String, title: String, prompt: String, response: String, status: String, createdAt: Date, answeredAt: Date?) {
        self.stableID = stableID
        self.task = task
        self.ref = ref
        self.title = title
        self.prompt = prompt
        self.response = response
        self.status = status
        self.createdAt = createdAt
        self.answeredAt = answeredAt
    }
}

/// Check-ins und Claude-Verlauf in der Datensicherung (ab Version 0.6).
public struct InsightsBackup: Codable, Sendable, Equatable {
    public var checkIns: [CheckInRecord]
    public var claudeExchanges: [ClaudeExchangeRecord]

    public init(checkIns: [CheckInRecord] = [], claudeExchanges: [ClaudeExchangeRecord] = []) {
        self.checkIns = checkIns
        self.claudeExchanges = claudeExchanges
    }
}
