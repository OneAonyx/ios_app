import Foundation
import Testing
@testable import TagwerkCore

@Suite("Listen, Sortierung und Fortschritt")
struct SmartListTests {
    private let now = date(2026, 10, 26, 15) // Montag

    @Test func todayIncludesOverdueDueAndFocus() {
        let overdue = TaskFacts(dueDate: date(2026, 10, 24))
        let dueToday = TaskFacts(dueDate: date(2026, 10, 26, 18), hasDueTime: true)
        let tomorrow = TaskFacts(dueDate: date(2026, 10, 27))
        let focusWithoutDate = TaskFacts(focusDate: date(2026, 10, 26, 7))
        let focusYesterday = TaskFacts(focusDate: date(2026, 10, 25))
        let doneToday = TaskFacts(dueDate: date(2026, 10, 26), isDone: true, completedAt: now)

        let today = SmartList.today
        #expect(today.includes(overdue, now: now, calendar: berlin))
        #expect(today.includes(dueToday, now: now, calendar: berlin))
        #expect(!today.includes(tomorrow, now: now, calendar: berlin))
        #expect(today.includes(focusWithoutDate, now: now, calendar: berlin))
        #expect(!today.includes(focusYesterday, now: now, calendar: berlin))
        #expect(!today.includes(doneToday, now: now, calendar: berlin))
    }

    @Test func otherLists() {
        let inbox = TaskFacts()
        let inList = TaskFacts(listID: "arbeit")
        let planned = TaskFacts(dueDate: date(2026, 11, 3))
        let flagged = TaskFacts(isFlagged: true, listID: "arbeit")
        let done = TaskFacts(isDone: true, completedAt: now)

        #expect(SmartList.inbox.includes(inbox, now: now, calendar: berlin))
        #expect(!SmartList.inbox.includes(inList, now: now, calendar: berlin))
        #expect(!SmartList.inbox.includes(planned, now: now, calendar: berlin))
        #expect(SmartList.planned.includes(planned, now: now, calendar: berlin))
        #expect(SmartList.flagged.includes(flagged, now: now, calendar: berlin))
        #expect(SmartList.done.includes(done, now: now, calendar: berlin))
        #expect(!SmartList.all.includes(done, now: now, calendar: berlin))
        #expect(SmartList.allCases.map(\.title) == ["Heute", "Geplant", "Eingang", "Markiert", "Alle offenen", "Erledigt"])
    }

    @Test func ordering() {
        let items: [(String, TaskFacts)] = [
            ("ohne Datum, hoch", TaskFacts(priority: 3)),
            ("morgen", TaskFacts(dueDate: date(2026, 10, 27))),
            ("heute 18 Uhr", TaskFacts(dueDate: date(2026, 10, 26, 18), hasDueTime: true)),
            ("heute ganztägig", TaskFacts(dueDate: date(2026, 10, 26))),
            ("überfällig", TaskFacts(dueDate: date(2026, 10, 20))),
            ("heute 16 Uhr", TaskFacts(dueDate: date(2026, 10, 26, 16), hasDueTime: true)),
            ("ohne Datum, keine", TaskFacts(priority: 0)),
            ("erledigt früh", TaskFacts(isDone: true, completedAt: date(2026, 10, 26, 8))),
            ("erledigt spät", TaskFacts(isDone: true, completedAt: date(2026, 10, 26, 12))),
        ]
        let sorted = TaskOrdering.sorted(items, facts: { $0.1 }, now: now, calendar: berlin).map(\.0)
        #expect(sorted == [
            "überfällig", "heute ganztägig", "heute 16 Uhr", "heute 18 Uhr", "morgen",
            "ohne Datum, hoch", "ohne Datum, keine", "erledigt spät", "erledigt früh",
        ])
    }

    @Test func overdueWithTimeCountsFirst() {
        let pastTime = TaskFacts(dueDate: date(2026, 10, 26, 9), hasDueTime: true)
        let allDayToday = TaskFacts(dueDate: date(2026, 10, 26))
        #expect(TaskOrdering.areInIncreasingOrder(pastTime, allDayToday, now: now, calendar: berlin))
    }

    @Test func progress() {
        let tasks = [
            TaskFacts(dueDate: date(2026, 10, 26)),                                    // offen heute
            TaskFacts(dueDate: date(2026, 10, 25)),                                    // überfällig → offen
            TaskFacts(dueDate: date(2026, 10, 26), isDone: true, completedAt: now),    // erledigt
            TaskFacts(isDone: true, completedAt: now, focusDate: now),                 // Fokus erledigt
            TaskFacts(dueDate: date(2026, 11, 5), isDone: true, completedAt: now),     // vorgezogen, zählt nicht
            TaskFacts(dueDate: date(2026, 10, 27)),                                    // morgen, zählt nicht
        ]
        let progress = TodayProgress.compute(tasks, now: now, calendar: berlin)
        #expect(progress == TodayProgress(done: 2, open: 2))
        #expect(progress.fraction == 0.5)
        #expect(TodayProgress(done: 0, open: 0).fraction == 0)
        #expect(FocusRules.canAddFocus(currentCount: 2))
        #expect(!FocusRules.canAddFocus(currentCount: 3))
    }
}

@Suite("Agenda")
struct AgendaTests {
    private let now = date(2026, 10, 26, 15)

    private func event(_ id: String, _ start: Date, _ end: Date, allDay: Bool = false) -> AgendaItem {
        AgendaItem(id: id, kind: .event, title: id, start: start, end: end, isAllDay: allDay)
    }

    private func task(_ id: String, _ due: Date, timed: Bool = false, done: Bool = false) -> AgendaItem {
        AgendaItem(id: id, kind: .task, title: id, start: due, isAllDay: !timed, isDone: done)
    }

    @Test func distributesItemsOverDays() {
        let items = [
            event("Zahnarzt", date(2026, 10, 26, 10), date(2026, 10, 26, 11)),
            event("Urlaub", date(2026, 10, 27), date(2026, 10, 28, 23, 59), allDay: true),
            task("Steuer", date(2026, 10, 27)),
            task("Anruf", date(2026, 10, 26, 17), timed: true),
            task("Alt", date(2026, 10, 20)),
            task("Alt erledigt", date(2026, 10, 20), done: true),
        ]
        let days = AgendaBuilder.build(items: items, from: now, days: 3, now: now, calendar: berlin)
        #expect(days.count == 3)
        #expect(days[0].date == date(2026, 10, 26))
        #expect(days[0].allDay.map(\.title) == ["Alt"])
        #expect(days[0].allDay.first?.isOverdue == true)
        #expect(days[0].timed.map(\.title) == ["Zahnarzt", "Anruf"])
        #expect(days[1].allDay.map(\.title) == ["Urlaub", "Steuer"])
        #expect(days[2].allDay.map(\.title) == ["Urlaub"])
        #expect(days[2].timed.isEmpty)
    }

    @Test func multiDayTimedEventAndMidnightEnd() {
        let items = [
            event("Konferenz", date(2026, 10, 26, 9), date(2026, 10, 27, 17)),
            event("Spätschicht", date(2026, 10, 26, 22), date(2026, 10, 27, 0)),
        ]
        let days = AgendaBuilder.build(items: items, from: now, days: 2, now: now, calendar: berlin)
        #expect(days[0].timed.map(\.title) == ["Konferenz", "Spätschicht"])
        // Am zweiten Tag läuft die Konferenz weiter (ganztägig angezeigt), die Schicht nicht.
        #expect(days[1].allDay.map(\.title) == ["Konferenz"])
        #expect(days[1].timed.isEmpty)
    }

    @Test func weekViewWithoutOverdue() {
        let monday = AgendaBuilder.startOfWeek(containing: date(2026, 10, 29), calendar: berlin)
        #expect(monday == date(2026, 10, 26))
        #expect(AgendaBuilder.startOfWeek(containing: date(2026, 11, 1, 20), calendar: berlin) == date(2026, 10, 26))
        let days = AgendaBuilder.build(
            items: [task("Alt", date(2026, 10, 20))],
            from: date(2026, 11, 2), days: 7, now: now, calendar: berlin
        )
        let allEmpty = days.allSatisfy { $0.isEmpty }
        #expect(allEmpty)
    }

    @Test func nextUp() {
        let items = [
            event("Vorbei", date(2026, 10, 26, 9), date(2026, 10, 26, 10)),
            event("Läuft", date(2026, 10, 26, 14, 30), date(2026, 10, 26, 15, 30)),
            task("Später", date(2026, 10, 26, 18), timed: true),
            task("Ganztägig", date(2026, 10, 26)),
        ]
        #expect(AgendaBuilder.nextUp(in: items, now: now, calendar: berlin)?.title == "Läuft")
        #expect(AgendaBuilder.nextUp(in: Array(items.dropFirst(2)), now: now, calendar: berlin)?.title == "Später")
    }
}

@Suite("Backup")
struct BackupTests {
    private func sampleDocument() -> BackupDocument {
        BackupDocument(
            createdAt: date(2026, 10, 26, 18, 17),
            appVersion: "0.2.0",
            lists: [TaskListRecord(stableID: "L1", name: "Arbeit", symbol: "briefcase", colorName: "blue", sortIndex: 1, createdAt: date(2026, 10, 1))],
            tasks: [
                TaskRecord(
                    stableID: "T1", title: "Steuer", notes: "Belege sammeln",
                    dueDate: date(2026, 10, 30), priority: 2, createdAt: date(2026, 10, 20),
                    recurrence: RecurrenceRule(frequency: .yearly), reminderOffsets: [0, 1_440],
                    listID: "L1", tags: ["Finanzen"],
                    subtasks: [SubtaskRecord(stableID: "S1", title: "Belege", isDone: true, sortIndex: 0)]
                ),
            ],
            settings: ["userName": "Max"]
        )
    }

    @Test func roundTrip() throws {
        let document = sampleDocument()
        let data = try BackupCodec.encode(document)
        #expect(try BackupCodec.decode(data) == document)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"format\" : \"tagwerk.backup.v1\""))
    }

    @Test func rejectsForeignAndFutureFiles() {
        #expect(throws: BackupError.notATagwerkBackup) {
            try BackupCodec.decode(Data("{\"hallo\": 1}".utf8))
        }
        #expect(throws: BackupError.notATagwerkBackup) {
            try BackupCodec.decode(Data("kein json".utf8))
        }
        #expect(throws: BackupError.unsupportedVersion("tagwerk.backup.v9")) {
            try BackupCodec.decode(Data("{\"format\": \"tagwerk.backup.v9\"}".utf8))
        }
        #expect(throws: BackupError.unreadable) {
            try BackupCodec.decode(Data("{\"format\": \"tagwerk.backup.v1\"}".utf8))
        }
    }

    @Test func fileNamesAndRetention() {
        #expect(BackupCodec.fileName(for: date(2026, 10, 26, 18, 7), calendar: berlin) == "Tagwerk-Backup-2026-10-26_18-07.json")
        let names = (1...16).map { String(format: "Tagwerk-Backup-2026-10-%02d_09-00.json", $0) } + ["Notizen.txt"]
        let toDelete = BackupRetention.filesToDelete(names, keep: 14)
        #expect(toDelete == ["Tagwerk-Backup-2026-10-02_09-00.json", "Tagwerk-Backup-2026-10-01_09-00.json"])
        #expect(BackupRetention.isAutomaticBackupDue(lastBackup: nil, now: date(2026, 10, 26)))
        #expect(!BackupRetention.isAutomaticBackupDue(lastBackup: date(2026, 10, 26, 8), now: date(2026, 10, 26, 18)))
        #expect(BackupRetention.isAutomaticBackupDue(lastBackup: date(2026, 10, 25, 8), now: date(2026, 10, 26, 18)))
    }
}

@Suite("Erinnerungsplanung")
struct ReminderPlannerTests {
    private let now = date(2026, 10, 26, 15)

    @Test func respectsWindowLimitAndPriority() {
        var candidates = (1...80).map { hour in
            ReminderCandidate(id: "t\(hour)", kind: .task, fireDate: now.addingTimeInterval(Double(hour) * 600), title: "A", body: "", referenceID: "x")
        }
        candidates.append(ReminderCandidate(id: "med", kind: .medication, fireDate: now.addingTimeInterval(70 * 3_600), title: "M", body: "", referenceID: "m"))
        candidates.append(ReminderCandidate(id: "past", kind: .task, fireDate: now.addingTimeInterval(-60), title: "P", body: "", referenceID: "p"))
        candidates.append(ReminderCandidate(id: "far", kind: .medication, fireDate: now.addingTimeInterval(100 * 3_600), title: "F", body: "", referenceID: "f"))

        let plan = ReminderPlanner.plan(candidates, now: now, limit: 60)
        #expect(plan.count == 60)
        #expect(plan.contains { $0.id == "med" })          // Medikament hat Vorrang
        #expect(!plan.contains { $0.id == "past" })        // Vergangenes fällt weg
        #expect(!plan.contains { $0.id == "far" })         // außerhalb des Zeitfensters
        #expect(plan.first?.id == "t1")
        #expect(plan == plan.sorted { $0.fireDate < $1.fireDate })
    }

    @Test func taskReminderTimes() {
        let timed = TaskReminders.candidates(taskID: "T", title: "Zahnarzt", dueDate: date(2026, 10, 27, 10), hasDueTime: true, offsets: [15, 0, 15], calendar: berlin)
        #expect(timed.map(\.fireDate) == [date(2026, 10, 27, 10), date(2026, 10, 27, 9, 45)])
        #expect(timed.first?.body == "Fällig um 10:00")
        #expect(timed.map(\.id) == ["task.T.0", "task.T.15"])

        let allDay = TaskReminders.candidates(taskID: "U", title: "Steuer", dueDate: date(2026, 10, 30), hasDueTime: false, offsets: [0, 1_440], calendar: berlin)
        #expect(allDay.map(\.fireDate) == [date(2026, 10, 30, 9), date(2026, 10, 29, 9)])
        #expect(allDay.map(\.body) == ["Heute fällig", "Morgen fällig"])
        #expect(TaskReminders.label(forOffset: 60) == "1 Std. vorher")
    }
}
