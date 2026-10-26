import Foundation
@testable import TagwerkCore

/// Fester Kalender für Tests: Europe/Berlin, Woche ab Montag.
let berlin: Calendar = GermanCalendar.make(timeZone: TimeZone(identifier: "Europe/Berlin")!)

/// Datum in Berliner Ortszeit.
func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    berlin.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

/// Liest Datum und Uhrzeit in Berliner Ortszeit zurück, z. B. für Vergleiche in Tests.
func parts(_ value: Date) -> (y: Int, m: Int, d: Int, h: Int, min: Int) {
    let c = berlin.dateComponents([.year, .month, .day, .hour, .minute], from: value)
    return (c.year!, c.month!, c.day!, c.hour!, c.minute!)
}
