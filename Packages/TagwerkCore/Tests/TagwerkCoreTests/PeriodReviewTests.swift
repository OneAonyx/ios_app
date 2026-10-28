import Foundation
import Testing
@testable import TagwerkCore

@Suite("Monats- und Jahresrückblick, Tabellen")
struct PeriodReviewTests {
    @Test("Zeiträume und Titel")
    func periods() {
        let (start, end) = ReviewPeriod.month.interval(containing: date(2026, 10, 28, 15), calendar: berlin)
        #expect(start == date(2026, 10, 1))
        #expect(end == date(2026, 11, 1))
        #expect(ReviewPeriod.month.label(start, calendar: berlin) == "Oktober 2026")
        #expect(ReviewPeriod.month.shifted(start, by: -1, calendar: berlin) == date(2026, 9, 1))
        let year = ReviewPeriod.year.interval(containing: date(2026, 3, 5), calendar: berlin)
        #expect(year.start == date(2026, 1, 1) && year.end == date(2027, 1, 1))
        #expect(ReviewPeriod.year.label(year.start, calendar: berlin) == "2026")
    }

    @Test("Laufender Monat wird je Woche fair verglichen")
    func partialMonthIsNormalized() {
        // 14 Tage mit 8 Einheiten (4 pro Woche) gegen 28 Tage mit 12 (3 pro Woche).
        let current = PeriodMetrics(days: 14, workouts: 8)
        let previous = PeriodMetrics(days: 28, workouts: 12)
        let review = PeriodReview.make(period: .month, start: date(2026, 10, 1), current: current, previous: previous, calendar: berlin)
        let line = review.lines.first { $0.id == "workouts" }
        #expect(line?.value == "8 Einheiten · 4 pro Woche")
        #expect(line?.direction == .better)
        #expect(line?.change == "+1 zum Vormonat")
        #expect(review.highlights.first?.hasPrefix("Öfter trainiert") == true)
    }

    @Test("Weniger Beschwerdetage ist besser, Gewicht ohne Wertung")
    func directions() {
        let current = PeriodMetrics(days: 30, symptomDays: 3, adherence: 0.97, weightStart: 82, weightEnd: 82.8)
        let previous = PeriodMetrics(days: 30, symptomDays: 9, adherence: 0.9)
        let review = PeriodReview.make(period: .month, start: date(2026, 10, 1), current: current, previous: previous, calendar: berlin)
        #expect(review.lines.first { $0.id == "symptoms" }?.direction == .better)
        #expect(review.lines.first { $0.id == "symptoms" }?.value == "an 3 von 30 Tagen")
        #expect(review.lines.first { $0.id == "adherence" }?.value == "97 %")
        let weight = review.lines.first { $0.id == "weight" }
        #expect(weight?.direction == PeriodReviewLine.Direction.none)
        #expect(weight?.change == "+0,8 kg im Monat")
        #expect(review.highlights.contains { $0.contains("Weniger Tage mit Beschwerden") })
        #expect(review.highlights.contains { $0.contains("zuverlässig") })
    }

    @Test("Ohne Daten leer, ohne Vorzeitraum ohne Vergleich")
    func emptyAndFirst() {
        let empty = PeriodReview.make(period: .year, start: date(2026, 1, 1), current: PeriodMetrics(days: 300), previous: nil, calendar: berlin)
        #expect(empty.isEmpty)
        let first = PeriodReview.make(period: .year, start: date(2026, 1, 1), current: PeriodMetrics(days: 300, workouts: 200), previous: nil, calendar: berlin)
        #expect(first.lines.first?.change == nil)
        #expect(first.lines.first?.direction == PeriodReviewLine.Direction.none)
    }

    @Test("Gleich bleibt gleich")
    func same() {
        let review = PeriodReview.make(period: .month, start: date(2026, 10, 1), current: PeriodMetrics(days: 31, workouts: 16), previous: PeriodMetrics(days: 31, workouts: 16), calendar: berlin)
        #expect(review.lines.first?.direction == .same)
        #expect(review.lines.first?.change == "wie im Vormonat")
    }

    @Test("CSV: Semikolon, Anführungszeichen, BOM, deutsches Format")
    func csv() {
        var table = CSVTable(name: "Mahlzeiten", header: ["Datum", "Lebensmittel", "Menge"])
        table.rows.append(["28.10.2026", "Reis; Huhn", CSVFormat.number(82.5)])
        table.rows.append(["29.10.2026", "„Quark\" mit \"Honig\"", CSVFormat.number(nil)])
        #expect(table.fileName == "Mahlzeiten.csv")
        #expect(table.text == "Datum;Lebensmittel;Menge\r\n28.10.2026;\"Reis; Huhn\";82,5\r\n29.10.2026;\"„Quark\"\" mit \"\"Honig\"\"\";\r\n")
        #expect(Array(table.data.prefix(3)) == [0xEF, 0xBB, 0xBF])
        #expect(CSVFormat.date(date(2026, 3, 5, 7, 45), calendar: berlin) == "05.03.2026")
        #expect(CSVFormat.time(date(2026, 3, 5, 7, 45), calendar: berlin) == "07:45")
        #expect(CSVFormat.fileDate(date(2026, 3, 5), calendar: berlin) == "2026-03-05")
        #expect(CSVFormat.number(80) == "80")
    }
}
