import Foundation
import SwiftData
import TagwerkCore

/// Version 1 des Datenmodells (Phase 1: Aufgaben, Unteraufgaben, Listen).
///
/// Regeln für späteren iCloud-Sync (CloudKit), von Anfang an eingehalten:
/// - keine `@Attribute(.unique)`, Eindeutigkeit über `stableID`
/// - jede Eigenschaft optional oder mit Standardwert
/// - alle Beziehungen optional, keine `.deny`-Löschregel
///
/// Neue Bereiche (Medikamente, Training …) kommen als neue Schema-Versionen dazu.
public enum TagwerkSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [TaskItem.self, Subtask.self, TaskList.self]
    }

    @Model
    public final class TaskList {
        public var stableID: String = UUID().uuidString
        public var name: String = ""
        public var symbol: String = "list.bullet"
        public var colorName: String = "indigo"
        public var sortIndex: Double = 0
        public var createdAt: Date = Date()

        @Relationship(deleteRule: .nullify, inverse: \TaskItem.list)
        public var tasks: [TaskItem]? = []

        public init(
            name: String,
            symbol: String = "list.bullet",
            colorName: String = "indigo",
            sortIndex: Double = 0,
            stableID: String = UUID().uuidString,
            createdAt: Date = Date()
        ) {
            self.stableID = stableID
            self.name = name
            self.symbol = symbol
            self.colorName = colorName
            self.sortIndex = sortIndex
            self.createdAt = createdAt
        }
    }

    @Model
    public final class TaskItem {
        public var stableID: String = UUID().uuidString
        public var title: String = ""
        public var notes: String = ""
        public var dueDate: Date?
        public var hasDueTime: Bool = false
        /// 0 = keine, 1 = niedrig, 2 = mittel, 3 = hoch.
        public var priority: Int = 0
        public var isFlagged: Bool = false
        /// Tag, an dem die Aufgabe im „Fokus“ steht.
        public var focusDate: Date?
        public var isDone: Bool = false
        public var completedAt: Date?
        public var createdAt: Date = Date()
        public var sortIndex: Double = 0
        public var estimateMinutes: Int?
        /// `RecurrenceRule` als JSON (siehe `recurrence`).
        public var recurrenceData: Data?
        /// Erinnerungen in Minuten vor der Fälligkeit.
        public var reminderOffsets: [Int] = []
        public var tags: [String] = []
        /// `task`, später auch `routine`, `deadline`, `contract`, `birthday`.
        public var kindRaw: String = "task"
        /// Folgeaufgabe, die beim Erledigen einer Wiederholung entstand (für „wieder öffnen“).
        public var nextOccurrenceID: String?

        public var list: TaskList?

        @Relationship(deleteRule: .cascade, inverse: \Subtask.task)
        public var subtasks: [Subtask]? = []

        public init(
            title: String,
            notes: String = "",
            dueDate: Date? = nil,
            hasDueTime: Bool = false,
            priority: Int = 0,
            list: TaskList? = nil,
            sortIndex: Double = 0,
            stableID: String = UUID().uuidString,
            createdAt: Date = Date()
        ) {
            self.stableID = stableID
            self.title = title
            self.notes = notes
            self.dueDate = dueDate
            self.hasDueTime = hasDueTime
            self.priority = priority
            self.list = list
            self.sortIndex = sortIndex
            self.createdAt = createdAt
        }
    }

    @Model
    public final class Subtask {
        public var stableID: String = UUID().uuidString
        public var title: String = ""
        public var isDone: Bool = false
        public var sortIndex: Double = 0
        public var task: TaskItem?

        public init(title: String, isDone: Bool = false, sortIndex: Double = 0, stableID: String = UUID().uuidString) {
            self.stableID = stableID
            self.title = title
            self.isDone = isDone
            self.sortIndex = sortIndex
        }
    }
}

/// Die aktuelle Schema-Version für den Rest der App.
public typealias TaskItem = TagwerkSchemaV1.TaskItem
public typealias Subtask = TagwerkSchemaV1.Subtask
public typealias TaskList = TagwerkSchemaV1.TaskList

public enum TagwerkMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [TagwerkSchemaV1.self]
    }

    public static var stages: [MigrationStage] {
        []
    }
}

// MARK: - Bequeme Zugriffe

extension TagwerkSchemaV1.TaskItem {
    /// Wiederholungsregel, gespeichert als JSON in `recurrenceData`.
    public var recurrence: RecurrenceRule? {
        get {
            guard let recurrenceData else { return nil }
            return try? JSONDecoder().decode(RecurrenceRule.self, from: recurrenceData)
        }
        set {
            recurrenceData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }

    /// Werte für Filter und Sortierung aus `TagwerkCore`.
    public var facts: TaskFacts {
        TaskFacts(
            dueDate: dueDate,
            hasDueTime: hasDueTime,
            isDone: isDone,
            completedAt: completedAt,
            priority: priority,
            isFlagged: isFlagged,
            focusDate: focusDate,
            listID: list?.stableID,
            sortIndex: sortIndex,
            createdAt: createdAt
        )
    }

    public var sortedSubtasks: [Subtask] {
        (subtasks ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }

    public var subtaskProgress: (done: Int, total: Int) {
        let all = subtasks ?? []
        return (all.filter(\.isDone).count, all.count)
    }

    public func isOverdue(now: Date = .now, calendar: Calendar) -> Bool {
        facts.isOverdue(now: now, calendar: calendar)
    }

    /// Als Eintrag für Agenda und Woche (nur mit Fälligkeitsdatum).
    public func agendaItem() -> AgendaItem? {
        guard let dueDate else { return nil }
        return AgendaItem(
            id: "task-\(stableID)",
            kind: .task,
            title: title,
            start: dueDate,
            isAllDay: !hasDueTime,
            isDone: isDone,
            subtitle: list?.name
        )
    }
}

extension TagwerkSchemaV1.TaskList {
    public var openTaskCount: Int {
        (tasks ?? []).filter { !$0.isDone }.count
    }
}
