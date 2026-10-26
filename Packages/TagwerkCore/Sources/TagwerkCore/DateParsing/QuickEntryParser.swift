import Foundation

/// Ergebnis der Schnellerfassung, z. B. aus „morgen 10 Uhr Zahnarzt !! #Privat“.
public struct QuickEntry: Sendable, Equatable {
    /// Erkannter Teil der Eingabe, für die Anzeige als Chip unter dem Textfeld.
    public struct Chip: Sendable, Equatable, Hashable {
        public enum Kind: String, Sendable {
            case date
            case time
            case recurrence
            case priority
            case list
        }

        public var kind: Kind
        public var label: String

        public init(kind: Kind, label: String) {
            self.kind = kind
            self.label = label
        }
    }

    public var title: String
    public var dueDate: Date?
    public var hasTime: Bool
    public var recurrence: RecurrenceRule?
    /// 0 = keine, 1 = niedrig, 2 = mittel, 3 = hoch.
    public var priority: Int
    public var listName: String?
    public var chips: [Chip]

    public init(
        title: String,
        dueDate: Date? = nil,
        hasTime: Bool = false,
        recurrence: RecurrenceRule? = nil,
        priority: Int = 0,
        listName: String? = nil,
        chips: [Chip] = []
    ) {
        self.title = title
        self.dueDate = dueDate
        self.hasTime = hasTime
        self.recurrence = recurrence
        self.priority = priority
        self.listName = listName
        self.chips = chips
    }
}

/// Versteht deutsche Kurzangaben in der Schnellerfassung.
///
/// Datum: heute, morgen, übermorgen, Wochentage („freitag“, „am mo“, „nächsten dienstag“),
/// „nächste woche“, „wochenende“, „24.12.“, „24.12.2027“, „am 15.“, „in 3 tagen“.
/// Uhrzeit: „10 uhr“, „um 10“, „10:30“, „18.30 uhr“, „14h“, „in 2 stunden“,
/// „morgens“, „abends“, „heute abend“, „morgen früh“.
/// Wiederholung: täglich, werktags, wöchentlich, monatlich, jährlich, „jeden montag“,
/// „jeden di und do“, „montags“, „alle 2 wochen“.
/// Priorität: „!“, „!!“, „!!!“. Liste: „#Arbeit“.
/// Alles, was nicht erkannt wird, bleibt als Titel stehen.
public struct QuickEntryParser: Sendable {
    public let calendar: Calendar

    public init(calendar: Calendar = GermanCalendar.make()) {
        self.calendar = calendar
    }

    public func parse(_ text: String, now: Date) -> QuickEntry {
        var state = ParseState(tokens: tokenize(text))
        var index = 0
        while index < state.tokens.count {
            if state.consumed.contains(index) {
                index += 1
                continue
            }
            let used = matchPriority(&state, at: index)
                ?? matchList(&state, at: index)
                ?? matchRecurrence(&state, at: index, now: now)
                ?? matchRelative(&state, at: index, now: now)
                ?? matchDate(&state, at: index, now: now)
                ?? matchTime(&state, at: index)
            if let used, used > 0 {
                for offset in 0..<used {
                    state.consumed.insert(index + offset)
                }
                index += used
            } else {
                index += 1
            }
        }
        return finish(state, now: now)
    }

    // MARK: - Zustand

    private struct Token {
        let original: String
        let norm: String
    }

    private struct ParseState {
        let tokens: [Token]
        var consumed: Set<Int> = []
        var day: Date?
        var time: (hour: Int, minute: Int)?
        var relativeDateTime: Date?
        var recurrence: RecurrenceRule?
        var priority = 0
        var listName: String?

        init(tokens: [Token]) {
            self.tokens = tokens
        }

        func norm(_ index: Int) -> String? {
            guard index >= 0, index < tokens.count, !consumed.contains(index) else { return nil }
            return tokens[index].norm
        }
    }

    private func tokenize(_ text: String) -> [Token] {
        let trimSet = CharacterSet(charactersIn: ",;()\"„“”'")
        return text
            .split(whereSeparator: { $0.isWhitespace })
            .map { word in
                let original = String(word)
                let norm = original.lowercased().trimmingCharacters(in: trimSet)
                return Token(original: original, norm: Self.foldUmlautSpellings(norm))
            }
    }

    /// „uebermorgen“ → „übermorgen“, „taeglich“ → „täglich“ usw. (nur bekannte Wörter).
    private static func foldUmlautSpellings(_ word: String) -> String {
        let map = [
            "uebermorgen": "übermorgen", "taeglich": "täglich", "woechentlich": "wöchentlich",
            "jaehrlich": "jährlich", "naechste": "nächste", "naechsten": "nächsten",
            "naechster": "nächster", "frueh": "früh", "fuenf": "fünf", "zwoelf": "zwölf",
        ]
        return map[word] ?? word
    }

    // MARK: - Priorität und Liste

    private func matchPriority(_ state: inout ParseState, at index: Int) -> Int? {
        guard let word = state.norm(index), (1...3).contains(word.count), word.allSatisfy({ $0 == "!" }) else {
            return nil
        }
        state.priority = max(state.priority, word.count)
        return 1
    }

    private func matchList(_ state: inout ParseState, at index: Int) -> Int? {
        let original = state.tokens[index].original
        guard state.listName == nil, original.hasPrefix("#"), original.count > 1 else { return nil }
        let name = String(original.dropFirst()).trimmingCharacters(in: .punctuationCharacters)
        guard !name.isEmpty else { return nil }
        state.listName = name
        return 1
    }

    // MARK: - Wiederholung

    private func matchRecurrence(_ state: inout ParseState, at index: Int, now: Date) -> Int? {
        guard state.recurrence == nil, let word = state.norm(index) else { return nil }

        switch word {
        case "täglich":
            state.recurrence = .daily
            return 1
        case "werktags":
            state.recurrence = .workdays
            return 1
        case "wöchentlich":
            state.recurrence = .weekly
            return 1
        case "monatlich":
            state.recurrence = .monthly
            return 1
        case "jährlich":
            state.recurrence = .yearly
            return 1
        default:
            break
        }

        if let weekday = Self.pluralWeekdays[word] {
            state.recurrence = RecurrenceRule(frequency: .weekly, weekdays: [weekday])
            return 1
        }

        if ["jeden", "jede", "jedes"].contains(word), let next = state.norm(index + 1) {
            switch next {
            case "tag":
                state.recurrence = .daily
                return 2
            case "werktag":
                state.recurrence = .workdays
                return 2
            case "woche":
                state.recurrence = .weekly
                return 2
            case "monat":
                state.recurrence = .monthly
                return 2
            case "jahr":
                state.recurrence = .yearly
                return 2
            default:
                break
            }
            if let first = weekday(from: next, allowAbbreviation: true) {
                var weekdays = [first]
                var used = 2
                // „jeden montag und donnerstag“, „jeden mo, mi und fr“
                while state.norm(index + used) == "und",
                      let next = state.norm(index + used + 1),
                      let more = weekday(from: next, allowAbbreviation: true) {
                    weekdays.append(more)
                    used += 2
                }
                state.recurrence = RecurrenceRule(frequency: .weekly, weekdays: weekdays)
                return used
            }
        }

        if word == "alle",
           let amountWord = state.norm(index + 1), let amount = number(from: amountWord),
           let unitWord = state.norm(index + 2), let frequency = Self.recurrenceUnits[unitWord] {
            state.recurrence = RecurrenceRule(frequency: frequency, interval: amount)
            return 3
        }
        return nil
    }

    // MARK: - Relative Angaben („in 2 stunden“)

    private func matchRelative(_ state: inout ParseState, at index: Int, now: Date) -> Int? {
        guard state.norm(index) == "in", state.day == nil, state.relativeDateTime == nil,
              let amountWord = state.norm(index + 1), let amount = number(from: amountWord),
              let unitWord = state.norm(index + 2)
        else { return nil }

        switch unitWord {
        case "minute", "minuten", "min", "min.":
            state.relativeDateTime = now.addingTimeInterval(TimeInterval(amount * 60))
        case "stunde", "stunden", "std", "std.", "h":
            state.relativeDateTime = now.addingTimeInterval(TimeInterval(amount * 3_600))
        case "tag", "tage", "tagen":
            state.day = calendar.date(byAdding: .day, value: amount, to: calendar.startOfDay(for: now))
        case "woche", "wochen":
            state.day = calendar.date(byAdding: .day, value: 7 * amount, to: calendar.startOfDay(for: now))
        case "monat", "monate", "monaten":
            state.day = calendar.date(byAdding: .month, value: amount, to: calendar.startOfDay(for: now))
        default:
            return nil
        }
        return 3
    }

    // MARK: - Datum

    private func matchDate(_ state: inout ParseState, at index: Int, now: Date) -> Int? {
        guard state.day == nil, state.relativeDateTime == nil, let word = state.norm(index) else { return nil }

        // Füllwörter vor einem Datum („am freitag“, „bis montag“)
        if ["am", "bis"].contains(word) {
            guard let (day, used) = dateExpression(state, at: index + 1, now: now, afterPrefix: true) else {
                return nil
            }
            state.day = day
            return 1 + used + dayPart(&state, at: index + 1 + used)
        }

        guard let (day, used) = dateExpression(state, at: index, now: now, afterPrefix: false) else {
            return nil
        }
        state.day = day
        return used + dayPart(&state, at: index + used)
    }

    /// Erkennt ein Datum ab `index` und gibt Tag (Mitternacht) und Anzahl verbrauchter Wörter zurück.
    private func dateExpression(_ state: ParseState, at index: Int, now: Date, afterPrefix: Bool) -> (Date, Int)? {
        guard let word = state.norm(index) else { return nil }
        let today = calendar.startOfDay(for: now)

        switch word {
        case "heute":
            return (today, 1)
        case "morgen":
            return calendar.date(byAdding: .day, value: 1, to: today).map { ($0, 1) }
        case "übermorgen":
            return calendar.date(byAdding: .day, value: 2, to: today).map { ($0, 1) }
        case "wochenende":
            return (upcomingWeekend(from: today), 1)
        case "nächste", "kommende":
            if state.norm(index + 1) == "woche" {
                return startOfNextWeek(from: today).map { ($0, 2) }
            }
            return nil
        case "nächsten", "nächster", "kommenden", "kommender":
            if let next = state.norm(index + 1), let weekday = weekday(from: next, allowAbbreviation: true) {
                return nextWeekday(weekday, from: today, includeToday: false).map { ($0, 2) }
            }
            return nil
        default:
            break
        }

        if let weekday = weekday(from: word, allowAbbreviation: afterPrefix) {
            return nextWeekday(weekday, from: today, includeToday: true).map { ($0, 1) }
        }
        if let day = numericDate(word, today: today, allowDayOnly: afterPrefix) {
            return (day, 1)
        }
        return nil
    }

    /// „heute abend“, „morgen früh“, „freitag nachmittag“ – Tageszeit direkt nach einem Datum.
    private func dayPart(_ state: inout ParseState, at index: Int) -> Int {
        guard state.time == nil, let word = state.norm(index), let time = Self.dayParts[word] ?? Self.dayPartsAfterDate[word] else {
            return 0
        }
        state.time = time
        return 1
    }

    // MARK: - Uhrzeit

    private func matchTime(_ state: inout ParseState, at index: Int) -> Int? {
        guard state.time == nil, state.relativeDateTime == nil, let word = state.norm(index) else { return nil }

        if let time = Self.dayParts[word] {
            state.time = time
            return 1
        }

        // „um 10“, „um 10:30“, „um 10 uhr“, „um 18.30 uhr“
        if word == "um", let next = state.norm(index + 1) {
            let followedByUhr = state.norm(index + 2) == "uhr"
            if let time = clockTime(next, allowDotSeparator: followedByUhr, allowBareHour: true) {
                state.time = time
                return followedByUhr ? 3 : 2
            }
        }

        // „10 uhr“, „18.30 uhr“
        if state.norm(index + 1) == "uhr", let time = clockTime(word, allowDotSeparator: true, allowBareHour: true) {
            state.time = time
            return 2
        }

        // „10:30“, „10uhr“, „14h“
        if let time = clockTime(word, allowDotSeparator: false, allowBareHour: false) {
            state.time = time
            return 1
        }
        return nil
    }

    private func clockTime(_ word: String, allowDotSeparator: Bool, allowBareHour: Bool) -> (hour: Int, minute: Int)? {
        var text = word
        var hasUnit = false
        for suffix in ["uhr", "h"] where text.hasSuffix(suffix) && text.count > suffix.count {
            text.removeLast(suffix.count)
            hasUnit = true
            break
        }
        let separators: [Character] = allowDotSeparator || hasUnit ? [":", "."] : [":"]
        let pieces = text.split(omittingEmptySubsequences: false, whereSeparator: { separators.contains($0) })

        let hour: Int
        let minute: Int
        switch pieces.count {
        case 1:
            guard allowBareHour || hasUnit, let value = Int(pieces[0]), pieces[0].count <= 2 else { return nil }
            hour = value
            minute = 0
        case 2:
            guard let h = Int(pieces[0]), let m = Int(pieces[1]), pieces[1].count == 2 else { return nil }
            hour = h
            minute = m
        default:
            return nil
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }

    // MARK: - Abschluss

    private func finish(_ state: ParseState, now: Date) -> QuickEntry {
        var due: Date?
        var hasTime = false
        var recurrence = state.recurrence

        if let relative = state.relativeDateTime {
            due = relative
            hasTime = true
        } else if state.day != nil || state.time != nil || recurrence != nil {
            let start = state.day ?? firstMatchingDay(for: recurrence, time: state.time, now: now)
            if let time = state.time {
                due = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: start)
                hasTime = true
            } else {
                due = start
            }
        }

        if var rule = recurrence, rule.frequency == .monthly, rule.monthDay == nil, let due {
            rule.monthDay = calendar.component(.day, from: due)
            recurrence = rule
        }

        var chips: [QuickEntry.Chip] = []
        if let due {
            chips.append(.init(kind: .date, label: DueFormatter.dayLabel(for: due, now: now, calendar: calendar)))
            if hasTime {
                chips.append(.init(kind: .time, label: GermanCalendar.time(due, calendar: calendar)))
            }
        }
        if let recurrence {
            chips.append(.init(kind: .recurrence, label: recurrence.summary(calendar: calendar)))
        }
        if state.priority > 0 {
            let names = ["", "niedrig", "mittel", "hoch"]
            chips.append(.init(kind: .priority, label: "Priorität \(names[state.priority])"))
        }
        if let listName = state.listName {
            chips.append(.init(kind: .list, label: listName))
        }

        let remaining = state.tokens.indices
            .filter { !state.consumed.contains($0) }
            .map { state.tokens[$0].original }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)

        return QuickEntry(
            title: capitalizedFirstLetter(remaining),
            dueDate: due,
            hasTime: hasTime,
            recurrence: recurrence,
            priority: state.priority,
            listName: state.listName,
            chips: chips
        )
    }

    /// Erster passender Tag ohne ausdrückliches Datum: heute, falls die Uhrzeit noch nicht
    /// vorbei ist und der Wochentag zur Wiederholung passt, sonst der nächste passende Tag.
    private func firstMatchingDay(for recurrence: RecurrenceRule?, time: (hour: Int, minute: Int)?, now: Date) -> Date {
        let today = calendar.startOfDay(for: now)
        let allowed = recurrence.flatMap { $0.frequency == .weekly && !$0.weekdays.isEmpty ? Set($0.weekdays) : nil }
        for offset in 0..<14 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            if let allowed, !allowed.contains(calendar.component(.weekday, from: day)) {
                continue
            }
            if let time,
               let candidate = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day),
               candidate <= now {
                continue
            }
            return day
        }
        return today
    }

    // MARK: - Hilfen

    private func weekday(from word: String, allowAbbreviation: Bool) -> Int? {
        if let weekday = Self.weekdayNames[word] {
            return weekday
        }
        // Abkürzungen nur mit Punkt („so.“) oder nach „am“, „jeden“, „nächsten“ –
        // sonst würde z. B. das Wort „so“ als Sonntag gelesen.
        if word.hasSuffix("."), let weekday = Self.weekdayAbbreviations[String(word.dropLast())] {
            return weekday
        }
        if allowAbbreviation, let weekday = Self.weekdayAbbreviations[word] {
            return weekday
        }
        return nil
    }

    private func nextWeekday(_ weekday: Int, from today: Date, includeToday: Bool) -> Date? {
        let current = calendar.component(.weekday, from: today)
        var days = (weekday - current + 7) % 7
        if days == 0, !includeToday {
            days = 7
        }
        return calendar.date(byAdding: .day, value: days, to: today)
    }

    private func startOfNextWeek(from today: Date) -> Date? {
        let index = GermanCalendar.mondayIndex(ofWeekday: calendar.component(.weekday, from: today))
        return calendar.date(byAdding: .day, value: 7 - index, to: today)
    }

    /// Samstag dieser Woche, oder heute, wenn schon Wochenende ist.
    private func upcomingWeekend(from today: Date) -> Date {
        let index = GermanCalendar.mondayIndex(ofWeekday: calendar.component(.weekday, from: today))
        if index >= 5 {
            return today
        }
        return calendar.date(byAdding: .day, value: 5 - index, to: today) ?? today
    }

    /// „24.12.“, „24.12“, „24.12.2027“, „24.12.27“ und nach „am“ auch „15.“ (Tag im Monat).
    private func numericDate(_ word: String, today: Date, allowDayOnly: Bool) -> Date? {
        let pieces = word.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let numbers = pieces.filter { !$0.isEmpty }
        guard !numbers.isEmpty, numbers.allSatisfy({ Int($0) != nil }) else { return nil }
        let values = numbers.compactMap { Int($0) }
        let currentYear = calendar.component(.year, from: today)
        let currentMonth = calendar.component(.month, from: today)

        switch values.count {
        case 1:
            // Nur Tag („am 15.“): dieser Monat, sonst der nächste.
            guard allowDayOnly, word.hasSuffix("."), (1...31).contains(values[0]) else { return nil }
            for monthOffset in 0..<3 {
                var components = DateComponents(year: currentYear, month: currentMonth + monthOffset, day: 1)
                guard let first = calendar.date(from: components),
                      let length = calendar.range(of: .day, in: .month, for: first)?.count,
                      values[0] <= length
                else { continue }
                components = calendar.dateComponents([.year, .month], from: first)
                components.day = values[0]
                if let candidate = calendar.date(from: components), candidate >= today {
                    return candidate
                }
            }
            return nil
        case 2:
            guard pieces.count <= 3 else { return nil }
            if let candidate = validDate(day: values[0], month: values[1], year: currentYear), candidate >= today {
                return candidate
            }
            return validDate(day: values[0], month: values[1], year: currentYear + 1)
        case 3:
            var year = values[2]
            if numbers[2].count == 2 {
                year += 2000
            }
            guard numbers[2].count == 2 || numbers[2].count == 4 else { return nil }
            return validDate(day: values[0], month: values[1], year: year)
        default:
            return nil
        }
    }

    private func validDate(day: Int, month: Int, year: Int) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.component(.day, from: date) == day,
              calendar.component(.month, from: date) == month
        else { return nil }
        return date
    }

    private func number(from word: String) -> Int? {
        if let value = Int(word), value > 0, value < 1_000 {
            return value
        }
        return Self.numberWords[word]
    }

    private func capitalizedFirstLetter(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    // MARK: - Wortlisten

    private static let weekdayNames: [String: Int] = [
        "montag": 2, "dienstag": 3, "mittwoch": 4, "donnerstag": 5,
        "freitag": 6, "samstag": 7, "sonnabend": 7, "sonntag": 1,
    ]

    private static let weekdayAbbreviations: [String: Int] = [
        "mo": 2, "di": 3, "mi": 4, "do": 5, "fr": 6, "sa": 7, "so": 1,
    ]

    private static let pluralWeekdays: [String: Int] = [
        "montags": 2, "dienstags": 3, "mittwochs": 4, "donnerstags": 5,
        "freitags": 6, "samstags": 7, "sonntags": 1,
    ]

    private static let recurrenceUnits: [String: RecurrenceRule.Frequency] = [
        "tag": .daily, "tage": .daily,
        "woche": .weekly, "wochen": .weekly,
        "monat": .monthly, "monate": .monthly,
        "jahr": .yearly, "jahre": .yearly,
    ]

    /// Tageszeiten, die allein stehen dürfen („abends joggen“).
    private static let dayParts: [String: (hour: Int, minute: Int)] = [
        "morgens": (8, 0), "vormittags": (10, 0), "mittags": (12, 0),
        "nachmittags": (15, 0), "abends": (19, 0), "nachts": (22, 0),
    ]

    /// Tageszeiten, die nur direkt nach einem Datum zählen („heute abend“, „morgen früh“).
    private static let dayPartsAfterDate: [String: (hour: Int, minute: Int)] = [
        "früh": (8, 0), "vormittag": (10, 0), "mittag": (12, 0),
        "nachmittag": (15, 0), "abend": (19, 0), "nacht": (22, 0),
    ]

    private static let numberWords: [String: Int] = [
        "ein": 1, "eine": 1, "einer": 1, "einem": 1, "einen": 1,
        "zwei": 2, "drei": 3, "vier": 4, "fünf": 5, "sechs": 6,
        "sieben": 7, "acht": 8, "neun": 9, "zehn": 10, "elf": 11, "zwölf": 12,
    ]
}
