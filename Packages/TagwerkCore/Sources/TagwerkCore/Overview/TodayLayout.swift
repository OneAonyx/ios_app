import Foundation

/// Eine Karte auf „Heute“. Der Überblick oben ist fest, alles andere lässt sich ordnen und ausblenden.
/// Die meisten Karten erscheinen ohnehin nur, wenn es etwas zu tun gibt.
public enum TodayCard: String, CaseIterable, Codable, Sendable, Identifiable {
    case quickCapture
    case nextUp
    case tasks
    case medications
    case training
    case checkIn
    case diary
    case events
    case habits
    case nutrition
    case upcoming
    case review
    case journal

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .quickCapture: "Schnell erfassen"
        case .nextUp: "Als Nächstes"
        case .tasks: "Aufgaben heute"
        case .medications: "Medikamente"
        case .training: "Training"
        case .checkIn: "Check-in"
        case .diary: "Tagebuch heute"
        case .events: "Termine"
        case .habits: "Routinen"
        case .nutrition: "Ernährung"
        case .upcoming: "Demnächst"
        case .review: "Wochenrückblick"
        case .journal: "Abend-Tagebuch"
        }
    }

    /// Wann die Karte erscheint (für die Einstellung „Startseite anpassen“).
    public var detail: String {
        switch self {
        case .quickCapture: "Aufgabe, Mahlzeit, Wasser, Beschwerde, Schmerz, Bewegung mit einem Tipp"
        case .nextUp: "Das Nächste aus Aufgaben, Terminen, Einnahmen und Training"
        case .tasks: "Fokus und fällige Aufgaben"
        case .medications: "Nur solange heute noch Einnahmen offen sind"
        case .training: "Laufende oder nächste Einheit"
        case .checkIn: "Morgens und abends, bis er ausgefüllt ist"
        case .diary: "Was fürs Arzt-Tagebuch heute noch fehlt"
        case .events: "Nur an Tagen mit Terminen"
        case .habits: "Nur wenn heute Routinen anstehen"
        case .nutrition: "Histamin-Tageslast, Eiweiß und Wasser in einer Zeile"
        case .upcoming: "Geburtstage und Fristen der nächsten Tage"
        case .review: "Sonntagnachmittag und Montagvormittag"
        case .journal: "Abends ab 19 Uhr, bis du geschrieben hast"
        }
    }

    public var symbol: String {
        switch self {
        case .quickCapture: "plus.circle"
        case .nextUp: "arrow.forward.circle"
        case .tasks: "checklist"
        case .medications: "pills"
        case .training: "dumbbell"
        case .checkIn: "heart.text.square"
        case .diary: "stethoscope"
        case .events: "calendar"
        case .habits: "repeat"
        case .nutrition: "fork.knife"
        case .upcoming: "calendar.badge.exclamationmark"
        case .review: "calendar.badge.checkmark"
        case .journal: "book.closed"
        }
    }
}

/// Reihenfolge und ausgeblendete Karten auf „Heute“, gespeichert als kurzer Text.
public struct TodayLayout: Equatable, Sendable {
    public var order: [TodayCard]
    public var hidden: Set<TodayCard>

    public init(order: [TodayCard] = TodayCard.allCases, hidden: Set<TodayCard> = []) {
        // Jede Karte genau einmal, fehlende hinten an.
        var seen = Set<TodayCard>()
        var cleaned = order.filter { seen.insert($0).inserted }
        cleaned += TodayCard.allCases.filter { !seen.contains($0) }
        self.order = cleaned
        self.hidden = hidden
    }

    /// Nach Wichtigkeit: erst was jetzt dran ist, dann was heute fehlt, dann Ausblicke.
    public static let standard = TodayLayout()

    public var visibleCards: [TodayCard] {
        order.filter { !hidden.contains($0) }
    }

    public func isVisible(_ card: TodayCard) -> Bool {
        !hidden.contains(card)
    }

    public mutating func setVisible(_ card: TodayCard, _ visible: Bool) {
        if visible { hidden.remove(card) } else { hidden.insert(card) }
    }

    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().map { order[$0] }
        var rest = order.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        rest.insert(contentsOf: moving, at: min(max(insertAt, 0), rest.count))
        order = rest
    }

    public var isStandard: Bool { self == .standard }

    /// „nextUp,tasks,-nutrition,…“: Reihenfolge, ausgeblendete mit Minus.
    public var encoded: String {
        order.map { (hidden.contains($0) ? "-" : "") + $0.rawValue }.joined(separator: ",")
    }

    /// Unbekannte Einträge werden übersprungen, neue Karten (aus späteren Versionen) hinten angehängt.
    public static func decode(_ text: String) -> TodayLayout {
        guard !text.isEmpty else { return .standard }
        var order: [TodayCard] = []
        var hidden = Set<TodayCard>()
        for part in text.split(separator: ",") {
            let isHidden = part.hasPrefix("-")
            guard let card = TodayCard(rawValue: String(isHidden ? part.dropFirst() : part)) else { continue }
            order.append(card)
            if isHidden { hidden.insert(card) }
        }
        return TodayLayout(order: order, hidden: hidden)
    }
}
