import Foundation
import Testing
@testable import TagwerkCore

@Suite("Tag planen")
struct DayPlanningTests {
    @Test("Briefing fasst den Tag zusammen")
    func body() {
        let day = date(2026, 10, 29)
        let facts = BriefingFacts(
            day: day,
            events: [.init(start: date(2026, 10, 29, 14), title: "Physio"), .init(start: date(2026, 10, 29, 9), title: "Zahnarzt")],
            focus: ["Steuer", "Rezept"], dueTasks: 3, doses: 2, firstDose: date(2026, 10, 29, 8),
            training: "Push", birthdays: ["Lena"], weekFocus: "Früher schlafen"
        )
        let text = MorningBriefing.body(facts, calendar: berlin)
        #expect(text == "2 Termine, zuerst 09:00 Zahnarzt · Fokus: Steuer, Rezept · 3 weitere Aufgaben · 2 Einnahmen ab 08:00 · Training: Push · Geburtstag: Lena\nWoche: Früher schlafen")
        #expect(MorningBriefing.title(name: " Anna ") == "Guten Morgen, Anna")
        #expect(MorningBriefing.title(name: "") == "Guten Morgen")
    }

    @Test("Kurze Tage, ganztägige Termine, nichts los")
    func shortDays() {
        let day = date(2026, 10, 29)
        #expect(MorningBriefing.body(BriefingFacts(day: day, dueTasks: 1), calendar: berlin) == "1 Aufgabe")
        #expect(MorningBriefing.body(BriefingFacts(day: day, events: [.init(start: day, title: "Urlaub", isAllDay: true)]), calendar: berlin) == "Urlaub")
        #expect(MorningBriefing.body(BriefingFacts(day: day, events: [.init(start: date(2026, 10, 29, 10), title: "Team")]), calendar: berlin) == "1 Termin, 10:00 Team")
        #expect(BriefingFacts(day: day).isEmpty)
    }

    @Test("Mitteilung nur, wenn die Uhrzeit noch kommt und es etwas gibt")
    func candidate() {
        let facts = BriefingFacts(day: date(2026, 10, 29), dueTasks: 2)
        let early = MorningBriefing.candidate(facts, minuteOfDay: 7 * 60 + 15, name: "", now: date(2026, 10, 29, 6), calendar: berlin)
        #expect(early?.fireDate == date(2026, 10, 29, 7, 15))
        #expect(early?.id == "brief.20261029")
        #expect(early?.kind == .briefing)
        #expect(MorningBriefing.candidate(facts, minuteOfDay: 7 * 60 + 15, name: "", now: date(2026, 10, 29, 8), calendar: berlin) == nil)
        #expect(MorningBriefing.candidate(facts, minuteOfDay: -1, name: "", now: date(2026, 10, 29, 6), calendar: berlin) == nil)
        #expect(MorningBriefing.candidate(BriefingFacts(day: date(2026, 10, 29)), minuteOfDay: 420, name: "", now: date(2026, 10, 29, 6), calendar: berlin) == nil)
        #expect(NotificationIDs.Prefix.managed.contains(NotificationIDs.Prefix.briefing))
    }

    @Test("Fokus der Woche gilt nur in derselben Woche")
    func weekFocus() {
        #expect(WeekFocus.key(for: date(2026, 10, 28), calendar: berlin) == "2026-W44")
        #expect(WeekFocus.key(for: date(2027, 1, 1), calendar: berlin) == "2026-W53")
        let stored = WeekFocus.store("  Früher schlafen ", now: date(2026, 10, 26), calendar: berlin)
        #expect(stored == "2026-W44|Früher schlafen")
        #expect(WeekFocus.current(stored, now: date(2026, 11, 1, 20), calendar: berlin) == "Früher schlafen")
        #expect(WeekFocus.current(stored, now: date(2026, 11, 2), calendar: berlin) == nil)
        #expect(WeekFocus.store("   ", now: date(2026, 10, 26), calendar: berlin) == "")
        #expect(WeekFocus.current("", now: date(2026, 10, 26), calendar: berlin) == nil)
    }
}
