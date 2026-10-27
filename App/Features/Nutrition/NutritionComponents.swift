import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Ziele im Tab „Ernährung“.
enum NutritionRoute: Hashable {
    case lexicon
    case food(String)
    case shopping
    case recipes
    case recipe(String)
    case mealPlan
    case patterns
    case ingredientCheck
    case symptoms
    case settings
}

/// Eine neue Mahlzeit, die der Editor vorbelegt öffnet.
struct MealDraft: Identifiable {
    let id = UUID()
    var type: MealType
    var date: Date
    var items: [MealDraftItem] = []
    var recipeID: String?
    var freshness: Freshness = .fresh
}

/// Lebensmittel einer Kategorie (für Listen mit Abschnitten).
struct FoodGroup: Identifiable {
    let category: FoodCategory
    let foods: [FoodInfo]
    var id: String { category.rawValue }

    static func make(_ groups: [(FoodCategory, [FoodInfo])]) -> [FoodGroup] {
        groups.map { FoodGroup(category: $0.0, foods: $0.1) }
    }
}

struct MealDraftItem: Identifiable, Hashable {
    var id = UUID()
    var foodID: String
    var grams: Double
}

extension HistamineScore {
    var color: Color {
        switch self {
        case .good: .green
        case .moderate: .yellow
        case .poor: .orange
        case .bad: .red
        }
    }

    /// Lesbare Textfarbe (Gelb ist auf hellem Grund zu blass).
    var textColor: Color {
        switch self {
        case .good: .green
        case .moderate: Color(red: 0.72, green: 0.52, blue: 0.0)
        case .poor: .orange
        case .bad: .red
        }
    }
}

extension HistamineLoad.Level {
    var color: Color {
        switch self {
        case .calm: .green
        case .elevated: .orange
        case .high: .red
        }
    }
}

/// Bewertung als Kapsel: Symbol und Zahl, nie nur Farbe.
struct ScoreBadge: View {
    let score: HistamineScore
    var showsTitle = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: score.symbol)
            Text(showsTitle ? score.label : "\(score.rawValue)")
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(score.textColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(score.color.opacity(0.16), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Histamin \(score.label)")
    }
}

/// Eigene Einschätzung als kleines Symbol.
struct ToleranceMark: View {
    let tolerance: Tolerance

    var body: some View {
        if tolerance != .unknown {
            Image(systemName: tolerance.symbol)
                .font(.caption)
                .foregroundStyle(tint)
                .accessibilityLabel(tolerance.title)
        }
    }

    private var tint: Color {
        switch tolerance {
        case .unknown: .secondary
        case .ok: .green
        case .caution: .orange
        case .avoid: .red
        }
    }
}

/// Eine Zeile im Lexikon und in Auswahllisten.
struct FoodRow: View {
    let food: FoodInfo
    var tolerance: Tolerance = .unknown
    var detail: String?

    var body: some View {
        let effective = tolerance.effectiveScore(general: food.score)
        HStack(spacing: Spacing.s) {
            IconBadge(systemImage: food.category.symbol, tint: effective.color, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(food.name)
                        .foregroundStyle(Color.primary)
                    ToleranceMark(tolerance: tolerance)
                }
                Text(detail ?? subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.xs)
            ScoreBadge(score: effective)
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts = [food.brand ?? food.category.title]
        if !food.flags.isEmpty { parts.append(food.flags.map(\.shortTitle).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}

/// Tageslast als Balken mit Stufen.
struct LoadBar: View {
    let load: HistamineLoad

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule()
                    .fill(load.level.color.gradient)
                    .frame(width: max(8, proxy.size.width * load.fraction))
                // Grenzen „erhöht“ und „hoch“.
                ForEach([HistamineLoad.elevatedFrom, HistamineLoad.highFrom], id: \.self) { mark in
                    Rectangle()
                        .fill(Color.primary.opacity(0.25))
                        .frame(width: 1.5, height: 10)
                        .offset(x: proxy.size.width * mark / HistamineLoad.scaleMax)
                }
            }
        }
        .frame(height: 10)
        .accessibilityElement()
        .accessibilityLabel("Histamin-Tageslast \(load.level.title)")
    }
}

/// Kleine Kennzahl mit Ring (Eiweiß, Wasser).
struct NutritionRing: View {
    let title: String
    let value: String
    let fraction: Double
    let tint: Color
    let symbol: String

    var body: some View {
        HStack(spacing: Spacing.s) {
            ProgressRing(fraction: fraction, tint: tint, lineWidth: 6) {
                Image(systemName: symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Eiweiß und Wasser nebeneinander, bei sehr großer Schrift untereinander.
struct NutritionRings: View {
    let day: NutritionDay

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.s))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Spacing.s))
        layout {
            NutritionRing(title: "Eiweiß", value: day.proteinLabel, fraction: day.proteinFraction, tint: ModuleAccent.training, symbol: "bolt.fill")
            NutritionRing(title: "Wasser", value: day.waterLabel, fraction: day.waterFraction, tint: .cyan, symbol: "drop.fill")
        }
    }
}

/// „Vor allem: Tomate, Reste“ bzw. bei ruhiger Last „Kleine Beiträge: Mandeln“.
func loadContributorsText(_ load: HistamineLoad) -> String {
    let names = load.contributors.prefix(3).map(\.name).joined(separator: ", ")
    return (load.level == .calm ? "Kleine Beiträge: " : "Vor allem: ") + names
}

/// Hinweis, dass Bewertungen nur Orientierung sind.
struct NutritionDisclaimer: View {
    var body: some View {
        Text("Bewertungen sind eine Orientierung und ersetzen keine ärztliche oder Ernährungsberatung. Deine eigene Einschätzung hat Vorrang.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension Date {
    /// „Heute“, „Gestern“, „Mo, 26. Okt.“
    func nutritionDayLabel(calendar: Calendar = AppModel.calendar, now: Date = .now) -> String {
        if calendar.isDate(self, inSameDayAs: now) { return "Heute" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(self, inSameDayAs: yesterday) {
            return "Gestern"
        }
        return GermanCalendar.shortDate(self, calendar: calendar)
    }
}
