import Foundation

/// Einnahmen von heute und morgen im gemeinsamen Speicher. Widgets, Kontrollzentrum
/// und Siri lesen nur diese Datei und brauchen deshalb keinen Zugriff auf die Datenbank.
public struct MedicationWidgetSnapshot: Codable, Sendable, Equatable {
    public struct Dose: Codable, Sendable, Equatable, Hashable, Identifiable {
        public enum State: String, Codable, Sendable {
            case open
            case taken
            case skipped
        }

        /// `DoseID`
        public var id: String
        public var medicationID: String
        public var name: String
        /// z. B. „1 Tablette · vor dem Essen“
        public var detail: String
        public var time: Date
        public var colorName: String
        public var symbol: String
        public var state: State

        public init(id: String, medicationID: String, name: String, detail: String, time: Date, colorName: String, symbol: String, state: State) {
            self.id = id
            self.medicationID = medicationID
            self.name = name
            self.detail = detail
            self.time = time
            self.colorName = colorName
            self.symbol = symbol
            self.state = state
        }

        public var isOpen: Bool { state == .open }
    }

    public var writtenAt: Date
    public var doses: [Dose]
    /// Namen der Medikamente mit knappem Vorrat.
    public var lowStock: [String]

    public init(writtenAt: Date, doses: [Dose], lowStock: [String] = []) {
        self.writtenAt = writtenAt
        self.doses = doses.sorted { $0.time < $1.time }
        self.lowStock = lowStock
    }

    public static let empty = MedicationWidgetSnapshot(writtenAt: .distantPast, doses: [])

    // MARK: Abfragen

    public func doses(on day: Date, calendar: Calendar) -> [Dose] {
        doses.filter { calendar.isDate($0.time, inSameDayAs: day) }
    }

    /// Erledigt (genommen oder ausgelassen) und gesamt an einem Tag.
    public func progress(on day: Date, calendar: Calendar) -> (done: Int, total: Int) {
        let today = doses(on: day, calendar: calendar)
        return (today.filter { !$0.isOpen }.count, today.count)
    }

    /// Die Einnahme, die „Genommen“ ohne Auswahl meint: die früheste offene, die schon
    /// fällig ist oder in den nächsten 2 Stunden kommt (Verpasstes zählt bis 12 Std. danach).
    public func actionableDose(now: Date) -> Dose? {
        let earliest = now.addingTimeInterval(-DoseTiming.missedAfter)
        let latest = now.addingTimeInterval(2 * 3_600)
        return doses.first { $0.isOpen && $0.time >= earliest && $0.time <= latest }
    }

    /// Nächste offene Einnahme für die Anzeige: zuerst überfällige von heute, dann die nächste.
    public func nextOpenDose(now: Date) -> Dose? {
        actionableDose(now: now) ?? doses.first { $0.isOpen && $0.time > now }
    }

    /// Antwort für Siri: „Du hast heute 2 von 3 Einnahmen erledigt. Offen: Vitamin D um 20:00.“
    public func statusSentence(now: Date, calendar: Calendar) -> String {
        let today = doses(on: now, calendar: calendar)
        guard !today.isEmpty else { return "Heute stehen keine Medikamente an." }
        let open = today.filter(\.isOpen)
        let taken = today.filter { $0.state == .taken }.count
        if open.isEmpty {
            return taken == today.count
                ? "Alles erledigt – heute sind alle \(today.count) Einnahmen abgehakt."
                : "Alles erledigt – \(taken) von \(today.count) genommen, der Rest ausgelassen."
        }
        let openText = open.prefix(3)
            .map { "\($0.name) um \(GermanCalendar.time($0.time, calendar: calendar))" }
            .joined(separator: ", ")
        let more = open.count > 3 ? " und \(open.count - 3) weitere" : ""
        return "Du hast heute \(taken) von \(today.count) Einnahmen genommen. Offen: \(openText)\(more)."
    }

    // MARK: Ändern

    /// Markiert eine Einnahme sofort, damit das Widget nicht auf die App warten muss.
    @discardableResult
    public mutating func apply(_ action: PendingDoseAction) -> Bool {
        guard let index = doses.firstIndex(where: { $0.id == action.doseID }) else { return false }
        doses[index].state = action.kind == .taken ? .taken : .skipped
        return true
    }

    // MARK: Kodierung

    public func encoded() throws -> Data {
        try SharedCoding.encoder.encode(self)
    }

    public static func decode(_ data: Data?) -> MedicationWidgetSnapshot? {
        guard let data else { return nil }
        return try? SharedCoding.decoder.decode(MedicationWidgetSnapshot.self, from: data)
    }
}

/// Eine Einnahme, die außerhalb der App abgehakt wurde (Widget, Kontrollzentrum, Siri, Wecker).
public struct PendingDoseAction: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case taken
        case skipped
    }

    public var id: String
    public var doseID: String
    public var kind: Kind
    public var at: Date
    /// Woher: „widget“, „control“, „siri“, „alarm“, „notification“.
    public var source: String

    public init(id: String = UUID().uuidString, doseID: String, kind: Kind, at: Date, source: String) {
        self.id = id
        self.doseID = doseID
        self.kind = kind
        self.at = at
        self.source = source
    }
}

/// Warteschlange im gemeinsamen Speicher (JSON-Liste).
public enum PendingDoseQueue {
    /// Höchstens so viele Einträge aufheben, falls die App lange nicht geöffnet wird.
    public static let limit = 200

    public static func decode(_ data: Data?) -> [PendingDoseAction] {
        guard let data, let actions = try? SharedCoding.decoder.decode([PendingDoseAction].self, from: data) else { return [] }
        return actions
    }

    public static func appending(_ action: PendingDoseAction, to data: Data?) -> Data? {
        var actions = decode(data).filter { $0.doseID != action.doseID }
        actions.append(action)
        return try? SharedCoding.encoder.encode(Array(actions.suffix(limit)))
    }
}
