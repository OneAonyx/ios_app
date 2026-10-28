import Foundation
import Testing
@testable import TagwerkCore

@Suite("Arzt-Tagebuch: Schmerzen")
struct PainTests {
    @Test func everyRegionIsOnTheMap() {
        for region in BodyRegion.allCases {
            #expect(!region.positions.isEmpty, "\(region) fehlt auf der Karte")
            for point in region.positions.values {
                #expect((0...1).contains(point.x) && (0...1).contains(point.y))
            }
        }
        #expect(BodyRegion.shoulderLeft.title == "Schulter links")
        #expect(BodyRegion.lowerBack.title == "Unterer Rücken")
        // Vorne liegt die linke Körperseite rechts im Bild, hinten links.
        let front = BodyRegion.kneeLeft.positions[.front]?.x ?? 0
        let backLeft = BodyRegion.calfLeft.positions[.back]?.x ?? 1
        #expect(front > 0.5 && backLeft < 0.5)
        #expect(BodyRegion.regions(on: .back).contains(.lowerBack))
        #expect(!BodyRegion.regions(on: .front).contains(.lowerBack))
    }

    @Test func scaleAndSummary() {
        #expect(PainScale.label(0) == "kein Schmerz")
        #expect(PainScale.label(6) == "mittel")
        #expect(PainScale.label(10) == "unerträglich")
        let fact = PainFact(date: date(2026, 10, 27, 9), regions: [.lowerBack], intensity: 14, qualities: [.stabbing], durationMinutes: 120)
        #expect(fact.intensity == 10, "auf 10 begrenzt")
        #expect(fact.summary == "Unterer Rücken 10/10, stechend, 2 Std.")
        #expect(DurationText.short(90) == "1,5 Std.")
        #expect(DurationText.short(45) == "45 Min.")
        #expect(DurationText.short(24 * 60) == "ganzer Tag")
    }

    @Test func summaryCountsRegionsWeeksAndActivity() {
        let facts = [
            PainFact(date: date(2026, 10, 5, 9), regions: [.lowerBack], intensity: 6, triggers: [.sitting], reliefs: [.heat]),
            PainFact(date: date(2026, 10, 6, 20), regions: [.lowerBack, .shoulderRight], intensity: 4, qualities: [.dull], triggers: [.training]),
            PainFact(date: date(2026, 10, 20, 8), regions: [.shoulderRight], intensity: 8, qualities: [.stabbing], triggers: [.training], reliefs: [.medication]),
            PainFact(date: date(2026, 9, 1), regions: [.head], intensity: 9),
        ]
        let gym = [ActivityFact(date: date(2026, 10, 19, 18), kind: .gym, minutes: 70, intensity: .vigorous)]
        let summary = PainSummary.compute(facts, activities: gym, from: date(2026, 10, 1), to: date(2026, 10, 28), calendar: berlin)
        #expect(summary.count == 3 && summary.days == 3)
        #expect(summary.maxIntensity == 8)
        #expect(summary.regions.map(\.region) == [.shoulderRight, .lowerBack], "gleich oft: stärkerer Schmerz zuerst")
        #expect(summary.regions.first?.maxIntensity == 8)
        #expect(summary.triggers.first?.0 == .training && summary.triggers.first?.1 == 2)
        #expect(summary.weeks.map(\.count) == [0, 2, 0, 1, 0])
        #expect(summary.afterActivity == 1, "Schmerz am Tag nach dem Gym")
    }
}

@Suite("Arzt-Tagebuch: Bewegung")
struct ActivityTests {
    @Test func weightedMinutesAndWeeks() {
        let facts = [
            ActivityFact(date: date(2026, 10, 19, 7), kind: .walking, minutes: 40, intensity: .light),
            ActivityFact(date: date(2026, 10, 20, 18), kind: .running, minutes: 30, intensity: .vigorous),
            ActivityFact(date: date(2026, 10, 22, 18), kind: .cycling, minutes: 45, intensity: .moderate),
            ActivityFact(date: date(2026, 10, 22, 19), kind: .gym, minutes: 60, intensity: .moderate),
        ]
        #expect(facts[0].weightedMinutes == 0 && facts[1].weightedMinutes == 60)
        #expect(!facts[0].isStrenuous && facts[1].isStrenuous && facts[3].isStrenuous)
        let weeks = ActivityStats.weeks(facts, from: date(2026, 10, 19), to: date(2026, 10, 26), calendar: berlin)
        #expect(weeks.count == 1)
        #expect(weeks[0].minutes == 175 && weeks[0].weightedMinutes == 165 && weeks[0].activeDays == 3 && weeks[0].sessions == 4)
        #expect(ActivityStats.byKind(facts).first?.kind == .gym)
        #expect(facts[1].summary == "Laufen 30 Min., intensiv")
        let factors = ActivityStats.dayFactors(facts)
        #expect(factors.count == 3)
        #expect(factors[0].contains(date(2026, 10, 20, 23)) && !factors[0].contains(date(2026, 10, 21, 2)))
        #expect(!ActivityKind.loggable.contains(.gym))
    }
}

@Suite("Arzt-Tagebuch: Tages-Check und Bericht")
struct DiaryCheckTests {
    @Test func itemsAndReminder() throws {
        let day = berlin.startOfDay(for: date(2026, 10, 27))
        var facts = DiaryDayFacts(day: day, meals: 2, dosesDue: 2, dosesResolved: 1)
        let items = DiaryCheck.items(facts)
        #expect(items.map(\.kind) == [.meals, .symptoms, .activity, .medications, .checkIn])
        #expect(items.map(\.isDone) == [true, false, false, false, false])
        #expect(items[3].detail == "1 von 2")

        let reminder = try #require(DiaryCheck.reminder(facts, minuteOfDay: 20 * 60, now: date(2026, 10, 27, 10), calendar: berlin))
        #expect(reminder.id == "diary.20261027" && reminder.kind == .diary)
        #expect(reminder.body.hasPrefix("Noch offen: Beschwerden, Bewegung"))

        facts.symptomFree = true
        facts.restDay = true
        #expect(DiaryCheck.items(facts)[1].detail == "keine")
        #expect(DiaryCheck.items(facts)[2].detail == "Ruhetag")
        #expect(DiaryCheck.reminder(facts, minuteOfDay: 20 * 60, now: date(2026, 10, 27, 10), calendar: berlin) == nil)
        #expect(DiaryCheck.reminder(DiaryDayFacts(day: day), minuteOfDay: -1, now: date(2026, 10, 27, 10), calendar: berlin) == nil)
        #expect(DiaryCheck.reminder(DiaryDayFacts(day: day), minuteOfDay: 9 * 60, now: date(2026, 10, 27, 10), calendar: berlin) == nil, "schon vorbei")
    }

    @Test func completeness() {
        let days = [
            DiaryDayFacts(day: date(2026, 10, 20), meals: 3, symptoms: 1),
            DiaryDayFacts(day: date(2026, 10, 21), meals: 2, symptomFree: true, gymSessions: 1),
            DiaryDayFacts(day: date(2026, 10, 22), meals: 0, pains: 1, restDay: true),
            DiaryDayFacts(day: date(2026, 10, 23)),
        ]
        let result = DiaryCompleteness.compute(days)
        #expect(result.days == 4 && result.withMeals == 2 && result.withSymptomInfo == 3 && result.withActivityInfo == 2)
        #expect(result.complete == 2 && result.symptomFreeDays == 1)
        #expect(result.summary == "Vollständig an 2 von 4 Tagen (50 %)")
    }

    @Test func reportGetsDiaryTableAndSummaries() {
        let base = DoctorReport.make(
            from: date(2026, 10, 20), to: date(2026, 10, 23), createdAt: date(2026, 10, 23, 12), name: "",
            medications: [],
            symptoms: [.init(date: date(2026, 10, 20, 14), type: .headache, severity: 3, durationMinutes: 120, note: "")],
            findings: [], mealCount: 3, avoidedFoods: [], cautionFoods: [], loads: [], weights: [], checkIns: [], calendar: berlin
        )
        let input = DiaryReportInput(
            pains: [PainFact(date: date(2026, 10, 20, 9), regions: [.lowerBack], intensity: 6, qualities: [.stabbing])],
            activities: [ActivityFact(date: date(2026, 10, 21, 18), kind: .gym, minutes: 70, intensity: .vigorous)],
            days: [
                DiaryDayFacts(day: date(2026, 10, 20), meals: 2, symptoms: 1, pains: 1, restDay: true),
                DiaryDayFacts(day: date(2026, 10, 21), meals: 1, symptomFree: true, gymSessions: 1),
                DiaryDayFacts(day: date(2026, 10, 22)),
            ],
            meals: [DiaryEvent(date: date(2026, 10, 20, 12, 30), text: "Reis, Hähnchen"), DiaryEvent(date: date(2026, 10, 20, 8), text: "Haferflocken")],
            medications: [
                DiaryEvent(date: date(2026, 10, 20, 18, 45), text: "DAO-Enzym"),
                DiaryEvent(date: date(2026, 10, 20, 11, 45), text: "DAO-Enzym"),
                DiaryEvent(date: date(2026, 10, 20, 8), text: "ausgelassen: Vitamin D"),
            ],
            checkIns: [CheckInFact(day: date(2026, 10, 21), sleepHours: 7.5, mood: 4, stress: 2)],
            questions: "  Ist das Histamin?  "
        )
        let report = base.withDiary(input, calendar: berlin)
        #expect(report.diary.count == 3)
        let first = report.diary[0]
        #expect(first.meals == ["08:00 Haferflocken", "12:30 Reis, Hähnchen"])
        #expect(first.complaints == ["09:00 Schmerz: Unterer Rücken 6/10, stechend", "14:00 Kopfschmerz 3/5, 2 Std."])
        #expect(first.medications == ["ausgelassen: Vitamin D: 08:00", "DAO-Enzym: 11:45, 18:45"])
        #expect(first.activities == ["Ruhetag"])
        #expect(report.diary[1].complaints == ["keine"])
        #expect(report.diary[1].activities == ["18:00 Gym 1 Std., intensiv"])
        #expect(report.diary[1].wellbeing == "Schlaf 7,5 Std. · Stimmung 4/5 · Stress 2/5")
        #expect(report.diary[1].wellbeingLines.count == 3)
        #expect(report.diary[2].isEmpty)
        #expect(report.painSummary.count == 1 && report.activityWeeks.count == 1)
        #expect(report.completeness.complete == 2)
        #expect(report.questions == "Ist das Histamin?")
        #expect(report.averageSleepHours == 7.5)
    }

    @Test func paginationKeepsRowsTogether() {
        let long = String(repeating: "x", count: 80)
        let rows = (0..<10).map { index in
            DiaryRow(day: date(2026, 10, 1 + index), meals: [long, "kurz"], complaints: [], medications: [], activities: [], wellbeing: nil)
        }
        #expect(DiaryPagination.lines(rows[0]) == 4)
        let pages = DiaryPagination.pages(rows, linesPerPage: 16)
        #expect(pages.map(\.count) == [3, 3, 3, 1])
    }

    @Test func backupRoundTrip() throws {
        let backup = DiaryBackup(
            pains: [PainRecord(stableID: "p", date: date(2026, 10, 1), regions: ["lowerBack"], intensity: 5, qualities: ["dull"], durationMinutes: nil, triggers: [], reliefs: ["heat"], note: "", createdAt: date(2026, 10, 1))],
            activities: [ActivityRecord(stableID: "a", date: date(2026, 10, 2), kind: "running", minutes: 30, intensity: 3, note: "", createdAt: date(2026, 10, 2))],
            days: [DiaryDayRecord(stableID: "d", day: date(2026, 10, 3), symptomFree: true, restDay: false)]
        )
        let document = BackupDocument(createdAt: date(2026, 10, 4), appVersion: "0.8.0", lists: [], tasks: [], settings: [:], diary: backup)
        let decoded = try BackupCodec.decode(BackupCodec.encode(document))
        #expect(decoded.diary == backup)
        #expect(ReminderCandidate.Kind.diary.rank > ReminderCandidate.Kind.habit.rank)
        #expect(NotificationIDs.Prefix.managed.contains(NotificationIDs.Prefix.diary))
    }
}
