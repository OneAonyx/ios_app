import Foundation

// MARK: - Mahlzeiten

public enum MealType: String, Codable, Sendable, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .breakfast: "Frühstück"
        case .lunch: "Mittagessen"
        case .dinner: "Abendessen"
        case .snack: "Snack"
        }
    }

    public var symbol: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch: "sun.max.fill"
        case .dinner: "moon.stars.fill"
        case .snack: "carrot.fill"
        }
    }

    /// Typische Uhrzeit (für neue Einträge in der Vergangenheit).
    public var defaultHour: Int {
        switch self {
        case .breakfast: 8
        case .lunch: 12
        case .dinner: 19
        case .snack: 16
        }
    }

    /// Passende Mahlzeit zur Uhrzeit.
    public static func suggested(for date: Date, calendar: Calendar) -> MealType {
        switch calendar.component(.hour, from: date) {
        case 4..<11: .breakfast
        case 11..<15: .lunch
        case 17..<22: .dinner
        default: .snack
        }
    }
}

/// Wie frisch das Essen war. Reste und Aufgewärmtes enthalten mehr Histamin.
public enum Freshness: String, Codable, Sendable, CaseIterable, Identifiable {
    case fresh, leftover, reheated

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fresh: "Frisch zubereitet"
        case .leftover: "Reste"
        case .reheated: "Aufgewärmt"
        }
    }

    public var shortTitle: String {
        switch self {
        case .fresh: "frisch"
        case .leftover: "Reste"
        case .reheated: "aufgewärmt"
        }
    }

    public var symbol: String {
        switch self {
        case .fresh: "leaf.fill"
        case .leftover: "refrigerator.fill"
        case .reheated: "flame.fill"
        }
    }
}

public enum MealPlace: String, Codable, Sendable, CaseIterable, Identifiable {
    case home, out

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .home: "Zuhause"
        case .out: "Auswärts"
        }
    }

    public var symbol: String {
        switch self {
        case .home: "house.fill"
        case .out: "fork.knife.circle.fill"
        }
    }
}

/// Ein Lebensmittel in einer Mahlzeit, wie es in die Berechnungen eingeht.
public struct MealItemFact: Sendable, Hashable {
    public var foodID: String
    public var name: String
    public var grams: Double
    /// Bewertung inkl. eigener Einschätzung.
    public var score: HistamineScore
    public var flags: [HistamineFlag]
    /// Eiweiß g/100 g.
    public var proteinPer100: Double
    public var kcalPer100: Double

    public init(
        foodID: String, name: String, grams: Double, score: HistamineScore, flags: [HistamineFlag] = [],
        proteinPer100: Double = 0, kcalPer100: Double = 0
    ) {
        self.foodID = foodID
        self.name = name
        self.grams = grams
        self.score = score
        self.flags = flags
        self.proteinPer100 = proteinPer100
        self.kcalPer100 = kcalPer100
    }

    public var protein: Double { proteinPer100 * grams / 100 }
    public var kcal: Double { kcalPer100 * grams / 100 }
}

public struct MealFact: Sendable, Hashable {
    public var id: String
    public var date: Date
    public var type: MealType
    public var freshness: Freshness
    public var place: MealPlace
    public var items: [MealItemFact]

    public init(id: String, date: Date, type: MealType, freshness: Freshness = .fresh, place: MealPlace = .home, items: [MealItemFact]) {
        self.id = id
        self.date = date
        self.type = type
        self.freshness = freshness
        self.place = place
        self.items = items
    }

    public var protein: Double { items.reduce(0) { $0 + $1.protein } }
    public var kcal: Double { items.reduce(0) { $0 + $1.kcal } }
    public var worstScore: HistamineScore? { items.map(\.score).max() }
}

// MARK: - Tageslast

/// Grobe Histamin-Tageslast aus den Mahlzeiten. Nur eine Orientierung: Wie viel Histamin
/// tatsächlich drin war, hängt von Frische, Lagerung und Zubereitung ab.
public struct HistamineLoad: Sendable, Hashable {
    public enum Level: String, Sendable, CaseIterable {
        case calm, elevated, high

        public var title: String {
            switch self {
            case .calm: "ruhig"
            case .elevated: "erhöht"
            case .high: "hoch"
            }
        }

        public var symbol: String {
            switch self {
            case .calm: "leaf.fill"
            case .elevated: "exclamationmark.circle.fill"
            case .high: "exclamationmark.triangle.fill"
            }
        }

        public var colorName: String {
            switch self {
            case .calm: "green"
            case .elevated: "orange"
            case .high: "red"
            }
        }
    }

    /// Ein Beitrag zur Tageslast.
    public struct Contributor: Sendable, Hashable, Identifiable {
        public var name: String
        public var points: Double
        public var id: String { name }
    }

    public var points: Double
    public var contributors: [Contributor]

    /// Ab hier „erhöht“ bzw. „hoch“.
    public static let elevatedFrom = 4.0
    public static let highFrom = 10.0
    /// Für Balken: bei diesem Wert ist der Balken voll.
    public static let scaleMax = 15.0

    public var level: Level {
        if points >= Self.highFrom { return .high }
        if points >= Self.elevatedFrom { return .elevated }
        return .calm
    }

    /// 0…1 für Balken und Ringe.
    public var fraction: Double { min(1, points / Self.scaleMax) }

    /// Punkte je Bewertung: nicht linear, damit „3“ deutlich mehr zählt als „1“.
    static func weight(_ score: HistamineScore) -> Double {
        switch score {
        case .good: 0
        case .moderate: 1
        case .poor: 3
        case .bad: 6
        }
    }

    /// Mengenfaktor: 100 g = 1, mindestens ¼, höchstens 3.
    static func portionFactor(grams: Double) -> Double {
        min(3, max(0.25, grams / 100))
    }

    public static func compute(_ meals: [MealFact]) -> HistamineLoad {
        var byName: [String: Double] = [:]
        var total = 0.0
        for meal in meals {
            let multiplier: Double
            var surcharge = 0.0
            switch meal.freshness {
            case .fresh: multiplier = 1
            case .leftover: multiplier = 1.5; surcharge = 1
            case .reheated: multiplier = 1.5; surcharge = 1.5
            }
            if meal.place == .out { surcharge += 1 }
            for item in meal.items {
                let points = weight(item.score) * portionFactor(grams: item.grams) * multiplier
                guard points > 0 else { continue }
                byName[item.name, default: 0] += points
                total += points
            }
            if surcharge > 0, !meal.items.isEmpty {
                let label = meal.place == .out && meal.freshness == .fresh ? "Auswärts gegessen" : "\(meal.freshness.title)"
                byName[label, default: 0] += surcharge
                total += surcharge
            }
        }
        let contributors = byName
            .map { Contributor(name: $0.key, points: $0.value) }
            .sorted { $0.points > $1.points }
        return HistamineLoad(points: total, contributors: contributors)
    }
}

// MARK: - Ziele

public enum NutritionTargets {
    /// Eiweiß-Ziel für Muskelaufbau: 1,6–2,2 g je kg, Standard 1,8.
    public static let proteinRange: ClosedRange<Double> = 1.6...2.2
    public static let defaultProteinPerKg = 1.8
    public static let defaultWaterML = 2500
    public static let defaultBodyweight = 80.0
    /// Ein Glas Wasser.
    public static let glassML = 250

    public static func proteinTarget(bodyweight: Double?, perKg: Double = defaultProteinPerKg) -> Double {
        let weight = bodyweight.flatMap { $0 > 30 ? $0 : nil } ?? defaultBodyweight
        return (weight * min(max(perKg, 1.0), 3.0)).rounded()
    }
}

/// Alles zu einem Tag: Tageslast, Eiweiß, Kalorien, Wasser.
public struct NutritionDay: Sendable, Hashable {
    public var day: Date
    public var meals: [MealFact]
    public var waterML: Int
    public var proteinTarget: Double
    public var waterTarget: Int

    public init(day: Date, meals: [MealFact], waterML: Int, proteinTarget: Double, waterTarget: Int = NutritionTargets.defaultWaterML) {
        self.day = day
        self.meals = meals
        self.waterML = waterML
        self.proteinTarget = proteinTarget
        self.waterTarget = waterTarget
    }

    public var load: HistamineLoad { HistamineLoad.compute(meals) }
    public var protein: Double { meals.reduce(0) { $0 + $1.protein } }
    public var kcal: Double { meals.reduce(0) { $0 + $1.kcal } }

    public var proteinFraction: Double { proteinTarget > 0 ? min(1, protein / proteinTarget) : 0 }
    public var waterFraction: Double { waterTarget > 0 ? min(1, Double(waterML) / Double(waterTarget)) : 0 }

    /// „96 von 150 g“
    public var proteinLabel: String {
        "\(Int(protein.rounded())) von \(Int(proteinTarget.rounded())) g"
    }

    /// „1,5 von 2,5 l“
    public var waterLabel: String {
        "\(Self.liters(waterML)) von \(Self.liters(waterTarget)) l"
    }

    public static func liters(_ ml: Int) -> String {
        WeightFormat.number((Double(ml) / 100).rounded() / 10)
    }
}
