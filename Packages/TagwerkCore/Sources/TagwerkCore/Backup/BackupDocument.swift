import Foundation

/// Vollständige Datensicherung als JSON. Dient auch zum Umzug auf eine neue
/// Bundle-ID (z. B. beim Wechsel von kostenloser Apple-ID zum Developer-Account).
public struct BackupDocument: Codable, Sendable, Equatable {
    public static let currentFormat = "tagwerk.backup.v1"

    public var format: String
    public var createdAt: Date
    public var appVersion: String
    public var lists: [TaskListRecord]
    public var tasks: [TaskRecord]
    /// Einfache Einstellungen (Name, Kalenderauswahl …) als Schlüssel/Wert.
    public var settings: [String: String]

    public init(
        format: String = BackupDocument.currentFormat,
        createdAt: Date,
        appVersion: String,
        lists: [TaskListRecord],
        tasks: [TaskRecord],
        settings: [String: String] = [:]
    ) {
        self.format = format
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.lists = lists
        self.tasks = tasks
        self.settings = settings
    }
}

public struct TaskListRecord: Codable, Sendable, Equatable {
    public var stableID: String
    public var name: String
    public var symbol: String
    public var colorName: String
    public var sortIndex: Double
    public var createdAt: Date

    public init(stableID: String, name: String, symbol: String, colorName: String, sortIndex: Double, createdAt: Date) {
        self.stableID = stableID
        self.name = name
        self.symbol = symbol
        self.colorName = colorName
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }
}

public struct TaskRecord: Codable, Sendable, Equatable {
    public var stableID: String
    public var title: String
    public var notes: String
    public var dueDate: Date?
    public var hasDueTime: Bool
    public var priority: Int
    public var isFlagged: Bool
    public var focusDate: Date?
    public var isDone: Bool
    public var completedAt: Date?
    public var createdAt: Date
    public var sortIndex: Double
    public var estimateMinutes: Int?
    public var recurrence: RecurrenceRule?
    public var reminderOffsets: [Int]
    public var listID: String?
    public var tags: [String]
    public var kind: String
    public var subtasks: [SubtaskRecord]

    public init(
        stableID: String,
        title: String,
        notes: String = "",
        dueDate: Date? = nil,
        hasDueTime: Bool = false,
        priority: Int = 0,
        isFlagged: Bool = false,
        focusDate: Date? = nil,
        isDone: Bool = false,
        completedAt: Date? = nil,
        createdAt: Date,
        sortIndex: Double = 0,
        estimateMinutes: Int? = nil,
        recurrence: RecurrenceRule? = nil,
        reminderOffsets: [Int] = [],
        listID: String? = nil,
        tags: [String] = [],
        kind: String = "task",
        subtasks: [SubtaskRecord] = []
    ) {
        self.stableID = stableID
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.hasDueTime = hasDueTime
        self.priority = priority
        self.isFlagged = isFlagged
        self.focusDate = focusDate
        self.isDone = isDone
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.sortIndex = sortIndex
        self.estimateMinutes = estimateMinutes
        self.recurrence = recurrence
        self.reminderOffsets = reminderOffsets
        self.listID = listID
        self.tags = tags
        self.kind = kind
        self.subtasks = subtasks
    }
}

public struct SubtaskRecord: Codable, Sendable, Equatable {
    public var stableID: String
    public var title: String
    public var isDone: Bool
    public var sortIndex: Double

    public init(stableID: String, title: String, isDone: Bool, sortIndex: Double) {
        self.stableID = stableID
        self.title = title
        self.isDone = isDone
        self.sortIndex = sortIndex
    }
}

public enum BackupError: Error, Equatable, LocalizedError {
    case notATagwerkBackup
    case unsupportedVersion(String)
    case unreadable

    public var errorDescription: String? {
        switch self {
        case .notATagwerkBackup: "Die Datei ist keine Tagwerk-Sicherung."
        case .unsupportedVersion(let format): "Diese Sicherung (\(format)) stammt von einer neueren Tagwerk-Version."
        case .unreadable: "Die Sicherung ist beschädigt oder unvollständig."
        }
    }
}

public enum BackupCodec {
    public static let filePrefix = "Tagwerk-Backup-"

    public static func encode(_ document: BackupDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    public static func decode(_ data: Data) throws -> BackupDocument {
        struct Header: Decodable {
            var format: String?
        }
        guard let header = try? JSONDecoder().decode(Header.self, from: data), let format = header.format,
              format.hasPrefix("tagwerk.backup.")
        else {
            throw BackupError.notATagwerkBackup
        }
        guard format == BackupDocument.currentFormat else {
            throw BackupError.unsupportedVersion(format)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(BackupDocument.self, from: data)
        } catch {
            throw BackupError.unreadable
        }
    }

    /// „Tagwerk-Backup-2026-10-26_18-17.json“ – sortiert sich chronologisch.
    public static func fileName(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(
            format: "%@%04d-%02d-%02d_%02d-%02d.json",
            filePrefix, c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0
        )
    }
}

public enum BackupRetention {
    /// Dateien, die gelöscht werden können, damit nur die neuesten `keep` Sicherungen bleiben.
    /// Andere Dateien im Ordner werden nie angefasst.
    public static func filesToDelete(_ fileNames: [String], keep: Int) -> [String] {
        let backups = fileNames
            .filter { $0.hasPrefix(BackupCodec.filePrefix) && $0.hasSuffix(".json") }
            .sorted(by: >)
        return Array(backups.dropFirst(max(0, keep)))
    }

    /// Ob eine automatische Sicherung fällig ist (Standard: nach 20 Stunden).
    public static func isAutomaticBackupDue(lastBackup: Date?, now: Date, minimumInterval: TimeInterval = 20 * 3_600) -> Bool {
        guard let lastBackup else { return true }
        return now.timeIntervalSince(lastBackup) >= minimumInterval
    }
}
