import Foundation

/// Darreichungsform. Bestimmt, wie Mengen angezeigt werden („½ Tablette“, „10 Tropfen“).
public enum MedicationForm: String, Codable, Sendable, CaseIterable, Identifiable {
    case tablet
    case capsule
    case drops
    case liquid
    case spray
    case sachet
    case injection
    case patch
    case suppository
    case cream
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .tablet: "Tablette"
        case .capsule: "Kapsel"
        case .drops: "Tropfen"
        case .liquid: "Saft / Lösung (ml)"
        case .spray: "Spray / Inhalation"
        case .sachet: "Beutel / Pulver"
        case .injection: "Spritze / Pen"
        case .patch: "Pflaster"
        case .suppository: "Zäpfchen"
        case .cream: "Creme / Salbe"
        case .other: "Sonstiges"
        }
    }

    /// Einheit für eine Menge: Einzahl bei bis zu 1, sonst Mehrzahl.
    public func unit(for amount: Double) -> String {
        let singular = amount <= 1
        switch self {
        case .tablet: return singular ? "Tablette" : "Tabletten"
        case .capsule: return singular ? "Kapsel" : "Kapseln"
        case .drops: return "Tropfen"
        case .liquid: return "ml"
        case .spray: return singular ? "Hub" : "Hübe"
        case .sachet: return "Beutel"
        case .injection: return singular ? "Spritze" : "Spritzen"
        case .patch: return "Pflaster"
        case .suppository: return "Zäpfchen"
        case .cream: return singular ? "Anwendung" : "Anwendungen"
        case .other: return singular ? "Dosis" : "Dosen"
        }
    }

    /// „½ Tablette“, „2 Kapseln“, „5 ml“.
    public func amountLabel(_ amount: Double) -> String {
        "\(DoseAmount.format(amount)) \(unit(for: amount))"
    }

    /// Passendes SF-Symbol für die Auswahl im Editor.
    public var defaultSymbol: String {
        switch self {
        case .tablet, .other: "pills.fill"
        case .capsule: "capsule.fill"
        case .drops: "drop.fill"
        case .liquid: "cup.and.saucer.fill"
        case .spray: "wind"
        case .sachet: "bag.fill"
        case .injection: "syringe.fill"
        case .patch: "bandage.fill"
        case .suppository: "capsule.portrait.fill"
        case .cream: "hand.raised.fill"
        }
    }

    /// Schrittweite für Mengen im Editor.
    public var amountStep: Double {
        switch self {
        case .tablet: 0.25
        case .liquid: 0.5
        default: 1
        }
    }
}

/// Bezug zur Mahlzeit, z. B. DAO-Enzym „vor dem Essen“.
public enum MealTiming: String, Codable, Sendable, CaseIterable, Identifiable {
    case none
    case beforeMeal
    case withMeal
    case afterMeal
    case fasting
    case bedtime

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: "Egal"
        case .beforeMeal: "Vor dem Essen"
        case .withMeal: "Zum Essen"
        case .afterMeal: "Nach dem Essen"
        case .fasting: "Nüchtern"
        case .bedtime: "Vor dem Schlafen"
        }
    }

    /// Kurzform für Zeilen und Mitteilungen, `nil` bei „egal“.
    public var hint: String? {
        switch self {
        case .none: nil
        case .beforeMeal: "vor dem Essen"
        case .withMeal: "zum Essen"
        case .afterMeal: "nach dem Essen"
        case .fasting: "nüchtern"
        case .bedtime: "vor dem Schlafen"
        }
    }
}

/// Wie an eine Einnahme erinnert wird.
public enum ReminderStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Keine Erinnerung.
    case none
    /// Mitteilung mit „Genommen“, „In 10 Min.“, „Auslassen“.
    case notification
    /// Wecker (AlarmKit), klingelt auch im Stumm- und Fokusmodus.
    case alarm

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: "Keine"
        case .notification: "Mitteilung"
        case .alarm: "Wecker"
        }
    }
}

/// Status eines Eintrags im Einnahme-Protokoll.
public enum DoseStatus: String, Codable, Sendable, CaseIterable {
    case taken
    case skipped
}

/// Mengen in deutscher Schreibweise: „½“, „1½“, „0,3“.
public enum DoseAmount {
    public static func format(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "0" }
        let whole = value.rounded(.down)
        let fraction = value - whole
        let fractionSymbol: String?
        switch fraction {
        case let f where abs(f) < 0.001: fractionSymbol = ""
        case let f where abs(f - 0.25) < 0.001: fractionSymbol = "¼"
        case let f where abs(f - 0.5) < 0.001: fractionSymbol = "½"
        case let f where abs(f - 0.75) < 0.001: fractionSymbol = "¾"
        default: fractionSymbol = nil
        }
        if let fractionSymbol {
            if whole == 0 { return fractionSymbol }
            return "\(Int(whole))\(fractionSymbol)"
        }
        // Höchstens zwei Nachkommastellen, Komma statt Punkt.
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text.replacingOccurrences(of: ".", with: ",")
    }

    /// Vorrat ohne Bruchzeichen: „28“, „27,5“.
    public static func formatStock(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        var text = String(format: "%.2f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        return text.replacingOccurrences(of: ".", with: ",")
    }
}
