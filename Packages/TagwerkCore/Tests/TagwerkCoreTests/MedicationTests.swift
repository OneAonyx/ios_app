import Foundation
import Testing
@testable import TagwerkCore

/// Stunden und Minuten der Einnahmen in Berliner Ortszeit, z. B. „26 08:00“.
private func labels(_ doses: [ScheduledDose]) -> [String] {
    doses.map { dose in
        let p = parts(dose.date)
        return String(format: "%02d %02d:%02d", p.d, p.h, p.min)
    }
}

private func doses(
    _ schedule: MedicationSchedule,
    start: Date = date(2026, 10, 20),
    end: Date? = nil,
    trackFrom: Date? = nil,
    from: Date,
    to: Date
) -> [ScheduledDose] {
    DoseCalculator.doses(
        medicationID: "med", schedule: schedule, startDate: start, endDate: end,
        trackFrom: trackFrom, from: from, to: to, calendar: berlin
    )
}

@Suite("Medikamente: Zeitpläne")
struct MedicationScheduleTests {
    @Test func dailyWithAmounts() {
        let plan = MedicationSchedule.daily([DoseTime(hour: 20, amount: 0.5), DoseTime(hour: 8)])
        let result = doses(plan, from: date(2026, 10, 26), to: date(2026, 10, 28))
        #expect(labels(result) == ["26 08:00", "26 20:00", "27 08:00", "27 20:00"])
        #expect(result.map(\.amount) == [1, 0.5, 1, 0.5])
    }

    @Test func staysAtLocalTimeAcrossDaylightSavingChange() {
        // Zeitumstellung am 25. Oktober 2026.
        let result = doses(.daily([DoseTime(hour: 8)]), from: date(2026, 10, 24), to: date(2026, 10, 27))
        #expect(labels(result) == ["24 08:00", "25 08:00", "26 08:00"])
        #expect(result[1].date.timeIntervalSince(result[0].date) == 25 * 3_600)
    }

    @Test func weekdays() {
        let plan = MedicationSchedule.weekdays([6, 2, 4], times: [DoseTime(hour: 7, minute: 30)])
        let result = doses(plan, from: date(2026, 10, 26), to: date(2026, 11, 2))
        #expect(labels(result) == ["26 07:30", "28 07:30", "30 07:30"])
    }

    @Test func everyNDaysCountsFromStart() {
        let result = doses(.everyNDays(3, times: [DoseTime(hour: 9)]), from: date(2026, 10, 20), to: date(2026, 10, 30))
        #expect(labels(result) == ["20 09:00", "23 09:00", "26 09:00", "29 09:00"])
    }

    @Test func intervalRepeatsEachDay() {
        let eight = doses(.interval(hours: 8, start: DoseTime(hour: 6)), from: date(2026, 10, 26), to: date(2026, 10, 27))
        #expect(labels(eight) == ["26 06:00", "26 14:00", "26 22:00"])
        let five = doses(.interval(hours: 5, start: DoseTime(hour: 7, amount: 2)), from: date(2026, 10, 26), to: date(2026, 10, 27))
        #expect(labels(five) == ["26 07:00", "26 12:00", "26 17:00", "26 22:00"])
        #expect(five.allSatisfy { $0.amount == 2 })
    }

    @Test func cycleWithBreaks() {
        let result = doses(.cycle(on: 2, off: 1, times: [DoseTime(hour: 8)]), from: date(2026, 10, 20), to: date(2026, 10, 26))
        #expect(labels(result) == ["20 08:00", "21 08:00", "23 08:00", "24 08:00"])
    }

    @Test func taperStepsAndEnd() {
        let plan = MedicationSchedule.taper(
            [TaperStep(days: 2, amount: 2), TaperStep(days: 3, amount: 1), TaperStep(days: 2, amount: 0.5)],
            times: [DoseTime(hour: 8)]
        )
        let result = doses(plan, from: date(2026, 10, 20), to: date(2026, 10, 31))
        #expect(labels(result) == ["20 08:00", "21 08:00", "22 08:00", "23 08:00", "24 08:00", "25 08:00", "26 08:00"])
        #expect(result.map(\.amount) == [2, 2, 1, 1, 1, 0.5, 0.5])
        #expect(plan.taperTotalDays == 7)
    }

    @Test func endDateIsInclusive() {
        let result = doses(.daily([DoseTime(hour: 8), DoseTime(hour: 20)]), end: date(2026, 10, 27, 0), from: date(2026, 10, 26), to: date(2026, 10, 30))
        #expect(labels(result) == ["26 08:00", "26 20:00", "27 08:00", "27 20:00"])
    }

    @Test func trackFromSkipsEarlierDoses() {
        let result = doses(.daily([DoseTime(hour: 8), DoseTime(hour: 20)]), start: date(2026, 10, 26), trackFrom: date(2026, 10, 26, 12), from: date(2026, 10, 26), to: date(2026, 10, 27, 12))
        #expect(labels(result) == ["26 20:00", "27 08:00"])
    }

    @Test func nothingBeforeStartAndNothingForAsNeeded() {
        #expect(doses(.daily([DoseTime(hour: 8)]), start: date(2026, 10, 28), from: date(2026, 10, 26), to: date(2026, 10, 29)).count == 1)
        #expect(doses(.asNeeded(maxPerDay: 3, minGapHours: 6), from: date(2026, 10, 26), to: date(2026, 10, 29)).isEmpty)
    }

    @Test func summaries() {
        #expect(MedicationSchedule.daily([DoseTime(hour: 20), DoseTime(hour: 8)]).summary == "Täglich um 08:00, 20:00")
        #expect(MedicationSchedule.weekdays([2, 3, 4, 5, 6], times: [DoseTime(hour: 8)]).summary == "Werktags um 08:00")
        #expect(MedicationSchedule.weekdays([6, 2, 4], times: [DoseTime(hour: 8)]).summary == "Mo, Mi, Fr um 08:00")
        #expect(MedicationSchedule.everyNDays(3, times: [DoseTime(hour: 8)]).summary == "Alle 3 Tage um 08:00")
        #expect(MedicationSchedule.interval(hours: 8, start: DoseTime(hour: 6)).summary == "Alle 8 Std. ab 06:00")
        #expect(MedicationSchedule.asNeeded(maxPerDay: 3, minGapHours: 6).summary == "Bei Bedarf · max. 3× in 24 Std. · mind. 6 Std. Abstand")
        #expect(MedicationSchedule.asNeeded(maxPerDay: nil, minGapHours: 1.5).summary == "Bei Bedarf · mind. 1,5 Std. Abstand")
        #expect(MedicationSchedule.asNeeded(maxPerDay: nil, minGapHours: nil).summary == "Bei Bedarf")
        #expect(MedicationSchedule.cycle(on: 21, off: 7, times: [DoseTime(hour: 8)]).summary == "21 Tage Einnahme, 7 Tage Pause · 08:00")
        #expect(MedicationSchedule.taper([TaperStep(days: 5, amount: 2), TaperStep(days: 5, amount: 1)], times: [DoseTime(hour: 8)]).summary
            == "Ausschleichen in 2 Stufen (10 Tage) · 08:00")
    }

    @Test func validationAndNormalizing() {
        #expect(MedicationSchedule.daily([]).validationMessage == "Mindestens eine Uhrzeit hinzufügen.")
        #expect(MedicationSchedule.weekdays([], times: [DoseTime(hour: 8)]).validationMessage == "Mindestens einen Wochentag wählen.")
        #expect(MedicationSchedule.taper([], times: [DoseTime(hour: 8)]).validationMessage == "Mindestens eine Stufe hinzufügen.")
        #expect(MedicationSchedule.asNeeded(maxPerDay: nil, minGapHours: nil).validationMessage == nil)
        let messy = MedicationSchedule(kind: .daily, times: [DoseTime(hour: 20), DoseTime(hour: 8), DoseTime(hour: 8, amount: 2)], dayInterval: 0)
        let clean = messy.normalized()
        #expect(clean.times.map(\.label) == ["08:00", "20:00"])
        #expect(clean.dayInterval == 1)
    }

    @Test func codableKeepsDefaultsForMissingFields() throws {
        let plan = MedicationSchedule.taper([TaperStep(days: 3, amount: 0.5)], times: [DoseTime(hour: 7, minute: 15)])
        #expect(MedicationSchedule.decode(plan.encoded()) == plan)
        let partial = try JSONDecoder().decode(MedicationSchedule.self, from: Data(#"{"kind":"asNeeded","maxPerDay":3}"#.utf8))
        #expect(partial.kind == .asNeeded)
        #expect(partial.maxPerDay == 3)
        #expect(partial.minGapHours == nil)
        #expect(partial.asNeededAmount == 1)
        let unknown = try JSONDecoder().decode(MedicationSchedule.self, from: Data(#"{"kind":"lunar"}"#.utf8))
        #expect(unknown.kind == .daily)
    }
}

@Suite("Medikamente: Einnahmen und Protokoll")
struct DosePlannerTests {
    private let now = date(2026, 10, 26, 10)

    @Test func doseIDRoundTrip() {
        let id = DoseID.make(medicationID: "ABC-123", date: date(2026, 10, 26, 8))
        let parsed = DoseID.parse(id)
        #expect(parsed?.medicationID == "ABC-123")
        #expect(parsed?.date == date(2026, 10, 26, 8))
        #expect(DoseID.parse("kaputt") == nil)
        #expect(DoseID.parse("|123") == nil)
        #expect(DoseID.parse("abc|x") == nil)
    }

    @Test func states() {
        #expect(DoseTiming.state(for: date(2026, 10, 26, 11), now: now) == .upcoming)
        #expect(DoseTiming.state(for: date(2026, 10, 26, 10, 20), now: now) == .due)
        #expect(DoseTiming.state(for: date(2026, 10, 26, 9, 30), now: now) == .due)
        #expect(DoseTiming.state(for: date(2026, 10, 26, 8, 30), now: now) == .late)
        #expect(DoseTiming.state(for: date(2026, 10, 25, 20), now: now) == .missed)
    }

    @Test func matchesLogsExactlyAndAfterTimeChange() {
        let plan = doses(.daily([DoseTime(hour: 9), DoseTime(hour: 21)]), from: date(2026, 10, 25), to: date(2026, 10, 27))
        let logs = [
            // Exakt: gestern 09:00 genommen.
            DoseLogFact(id: "a", scheduledAt: date(2026, 10, 25, 9), takenAt: date(2026, 10, 25, 9, 5), status: .taken),
            // Plan wurde von 20:00 auf 21:00 geändert: gestern 20:00 ausgelassen.
            DoseLogFact(id: "b", scheduledAt: date(2026, 10, 25, 20), takenAt: nil, status: .skipped),
            // Doppelt für heute 09:00: „genommen“ gewinnt.
            DoseLogFact(id: "c", scheduledAt: date(2026, 10, 26, 9), takenAt: nil, status: .skipped),
            DoseLogFact(id: "d", scheduledAt: date(2026, 10, 26, 9), takenAt: date(2026, 10, 26, 9, 2), status: .taken),
            // Anderer Tag, passt zu nichts.
            DoseLogFact(id: "e", scheduledAt: date(2026, 10, 20, 9), takenAt: date(2026, 10, 20, 9), status: .taken),
        ]
        let entries = DosePlanner.entries(doses: plan, logs: logs, now: now, calendar: berlin)
        #expect(entries.map(\.state) == [.taken, .skipped, .taken, .upcoming])
        #expect(entries.map { $0.log?.id } == ["a", "b", "d", nil])
        #expect(entries[3].isOpen)
        #expect(entries[0].isResolved)
    }

    @Test func unscheduledIntakes() {
        let logs = [
            DoseLogFact(id: "1", scheduledAt: nil, takenAt: date(2026, 10, 26, 8), status: .taken),
            DoseLogFact(id: "2", scheduledAt: nil, takenAt: date(2026, 10, 26, 9), status: .taken),
            DoseLogFact(id: "3", scheduledAt: date(2026, 10, 26, 9), takenAt: date(2026, 10, 26, 9), status: .taken),
            DoseLogFact(id: "4", scheduledAt: nil, takenAt: date(2026, 10, 24, 9), status: .taken),
        ]
        let result = DosePlanner.unscheduledIntakes(logs, from: date(2026, 10, 26), to: date(2026, 10, 27))
        #expect(result.map(\.id) == ["2", "1"])
    }

    @Test func adherenceSummaryAndDays() {
        let plan = doses(.daily([DoseTime(hour: 8), DoseTime(hour: 20)]), from: date(2026, 10, 23), to: date(2026, 10, 27))
        let logs = [
            // 23.: beide genommen, 24.: eine genommen, 25.: nichts, 26.: 08:00 genommen
            DoseLogFact(id: "1", scheduledAt: date(2026, 10, 23, 8), takenAt: nil, status: .taken),
            DoseLogFact(id: "2", scheduledAt: date(2026, 10, 23, 20), takenAt: nil, status: .taken),
            DoseLogFact(id: "3", scheduledAt: date(2026, 10, 24, 8), takenAt: nil, status: .taken),
            DoseLogFact(id: "4", scheduledAt: date(2026, 10, 24, 20), takenAt: nil, status: .skipped),
            DoseLogFact(id: "5", scheduledAt: date(2026, 10, 26, 8), takenAt: nil, status: .taken),
        ]
        let entries = DosePlanner.entries(doses: plan, logs: logs, now: date(2026, 10, 26, 15), calendar: berlin)
        let summary = Adherence.summarize(entries)
        #expect(summary == AdherenceSummary(taken: 4, skipped: 1, missed: 2, open: 1))
        #expect(summary.percentLabel == "57 %")
        let days = Adherence.days(entries, from: date(2026, 10, 22), days: 6, calendar: berlin)
        #expect(days.map(\.status) == [.none, .complete, .partial, .missed, .pending, .none])
        #expect(days[2].taken == 1 && days[2].total == 2)
        #expect(AdherenceSummary().percentLabel == "–")
    }
}

@Suite("Medikamente: Vorrat und Bei Bedarf")
struct StockAndAsNeededTests {
    private let now = date(2026, 10, 26, 15)

    @Test func forecastFromSchedule() {
        let upcoming = doses(.daily([DoseTime(hour: 8), DoseTime(hour: 20)]), from: now, to: date(2026, 12, 31))
        let short = StockCalculator.forecast(stock: 5, upcoming: upcoming, refillThresholdDays: 7, now: now, calendar: berlin)
        #expect(short.daysLeft == 3)
        #expect(short.needsRefill)
        #expect(short.rangeLabel(calendar: berlin) == "reicht noch 3 Tage")

        let daily = doses(.daily([DoseTime(hour: 8)]), from: now, to: date(2027, 3, 1))
        let long = StockCalculator.forecast(stock: 40, upcoming: daily, refillThresholdDays: 7, now: now, calendar: berlin)
        #expect(long.daysLeft == 41)
        #expect(!long.needsRefill)
        #expect(long.rangeLabel(calendar: berlin) == "reicht bis Sa, 5. Dez.")

        let plenty = StockCalculator.forecast(stock: 500, upcoming: Array(daily.prefix(10)), refillThresholdDays: 7, now: now, calendar: berlin)
        #expect(plenty.daysLeft == nil)
        #expect(plenty.rangeLabel(calendar: berlin) == nil)

        let empty = StockCalculator.forecast(stock: 0, upcoming: upcoming, refillThresholdDays: 7, now: now, calendar: berlin)
        #expect(empty.isEmpty && empty.needsRefill)
        #expect(empty.rangeLabel(calendar: berlin) == "Vorrat leer")
    }

    @Test func halfTabletsAndShortLabels() {
        let upcoming = doses(.daily([DoseTime(hour: 20, amount: 0.5)]), from: now, to: date(2026, 11, 30))
        // 1,5 Tabletten = 3 halbe: 26., 27., 28. gedeckt, 29. nicht.
        let forecast = StockCalculator.forecast(stock: 1.5, upcoming: upcoming, refillThresholdDays: 2, now: now, calendar: berlin)
        #expect(forecast.daysLeft == 3)
        #expect(!forecast.needsRefill)
        #expect(StockCalculator.forecast(stock: 1, upcoming: upcoming, refillThresholdDays: 2, now: now, calendar: berlin).rangeLabel(calendar: berlin) == "reicht bis morgen")
        #expect(StockCalculator.forecast(stock: 0.5, upcoming: upcoming, refillThresholdDays: 2, now: now, calendar: berlin).rangeLabel(calendar: berlin) == "reicht nur noch heute")
        #expect(StockCalculator.forecast(stock: 0.25, upcoming: upcoming, refillThresholdDays: 2, now: now, calendar: berlin).rangeLabel(calendar: berlin) == "reicht nicht für die nächste Einnahme")
    }

    @Test func forecastForAsNeeded() {
        let average = StockCalculator.averageDailyUse(
            takenAmounts: (0..<14).map { (date(2026, 10, 13 + $0, 12), 2.0) } + [(date(2026, 9, 1), 50.0)],
            now: now, days: 14
        )
        #expect(average == 2)
        let forecast = StockCalculator.forecast(stock: 10, upcoming: [], averageDailyUse: average, refillThresholdDays: 7, now: now, calendar: berlin)
        #expect(forecast.daysLeft == 5)
        #expect(forecast.needsRefill)
        #expect(StockCalculator.forecast(stock: 10, upcoming: [], averageDailyUse: nil, refillThresholdDays: 7, now: now, calendar: berlin).daysLeft == nil)
    }

    @Test func asNeededLimits() {
        let taken = [date(2026, 10, 26, 2), date(2026, 10, 26, 8), date(2026, 10, 26, 13)]
        let blocked = AsNeededGuard.check(takenAt: taken, maxPerDay: 3, minGapHours: 6, now: now, calendar: berlin)
        #expect(!blocked.isAllowed)
        #expect(blocked.warnings == [
            "Schon 3× in den letzten 24 Std. genommen (max. 3×).",
            "Letzte Einnahme um 13:00 – empfohlen sind mind. 6 Std. Abstand.",
        ])
        #expect(blocked.nextAllowed == date(2026, 10, 27, 2))
        #expect(blocked.statusLine == "3 von max. 3 in 24 Std. · zuletzt 13:00")
        #expect(AsNeededGuard.nextAllowedLabel(blocked.nextAllowed!, now: now, calendar: berlin) == "Wieder ab morgen 02:00")

        let gapOnly = AsNeededGuard.check(takenAt: [date(2026, 10, 26, 12)], maxPerDay: nil, minGapHours: 4, now: now, calendar: berlin)
        #expect(gapOnly.warnings.count == 1)
        #expect(gapOnly.nextAllowed == date(2026, 10, 26, 16))
        #expect(gapOnly.statusLine == "1× in 24 Std. · zuletzt 12:00")

        let free = AsNeededGuard.check(takenAt: [date(2026, 10, 25, 10)], maxPerDay: 3, minGapHours: 6, now: now, calendar: berlin)
        #expect(free.isAllowed)
        #expect(free.nextAllowed == nil)
        #expect(free.statusLine == "0 von max. 3 in 24 Std. · zuletzt gestern 10:00")

        #expect(AsNeededGuard.check(takenAt: [], maxPerDay: nil, minGapHours: nil, now: now, calendar: berlin).statusLine
            == "In den letzten 24 Std. nicht genommen")
    }
}

@Suite("Medikamente: Texte, Erinnerungen, Widget")
struct MedicationPresentationTests {
    @Test func amounts() {
        #expect(DoseAmount.format(0.5) == "½")
        #expect(DoseAmount.format(0.25) == "¼")
        #expect(DoseAmount.format(1) == "1")
        #expect(DoseAmount.format(1.5) == "1½")
        #expect(DoseAmount.format(2.75) == "2¾")
        #expect(DoseAmount.format(0.3) == "0,3")
        #expect(DoseAmount.format(1.3) == "1,3")
        #expect(DoseAmount.formatStock(27.5) == "27,5")
        #expect(DoseAmount.formatStock(28) == "28")
        #expect(MedicationForm.tablet.amountLabel(0.5) == "½ Tablette")
        #expect(MedicationForm.tablet.amountLabel(2) == "2 Tabletten")
        #expect(MedicationForm.capsule.amountLabel(1) == "1 Kapsel")
        #expect(MedicationForm.drops.amountLabel(10) == "10 Tropfen")
        #expect(MedicationForm.spray.amountLabel(2) == "2 Hübe")
        #expect(MedicationForm.liquid.amountLabel(5) == "5 ml")
        #expect(MealTiming.beforeMeal.hint == "vor dem Essen")
        #expect(MealTiming.none.hint == nil)
    }

    @Test func reminderCandidates() {
        let upcoming = doses(.daily([DoseTime(hour: 8), DoseTime(hour: 20)]), from: date(2026, 10, 26, 12), to: date(2026, 10, 27, 12))
        let all = MedicationReminders.candidates(doses: upcoming, name: "DAO-Enzym", detail: { _ in "1 Kapsel · vor dem Essen" }, calendar: berlin)
        #expect(all.count == 4)
        #expect(all[0].id == "med.\(upcoming[0].id)")
        #expect(all[0].body == "1 Kapsel · vor dem Essen · 20:00")
        #expect(all[1].kind == .medicationFollowUp)
        #expect(all[1].fireDate == date(2026, 10, 26, 20, 30))
        #expect(all[1].title == "Noch offen: DAO-Enzym")
        #expect(all[0].referenceID == upcoming[0].id)

        let alarmOnly = MedicationReminders.candidates(doses: upcoming, name: "X", detail: { _ in "" }, includeMain: false, calendar: berlin)
        #expect(alarmOnly.allSatisfy { $0.kind == .medicationFollowUp })

        // Viele Aufgaben verdrängen keine Medikamente.
        let tasks = (0..<70).map { ReminderCandidate(id: "task.\($0)", kind: .task, fireDate: date(2026, 10, 26, 13).addingTimeInterval(Double($0) * 60), title: "", body: "", referenceID: "") }
        let planned = ReminderPlanner.plan(tasks + all, now: date(2026, 10, 26, 12))
        #expect(planned.count == ReminderPlanner.defaultLimit)
        #expect(planned.filter { $0.kind == .medication }.count == 2)
        #expect(planned.filter { $0.kind == .medicationFollowUp }.count == 2)
    }

    @Test func refillReminder() {
        let low = StockForecast(stock: 3, daysLeft: 3, runOutDate: date(2026, 10, 29), needsRefill: true)
        let afternoon = MedicationReminders.refillCandidate(medicationID: "m", name: "Vitamin D", stockText: "3 Tabletten", forecast: low, now: date(2026, 10, 26, 15), calendar: berlin)
        #expect(afternoon?.fireDate == date(2026, 10, 27, 9))
        #expect(afternoon?.body == "Noch 3 Tabletten – reicht noch 3 Tage. Zeit für Nachschub.")
        #expect(afternoon?.id == "refill.m")
        let morning = MedicationReminders.refillCandidate(medicationID: "m", name: "Vitamin D", stockText: "3 Tabletten", forecast: low, now: date(2026, 10, 26, 7), calendar: berlin)
        #expect(morning?.fireDate == date(2026, 10, 26, 9))
        let fine = StockForecast(stock: 30, daysLeft: 30, runOutDate: nil, needsRefill: false)
        #expect(MedicationReminders.refillCandidate(medicationID: "m", name: "", stockText: "", forecast: fine, now: date(2026, 10, 26, 7), calendar: berlin) == nil)
    }

    @Test func stableUUIDs() {
        let a = StableUUID.make(from: "med|1793000000")
        #expect(a == StableUUID.make(from: "med|1793000000"))
        #expect(a != StableUUID.make(from: "med|1793000001"))
        let text = a.uuidString
        #expect(Array(text)[14] == "8")
    }

    private func snapshot() -> MedicationWidgetSnapshot {
        MedicationWidgetSnapshot(writtenAt: date(2026, 10, 26, 6), doses: [
            .init(id: "a|2", medicationID: "a", name: "Vitamin D", detail: "1 Tablette", time: date(2026, 10, 26, 20), colorName: "orange", symbol: "sun.max.fill", state: .open),
            .init(id: "b|1", medicationID: "b", name: "DAO-Enzym", detail: "1 Kapsel", time: date(2026, 10, 26, 8), colorName: "teal", symbol: "capsule.fill", state: .open),
            .init(id: "c|1", medicationID: "c", name: "L-Thyroxin", detail: "1 Tablette", time: date(2026, 10, 26, 6, 30), colorName: "blue", symbol: "pills.fill", state: .taken),
            .init(id: "b|3", medicationID: "b", name: "DAO-Enzym", detail: "1 Kapsel", time: date(2026, 10, 27, 8), colorName: "teal", symbol: "capsule.fill", state: .open),
        ])
    }

    @Test func snapshotQueries() throws {
        var snap = snapshot()
        let today = date(2026, 10, 26, 12)
        #expect(snap.doses.map(\.id) == ["c|1", "b|1", "a|2", "b|3"])
        let progress = snap.progress(on: today, calendar: berlin)
        #expect(progress.done == 1 && progress.total == 3)
        #expect(snap.actionableDose(now: date(2026, 10, 26, 7, 45))?.id == "b|1")
        #expect(snap.actionableDose(now: date(2026, 10, 26, 15))?.id == "b|1")
        #expect(snap.nextOpenDose(now: date(2026, 10, 26, 15))?.id == "b|1")
        #expect(snap.statusSentence(now: today, calendar: berlin) == "Du hast heute 1 von 3 Einnahmen genommen. Offen: DAO-Enzym um 08:00, Vitamin D um 20:00.")

        let appliedKnown = snap.apply(PendingDoseAction(doseID: "b|1", kind: .taken, at: today, source: "widget"))
        let appliedUnknown = snap.apply(PendingDoseAction(doseID: "x|1", kind: .taken, at: today, source: "widget"))
        #expect(appliedKnown && !appliedUnknown)
        #expect(snap.actionableDose(now: date(2026, 10, 26, 15)) == nil)
        #expect(snap.nextOpenDose(now: date(2026, 10, 26, 15))?.id == "a|2")
        snap.apply(PendingDoseAction(doseID: "a|2", kind: .skipped, at: today, source: "siri"))
        #expect(snap.statusSentence(now: today, calendar: berlin) == "Alles erledigt – 2 von 3 genommen, der Rest ausgelassen.")
        #expect(MedicationWidgetSnapshot.empty.statusSentence(now: today, calendar: berlin) == "Heute stehen keine Medikamente an.")

        let decoded = MedicationWidgetSnapshot.decode(try snap.encoded())
        #expect(decoded == snap)
        #expect(MedicationWidgetSnapshot.decode(Data("{}".utf8)) == nil)
    }

    @Test func pendingQueue() {
        let first = PendingDoseAction(doseID: "a|1", kind: .taken, at: date(2026, 10, 26, 8), source: "widget")
        let again = PendingDoseAction(doseID: "a|1", kind: .skipped, at: date(2026, 10, 26, 9), source: "control")
        let other = PendingDoseAction(doseID: "b|1", kind: .taken, at: date(2026, 10, 26, 9), source: "alarm")
        var data = PendingDoseQueue.appending(first, to: nil)
        data = PendingDoseQueue.appending(other, to: data)
        data = PendingDoseQueue.appending(again, to: data)
        let actions = PendingDoseQueue.decode(data)
        #expect(actions.map(\.doseID) == ["b|1", "a|1"])
        #expect(actions.last?.kind == .skipped)
        #expect(PendingDoseQueue.decode(nil).isEmpty)
    }

    @Test func backupWithMedicationsAndOlderBackups() throws {
        let document = BackupDocument(
            createdAt: date(2026, 10, 26, 18),
            appVersion: "0.3.0",
            lists: [],
            tasks: [],
            medications: [MedicationRecord(
                stableID: "m1", name: "DAO-Enzym", dosage: "10.000 HDU", form: "capsule", timing: "beforeMeal",
                schedule: .daily([DoseTime(hour: 12, minute: 15)]), startDate: date(2026, 10, 1), stock: 27.5,
                reminderStyle: "alarm", createdAt: date(2026, 10, 1)
            )],
            doseLogs: [DoseLogRecord(stableID: "l1", medicationID: "m1", scheduledAt: date(2026, 10, 26, 12, 15), takenAt: date(2026, 10, 26, 12, 20), status: "taken", amount: 1, createdAt: date(2026, 10, 26, 12, 20))]
        )
        let decoded = try BackupCodec.decode(BackupCodec.encode(document))
        #expect(decoded == document)

        let older = #"{"format":"tagwerk.backup.v1","createdAt":"2026-10-20T10:00:00Z","appVersion":"0.2.0","lists":[],"tasks":[],"settings":{}}"#
        let old = try BackupCodec.decode(Data(older.utf8))
        #expect(old.medications == nil)
        #expect(old.doseLogs == nil)
    }
}
