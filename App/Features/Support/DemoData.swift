import Foundation
import SwiftData
import TagwerkCore
import TagwerkKit

/// Beispieldaten nur für die UI-Tests im CI (Screenshots). Werden nie in echte Speicher geschrieben.
@MainActor
enum DemoData {
    static func seed(into context: ModelContext, now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int, _ hour: Int? = nil, _ minute: Int = 0) -> Date {
            let base = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            guard let hour else { return base }
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        }

        let personal = TaskList(name: "Persönlich", symbol: "person", colorName: ListColor.indigo.rawValue, sortIndex: 0)
        let home = TaskList(name: "Haushalt", symbol: "house", colorName: ListColor.teal.rawValue, sortIndex: 1)
        let work = TaskList(name: "Arbeit", symbol: "briefcase", colorName: ListColor.blue.rawValue, sortIndex: 2)
        for list in [personal, home, work] {
            context.insert(list)
        }

        var index = 0.0
        @discardableResult
        func task(
            _ title: String, due: Date? = nil, time: Bool = false, list: TaskList? = nil,
            priority: Int = 0, focus: Bool = false, flagged: Bool = false,
            recurrence: RecurrenceRule? = nil, doneAt: Date? = nil, reminders: [Int] = []
        ) -> TaskItem {
            index += 1
            let item = TaskItem(title: title, dueDate: due, hasDueTime: time, priority: priority, list: list, sortIndex: index, createdAt: now.addingTimeInterval(-index * 3_600))
            item.focusDate = focus ? today : nil
            item.isFlagged = flagged
            item.recurrence = recurrence
            item.reminderOffsets = reminders
            if let doneAt {
                item.isDone = true
                item.completedAt = doneAt
            }
            context.insert(item)
            return item
        }

        task("Rezept in der Apotheke abholen", due: day(0, 17, 30), time: true, list: personal, priority: 2, focus: true, reminders: [30])
        task("Steuerunterlagen sortieren", due: day(0), list: work, focus: true, flagged: true)
        task("Bettwäsche wechseln", due: day(-1), list: home, recurrence: RecurrenceRule(frequency: .weekly, mode: .afterCompletion))
        task("Müll rausbringen", due: day(0), list: home, recurrence: RecurrenceRule(frequency: .weekly, weekdays: [calendar.component(.weekday, from: now)]))
        task("Zahnarzt anrufen")
        let gift = task("Geschenk für Mama besorgen", due: day(3), list: personal)
        task("Präsentation vorbereiten", due: day(1, 10), time: true, list: work, priority: 3)
        task("Laufschuhe kaufen", due: day(0), list: personal, doneAt: now.addingTimeInterval(-7_200))
        task("Wasser trinken", due: day(0), recurrence: .daily, doneAt: now.addingTimeInterval(-3_600))
        task("Urlaub planen", due: day(9), list: personal)

        for (offset, title) in ["Ideen sammeln", "Laden auswählen"].enumerated() {
            let subtask = Subtask(title: title, isDone: offset == 0, sortIndex: Double(offset))
            context.insert(subtask)
            subtask.task = gift
        }
        try? context.save()
    }
}
