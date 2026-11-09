import Foundation

/// Worauf du empfindlich reagierst. Die App bewertet Lebensmittel nur nach den aktiven Profilen.
public enum Sensitivity: String, Codable, Sendable, CaseIterable, Identifiable {
    case lactose
    case fructose
    case fat
    case histamine

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .lactose: "Laktose"
        case .fructose: "Fruktose und Sorbit"
        case .fat: "Fett und große Mengen"
        case .histamine: "Histamin"
        }
    }

    public var shortTitle: String {
        switch self {
        case .lactose: "Laktose"
        case .fructose: "Fruktose"
        case .fat: "Fett"
        case .histamine: "Histamin"
        }
    }

    public var detail: String {
        switch self {
        case .lactose:
            "Milchzucker in Milch, Quark, Joghurt, Sahne und Fertigprodukten. Gereifter Hartkäse und Butter enthalten kaum welchen."
        case .fructose:
            "Fruchtzucker im Überschuss (Apfel, Birne, Mango, Honig, Säfte, Trockenobst) und Zuckeralkohole wie Sorbit (E420)."
        case .fat:
            "Sehr fettige Speisen und große Portionen, z. B. Chips, Frittiertes, Wagyu, Sahnesaucen. Bewertet nach Fett je Portion und Größe der Mahlzeit."
        case .histamine:
            "Gereiftes, Fermentiertes, Reste und Liberatoren wie Tomate oder Zitrus."
        }
    }

    public var symbol: String {
        switch self {
        case .lactose: "drop.fill"
        case .fructose: "leaf.fill"
        case .fat: "flame.fill"
        case .histamine: "allergens"
        }
    }
}

/// Die aktiven Profile. Gespeichert als „lactose,fructose,fat“, „none“ für keines.
public struct SensitivityProfile: Sendable, Hashable {
    public var active: Set<Sensitivity>

    public init(active: Set<Sensitivity>) {
        self.active = active
    }

    /// Standard: Laktose, Fruktose, Fett und Mengen.
    public static let standard = SensitivityProfile(active: [.lactose, .fructose, .fat])

    public func contains(_ sensitivity: Sensitivity) -> Bool { active.contains(sensitivity) }

    /// In fester Reihenfolge.
    public var ordered: [Sensitivity] { Sensitivity.allCases.filter(active.contains) }

    public var encoded: String {
        active.isEmpty ? "none" : ordered.map(\.rawValue).joined(separator: ",")
    }

    /// Leer oder unbekannt → Standard.
    public static func decode(_ text: String?) -> SensitivityProfile {
        guard let text, !text.isEmpty else { return .standard }
        if text == "none" { return SensitivityProfile(active: []) }
        let parsed = Set(text.split(separator: ",").compactMap { Sensitivity(rawValue: String($0)) })
        return parsed.isEmpty ? .standard : SensitivityProfile(active: parsed)
    }

    /// „Laktose, Fruktose, Fett“
    public var summary: String {
        active.isEmpty ? "Keine" : ordered.map(\.shortTitle).joined(separator: ", ")
    }

    /// Bewertung für eine Menge: die schlechteste der aktiven Profile.
    public func score(_ ratings: FoodRatings, grams: Double) -> FoodScore {
        ordered.map { ratings.score(for: $0, grams: grams) }.max() ?? .good
    }

    /// Markierungen, die zu den aktiven Profilen passen.
    public func flags(_ ratings: FoodRatings, grams: Double) -> [FoodFlag] {
        ratings.flags(grams: grams).filter { active.contains($0.sensitivity) }
    }
}

/// Bewertungen eines Lebensmittels für alle Profile.
public struct FoodRatings: Sendable, Hashable {
    public var histamine: FoodScore
    public var histamineFlags: [FoodFlag]
    /// Laktose in g je 100 g, `nil` = unbekannt (zählt als laktosefrei).
    public var lactose: Double?
    /// Fruktose-Überschuss und Zuckeralkohole, 0–3 für eine übliche Portion.
    public var fructose: FoodScore
    /// Enthält Sorbit oder andere Zuckeralkohole.
    public var sorbitol: Bool
    /// Fett in g je 100 g, `nil` = unbekannt.
    public var fat: Double?

    public init(
        histamine: FoodScore = .good, histamineFlags: [FoodFlag] = [], lactose: Double? = nil,
        fructose: FoodScore = .good, sorbitol: Bool = false, fat: Double? = nil
    ) {
        self.histamine = histamine
        self.histamineFlags = histamineFlags
        self.lactose = lactose
        self.fructose = fructose
        self.sorbitol = sorbitol
        self.fat = fat
    }

    /// Aus gespeicherter Bewertung und Markierungen (eigene und gescannte Lebensmittel):
    /// `score` ist die Histamin-Bewertung, LAC/FRU/SOR/FAT stehen für die anderen Profile.
    public static func legacy(score: FoodScore, flags: [FoodFlag]) -> FoodRatings {
        FoodRatings(
            histamine: score,
            histamineFlags: flags.filter { $0.sensitivity == .histamine },
            lactose: flags.contains(.lactose) ? 4.5 : nil,
            fructose: flags.contains(.fructose) ? .poor : (flags.contains(.sorbitol) ? .poor : .good),
            sorbitol: flags.contains(.sorbitol),
            fat: flags.contains(.fatRich) ? 30 : nil
        )
    }

    public func lactoseGrams(_ grams: Double) -> Double { (lactose ?? 0) * grams / 100 }
    public func fatGrams(_ grams: Double) -> Double { (fat ?? 0) * grams / 100 }

    /// Laktose je Menge: bis 0,5 g gilt als laktosefrei, ab 8 g reagieren viele deutlich.
    /// Grundlage: EFSA (2010), bis etwa 12 g auf einmal werden von den meisten vertragen.
    static func lactoseScore(_ grams: Double) -> FoodScore {
        switch grams {
        case ..<0.5: .good
        case ..<3: .moderate
        case ..<8: .poor
        default: .bad
        }
    }

    /// Fett je Menge: ab 15 g viel, ab 25 g sehr viel für eine Portion.
    static func fatScore(_ grams: Double) -> FoodScore {
        switch grams {
        case ..<8: .good
        case ..<15: .moderate
        case ..<25: .poor
        default: .bad
        }
    }

    public func score(for sensitivity: Sensitivity, grams: Double) -> FoodScore {
        switch sensitivity {
        case .lactose:
            return Self.lactoseScore(lactoseGrams(grams))
        case .fat:
            return Self.fatScore(fatGrams(grams))
        case .fructose:
            return fructose
        case .histamine:
            return histamine
        }
    }

    /// Alle Markierungen, auch die anderer Profile.
    public func flags(grams: Double) -> [FoodFlag] {
        var result = histamineFlags
        if lactoseGrams(grams) >= 0.5 { result.append(.lactose) }
        if fructose >= .moderate { result.append(.fructose) }
        if sorbitol { result.append(.sorbitol) }
        if fatGrams(grams) >= 15 || (fat ?? 0) >= 25 { result.append(.fatRich) }
        return result
    }
}
