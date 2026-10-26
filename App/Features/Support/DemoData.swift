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
        seedMedications(into: context, now: now, calendar: calendar)
        try? context.save()
    }

    /// Medikamente mit Verlauf der letzten Tage (für Einnahmetreue und Kalender).
    private static func seedMedications(into context: ModelContext, now: Date, calendar: Calendar) {
        let start = calendar.date(byAdding: .day, value: -20, to: calendar.startOfDay(for: now)) ?? now

        func medication(
            _ name: String, dosage: String, form: MedicationForm, schedule: MedicationSchedule,
            color: ListColor, symbol: String? = nil, timing: MealTiming = .none,
            style: ReminderStyle = .notification, stock: Double? = nil, sortIndex: Double
        ) -> Medication {
            let item = Medication(name: name, dosage: dosage, form: form, schedule: schedule, startDate: start, sortIndex: sortIndex, createdAt: start)
            item.colorName = color.rawValue
            if let symbol { item.symbol = symbol }
            item.timing = timing
            item.reminderStyle = style
            item.stock = stock
            context.insert(item)
            return item
        }

        let vitamin = medication("Vitamin D3", dosage: "1000 IE", form: .tablet, schedule: .daily([DoseTime(hour: 8)]), color: .orange, symbol: "sun.max.fill", stock: 54, sortIndex: 0)
        let dao = medication(
            "DAO-Enzym", dosage: "10.000 HDU", form: .capsule,
            schedule: .daily([DoseTime(hour: 7, minute: 45), DoseTime(hour: 12, minute: 15), DoseTime(hour: 18, minute: 45)]),
            color: .teal, timing: .beforeMeal, style: .alarm, stock: 38, sortIndex: 1
        )
        let cetirizin = medication("Cetirizin", dosage: "10 mg", form: .tablet, schedule: .daily([DoseTime(hour: 21)]), color: .purple, timing: .bedtime, stock: 4, sortIndex: 2)
        let ibuprofen = medication("Ibuprofen", dosage: "400 mg", form: .tablet, schedule: .asNeeded(maxPerDay: 3, minGapHours: 6), color: .red, stock: 18, sortIndex: 3)

        // Verlauf: meist genommen, ab und zu verpasst oder ausgelassen.
        for (medIndex, item) in [vitamin, dao, cetirizin].enumerated() {
            let doses = item.scheduledDoses(from: start, to: now, calendar: calendar)
            for (index, dose) in doses.enumerated() where dose.date < now.addingTimeInterval(-DoseTiming.lateAfter) {
                let pattern = (index + medIndex * 3) % 13
                if pattern == 4 { continue }
                let status: DoseStatus = pattern == 9 ? .skipped : .taken
                let log = DoseLog(scheduledAt: dose.date, takenAt: status == .taken ? dose.date.addingTimeInterval(Double(index % 4) * 240) : nil, status: status, amount: dose.amount, createdAt: dose.date)
                context.insert(log)
                log.medication = item
            }
        }
        let headache = DoseLog(scheduledAt: nil, takenAt: now.addingTimeInterval(-3 * 3_600), status: .taken, amount: 1, note: "Kopfschmerzen", createdAt: now.addingTimeInterval(-3 * 3_600))
        context.insert(headache)
        headache.medication = ibuprofen
    }
}
