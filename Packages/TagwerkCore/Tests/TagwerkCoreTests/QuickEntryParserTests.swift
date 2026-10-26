import Foundation
import Testing
@testable import TagwerkCore

@Suite("Schnellerfassung (deutscher Parser)")
struct QuickEntryParserTests {
    /// Montag, 26.10.2026, 15:00 Uhr in Berlin.
    private let now = date(2026, 10, 26, 15)
    private let parser = QuickEntryParser(calendar: berlin)

    private func parse(_ text: String) -> QuickEntry {
        parser.parse(text, now: now)
    }

    // MARK: Datum und Uhrzeit

    @Test func tomorrowWithTime() {
        let entry = parse("morgen 10 uhr zahnarzt")
        #expect(entry.title == "Zahnarzt")
        #expect(entry.dueDate == date(2026, 10, 27, 10))
        #expect(entry.hasTime)
        #expect(entry.chips == [.init(kind: .date, label: "Morgen"), .init(kind: .time, label: "10:00")])
    }

    @Test func timeFormats() {
        #expect(parse("Zahnarzt morgen um 10:30").dueDate == date(2026, 10, 27, 10, 30))
        #expect(parse("übermorgen 14h friseur").dueDate == date(2026, 10, 28, 14))
        #expect(parse("morgen 18.30 uhr kino").dueDate == date(2026, 10, 27, 18, 30))
        #expect(parse("morgen um 18.30 uhr kino").title == "Kino")
        #expect(parse("morgen um 7 laufen").dueDate == date(2026, 10, 27, 7))
        #expect(parse("morgen 9uhr x").dueDate == date(2026, 10, 27, 9))
    }

    @Test func timeWithoutDatePicksNextPossibleDay() {
        // 10 Uhr ist heute schon vorbei → morgen. 18 Uhr kommt noch → heute.
        #expect(parse("10 uhr meeting").dueDate == date(2026, 10, 27, 10))
        #expect(parse("18 uhr meeting").dueDate == date(2026, 10, 26, 18))
    }

    @Test func dayParts() {
        let evening = parse("heute abend joggen")
        #expect(evening.title == "Joggen")
        #expect(evening.dueDate == date(2026, 10, 26, 19))
        #expect(parse("morgen früh laufen").dueDate == date(2026, 10, 27, 8))
        #expect(parse("abends lesen").dueDate == date(2026, 10, 26, 19))
        #expect(parse("freitag nachmittag einkaufen").dueDate == date(2026, 10, 30, 15))
    }

    @Test func weekdays() {
        #expect(parse("am freitag steuer").dueDate == date(2026, 10, 30))
        #expect(parse("am freitag steuer").title == "Steuer")
        #expect(!parse("am freitag steuer").hasTime)
        // Heute ist Montag: „montag“ = heute, „nächsten montag“ = in einer Woche.
        #expect(parse("montag wäsche").dueDate == date(2026, 10, 26))
        #expect(parse("nächsten montag wäsche").dueDate == date(2026, 11, 2))
        #expect(parse("naechsten mo wäsche").dueDate == date(2026, 11, 2))
        #expect(parse("bis donnerstag bericht").dueDate == date(2026, 10, 29))
        #expect(parse("Do. Arzt").dueDate == date(2026, 10, 29))
    }

    @Test func abbreviationsNeedContext() {
        // „so“ ist ein normales Wort und kein Sonntag.
        let entry = parse("so geht das")
        #expect(entry.title == "So geht das")
        #expect(entry.dueDate == nil)
        #expect(parse("am so grillen").dueDate == date(2026, 11, 1))
    }

    @Test func weekWords() {
        #expect(parse("nächste woche planung").dueDate == date(2026, 11, 2))
        #expect(parse("wochenende ausflug").dueDate == date(2026, 10, 31))
        #expect(parse("am wochenende ausflug").title == "Ausflug")
    }

    @Test func numericDates() {
        #expect(parse("24.12. geschenke kaufen").dueDate == date(2026, 12, 24))
        #expect(parse("24.12. geschenke kaufen").title == "Geschenke kaufen")
        // Schon vorbei in diesem Jahr → nächstes Jahr.
        #expect(parse("1.3. steuer").dueDate == date(2027, 3, 1))
        #expect(parse("24.12.2027 x").dueDate == date(2027, 12, 24))
        #expect(parse("5.1.27 x").dueDate == date(2027, 1, 5))
        #expect(parse("am 1. miete").dueDate == date(2026, 11, 1))
        // Ungültig bleibt Titel.
        #expect(parse("31.2. test").dueDate == nil)
    }

    @Test func relativeExpressions() {
        #expect(parse("in 2 stunden wäsche aufhängen").dueDate == date(2026, 10, 26, 17))
        #expect(parse("in 2 stunden wäsche aufhängen").hasTime)
        #expect(parse("in einer stunde anrufen").dueDate == date(2026, 10, 26, 16))
        #expect(parse("in 30 min tee").dueDate == date(2026, 10, 26, 15, 30))
        let days = parse("in 3 tagen rezept holen")
        #expect(days.dueDate == date(2026, 10, 29))
        #expect(!days.hasTime)
        #expect(days.title == "Rezept holen")
        #expect(parse("in zwei wochen zahnreinigung").dueDate == date(2026, 11, 9))
    }

    // MARK: Wiederholungen

    @Test func weeklyOnWeekday() {
        let entry = parse("jeden montag müll rausbringen")
        #expect(entry.title == "Müll rausbringen")
        #expect(entry.recurrence == RecurrenceRule(frequency: .weekly, weekdays: [2]))
        #expect(entry.dueDate == date(2026, 10, 26))
        #expect(entry.chips.contains(.init(kind: .recurrence, label: "Wöchentlich am Mo")))
    }

    @Test func severalWeekdays() {
        let entry = parse("jeden dienstag und donnerstag gym")
        #expect(entry.recurrence?.weekdays == [3, 5])
        #expect(entry.dueDate == date(2026, 10, 27))
        #expect(entry.title == "Gym")
        #expect(parse("mittwochs schwimmen").recurrence?.weekdays == [4])
        #expect(parse("mittwochs schwimmen").dueDate == date(2026, 10, 28))
    }

    @Test func dailyWithPastTimeStartsTomorrow() {
        let entry = parse("täglich 8 uhr tabletten")
        #expect(entry.recurrence == .daily)
        #expect(entry.dueDate == date(2026, 10, 27, 8))
        #expect(parse("taeglich wasser trinken").recurrence == .daily)
    }

    @Test func workdaysWithTime() {
        // 7:30 ist heute (Mo) vorbei → Dienstag.
        let entry = parse("werktags 7:30 stand-up")
        #expect(entry.recurrence == .workdays)
        #expect(entry.dueDate == date(2026, 10, 27, 7, 30))
        #expect(entry.title == "Stand-up")
    }

    @Test func intervals() {
        let entry = parse("alle 2 wochen bettwäsche wechseln")
        #expect(entry.recurrence == RecurrenceRule(frequency: .weekly, interval: 2))
        #expect(entry.dueDate == date(2026, 10, 26))
        #expect(parse("alle drei tage pflanzen gießen").recurrence?.interval == 3)
        #expect(parse("jedes jahr steuererklärung").recurrence == .yearly)
    }

    @Test func monthlyRemembersDayOfMonth() {
        let entry = parse("monatlich am 1. miete zahlen")
        #expect(entry.recurrence?.frequency == .monthly)
        #expect(entry.recurrence?.monthDay == 1)
        #expect(entry.dueDate == date(2026, 11, 1))
        #expect(entry.title == "Miete zahlen")
    }

    // MARK: Priorität, Liste, Titel

    @Test func priorityAndList() {
        let entry = parse("!!! steuererklärung #Arbeit")
        #expect(entry.priority == 3)
        #expect(entry.listName == "Arbeit")
        #expect(entry.title == "Steuererklärung")
        #expect(entry.chips == [.init(kind: .priority, label: "Priorität hoch"), .init(kind: .list, label: "Arbeit")])
    }

    @Test func plainTextStaysUntouched() {
        let entry = parse("2 Brötchen kaufen")
        #expect(entry.title == "2 Brötchen kaufen")
        #expect(entry.dueDate == nil)
        #expect(entry.recurrence == nil)
        #expect(entry.chips.isEmpty)
        #expect(parse("Um 25 Uhr").title == "Um 25 Uhr")
        #expect(parse("Morgenroutine planen").dueDate == nil)
        #expect(parse("").title == "")
    }

    @Test func titleIsCapitalized() {
        #expect(parse("zahnarzt anrufen").title == "Zahnarzt anrufen")
    }
}
