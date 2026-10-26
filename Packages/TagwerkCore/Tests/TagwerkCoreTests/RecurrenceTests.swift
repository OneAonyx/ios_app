import Foundation
import Testing
@testable import TagwerkCore

@Suite("Wiederholungsregeln")
struct RecurrenceTests {
    @Test func dailyAndInterval() {
        #expect(RecurrenceRule.daily.nextOccurrence(after: date(2026, 10, 26, 10), calendar: berlin) == date(2026, 10, 27, 10))
        let everyThree = RecurrenceRule(frequency: .daily, interval: 3)
        #expect(everyThree.nextOccurrence(after: date(2026, 10, 26, 10), calendar: berlin) == date(2026, 10, 29, 10))
    }

    @Test func keepsWallClockTimeAcrossDaylightSavingChange() throws {
        // In der Nacht zum 25.10.2026 endet die Sommerzeit.
        let next = try #require(RecurrenceRule.daily.nextOccurrence(after: date(2026, 10, 24, 9), calendar: berlin))
        #expect(parts(next).d == 25)
        #expect(parts(next).h == 9)
        // Und zurück in die Sommerzeit (29.03.2026).
        let spring = try #require(RecurrenceRule.daily.nextOccurrence(after: date(2026, 3, 28, 8, 30), calendar: berlin))
        #expect(parts(spring).h == 8)
        #expect(parts(spring).min == 30)
    }

    @Test func weeklyWithoutWeekdays() {
        #expect(RecurrenceRule.weekly.nextOccurrence(after: date(2026, 10, 26, 18), calendar: berlin) == date(2026, 11, 2, 18))
        #expect(RecurrenceRule.biweekly.nextOccurrence(after: date(2026, 10, 26), calendar: berlin) == date(2026, 11, 9))
    }

    @Test func weeklyOnSeveralWeekdays() {
        let monWed = RecurrenceRule(frequency: .weekly, weekdays: [4, 2]) // Mi, Mo (unsortiert)
        #expect(monWed.weekdays == [2, 4])
        #expect(monWed.nextOccurrence(after: date(2026, 10, 26), calendar: berlin) == date(2026, 10, 28)) // Mo → Mi
        #expect(monWed.nextOccurrence(after: date(2026, 10, 28), calendar: berlin) == date(2026, 11, 2)) // Mi → Mo

        let biweeklyMonWed = RecurrenceRule(frequency: .weekly, interval: 2, weekdays: [2, 4])
        #expect(biweeklyMonWed.nextOccurrence(after: date(2026, 10, 26), calendar: berlin) == date(2026, 10, 28))
        #expect(biweeklyMonWed.nextOccurrence(after: date(2026, 10, 28), calendar: berlin) == date(2026, 11, 9))
    }

    @Test func sundayIsEndOfGermanWeek() {
        let sunday = RecurrenceRule(frequency: .weekly, weekdays: [1, 2]) // So und Mo
        #expect(sunday.nextOccurrence(after: date(2026, 10, 26), calendar: berlin) == date(2026, 11, 1)) // Mo → So
        #expect(sunday.nextOccurrence(after: date(2026, 11, 1), calendar: berlin) == date(2026, 11, 2)) // So → Mo
    }

    @Test func workdaysSkipWeekend() {
        #expect(RecurrenceRule.workdays.nextOccurrence(after: date(2026, 10, 30, 7), calendar: berlin) == date(2026, 11, 2, 7))
        #expect(RecurrenceRule.workdays.isWorkdays)
    }

    @Test func monthlyKeepsDayOfMonth() {
        let monthly31 = RecurrenceRule(frequency: .monthly, monthDay: 31)
        #expect(monthly31.nextOccurrence(after: date(2026, 1, 31), calendar: berlin) == date(2026, 2, 28))
        #expect(monthly31.nextOccurrence(after: date(2026, 2, 28), calendar: berlin) == date(2026, 3, 31))
        #expect(RecurrenceRule.monthly.nextOccurrence(after: date(2026, 10, 15, 12), calendar: berlin) == date(2026, 11, 15, 12))
        let quarterly = RecurrenceRule(frequency: .monthly, interval: 3)
        #expect(quarterly.nextOccurrence(after: date(2026, 11, 30), calendar: berlin) == date(2027, 2, 28))
    }

    @Test func yearlyOnLeapDay() {
        #expect(RecurrenceRule.yearly.nextOccurrence(after: date(2028, 2, 29), calendar: berlin) == date(2029, 2, 28))
    }

    @Test func afterCompletionCountsFromCompletionDay() {
        let rule = RecurrenceRule(frequency: .daily, interval: 3, mode: .afterCompletion)
        let next = rule.nextOccurrence(after: date(2026, 10, 20, 18), completedAt: date(2026, 10, 26, 8), calendar: berlin)
        #expect(next == date(2026, 10, 29, 18))
        // Ohne Erledigungsdatum zählt die Fälligkeit.
        #expect(rule.nextOccurrence(after: date(2026, 10, 20, 18), calendar: berlin) == date(2026, 10, 23, 18))
    }

    @Test func endDateStopsSeries() {
        let rule = RecurrenceRule(frequency: .daily, endDate: date(2026, 10, 27))
        #expect(rule.nextOccurrence(after: date(2026, 10, 26, 9), calendar: berlin) == date(2026, 10, 27, 9))
        #expect(rule.nextOccurrence(after: date(2026, 10, 27, 9), calendar: berlin) == nil)
        #expect(rule.occurrences(startingAt: date(2026, 10, 25, 9), count: 10, calendar: berlin).count == 3)
    }

    @Test func intervalIsAtLeastOne() {
        #expect(RecurrenceRule(frequency: .daily, interval: 0).interval == 1)
    }

    @Test func summaries() {
        #expect(RecurrenceRule.daily.summary(calendar: berlin) == "Täglich")
        #expect(RecurrenceRule(frequency: .daily, interval: 2).summary(calendar: berlin) == "Alle 2 Tage")
        #expect(RecurrenceRule.workdays.summary(calendar: berlin) == "Werktags")
        #expect(RecurrenceRule.weekly.summary(calendar: berlin) == "Wöchentlich")
        #expect(RecurrenceRule(frequency: .weekly, weekdays: [1, 2, 4]).summary(calendar: berlin) == "Wöchentlich am Mo, Mi, So")
        #expect(RecurrenceRule(frequency: .weekly, interval: 2, weekdays: [3]).summary(calendar: berlin) == "Alle 2 Wochen am Di")
        #expect(RecurrenceRule(frequency: .monthly, monthDay: 15).summary(calendar: berlin) == "Monatlich am 15.")
        #expect(RecurrenceRule.yearly.summary(calendar: berlin) == "Jährlich")
        #expect(RecurrenceRule(frequency: .daily, interval: 3, mode: .afterCompletion).summary(calendar: berlin) == "3 Tage nach Erledigung")
        #expect(RecurrenceRule(frequency: .weekly, interval: 1, mode: .afterCompletion).summary(calendar: berlin) == "1 Woche nach Erledigung")
        #expect(RecurrenceRule(frequency: .daily, endDate: date(2026, 12, 31)).summary(calendar: berlin) == "Täglich bis 31.12.2026")
    }

    @Test func codableRoundTrip() throws {
        let rule = RecurrenceRule(frequency: .weekly, interval: 2, weekdays: [2, 6], mode: .fixed, endDate: date(2027, 1, 1))
        let data = try JSONEncoder().encode(rule)
        #expect(try JSONDecoder().decode(RecurrenceRule.self, from: data) == rule)
    }
}

@Suite("Fälligkeitstexte")
struct DueFormatterTests {
    private let now = date(2026, 10, 26, 15) // Montag

    @Test func relativeDays() {
        #expect(DueFormatter.dayLabel(for: date(2026, 10, 26, 9), now: now, calendar: berlin) == "Heute")
        #expect(DueFormatter.dayLabel(for: date(2026, 10, 27), now: now, calendar: berlin) == "Morgen")
        #expect(DueFormatter.dayLabel(for: date(2026, 10, 28), now: now, calendar: berlin) == "Übermorgen")
        #expect(DueFormatter.dayLabel(for: date(2026, 10, 25), now: now, calendar: berlin) == "Gestern")
    }

    @Test func absoluteDays() {
        #expect(DueFormatter.dayLabel(for: date(2026, 11, 2), now: now, calendar: berlin) == "Mo, 2. Nov.")
        #expect(DueFormatter.dayLabel(for: date(2026, 5, 1), now: now, calendar: berlin) == "Fr, 1. Mai")
        #expect(DueFormatter.dayLabel(for: date(2027, 3, 3), now: now, calendar: berlin) == "Mi, 3. März 2027")
    }

    @Test func withTime() {
        #expect(DueFormatter.label(due: date(2026, 10, 26, 9, 5), hasTime: true, now: now, calendar: berlin) == "Heute, 09:05")
        #expect(DueFormatter.label(due: date(2026, 10, 27), hasTime: false, now: now, calendar: berlin) == "Morgen")
    }

    @Test func overdueRules() {
        // Ganztägig heute: nicht überfällig. Mit Uhrzeit vorbei: überfällig.
        #expect(!DueFormatter.isOverdue(due: date(2026, 10, 26), hasTime: false, now: now, calendar: berlin))
        #expect(DueFormatter.isOverdue(due: date(2026, 10, 26, 10), hasTime: true, now: now, calendar: berlin))
        #expect(!DueFormatter.isOverdue(due: date(2026, 10, 26, 18), hasTime: true, now: now, calendar: berlin))
        #expect(DueFormatter.isOverdue(due: date(2026, 10, 25), hasTime: false, now: now, calendar: berlin))
    }
}
