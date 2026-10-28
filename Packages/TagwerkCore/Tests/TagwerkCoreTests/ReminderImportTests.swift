import Foundation
import Testing
@testable import TagwerkCore

@Suite("Import aus Apple Erinnerungen")
struct ReminderImportTests {
    @Test func mapsPriorityDueAndRecurrence() throws {
        #expect([0, 1, 4, 5, 6, 9].map(ReminderImport.priority) == [0, 3, 3, 2, 1, 1])
        let dayOnly = try #require(ReminderImport.dueDate(DateComponents(year: 2026, month: 11, day: 3), calendar: berlin))
        #expect(!dayOnly.hasTime && dayOnly.date == date(2026, 11, 3))
        let withTime = try #require(ReminderImport.dueDate(DateComponents(year: 2026, month: 11, day: 3, hour: 9, minute: 30), calendar: berlin))
        #expect(withTime.hasTime && withTime.date == date(2026, 11, 3, 9, 30))
        #expect(ReminderImport.dueDate(DateComponents(month: 11, day: 3), calendar: berlin) == nil)

        let weekly = ExternalReminder(id: "w", title: "Müll", listName: "Haushalt", frequency: .weekly, interval: 2, weekdays: [2])
        #expect(ReminderImport.recurrence(weekly) == RecurrenceRule(frequency: .weekly, interval: 2, weekdays: [2]))
        let daily = ExternalReminder(id: "d", title: "Wasser", listName: "Privat", frequency: .daily, weekdays: [2])
        #expect(ReminderImport.recurrence(daily)?.weekdays == [], "Wochentage nur bei wöchentlich")
    }

    @Test func planSkipsExistingEmptyAndCompleted() {
        let reminders = [
            ExternalReminder(id: "1", title: " Zahnarzt anrufen ", notes: "Praxis Dr. M.", listName: "Privat", due: DateComponents(year: 2026, month: 11, day: 2, hour: 10), priority: 1),
            ExternalReminder(id: "2", title: "Steuer", listName: "Arbeit"),
            ExternalReminder(id: "3", title: "Erledigt", listName: "Arbeit", isCompleted: true, completedAt: date(2026, 10, 1)),
            ExternalReminder(id: "4", title: "   ", listName: "Arbeit"),
        ]
        let plan = ReminderImport.plan(reminders, existingIDs: ["reminder-2"], includeCompleted: false, calendar: berlin)
        #expect(plan.map(\.stableID) == ["reminder-1"])
        #expect(plan[0].title == "Zahnarzt anrufen" && plan[0].priority == 3 && plan[0].hasDueTime && plan[0].notes == "Praxis Dr. M.")
        let withDone = ReminderImport.plan(reminders, existingIDs: [], includeCompleted: true, calendar: berlin)
        #expect(withDone.count == 3 && withDone[2].isDone && withDone[2].completedAt == date(2026, 10, 1))
        #expect(ReminderImport.summary(imported: 1, lists: 1, skipped: 2) == "1 neue Aufgabe aus 1 Liste, 2 schon vorhanden oder erledigt")
        #expect(ReminderImport.summary(imported: 5, lists: 2, skipped: 0) == "5 neue Aufgaben aus 2 Listen")
    }
}
