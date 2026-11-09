import Foundation

/// Wiederholbarer Wochen-Essensplan: je Wochentag und Mahlzeit ein bis drei Rezepte zur Wahl.
/// Die erste Option ist der Vorschlag, die anderen sind Alternativen.
public struct MealPlanTemplate: Codable, Sendable, Hashable, Identifiable {
    public struct Day: Codable, Sendable, Hashable, Identifiable {
        /// 1 = Sonntag … 7 = Samstag (wie `Calendar`).
        public var weekday: Int
        /// Mahlzeit → Rezept-IDs, erste = Vorschlag.
        public var meals: [String: [String]]

        public var id: Int { weekday }

        public init(weekday: Int, meals: [MealType: [String]]) {
            self.weekday = weekday
            self.meals = Dictionary(uniqueKeysWithValues: meals.map { ($0.key.rawValue, $0.value) })
        }

        public func options(for meal: MealType) -> [String] {
            meals[meal.rawValue] ?? []
        }

        /// „Montag“
        public var title: String {
            GermanCalendar.longWeekdays[(weekday - 1) % 7]
        }
    }

    public var id: String
    public var title: String
    public var summary: String
    public var days: [Day]
    public var guidelines: [String]

    public init(id: String, title: String, summary: String = "", days: [Day], guidelines: [String] = []) {
        self.id = id
        self.title = title
        self.summary = summary
        self.days = days
        self.guidelines = guidelines
    }

    /// Montag zuerst.
    public var orderedDays: [Day] {
        days.sorted { ($0.weekday + 5) % 7 < ($1.weekday + 5) % 7 }
    }

    public func day(weekday: Int) -> Day? {
        days.first { $0.weekday == weekday }
    }

    /// Alle Rezepte, die im Plan vorkommen.
    public var recipeIDs: Set<String> {
        Set(days.flatMap { $0.meals.values.flatMap { $0 } })
    }

    /// Einträge für eine Woche ab `weekStart` (Montag): Tag, Mahlzeit, Rezept.
    /// `choices` überschreibt den Vorschlag („2-lunch“ → Rezept-ID, Schlüssel aus `choiceKey`).
    public func entries(weekStart: Date, choices: [String: String] = [:], calendar: Calendar) -> [(day: Date, meal: MealType, recipeID: String)] {
        var result: [(Date, MealType, String)] = []
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: weekStart)) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            guard let plan = self.day(weekday: weekday) else { continue }
            for meal in MealType.allCases {
                let options = plan.options(for: meal)
                guard let first = options.first else { continue }
                let chosen = choices[Self.choiceKey(weekday: weekday, meal: meal)].flatMap { options.contains($0) ? $0 : nil } ?? first
                result.append((day, meal, chosen))
            }
        }
        return result
    }

    public static func choiceKey(weekday: Int, meal: MealType) -> String {
        "\(weekday)-\(meal.rawValue)"
    }

    /// Prüft, dass alle Rezepte existieren und jeder Tag jede Mahlzeit hat.
    public func validationIssues(recipes: RecipeCatalog) -> [String] {
        var issues: [String] = []
        if Set(days.map(\.weekday)) != Set(1...7) { issues.append("Nicht alle 7 Wochentage") }
        for day in days {
            for meal in MealType.allCases where day.options(for: meal).isEmpty {
                issues.append("\(day.title): \(meal.title) fehlt")
            }
            for id in day.meals.values.flatMap({ $0 }) where recipes.recipe(id: id) == nil {
                issues.append("\(day.title): Rezept \(id) fehlt")
            }
        }
        return issues
    }

    public static func decode(_ data: Data) throws -> MealPlanTemplate {
        try JSONDecoder().decode(MealPlanTemplate.self, from: data)
    }

    /// Der mitgelieferte Wochenplan (`mealplan-week.de.json`).
    public static func bundledWeek() -> MealPlanTemplate? {
        guard let url = Bundle.module.url(forResource: "mealplan-week.de", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? decode(data)
    }
}
