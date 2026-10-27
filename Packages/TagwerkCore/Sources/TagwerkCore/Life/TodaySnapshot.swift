import Foundation

/// Stand von „Heute“ für die Widgets „Heute“ und „Aufgaben“. Die App schreibt ihn in die App Group.
public struct TodayWidgetSnapshot: Codable, Sendable, Equatable {
    public struct TaskLine: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        public var title: String
        /// „heute 17:30“, „überfällig“, leer ohne Datum.
        public var detail: String
        public var priority: Int
        public var isFocus: Bool

        public init(id: String, title: String, detail: String, priority: Int, isFocus: Bool) {
            self.id = id
            self.title = title
            self.detail = detail
            self.priority = priority
            self.isFocus = isFocus
        }
    }

    public var writtenAt: Date
    public var nextUpTitle: String?
    public var nextUpTime: Date?
    public var nextUpSymbol: String?
    public var tasksOpen: Int
    public var tasksDone: Int
    public var dosesDone: Int
    public var dosesTotal: Int
    public var habitsDone: Int
    public var habitsTotal: Int
    /// Fokus zuerst, dann heute fällig. Höchstens 6.
    public var tasks: [TaskLine]
    /// „Lena wird 30 · in 7 Tagen“
    public var upcoming: String?

    public init(
        writtenAt: Date, nextUpTitle: String? = nil, nextUpTime: Date? = nil, nextUpSymbol: String? = nil,
        tasksOpen: Int = 0, tasksDone: Int = 0, dosesDone: Int = 0, dosesTotal: Int = 0,
        habitsDone: Int = 0, habitsTotal: Int = 0, tasks: [TaskLine] = [], upcoming: String? = nil
    ) {
        self.writtenAt = writtenAt
        self.nextUpTitle = nextUpTitle
        self.nextUpTime = nextUpTime
        self.nextUpSymbol = nextUpSymbol
        self.tasksOpen = tasksOpen
        self.tasksDone = tasksDone
        self.dosesDone = dosesDone
        self.dosesTotal = dosesTotal
        self.habitsDone = habitsDone
        self.habitsTotal = habitsTotal
        self.tasks = Array(tasks.prefix(6))
        self.upcoming = upcoming
    }

    /// Aufgabe sofort im Widget abhaken (bevor die App sie übernimmt).
    public func completing(taskID: String) -> TodayWidgetSnapshot {
        guard tasks.contains(where: { $0.id == taskID }) else { return self }
        var copy = self
        copy.tasks.removeAll { $0.id == taskID }
        copy.tasksOpen = max(0, tasksOpen - 1)
        copy.tasksDone += 1
        return copy
    }

    public func encoded() throws -> Data {
        try SharedCoding.encoder.encode(self)
    }

    public static func decode(_ data: Data?) -> TodayWidgetSnapshot? {
        guard let data else { return nil }
        return try? SharedCoding.decoder.decode(TodayWidgetSnapshot.self, from: data)
    }

    /// Beispiel für die Widget-Galerie.
    public static func placeholder(now: Date) -> TodayWidgetSnapshot {
        TodayWidgetSnapshot(
            writtenAt: now, nextUpTitle: "DAO-Enzym", nextUpTime: now.addingTimeInterval(1_800), nextUpSymbol: "pills.fill",
            tasksOpen: 3, tasksDone: 2, dosesDone: 1, dosesTotal: 3, habitsDone: 1, habitsTotal: 2,
            tasks: [
                TaskLine(id: "1", title: "Rezept abholen", detail: "heute 17:30", priority: 2, isFocus: true),
                TaskLine(id: "2", title: "Steuerunterlagen sortieren", detail: "heute", priority: 0, isFocus: true),
                TaskLine(id: "3", title: "Bad putzen", detail: "heute", priority: 0, isFocus: false),
            ],
            upcoming: "Lena wird 30 · in 7 Tagen"
        )
    }
}

/// Aufgaben, die im Widget abgehakt wurden, bis die App sie übernimmt.
public enum PendingTaskQueue {
    public static func appending(_ taskID: String, to data: Data?) -> Data? {
        var ids = decode(data)
        if !ids.contains(taskID) { ids.append(taskID) }
        return try? JSONEncoder().encode(ids)
    }

    public static func decode(_ data: Data?) -> [String] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}
