import Foundation

/// Fälligkeit als kurzer deutscher Text, z. B. „Heute, 10:00“, „Morgen“, „Mo, 2. Nov.“.
public enum DueFormatter {
    public static func label(due: Date, hasTime: Bool, now: Date, calendar: Calendar) -> String {
        let dayText = dayLabel(for: due, now: now, calendar: calendar)
        guard hasTime else { return dayText }
        return "\(dayText), \(GermanCalendar.time(due, calendar: calendar))"
    }

    /// „Heute“, „Morgen“, „Übermorgen“, „Gestern“, sonst Wochentag und Datum.
    /// Das Jahr erscheint nur, wenn es nicht das aktuelle ist.
    public static func dayLabel(for date: Date, now: Date, calendar: Calendar) -> String {
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let offset = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        switch offset {
        case 0: return "Heute"
        case 1: return "Morgen"
        case 2: return "Übermorgen"
        case -1: return "Gestern"
        default:
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            return GermanCalendar.shortDate(date, calendar: calendar, includeYear: !sameYear)
        }
    }

    /// `true`, wenn eine offene Aufgabe überfällig ist. Ganztägige Aufgaben
    /// sind erst ab dem Folgetag überfällig, Aufgaben mit Uhrzeit ab dieser Uhrzeit.
    public static func isOverdue(due: Date, hasTime: Bool, now: Date, calendar: Calendar) -> Bool {
        hasTime ? due < now : calendar.startOfDay(for: due) < calendar.startOfDay(for: now)
    }
}
