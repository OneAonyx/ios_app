import Foundation

/// Eine Regel für Zutatenlisten: Stichworte und E-Nummern mit Bewertung.
///
/// Stichworte werden normalisiert verglichen (klein, Umlaute ausgeschrieben). Präfixe:
/// `^wort` zählt nur am Wortanfang, `=wort` nur als ganzes Wort.
public struct IngredientRule: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var keywords: [String]
    public var exclude: [String]
    public var eNumbers: [String]
    public var score: HistamineScore
    public var flags: [HistamineFlag]
    public var reason: String

    public init(
        id: String, name: String, keywords: [String], exclude: [String] = [], eNumbers: [String] = [],
        score: HistamineScore, flags: [HistamineFlag] = [], reason: String
    ) {
        self.id = id
        self.name = name
        self.keywords = keywords
        self.exclude = exclude
        self.eNumbers = eNumbers
        self.score = score
        self.flags = flags
        self.reason = reason
    }

    enum CodingKeys: String, CodingKey {
        case id, name, keywords, exclude, eNumbers, score, flags, reason
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        keywords = try c.decodeIfPresent([String].self, forKey: .keywords) ?? []
        exclude = try c.decodeIfPresent([String].self, forKey: .exclude) ?? []
        eNumbers = try c.decodeIfPresent([String].self, forKey: .eNumbers) ?? []
        let raw = try c.decodeIfPresent(Int.self, forKey: .score) ?? 1
        score = HistamineScore(rawValue: min(max(raw, 0), 3)) ?? .moderate
        flags = (try c.decodeIfPresent([String].self, forKey: .flags) ?? []).compactMap(HistamineFlag.init(rawValue:))
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
    }
}

/// Ein Fund in einer Zutatenliste.
public struct IngredientHit: Sendable, Hashable, Identifiable {
    public var rule: IngredientRule
    /// Das gefundene Wort (normalisiert), z. B. „tomatenmark“ oder „e 220“.
    public var matched: String

    public var id: String { rule.id }
    public var score: HistamineScore { rule.score }
}

/// Ergebnis der Prüfung einer Zutatenliste.
public struct IngredientReport: Sendable, Hashable {
    /// Funde, schlechteste zuerst, je Regel nur einmal.
    public var hits: [IngredientHit]
    /// Anzahl erkannter Zutaten (grob, nach Kommas).
    public var ingredientCount: Int

    public var worstScore: HistamineScore? { hits.map(\.score).max() }

    public var isEmpty: Bool { hits.isEmpty }

    /// „Kritisch: Hefeextrakt, Tomatenmark“ bzw. „Keine bekannten Auslöser gefunden“.
    public var summary: String {
        guard let worst = worstScore else {
            return ingredientCount == 0
                ? "Keine Zutaten erkannt."
                : "Keine bekannten Auslöser in \(ingredientCount) Zutaten gefunden."
        }
        let names = hits.filter { $0.score == worst }.map(\.rule.name)
        let lead: String
        switch worst {
        case .good: lead = "Unauffällig"
        case .moderate: lead = "Mäßig"
        case .poor: lead = "Kritisch"
        case .bad: lead = "Sehr kritisch"
        }
        return "\(lead): \(names.joined(separator: ", "))"
    }
}

/// Prüft Zutatenlisten (abgetippt, eingefügt oder per Texterkennung) gegen die Regeln.
public struct IngredientAnalyzer: Sendable {
    public let rules: [IngredientRule]

    private struct Keyword: Sendable {
        let rule: Int
        let text: String
        let wordStart: Bool
        let wholeWord: Bool
    }

    private let keywords: [Keyword]
    private let excludes: [[String]]
    private let eNumberRules: [String: Int]

    public init(rules: [IngredientRule]) {
        self.rules = rules
        var keywords: [Keyword] = []
        var eNumbers: [String: Int] = [:]
        for (index, rule) in rules.enumerated() {
            for raw in rule.keywords {
                var text = raw
                var wordStart = false
                var wholeWord = false
                if text.hasPrefix("^") { wordStart = true; text.removeFirst() }
                if text.hasPrefix("=") { wholeWord = true; text.removeFirst() }
                let normalized = NameMatcher.normalize(text)
                guard !normalized.isEmpty else { continue }
                keywords.append(Keyword(rule: index, text: normalized, wordStart: wordStart || wholeWord, wholeWord: wholeWord))
            }
            for number in rule.eNumbers {
                eNumbers[number.lowercased()] = index
            }
        }
        self.keywords = keywords
        self.excludes = rules.map { $0.exclude.map(NameMatcher.normalize) }
        self.eNumberRules = eNumbers
    }

    public func analyze(_ text: String) -> IngredientReport {
        let normalized = " " + NameMatcher.normalize(text) + " "
        let chars = Array(normalized)
        // Pro Wort-Bereich gewinnt das längste Stichwort („tomatenmark“ vor „tomate“).
        var bestPerSpan: [Range<Int>: (keyword: Keyword, matched: String)] = [:]

        for keyword in keywords {
            let needle = Array(keyword.text)
            guard needle.count <= chars.count else { continue }
            var start = 0
            while start + needle.count <= chars.count {
                guard let found = Self.find(needle, in: chars, from: start) else { break }
                start = found + 1
                let wordStart = Self.wordStart(chars, at: found)
                let wordEnd = Self.wordEnd(chars, at: found + needle.count)
                if keyword.wordStart, wordStart != found { continue }
                if keyword.wholeWord, wordEnd != found + needle.count { continue }
                let span = wordStart..<wordEnd
                let word = String(chars[span])
                if excludes[keyword.rule].contains(where: { word.contains($0) }) { continue }
                if let existing = bestPerSpan[span], existing.keyword.text.count >= needle.count { continue }
                bestPerSpan[span] = (keyword, word)
            }
        }

        var hitsByRule: [Int: IngredientHit] = [:]
        for (_, entry) in bestPerSpan {
            let rule = rules[entry.keyword.rule]
            if hitsByRule[entry.keyword.rule] == nil {
                hitsByRule[entry.keyword.rule] = IngredientHit(rule: rule, matched: entry.matched)
            }
        }
        for number in Self.eNumbers(in: normalized) {
            guard let index = eNumberRules[number] ?? eNumberRules[String(number.prefix { $0.isNumber })] else { continue }
            if hitsByRule[index] == nil {
                hitsByRule[index] = IngredientHit(rule: rules[index], matched: "e \(number)")
            }
        }

        let hits = hitsByRule.values.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.rule.name.localizedCompare(rhs.rule.name) == .orderedAscending
        }
        let count = text
            .split { ",;\n".contains($0) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .count
        return IngredientReport(hits: hits, ingredientCount: count)
    }

    /// E-Nummern im normalisierten Text: „e 220“, „e220“, „e-220“, „e 160b“.
    static func eNumbers(in normalized: String) -> [String] {
        let tokens = normalized.split(separator: " ").map(String.init)
        var result: [String] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token == "e", index + 1 < tokens.count, let number = eNumberBody(tokens[index + 1]) {
                result.append(number)
                index += 2
                continue
            }
            if token.hasPrefix("e"), let number = eNumberBody(String(token.dropFirst())) {
                result.append(number)
            }
            index += 1
        }
        return result
    }

    private static func eNumberBody(_ text: String) -> String? {
        let digits = text.prefix { $0.isNumber }
        guard (3...4).contains(digits.count) else { return nil }
        let rest = text.dropFirst(digits.count)
        guard rest.count <= 3, rest.allSatisfy({ $0.isLetter }) else { return nil }
        return text
    }

    private static func find(_ needle: [Character], in haystack: [Character], from start: Int) -> Int? {
        guard let first = needle.first else { return nil }
        var index = start
        while index + needle.count <= haystack.count {
            if haystack[index] == first, Array(haystack[index..<(index + needle.count)]) == needle {
                return index
            }
            index += 1
        }
        return nil
    }

    private static func wordStart(_ chars: [Character], at index: Int) -> Int {
        var position = index
        while position > 0, chars[position - 1] != " " { position -= 1 }
        return position
    }

    private static func wordEnd(_ chars: [Character], at index: Int) -> Int {
        var position = index
        while position < chars.count, chars[position] != " " { position += 1 }
        return position
    }

    public static func decode(_ data: Data) throws -> IngredientAnalyzer {
        struct File: Decodable { let rules: [IngredientRule] }
        return IngredientAnalyzer(rules: try JSONDecoder().decode(File.self, from: data).rules)
    }

    /// Die mitgelieferten Regeln (`ingredient-rules.de.json`).
    public static func bundled() -> IngredientAnalyzer {
        guard let url = Bundle.module.url(forResource: "ingredient-rules.de", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let analyzer = try? decode(data)
        else { return IngredientAnalyzer(rules: []) }
        return analyzer
    }
}
