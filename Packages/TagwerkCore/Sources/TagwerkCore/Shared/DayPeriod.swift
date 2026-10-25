import Foundation

/// Tageszeit für Begrüßung und den späteren Wechsel auf den Abendrückblick.
public enum DayPeriod: String, Sendable, CaseIterable {
    case night
    case morning
    case midday
    case afternoon
    case evening

    public init(hour: Int) {
        switch hour {
        case 5..<11: self = .morning
        case 11..<14: self = .midday
        case 14..<18: self = .afternoon
        case 18..<23: self = .evening
        default: self = .night
        }
    }

    public init(date: Date, calendar: Calendar = .current) {
        self.init(hour: calendar.component(.hour, from: date))
    }

    public var greeting: String {
        switch self {
        case .morning: "Guten Morgen"
        case .midday, .afternoon: "Guten Tag"
        case .evening: "Guten Abend"
        case .night: "Noch wach?"
        }
    }

    /// Ab 18 Uhr zeigt „Heute“ den Abendrückblick.
    public var prefersEveningReview: Bool {
        self == .evening || self == .night
    }
}
