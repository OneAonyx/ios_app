import Foundation
import Testing
@testable import TagwerkCore

/// Dienstag, 27. Oktober 2026, 10 Uhr.
private let now = date(2026, 10, 27, 10)

private func days(_ list: [(Int, Int)], value: Double = 1, steps: Set<String> = []) -> [Date: HabitDay] {
    var result: [Date: HabitDay] = [:]
    for (month, day) in list {
        let start = berlin.startOfDay(for: date(2026, month, day))
        result[start] = HabitDay(day: start, value: value, doneSteps: steps)
    }
    return result
}

@Suite("Leben: Routinen und Gewohnheiten")
struct HabitTests {
    @Test func scheduleSummaryAndDueDays() {
        #expect(HabitSchedule.daily.summary == "Täglich")
        #expect(HabitSchedule.weekdays([2, 3, 4, 5, 6]).summary == "Werktags")
        #expect(HabitSchedule.weekdays([6, 2, 4]).summary == "Mo, Mi, Fr")
        #expect(HabitSchedule.weekdays([1, 7]).summary == "Am Wochenende")
        #expect(HabitSchedule.times(3).summary == "3× pro Woche")
        #expect(HabitSchedule.weekdays([2, 4, 6]).isDue(on: now, calendar: berlin) == false)
        #expect(HabitSchedule.weekdays([3]).isDue(on: now, calendar: berlin))
        let decoded = HabitSchedule.decode(HabitSchedule.times(4).encoded())
        #expect(decoded == .times(4))
    }

    @Test func dailyStreakKeepsRunningWhileTodayIsOpen() {
        let fact = HabitFact(kind: .habit, schedule: .daily, target: 1, createdAt: date(2026, 10, 20, 8))
        let log = days([(10, 20), (10, 22), (10, 23), (10, 24), (10, 25), (10, 26)])
        let stats = HabitProgress.stats(fact, days: log, today: now, calendar: berlin)
        #expect(stats.current == 5)
        #expect(stats.best == 5)
        #expect(stats.streakText == "5 Tage in Folge")
        // 6 von 7 fälligen Tagen (heute zählt noch nicht).
        #expect(stats.rate == 6.0 / 7.0)

        var done = log
        done[berlin.startOfDay(for: now)] = HabitDay(day: berlin.startOfDay(for: now), value: 1)
        let after = HabitProgress.stats(fact, days: done, today: now, calendar: berlin)
        #expect(after.current == 6)
        #expect(after.best == 6)
    }

    @Test func weekdayStreakSkipsFreeDays() {
        let fact = HabitFact(kind: .habit, schedule: .weekdays([2, 4, 6]), createdAt: date(2026, 10, 12, 8))
        let log = days([(10, 14), (10, 16), (10, 19), (10, 21), (10, 23), (10, 26)])
        let stats = HabitProgress.stats(fact, days: log, today: now, calendar: berlin)
        #expect(stats.current == 6)
        #expect(stats.best == 6)
        // Diese Woche: Mo erledigt, Mi und Fr kommen noch.
        #expect(stats.thisWeek == 1)
        #expect(stats.weekTarget == 3)
    }

    @Test func timesPerWeekCountsWeeks() {
        let fact = HabitFact(kind: .habit, schedule: .times(3), createdAt: date(2026, 9, 28, 8))
        let log = days([
            (9, 28), (9, 30), (10, 2),
            (10, 5), (10, 6), (10, 8),
            (10, 13), (10, 15),
            (10, 19), (10, 21), (10, 24),
            (10, 26),
        ])
        let stats = HabitProgress.stats(fact, days: log, today: now, calendar: berlin)
        #expect(stats.unitIsWeeks)
        #expect(stats.current == 1)
        #expect(stats.best == 2)
        #expect(stats.thisWeek == 1)
        #expect(stats.weekTarget == 3)
        #expect(stats.streakText == "1 Woche geschafft")
    }

    @Test func routineNeedsAllSteps() {
        let steps = [RoutineStep(id: "a", title: "Wasser"), RoutineStep(id: "b", title: "Dehnen"), RoutineStep(id: "c", title: "Check-in")]
        let fact = HabitFact(kind: .routine, steps: steps, createdAt: now)
        let half = HabitDay(day: now, doneSteps: ["a", "b"])
        #expect(abs(fact.fraction(half) - 2.0 / 3.0) < 0.0001)
        #expect(!fact.isComplete(half))
        #expect(fact.isComplete(HabitDay(day: now, doneSteps: ["a", "b", "c"])))
        #expect(RoutineStep.decode(RoutineStep.encode(steps)) == steps)
    }

    @Test func habitWithAmountTarget() {
        let fact = HabitFact(kind: .habit, target: 20, createdAt: now)
        #expect(fact.fraction(HabitDay(day: now, value: 10)) == 0.5)
        #expect(fact.isComplete(HabitDay(day: now, value: 25)))
    }

    @Test func remindersSkipPassedTimesAndDoneDays() {
        let morning = HabitProgress.reminderCandidates(
            habitID: "h1", name: "Dehnen", kind: .habit, schedule: .daily, minuteOfDay: 8 * 60 + 30,
            completedToday: false, now: now, calendar: berlin
        )
        #expect(morning.count == 2)
        #expect(morning.first?.id == "habit.h1.20261028")
        let evening = HabitProgress.reminderCandidates(
            habitID: "h1", name: "Dehnen", kind: .habit, schedule: .daily, minuteOfDay: 20 * 60,
            completedToday: false, now: now, calendar: berlin
        )
        #expect(evening.count == 3)
        let done = HabitProgress.reminderCandidates(
            habitID: "h1", name: "Dehnen", kind: .habit, schedule: .daily, minuteOfDay: 20 * 60,
            completedToday: true, now: now, calendar: berlin
        )
        #expect(done.count == 2)
        #expect(done.allSatisfy { $0.kind == .habit })
    }
}

@Suite("Leben: Verträge, Abos und Fristen")
struct ContractTests {
    let gym = ContractFact(
        kind: .contract, name: "Fitnessstudio", cost: 29.99, billing: .monthly, startDate: date(2025, 11, 1),
        minimumTermMonths: 12, renewalMonths: 1, notice: NoticePeriod(value: 1, unit: .months), reminderDaysBefore: 21
    )

    @Test func costsAndTotals() {
        let insurance = ContractFact(kind: .insurance, name: "Haftpflicht", cost: 60, billing: .yearly)
        let cancelled = ContractFact(kind: .subscription, name: "Streaming", cost: 13.99, isCancelled: true)
        let once = ContractFact(kind: .contract, name: "Einmalig", cost: 100, billing: .once)
        #expect(ContractLogic.monthlyCost(insurance) == 5)
        let totals = ContractLogic.totals([gym, insurance, cancelled, once])
        #expect(abs(totals.monthly - 34.99) < 0.001)
        #expect(ContractLogic.euro(totals.monthly) == "34,99 €")
        #expect(ContractLogic.euro(5) == "5,00 €")
        #expect(ContractLogic.euro(totals.yearly) == "419,88 €")
    }

    @Test func missedNoticeMovesToNextPeriod() throws {
        // Mindestlaufzeit endet am 1.11., Frist dafür war der 1.10.: nächste Frist 1.11. für Ende 1.12.
        #expect(ContractLogic.termEnd(gym, now: now, calendar: berlin) == date(2026, 11, 1))
        #expect(ContractLogic.deadline(gym, now: now, calendar: berlin) == date(2026, 11, 1))
        #expect(ContractLogic.status(gym, now: now, calendar: berlin) == .dueSoon(date(2026, 11, 1)))
        #expect(ContractLogic.statusText(gym, now: now, calendar: berlin) == "kündbar bis 1. Nov.")
    }

    @Test func yearlyRenewalShowsNextYearsDeadline() {
        let old = ContractFact(
            kind: .contract, name: "Internet", cost: 39.99, startDate: date(2025, 1, 1), minimumTermMonths: 24, renewalMonths: 12,
            notice: NoticePeriod(value: 3, unit: .months)
        )
        #expect(ContractLogic.deadline(old, now: now, calendar: berlin) == date(2027, 10, 1))
        #expect(ContractLogic.status(old, now: now, calendar: berlin) == .running(deadline: date(2027, 10, 1)))
        #expect(ContractLogic.statusText(old, now: now, calendar: berlin) == "kündbar bis 1. Okt. 2027")
    }

    @Test func withoutRenewalAnytimeAfterTheTerm() {
        let contract = ContractFact(
            kind: .contract, name: "Handy", cost: 15, startDate: date(2024, 1, 1), minimumTermMonths: 12,
            notice: NoticePeriod(value: 1, unit: .months)
        )
        #expect(ContractLogic.status(contract, now: now, calendar: berlin) == .running(deadline: nil))
        #expect(ContractLogic.statusText(contract, now: now, calendar: berlin) == "jederzeit kündbar")
        #expect(ContractLogic.reminderCandidates(id: "c", fact: contract, now: now, calendar: berlin).isEmpty)
    }

    @Test func documentsExpire() {
        let id = ContractFact(kind: .document, name: "Personalausweis", endDate: date(2026, 12, 1), reminderDaysBefore: 60)
        #expect(ContractLogic.status(id, now: now, calendar: berlin) == .dueSoon(date(2026, 12, 1)))
        #expect(ContractLogic.statusText(id, now: now, calendar: berlin) == "läuft ab am 1. Dez.")
        let old = ContractFact(kind: .document, name: "Führerschein", endDate: date(2026, 9, 1))
        #expect(ContractLogic.status(old, now: now, calendar: berlin) == .expired(date(2026, 9, 1)))
        #expect(ContractLogic.statusText(old, now: now, calendar: berlin) == "abgelaufen am 1. Sept.")
        // 60 Tage vorher ist schon vorbei, also nur am Tag selbst.
        let reminders = ContractLogic.reminderCandidates(id: "d1", fact: id, now: now, calendar: berlin)
        #expect(reminders.map(\.title) == ["Personalausweis läuft heute ab"])
        #expect(reminders.first?.id == "life.d1.20261201")
    }

    @Test func gymReminderAndAgenda() throws {
        let reminders = ContractLogic.reminderCandidates(id: "g", fact: gym, now: now, calendar: berlin)
        #expect(reminders.map(\.title) == ["Heute letzter Tag zum Kündigen: Fitnessstudio"])
        #expect(reminders.first?.kind == .lifeDeadline)
        let item = try #require(ContractLogic.agendaItem(id: "g", fact: gym, from: now, to: date(2026, 11, 10), now: now, calendar: berlin))
        #expect(item.kind == .deadline)
        #expect(item.isAllDay)
        #expect(item.title == "Letzter Kündigungstag: Fitnessstudio")
        #expect(ContractLogic.agendaItem(id: "g", fact: gym, from: now, to: date(2026, 10, 30), now: now, calendar: berlin) == nil)
    }

    @Test func noticePeriodText() {
        #expect(NoticePeriod(value: 3, unit: .months).text == "3 Monate")
        #expect(NoticePeriod(value: 1, unit: .weeks).text == "1 Woche")
        #expect(NoticePeriod.none.text == "keine")
    }
}

@Suite("Leben: Geburtstage und Tagebuch")
struct BirthdayTests {
    let lena = BirthdayFact(name: "Lena", day: 3, month: 11, year: 1996, reminderDaysBefore: 3)

    @Test func nextOccurrenceAndAge() {
        #expect(BirthdayLogic.nextOccurrence(lena, now: now, calendar: berlin) == date(2026, 11, 3))
        #expect(BirthdayLogic.daysUntil(lena, now: now, calendar: berlin) == 7)
        #expect(BirthdayLogic.turningAge(lena, now: now, calendar: berlin) == 30)
        #expect(BirthdayLogic.whenText(lena, now: now, calendar: berlin) == "in 7 Tagen")
        #expect(BirthdayLogic.headline(lena, now: now, calendar: berlin) == "Lena wird 30")
        #expect(BirthdayLogic.dateText(lena) == "3. Nov. 1996")
    }

    @Test func todayCountsAndLeapDayFallsBack() {
        let max = BirthdayFact(name: "Max", day: 27, month: 10)
        #expect(BirthdayLogic.daysUntil(max, now: now, calendar: berlin) == 0)
        #expect(BirthdayLogic.whenText(max, now: now, calendar: berlin) == "heute")
        #expect(BirthdayLogic.headline(max, now: now, calendar: berlin) == "Max hat Geburtstag")
        let leap = BirthdayFact(name: "Ella", day: 29, month: 2, year: 2000)
        #expect(BirthdayLogic.nextOccurrence(leap, now: now, calendar: berlin) == date(2027, 2, 28))
        #expect(BirthdayLogic.turningAge(leap, now: now, calendar: berlin) == 27)
        let sorted = BirthdayLogic.upcoming([leap, lena, max], now: now, calendar: berlin)
        #expect(sorted.map(\.name) == ["Max", "Lena", "Ella"])
    }

    @Test func remindersBeforeAndOnTheDay() throws {
        let reminders = BirthdayLogic.reminderCandidates(id: "l", fact: lena, now: now, calendar: berlin)
        #expect(reminders.map(\.title) == ["Lena wird 30 in 3 Tagen", "Heute: Lena wird 30"])
        #expect(reminders.allSatisfy { $0.kind == .birthday })
        let max = BirthdayFact(name: "Max", day: 27, month: 10)
        // Heute 8 Uhr ist vorbei, 3 Tage vorher auch.
        #expect(BirthdayLogic.reminderCandidates(id: "m", fact: max, now: now, calendar: berlin).isEmpty)
        let item = try #require(BirthdayLogic.agendaItem(id: "l", fact: lena, from: now, to: date(2026, 11, 10), calendar: berlin))
        #expect(item.kind == .birthday)
        #expect(item.start == date(2026, 11, 3))
    }

    @Test func journalPromptIsStablePerDay() {
        let first = JournalPrompts.prompt(for: now, calendar: berlin)
        #expect(JournalPrompts.all.contains(first))
        #expect(JournalPrompts.prompt(for: now.addingTimeInterval(3_600), calendar: berlin) == first)
        #expect(JournalPrompts.prompt(for: date(2026, 10, 28, 10), calendar: berlin) != first)
    }

    @Test func templatesAreUsable() {
        #expect(LifeTemplates.chores.first { $0.title == "Bad putzen" }?.recurrence == RecurrenceRule(frequency: .daily, interval: 7, mode: .afterCompletion))
        #expect(LifeTemplates.habits.filter { $0.kind == .routine }.allSatisfy { !$0.steps.isEmpty })
        #expect(LifeTemplates.contracts.contains { $0.kind == .document && $0.name == "Personalausweis" })
    }

    @Test func lifeBackupRoundTrip() throws {
        let life = LifeBackup(
            habits: [HabitRecord(
                stableID: "h", kind: "routine", name: "Morgen", symbol: "sunrise.fill", colorName: "orange", period: "morning",
                schedule: .weekdays([2, 3]), target: 1, unit: "", steps: [RoutineStep(id: "s", title: "Wasser")],
                reminderMinute: 450, sortIndex: 1, isArchived: false, createdAt: date(2026, 10, 1)
            )],
            habitLogs: [HabitLogRecord(stableID: "l", habitID: "h", day: date(2026, 10, 26), value: 1, doneSteps: ["s"])],
            contracts: [ContractRecord(
                stableID: "c", kind: "contract", name: "Gym", provider: "", cost: 29.99, billing: "monthly", startDate: date(2025, 11, 1),
                endDate: nil, minimumTermMonths: 12, renewalMonths: 1, notice: NoticePeriod(value: 1, unit: .months),
                reminderDaysBefore: 21, note: "", isCancelled: false, createdAt: date(2026, 10, 1)
            )],
            birthdays: [BirthdayRecord(stableID: "b", name: "Lena", day: 3, month: 11, year: 1996, reminderDaysBefore: 3, note: "Buch")],
            journal: [JournalRecord(stableID: "j", day: date(2026, 10, 26), prompt: "Was lief gut?", answer: "Training", text: "", updatedAt: date(2026, 10, 26, 21))]
        )
        let document = BackupDocument(createdAt: now, appVersion: "0.7.0", lists: [], tasks: [], life: life)
        let decoded = try BackupCodec.decode(BackupCodec.encode(document))
        #expect(decoded.life == life)
    }

    @Test func remindersRankAboveTasks() {
        #expect(ReminderCandidate.Kind.lifeDeadline.rank > ReminderCandidate.Kind.habit.rank)
        #expect(ReminderCandidate.Kind.habit.rank > ReminderCandidate.Kind.task.rank)
        #expect(NotificationIDs.Prefix.managed.contains(NotificationIDs.Prefix.birthday))
    }
}

@Suite("Leben: Widget-Stand und Fokus-Filter")
struct TodaySnapshotTests {
    @Test func completingRemovesTaskAndCounts() throws {
        let snapshot = TodayWidgetSnapshot.placeholder(now: now)
        let done = snapshot.completing(taskID: "2")
        #expect(done.tasks.map(\.id) == ["1", "3"])
        #expect(done.tasksOpen == 2 && done.tasksDone == 3)
        #expect(done.completing(taskID: "x") == done)
        let decoded = try #require(TodayWidgetSnapshot.decode(try done.encoded()))
        #expect(decoded.tasks == done.tasks)
        #expect(PendingTaskQueue.decode(PendingTaskQueue.appending("a", to: PendingTaskQueue.appending("a", to: nil))) == ["a"])
    }

    @Test func focusFilterSummary() {
        #expect(FocusFilterState.none.isActive == false)
        #expect(FocusFilterState.none.summary == "alles sichtbar")
        let work = FocusFilterState(hideTraining: true, hideNutrition: true, listID: "l", listName: "Arbeit")
        #expect(work.isActive)
        #expect(work.summary == "Training und Ernährung ausgeblendet · nur Liste Arbeit")
    }
}
