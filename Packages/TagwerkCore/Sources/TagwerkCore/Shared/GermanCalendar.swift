import Foundation

/// Kalender und Formatierer für deutsche Datumsangaben.
public enum GermanCalendar {
    /// Gregorianischer Kalender mit deutscher Sprache, Woche beginnt am Montag (ISO 8601).
    public static func make(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "de_DE")
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    /// Kurze Wochentagsnamen, Index = `Calendar`-Wochentag − 1 (0 = Sonntag).
    public static let shortWeekdays = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]

    /// Lange Wochentagsnamen, Index = `Calendar`-Wochentag − 1 (0 = Sonntag).
    public static let longWeekdays = ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"]

    /// Monatsabkürzungen wie im Deutschen üblich, Index = Monat − 1.
    /// Eigene Tabelle statt `DateFormatter`, damit iOS und Linux gleich formatieren.
    public static let shortMonths = ["Jan.", "Feb.", "März", "Apr.", "Mai", "Juni", "Juli", "Aug.", "Sept.", "Okt.", "Nov.", "Dez."]

    /// Wochentage in deutscher Reihenfolge (Mo zuerst), als `Calendar`-Wochentag (1 = So … 7 = Sa).
    public static let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]

    /// „Mo, 2. Nov.“ bzw. mit Jahr „Mo, 2. Nov. 2027“.
    public static func shortDate(_ date: Date, calendar: Calendar, includeYear: Bool = false) -> String {
        let parts = calendar.dateComponents([.weekday, .day, .month, .year], from: date)
        var text = "\(shortWeekdays[(parts.weekday ?? 1) - 1]), \(parts.day ?? 1). \(shortMonths[(parts.month ?? 1) - 1])"
        if includeYear {
            text += " \(parts.year ?? 0)"
        }
        return text
    }

    /// „14:05“
    public static func time(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// 0 = Montag … 6 = Sonntag.
    public static func mondayIndex(ofWeekday weekday: Int) -> Int {
        (weekday + 5) % 7
    }

    public static func formatter(_ format: String, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }
}

extension Calendar {
    /// Gleiche Uhrzeit (Stunde, Minute, Sekunde) wie `timeSource`, aber am Tag von `day`.
    func combining(day: Date, timeOf timeSource: Date) -> Date {
        let time = dateComponents([.hour, .minute, .second], from: timeSource)
        return date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: day) ?? day
    }

    func endOfDay(for date: Date) -> Date {
        let start = startOfDay(for: date)
        return self.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    }
}
