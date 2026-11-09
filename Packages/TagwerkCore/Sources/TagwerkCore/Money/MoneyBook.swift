import Foundation

/// Geld, das du bekommst oder zahlst: Privates (geliehen, ausgelegt) und Rechnungen.
public struct MoneyEntry: Codable, Sendable, Hashable, Identifiable {
    public enum Direction: String, Codable, Sendable, CaseIterable, Identifiable {
        /// Jemand schuldet dir Geld bzw. du hast eine Rechnung gestellt.
        case incoming
        /// Du schuldest jemandem Geld bzw. musst eine Rechnung zahlen.
        case outgoing

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .incoming: "Ich bekomme"
            case .outgoing: "Ich zahle"
            }
        }
    }

    public enum Kind: String, Codable, Sendable, CaseIterable, Identifiable {
        /// Privat: geliehen, ausgelegt, Anteil an einer Rechnung.
        case personal
        /// Rechnung (gestellt oder erhalten).
        case invoice

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .personal: "Privat"
            case .invoice: "Rechnung"
            }
        }

        public var symbol: String {
            switch self {
            case .personal: "person.2"
            case .invoice: "doc.text"
            }
        }
    }

    public struct Payment: Codable, Sendable, Hashable, Identifiable {
        public var id: String
        public var date: Date
        /// Betrag in Cent.
        public var cents: Int

        public init(id: String = UUID().uuidString, date: Date, cents: Int) {
            self.id = id
            self.date = date
            self.cents = cents
        }
    }

    public var id: String
    public var direction: Direction
    public var kind: Kind
    /// Person oder Firma.
    public var counterparty: String
    /// Wofür, z. B. „Konzertkarten“ oder „Rechnung 2026-014“.
    public var title: String
    /// Betrag in Cent.
    public var cents: Int
    public var date: Date
    public var dueDate: Date?
    public var note: String
    public var payments: [Payment]
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString, direction: Direction, kind: Kind, counterparty: String, title: String = "",
        cents: Int, date: Date, dueDate: Date? = nil, note: String = "", payments: [Payment] = [], createdAt: Date = .now
    ) {
        self.id = id
        self.direction = direction
        self.kind = kind
        self.counterparty = counterparty
        self.title = title
        self.cents = max(0, cents)
        self.date = date
        self.dueDate = dueDate
        self.note = note
        self.payments = payments
        self.createdAt = createdAt
    }

    public var paidCents: Int { payments.reduce(0) { $0 + $1.cents } }
    public var openCents: Int { max(0, cents - paidCents) }
    public var isSettled: Bool { openCents == 0 }
    public var lastPayment: Date? { payments.map(\.date).max() }

    /// Offen und Fälligkeit vor heute.
    public func isOverdue(now: Date, calendar: Calendar) -> Bool {
        guard !isSettled, let dueDate else { return false }
        return calendar.startOfDay(for: dueDate) < calendar.startOfDay(for: now)
    }

    /// „fällig heute“, „seit 3 Tagen überfällig“, „fällig in 5 Tagen“, „fällig am 3. Dez.“
    public func dueText(now: Date, calendar: Calendar) -> String? {
        guard let dueDate, !isSettled else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: dueDate)).day ?? 0
        switch days {
        case ..<(-1): return "seit \(-days) Tagen überfällig"
        case -1: return "seit gestern überfällig"
        case 0: return "fällig heute"
        case 1: return "fällig morgen"
        case 2...14: return "fällig in \(days) Tagen"
        default: return "fällig am \(WeeklyReview.dayMonth(dueDate, calendar: calendar))"
        }
    }

    /// Name für Listen: „Lena · Konzertkarten“
    public var displayTitle: String {
        title.isEmpty ? counterparty : "\(counterparty) · \(title)"
    }
}

/// Alle Einträge mit Summen und Hilfen.
public struct MoneyBook: Sendable, Hashable {
    public var entries: [MoneyEntry]

    public init(entries: [MoneyEntry] = []) {
        self.entries = entries
    }

    /// Offene Einträge einer Richtung: überfällige zuerst, dann nach Fälligkeit, dann neueste.
    public func open(_ direction: MoneyEntry.Direction, now: Date, calendar: Calendar) -> [MoneyEntry] {
        entries.filter { $0.direction == direction && !$0.isSettled }.sorted { lhs, rhs in
            let lo = lhs.isOverdue(now: now, calendar: calendar)
            let ro = rhs.isOverdue(now: now, calendar: calendar)
            if lo != ro { return lo }
            switch (lhs.dueDate, rhs.dueDate) {
            case let (l?, r?) where l != r: return l < r
            case (_?, nil): return true
            case (nil, _?): return false
            default: return lhs.date > rhs.date
            }
        }
    }

    /// Erledigte, zuletzt bezahlte zuerst.
    public var settled: [MoneyEntry] {
        entries.filter(\.isSettled).sorted { ($0.lastPayment ?? $0.date) > ($1.lastPayment ?? $1.date) }
    }

    public func openCents(_ direction: MoneyEntry.Direction) -> Int {
        entries.filter { $0.direction == direction }.reduce(0) { $0 + $1.openCents }
    }

    public func overdue(now: Date, calendar: Calendar) -> [MoneyEntry] {
        entries.filter { $0.isOverdue(now: now, calendar: calendar) }
    }

    /// Je Person bzw. Firma: was du bekommst minus was du zahlst (nur offene Beträge).
    public var balances: [(name: String, cents: Int)] {
        var byName: [String: Int] = [:]
        var display: [String: String] = [:]
        for entry in entries where !entry.isSettled {
            let key = NameMatcher.normalize(entry.counterparty)
            display[key] = display[key] ?? entry.counterparty
            byName[key, default: 0] += entry.direction == .incoming ? entry.openCents : -entry.openCents
        }
        return byName.filter { $0.value != 0 }
            .map { (display[$0.key] ?? $0.key, $0.value) }
            .sorted { abs($0.1) > abs($1.1) }
    }

    /// Bekannte Namen für Vorschläge beim Eintragen, häufigste zuerst.
    public var knownCounterparties: [String] {
        let counts = Dictionary(grouping: entries, by: { $0.counterparty.trimmingCharacters(in: .whitespaces) }).mapValues(\.count)
        return counts.filter { !$0.key.isEmpty }.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
    }

    // MARK: Ändern

    public mutating func upsert(_ entry: MoneyEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
    }

    public mutating func remove(id: String) {
        entries.removeAll { $0.id == id }
    }

    /// Zahlung erfassen, höchstens bis zum offenen Betrag.
    public mutating func addPayment(to id: String, cents: Int, date: Date) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let amount = min(max(0, cents), entries[index].openCents)
        guard amount > 0 else { return }
        entries[index].payments.append(.init(date: date, cents: amount))
    }

    /// Den Rest als bezahlt markieren.
    public mutating func settle(id: String, date: Date) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        addPayment(to: id, cents: entry.openCents, date: date)
    }

    /// Wieder öffnen (alle Zahlungen entfernen).
    public mutating func reopen(id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].payments = []
    }

    // MARK: Texte

    /// „12,50 €“ aus Cent.
    public static func euro(_ cents: Int) -> String {
        let euros = cents / 100
        let rest = abs(cents % 100)
        let sign = cents < 0 && euros == 0 ? "-" : ""
        return "\(sign)\(GermanNumber.grouped(euros)),\(rest < 10 ? "0" : "")\(rest) €"
    }

    /// „12,50“ oder „12.5“ → 1250 Cent.
    public static func cents(from text: String) -> Int? {
        let cleaned = text.replacingOccurrences(of: "€", with: "").replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty else { return nil }
        // Tausenderpunkt nur, wenn danach noch ein Komma kommt („1.250,00“).
        let normalized = cleaned.contains(",") ? cleaned.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") : cleaned
        guard let value = Double(normalized), value >= 0, value < 10_000_000 else { return nil }
        return Int((value * 100).rounded())
    }

    /// Freundliche Erinnerung zum Verschicken (nur für Geld, das du bekommst).
    public static func reminderText(for entry: MoneyEntry, now: Date, calendar: Calendar) -> String {
        let firstName = entry.counterparty.split(separator: " ").first.map(String.init) ?? entry.counterparty
        let what = entry.title.isEmpty ? "" : " für \(entry.title)"
        let when = " vom \(WeeklyReview.dayMonth(entry.date, calendar: calendar))"
        switch entry.kind {
        case .personal:
            return "Hi \(firstName), kleine Erinnerung an die \(euro(entry.openCents))\(what)\(when) – danke dir!"
        case .invoice:
            let due = entry.dueDate.map { " (fällig seit \(WeeklyReview.dayMonth($0, calendar: calendar)))" } ?? ""
            return "Hallo \(firstName),\n\nich möchte freundlich an die offene Rechnung\(what)\(when) über \(euro(entry.openCents))\(due) erinnern.\n\nVielen Dank und viele Grüße"
        }
    }

    // MARK: Speichern

    public static func encode(_ book: MoneyBook) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(book.entries) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    public static func decode(_ text: String) -> MoneyBook {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard !text.isEmpty, let entries = try? decoder.decode([MoneyEntry].self, from: Data(text.utf8)) else { return MoneyBook() }
        return MoneyBook(entries: entries)
    }
}
