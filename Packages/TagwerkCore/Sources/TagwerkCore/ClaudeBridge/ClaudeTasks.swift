import Foundation

/// Wofür Orbit Claude fragt. Jede Aufgabe hat ein festes Antwortformat.
public enum ClaudeTask: String, Codable, Sendable, CaseIterable, Identifiable {
    case trainingPlan
    case weeklyReview
    case food
    case recipes
    case patterns

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .trainingPlan: "Trainingsplan anpassen"
        case .weeklyReview: "Wochenrückblick besprechen"
        case .food: "Lebensmittel bewerten"
        case .recipes: "Rezeptideen"
        case .patterns: "Muster deuten"
        }
    }

    public var subtitle: String {
        switch self {
        case .trainingPlan: "Claude schlägt einen angepassten Plan vor. Du siehst die Änderungen, bevor sie übernommen werden."
        case .weeklyReview: "Kennzahlen deiner Woche mit Tipps für die nächste."
        case .food: "Für Lebensmittel, die nicht im Lexikon stehen."
        case .recipes: "Histaminarme, eiweißreiche Rezepte nach deinen Wünschen."
        case .patterns: "Claude ordnet die gefundenen Muster ein und schlägt Tests vor."
        }
    }

    public var symbol: String {
        switch self {
        case .trainingPlan: "dumbbell"
        case .weeklyReview: "calendar.badge.checkmark"
        case .food: "carrot"
        case .recipes: "book"
        case .patterns: "magnifyingglass.circle"
        }
    }

    /// Erwartetes JSON-Format der Antwort.
    public var format: String {
        switch self {
        case .trainingPlan: "orbit.plan.v1"
        case .weeklyReview, .patterns: ClaudeTextAnswer.format
        case .food: ClaudeFoodAnswer.format
        case .recipes: ClaudeRecipesAnswer.format
        }
    }
}

/// Eine fertige Anfrage: Text für Claude und eine Liste, welche Daten darin stehen.
public struct ClaudePrompt: Sendable, Hashable {
    public var task: ClaudeTask
    /// Kurze Kennung, damit Orbit Antworten der richtigen Anfrage zuordnet.
    public var ref: String
    public var text: String
    /// Für die Vorschau „Diese Daten gehen an Claude“.
    public var includedData: [String]

    public init(task: ClaudeTask, ref: String, text: String, includedData: [String]) {
        self.task = task
        self.ref = ref
        self.text = text
        self.includedData = includedData
    }
}

// MARK: - Anfragen

/// Baut die Anfragen. Persönliche Angaben (Name, Notizen) gehen nie mit.
public enum ClaudePromptBuilder {
    static let intro = "Du hilfst in der iPhone-App „Orbit“ (Alltag, Training, Ernährung bei Histaminintoleranz). Antworte auf Deutsch, sachlich und konkret."

    static func outputRule(format: String, ref: String, example: String) -> String {
        """
        ANTWORTFORMAT: Antworte ausschließlich mit einem einzigen JSON-Objekt, ohne Text davor oder danach. \
        Es muss "format":"\(format)" und "ref":"\(ref)" enthalten. Beispiel für den Aufbau:
        \(example)
        """
    }

    public struct TrainingContext: Sendable {
        public var goal: String
        public var experience: String
        public var sessionsPerWeek: Int
        public var planJSON: String
        public var recentSets: [String]
        public var stagnating: [String]
        public var weeklyVolume: [String]
        public var wish: String
        public var exerciseNames: [String]
        /// „1,83 m, 82,4 kg“, leer ohne Angaben.
        public var body: String

        public init(goal: String, experience: String, sessionsPerWeek: Int, planJSON: String, recentSets: [String], stagnating: [String], weeklyVolume: [String], wish: String, exerciseNames: [String], body: String = "") {
            self.goal = goal
            self.experience = experience
            self.sessionsPerWeek = sessionsPerWeek
            self.planJSON = planJSON
            self.recentSets = recentSets
            self.stagnating = stagnating
            self.weeklyVolume = weeklyVolume
            self.wish = wish
            self.exerciseNames = exerciseNames
            self.body = body
        }
    }

    public static func trainingPlan(_ context: TrainingContext, ref: String) -> ClaudePrompt {
        let example = #"{"format":"orbit.plan.v1","ref":"\#(ref)","name":"Oberkörper 4er","mesoWeeks":6,"days":[{"name":"Push","shortName":"A","focus":"Brust","exercises":[{"name":"Bankdrücken (Langhantel)","sets":4,"repMin":6,"repMax":8,"rir":2,"restSec":150,"note":""}]}]}"#
        var parts = [
            intro,
            "AUFGABE: Passe meinen Trainingsplan an. Ziel: \(context.goal). Erfahrung: \(context.experience). Trainingstage pro Woche: \(context.sessionsPerWeek).",
            "WUNSCH: " + (context.wish.isEmpty ? "Prüfe den Plan und verbessere, was sinnvoll ist (Volumen je Muskel 10–20 Sätze, Erholung, Abwechslung)." : context.wish),
            "AKTUELLER PLAN (JSON):\n\(context.planJSON)",
        ]
        if !context.body.isEmpty { parts.insert("KÖRPER: \(context.body)", at: 2) }
        if !context.recentSets.isEmpty { parts.append("LETZTE TOP-SÄTZE:\n" + context.recentSets.map { "- \($0)" }.joined(separator: "\n")) }
        if !context.stagnating.isEmpty { parts.append("STAGNIERT: " + context.stagnating.joined(separator: ", ")) }
        if !context.weeklyVolume.isEmpty { parts.append("SÄTZE JE MUSKEL DIESE WOCHE: " + context.weeklyVolume.joined(separator: ", ")) }
        parts.append("ÜBUNGEN IN DER APP (Namen bitte genau so verwenden, andere nur wenn nötig):\n" + context.exerciseNames.joined(separator: "; "))
        parts.append("Gib den vollständigen neuen Plan zurück, nicht nur die Änderungen. Begründe Änderungen kurz im Feld \"note\" der jeweiligen Übung.")
        parts.append(outputRule(format: ClaudeTask.trainingPlan.format, ref: ref, example: example))
        var data = ["Ziel, Erfahrung, Trainingstage", "Aktueller Plan (Tage, Übungen, Sätze)"]
        if !context.body.isEmpty { data.append("Größe und Gewicht") }
        if !context.recentSets.isEmpty { data.append("Top-Sätze der letzten Wochen (\(context.recentSets.count) Übungen)") }
        if !context.stagnating.isEmpty { data.append("Stagnierende Übungen") }
        if !context.weeklyVolume.isEmpty { data.append("Sätze je Muskel") }
        if !context.wish.isEmpty { data.append("Dein Wunsch") }
        return ClaudePrompt(task: .trainingPlan, ref: ref, text: parts.joined(separator: "\n\n"), includedData: data)
    }

    public static func weeklyReview(_ review: WeeklyReview, wish: String, ref: String) -> ClaudePrompt {
        let example = #"{"format":"orbit.text.v1","ref":"\#(ref)","title":"Deine Woche","text":"**Gut gelaufen:** …\n\n**Für nächste Woche:**\n- …"}"#
        let parts = [
            intro,
            "AUFGABE: Bespreche meine Woche. Was lief gut, was fällt auf, und 3 konkrete, machbare Tipps für die nächste Woche. Höchstens 200 Wörter, Markdown erlaubt (fett, Listen). Keine Diagnosen.",
            wish.isEmpty ? nil : "WUNSCH: \(wish)",
            "KENNZAHLEN:\n\(review.plainText)",
            outputRule(format: ClaudeTextAnswer.format, ref: ref, example: example),
        ]
        var data = review.sections.map { "Kennzahlen \($0.title)" }
        if !wish.isEmpty { data.append("Dein Wunsch") }
        return ClaudePrompt(task: .weeklyReview, ref: ref, text: parts.compactMap { $0 }.joined(separator: "\n\n"), includedData: data)
    }

    public static func food(name: String, brand: String? = nil, ingredients: String? = nil, ref: String) -> ClaudePrompt {
        let categories = FoodCategory.allCases.map(\.rawValue).joined(separator: ", ")
        let example = #"{"format":"orbit.food.v1","ref":"\#(ref)","name":"Quinoa-Riegel","category":"sweets","score":1,"flags":["L"],"hint":"Enthält Cashew.","protein":8,"kcal":420,"portion":40}"#
        let parts = [
            intro,
            "AUFGABE: Bewerte dieses Lebensmittel für Menschen mit Histaminintoleranz auf der in DACH üblichen Skala: 0 gut verträglich, 1 mäßig, 2 schlecht, 3 sehr schlecht.",
            "LEBENSMITTEL: \(name)" + (brand.map { " (Marke: \($0))" } ?? ""),
            ingredients.map { "ZUTATEN: \($0)" },
            "Markierungen in \"flags\": H = histaminreich/verderblich, A = andere biogene Amine, L = Histaminliberator, B = hemmt den Abbau (DAO). \"category\" ist einer von: \(categories). \"protein\" und \"kcal\" je 100 g, \"portion\" übliche Portion in g. \"hint\" ein kurzer Satz mit dem wichtigsten Grund oder Tipp.",
            outputRule(format: ClaudeFoodAnswer.format, ref: ref, example: example),
        ]
        var data = ["Name des Lebensmittels"]
        if brand != nil { data.append("Marke") }
        if ingredients != nil { data.append("Zutatenliste") }
        return ClaudePrompt(task: .food, ref: ref, text: parts.compactMap { $0 }.joined(separator: "\n\n"), includedData: data)
    }

    public struct RecipeContext: Sendable {
        public var wish: String
        public var count: Int
        public var servings: Int
        public var proteinPerServing: Int
        public var tolerated: [String]
        public var avoid: [String]

        public init(wish: String, count: Int = 3, servings: Int = 2, proteinPerServing: Int = 40, tolerated: [String], avoid: [String]) {
            self.wish = wish
            self.count = count
            self.servings = servings
            self.proteinPerServing = proteinPerServing
            self.tolerated = tolerated
            self.avoid = avoid
        }
    }

    public static func recipes(_ context: RecipeContext, ref: String) -> ClaudePrompt {
        let example = #"{"format":"orbit.recipes.v1","ref":"\#(ref)","recipes":[{"title":"Hähnchen mit Reis","summary":"Schnell und mild.","servings":2,"minutes":25,"tags":["Abend"],"ingredients":[{"name":"Hähnchenbrust","grams":300},{"name":"Olivenöl","grams":10,"amount":"1 EL"}],"steps":["Reis kochen.","Hähnchen braten."]}]}"#
        let parts = [
            intro,
            "AUFGABE: Schlage \(context.count) Rezepte vor, histaminarm (nur frische Zutaten, kein Essig außer Branntweinessig, keine gereiften Käse, keine Tomate, kein Spinat, keine Avocado, kein Alkohol, keine Sojasauce) und eiweißreich (etwa \(context.proteinPerServing) g Eiweiß pro Portion), für \(context.servings) Portionen. Mengen in Gramm für das ganze Rezept.",
            context.wish.isEmpty ? nil : "WUNSCH: \(context.wish)",
            context.tolerated.isEmpty ? nil : "VERTRAGE ICH GUT: " + context.tolerated.joined(separator: ", "),
            context.avoid.isEmpty ? nil : "MEIDE ICH: " + context.avoid.joined(separator: ", "),
            "Verwende übliche deutsche Zutatennamen (z. B. „Hähnchenbrust“, „Magerquark“, „Zucchini“). Erlaubte Stichworte für \"tags\": Frühstück, Mittag, Abend, Snack, Süß, Vegetarisch, Fisch, Suppe, Meal Prep.",
            outputRule(format: ClaudeRecipesAnswer.format, ref: ref, example: example),
        ]
        var data = ["Anzahl Rezepte, Portionen, Eiweißziel"]
        if !context.wish.isEmpty { data.append("Dein Wunsch") }
        if !context.tolerated.isEmpty { data.append("Gut verträgliche Lebensmittel (\(context.tolerated.count))") }
        if !context.avoid.isEmpty { data.append("Gemiedene Lebensmittel (\(context.avoid.count))") }
        return ClaudePrompt(task: .recipes, ref: ref, text: parts.compactMap { $0 }.joined(separator: "\n\n"), includedData: data)
    }

    public static func patterns(
        _ report: TriggerReport, symptomSummary: [String], checkIns: CheckInAverages?, avoid: [String], wish: String, ref: String
    ) -> ClaudePrompt {
        let example = #"{"format":"orbit.text.v1","ref":"\#(ref)","title":"Mögliche Auslöser","text":"**Am auffälligsten:** …\n\n**So kannst du es testen:**\n1. …"}"#
        let findings = report.findings.isEmpty
            ? "Keine auffälligen Muster."
            : report.findings.map { finding in
                "- \(finding.name): \(finding.sentence), \(finding.comparison)" + (finding.companionText.map { "; \($0)" } ?? "")
            }.joined(separator: "\n")
        var averages: String?
        if let checkIns, checkIns.days > 0 {
            averages = "BEFINDEN (Ø 1–5): Schlaf \(CheckInAverages.format(checkIns.sleep)), Energie \(CheckInAverages.format(checkIns.energy)), Stimmung \(CheckInAverages.format(checkIns.mood)), Stress \(CheckInAverages.format(checkIns.stress))"
        }
        let parts = [
            intro,
            "AUFGABE: Ordne diese Auswertung meines Ernährungs- und Beschwerdetagebuchs ein (Histaminintoleranz). Was ist am ehesten ein Auslöser, was eher Zufall? Schlage einen einfachen Plan vor, wie ich Verdächtiges gezielt teste (z. B. Auslassen und Wiedereinführen). Höchstens 250 Wörter, Markdown erlaubt. Keine Diagnose, weise bei starken Beschwerden auf ärztlichen Rat hin.",
            wish.isEmpty ? nil : "FRAGE: \(wish)",
            "DATEN: \(report.mealCount) Mahlzeiten, \(report.symptomCount) Beschwerden.",
            "BESCHWERDEN: " + (symptomSummary.isEmpty ? "–" : symptomSummary.joined(separator: ", ")),
            "AUFFÄLLIG:\n\(findings)",
            averages,
            avoid.isEmpty ? nil : "MEIDE ICH SCHON: " + avoid.joined(separator: ", "),
            outputRule(format: ClaudeTextAnswer.format, ref: ref, example: example),
        ]
        var data = ["Anzahl Mahlzeiten und Beschwerden", "Auffällige Lebensmittel und Umstände", "Häufigste Beschwerden"]
        if averages != nil { data.append("Durchschnitte aus den Check-ins") }
        if !avoid.isEmpty { data.append("Gemiedene Lebensmittel") }
        if !wish.isEmpty { data.append("Deine Frage") }
        return ClaudePrompt(task: .patterns, ref: ref, text: parts.compactMap { $0 }.joined(separator: "\n\n"), includedData: data)
    }

    /// 6 Zeichen, gut lesbar.
    public static func makeRef() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6))
    }
}

// MARK: - Antworten

public struct ClaudeTextAnswer: Codable, Sendable, Hashable {
    public static let format = "orbit.text.v1"
    public var format: String
    public var ref: String?
    public var title: String?
    public var text: String
}

public struct ClaudeFoodAnswer: Codable, Sendable, Hashable {
    public static let format = "orbit.food.v1"
    public var format: String
    public var ref: String?
    public var name: String
    public var category: String?
    public var score: Int
    public var flags: [String]?
    public var hint: String?
    public var protein: Double?
    public var kcal: Double?
    public var portion: Double?
}

public struct ClaudeRecipesAnswer: Codable, Sendable, Hashable {
    public static let format = "orbit.recipes.v1"

    public struct Ingredient: Codable, Sendable, Hashable {
        public var name: String
        public var grams: Double
        public var amount: String?
    }

    public struct Recipe: Codable, Sendable, Hashable {
        public var title: String
        public var summary: String?
        public var servings: Int?
        public var minutes: Int?
        public var tags: [String]?
        public var ingredients: [Ingredient]
        public var steps: [String]
    }

    public var format: String
    public var ref: String?
    public var recipes: [Recipe]
}

/// Ausgelesene Antwort.
public enum ClaudeAnswer: Sendable {
    case plan(PlanTemplate)
    case text(title: String, body: String)
    case food(FoodInfo)
    case recipes([RecipeInfo], newFoods: [FoodInfo])
}

public enum ClaudeAnswerError: Error, Equatable, LocalizedError {
    case noJSON
    case wrongFormat(String)
    case empty

    public var errorDescription: String? {
        switch self {
        case .noJSON: "In der Antwort war kein passendes JSON. Versuche es noch einmal."
        case let .wrongFormat(format): "Claude hat im falschen Format geantwortet („\(format)“)."
        case .empty: "Die Antwort war leer."
        }
    }
}

public enum ClaudeAnswerParser {
    public static func parse(_ response: String, task: ClaudeTask, foods: FoodCatalog) throws -> ClaudeAnswer {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ClaudeAnswerError.empty }
        switch task {
        case .trainingPlan:
            do {
                return .plan(try PlanImporter.parse(trimmed))
            } catch PlanImportError.wrongFormat(let format) {
                throw ClaudeAnswerError.wrongFormat(format)
            } catch {
                throw ClaudeAnswerError.noJSON
            }
        case .weeklyReview, .patterns:
            if let answer = ClaudeResponseExtractor.decodeFirst(ClaudeTextAnswer.self, from: trimmed), !answer.text.isEmpty {
                return .text(title: answer.title ?? task.title, body: answer.text)
            }
            // Ohne JSON: freien Text übernehmen (Claude hat dann einfach geantwortet).
            guard !trimmed.hasPrefix("{") else { throw ClaudeAnswerError.noJSON }
            return .text(title: task.title, body: trimmed)
        case .food:
            guard let answer = ClaudeResponseExtractor.decodeFirst(ClaudeFoodAnswer.self, from: trimmed) else {
                throw ClaudeAnswerError.noJSON
            }
            guard answer.format == ClaudeFoodAnswer.format else { throw ClaudeAnswerError.wrongFormat(answer.format) }
            return .food(foodInfo(answer, catalog: foods))
        case .recipes:
            guard let answer = ClaudeResponseExtractor.decodeFirst(ClaudeRecipesAnswer.self, from: trimmed) else {
                throw ClaudeAnswerError.noJSON
            }
            guard answer.format == ClaudeRecipesAnswer.format else { throw ClaudeAnswerError.wrongFormat(answer.format) }
            guard !answer.recipes.isEmpty else { throw ClaudeAnswerError.empty }
            let resolved = recipes(answer, catalog: foods)
            return .recipes(resolved.recipes, newFoods: resolved.newFoods)
        }
    }

    /// Kennung aus der Antwort (falls vorhanden), um sie der Anfrage zuzuordnen.
    public static func ref(in response: String) -> String? {
        struct Ref: Decodable { let ref: String? }
        return ClaudeResponseExtractor.decodeFirst(Ref.self, from: response)?.ref
    }

    static func foodInfo(_ answer: ClaudeFoodAnswer, catalog: FoodCatalog) -> FoodInfo {
        let base = "custom-" + NameMatcher.normalize(answer.name).replacingOccurrences(of: " ", with: "-")
        var id = base
        var counter = 2
        while catalog.food(id: id) != nil {
            id = "\(base)-\(counter)"
            counter += 1
        }
        return FoodInfo(
            id: id,
            name: answer.name.trimmingCharacters(in: .whitespaces),
            category: answer.category.flatMap(FoodCategory.init(rawValue:)) ?? .other,
            score: HistamineScore(rawValue: min(max(answer.score, 0), 3)) ?? .moderate,
            flags: (answer.flags ?? []).compactMap(HistamineFlag.init(rawValue:)),
            protein: answer.protein,
            kcal: answer.kcal,
            portion: max(1, answer.portion ?? 100),
            hint: answer.hint,
            isCustom: true
        )
    }

    /// Ordnet Zutaten dem Lexikon zu. Unbekannte werden zu eigenen Lebensmitteln („1 · mäßig“).
    static func recipes(_ answer: ClaudeRecipesAnswer, catalog: FoodCatalog) -> (recipes: [RecipeInfo], newFoods: [FoodInfo]) {
        var newFoods: [String: FoodInfo] = [:]
        let recipes = answer.recipes.map { recipe -> RecipeInfo in
            let ingredients = recipe.ingredients.map { item -> RecipeIngredient in
                if let match = matchFood(item.name, catalog: catalog) {
                    return RecipeIngredient(food: match.id, grams: item.grams, amount: item.amount)
                }
                let id = "custom-" + NameMatcher.normalize(item.name).replacingOccurrences(of: " ", with: "-")
                if newFoods[id] == nil, catalog.food(id: id) == nil {
                    newFoods[id] = FoodInfo(
                        id: id, name: item.name, category: .other, score: .moderate,
                        hint: "Von Claude vorgeschlagen, bitte selbst einschätzen.", isCustom: true
                    )
                }
                return RecipeIngredient(food: id, grams: item.grams, amount: item.amount)
            }
            let title = recipe.title.trimmingCharacters(in: .whitespaces)
            return RecipeInfo(
                id: "claude-" + NameMatcher.normalize(title).replacingOccurrences(of: " ", with: "-"),
                title: title,
                summary: recipe.summary ?? "",
                servings: recipe.servings ?? 2,
                minutes: recipe.minutes ?? 30,
                tags: recipe.tags ?? [],
                ingredients: ingredients,
                steps: recipe.steps,
                isCustom: true
            )
        }
        return (recipes, newFoods.values.sorted { $0.name < $1.name })
    }

    /// Nur sichere Treffer: gleicher Name, Mehrzahl, oder der Lexikon-Name steckt im Zutatennamen.
    static func matchFood(_ name: String, catalog: FoodCatalog) -> FoodInfo? {
        let needle = NameMatcher.normalize(name)
        guard let candidate = catalog.bestMatch(for: name) else { return nil }
        for alias in [candidate.name] + candidate.aliases {
            let normalized = NameMatcher.normalize(alias)
            if normalized == needle || needle.hasPrefix(normalized) || normalized.hasPrefix(needle) {
                return candidate
            }
            if NameMatcher.similarity(alias, name) >= 0.72 { return candidate }
        }
        return nil
    }
}
