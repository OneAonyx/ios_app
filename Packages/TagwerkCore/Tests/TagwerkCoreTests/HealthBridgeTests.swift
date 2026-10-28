import Foundation
import Testing
@testable import TagwerkCore

@Suite("Apple Health über Kurzbefehle")
struct HealthBridgeTests {
    @Test func sanitizeKeepsPlausibleValues() {
        let raw = HealthValues(steps: 8_432, distanceKm: 6.14, flights: 7, sleepHours: 432, restingHeartRate: 0, weightKg: 1_200)
        let (values, rejected) = raw.sanitized()
        #expect(values.steps == 8_432 && values.distanceKm == 6.14 && values.flights == 7)
        #expect(values.sleepHours == 7.2, "Minuten werden zu Stunden")
        #expect(values.restingHeartRate == nil, "0 heißt nicht gemessen")
        #expect(values.weightKg == nil && rejected == ["Gewicht"])
        #expect(values.summary == "8.432 Schritte, 6,1 km, 7 Stockwerke, Schlaf 7,2 Std.")
        #expect(HealthValues().isEmpty && HealthValues().summary == "keine Werte")
        #expect(HealthValues(steps: -5).sanitized().rejected == ["Schritte"])
    }

    @Test func mergeKeepsMissingValues() {
        let day = berlin.startOfDay(for: date(2026, 10, 28))
        let morning = HealthDayFact(day: day).merging(HealthValues(steps: 1_200, sleepHours: 7))
        let evening = morning.merging(HealthValues(steps: 9_800, distanceKm: 7.1))
        #expect(evening.steps == 9_800 && evening.sleepHours == 7 && evening.distanceKm == 7.1)
        #expect(evening.stepsText == "9.800 Schritte")
    }

    @Test func summaryAveragesMeasuredDays() {
        let facts = [
            HealthDayFact(day: date(2026, 10, 20), steps: 8_000, distanceKm: 6, sleepHours: 7),
            HealthDayFact(day: date(2026, 10, 21), steps: 6_001, sleepHours: 8, restingHeartRate: 60),
            HealthDayFact(day: date(2026, 10, 22), steps: 0),
            HealthDayFact(day: date(2026, 9, 1), steps: 20_000),
        ]
        let summary = HealthSummary.compute(facts, from: date(2026, 10, 19), to: date(2026, 10, 26))
        #expect(summary.days == 3 && summary.stepDays == 2 && summary.averageSteps == 7_001)
        #expect(summary.averageSleepHours == 7.5 && summary.averageRestingHeartRate == 60 && summary.totalDistanceKm == 6)
        #expect(summary.stepsText == "Ø 7.001 Schritte am Tag (2 Tage gemessen)")
    }

    @Test func exportWithoutDuplicates() {
        let now = date(2026, 10, 28, 21, 30)
        let first = HealthExport.water(todayTotal: 1_500, marker: nil, now: now, calendar: berlin)
        #expect(first.milliliters == 1_500)
        let second = HealthExport.water(todayTotal: 1_750, marker: first.marker, now: now, calendar: berlin)
        #expect(second.milliliters == 250)
        let again = HealthExport.water(todayTotal: 1_750, marker: second.marker, now: now, calendar: berlin)
        #expect(again.milliliters == 0)
        let nextDay = HealthExport.water(todayTotal: 500, marker: again.marker, now: date(2026, 10, 29, 21), calendar: berlin)
        #expect(nextDay.milliliters == 500, "neuer Tag")

        let weights = [(date: date(2026, 10, 20), value: 82.0), (date: date(2026, 10, 27), value: 82.4)]
        #expect(HealthExport.weight(weights, lastExported: nil)?.value == 82.4)
        #expect(HealthExport.weight(weights, lastExported: date(2026, 10, 27)) == nil)
        #expect(HealthExport.weight([], lastExported: nil) == nil)

        // Marke aus den Einstellungen (Sekunden seit 1970): beim Umrechnen leicht kleiner, trotzdem kein zweiter Export.
        let odd = Date(timeIntervalSinceReferenceDate: 783_302_461.123_456_7)
        let restored = Date(timeIntervalSince1970: odd.timeIntervalSince1970 - 0.000_01)
        #expect(HealthExport.weight([(date: odd, value: 82.1)], lastExported: restored) == nil)
        #expect(HealthExport.weight([(date: odd.addingTimeInterval(1), value: 82.3)], lastExported: restored)?.value == 82.3)
    }

    @Test func shortcutURLAndTexts() {
        let url = HealthShortcut.runURL().absoluteString
        #expect(url.hasPrefix("shortcuts://x-callback-url/run-shortcut?name=Orbit%20Health"))
        #expect(url.contains("x-success=tagwerk%3A%2F%2Fhealthbridge%2Fsuccess"))
        let now = date(2026, 10, 28, 22)
        #expect(HealthShortcut.lastImportText(nil, now: now, calendar: berlin) == "noch nie")
        #expect(HealthShortcut.lastImportText(date(2026, 10, 28, 21, 50), now: now, calendar: berlin) == "vor 10 Min.")
        #expect(HealthShortcut.lastImportText(date(2026, 10, 28, 9, 5), now: now, calendar: berlin) == "heute 09:05")
        #expect(HealthShortcut.lastImportText(date(2026, 10, 27, 21, 30), now: now, calendar: berlin) == "gestern 21:30")
        #expect(GermanNumber.grouped(1_234_567) == "1.234.567" && GermanNumber.grouped(999) == "999")
    }

    @Test func stepsCountAsActivityInDiary() {
        let day = berlin.startOfDay(for: date(2026, 10, 28))
        let facts = DiaryDayFacts(day: day, steps: 7_400)
        #expect(facts.hasActivityInfo)
        #expect(DiaryCheck.items(facts)[2].detail == "7.400 Schritte")

        let base = DoctorReport.make(
            from: date(2026, 10, 27), to: date(2026, 10, 29), createdAt: date(2026, 10, 28, 22), name: "",
            medications: [], symptoms: [], findings: [], mealCount: 0, avoidedFoods: [], cautionFoods: [], loads: [], weights: [], checkIns: [], calendar: berlin
        )
        let report = base.withDiary(DiaryReportInput(
            activities: [ActivityFact(date: date(2026, 10, 28, 18), kind: .walking, minutes: 30, intensity: .light)],
            days: [DiaryDayFacts(day: date(2026, 10, 27), restDay: true)],
            health: [HealthDayFact(day: date(2026, 10, 27), steps: 3_100), HealthDayFact(day: date(2026, 10, 28), steps: 9_000)]
        ), calendar: berlin)
        #expect(report.diary[0].activities == ["Ruhetag", "3.100 Schritte"])
        #expect(report.diary[1].activities == ["18:00 Gehen 30 Min., leicht", "9.000 Schritte"])
        #expect(report.health.averageSteps == 6_050)
    }

    @Test func backupRoundTrip() throws {
        let backup = HealthBackup(days: [HealthDayRecord(stableID: "h", day: date(2026, 10, 1), steps: 9_000, distanceKm: 6.5, flights: nil, sleepHours: 7, restingHeartRate: nil, updatedAt: date(2026, 10, 1, 21))])
        let document = BackupDocument(createdAt: date(2026, 10, 2), appVersion: "0.9.0", lists: [], tasks: [], settings: [:], health: backup)
        #expect(try BackupCodec.decode(BackupCodec.encode(document)).health == backup)
    }
}
