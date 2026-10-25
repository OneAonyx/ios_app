import Foundation

/// Holt JSON aus einer Claude-Antwort, auch wenn Text oder Codeblöcke drumherum stehen.
public enum ClaudeResponseExtractor {
    /// Alle `{…}`-Abschnitte, die als JSON in Frage kommen, in sinnvoller Reihenfolge:
    /// zuerst aus Codeblöcken, danach aus dem Gesamttext. So stört Fließtext wie
    /// „{Name}“ vor dem eigentlichen JSON nicht.
    public static func jsonCandidates(in text: String) -> [String] {
        var results: [String] = []
        for source in fencedBlocks(in: text) + [text] {
            for object in balancedObjects(in: source) where !results.contains(object) {
                results.append(object)
            }
        }
        return results
    }

    /// Dekodiert den ersten passenden Kandidaten. Typografische Anführungszeichen
    /// werden als zweiter Versuch durch gerade ersetzt.
    public static func decodeFirst<T: Decodable>(_ type: T.Type, from text: String) -> T? {
        let decoder = JSONDecoder()
        for variant in [text, normalizingQuotes(text)] {
            for candidate in jsonCandidates(in: variant) {
                if let value = try? decoder.decode(T.self, from: Data(candidate.utf8)) {
                    return value
                }
            }
        }
        return nil
    }

    // MARK: - Intern

    static func fencedBlocks(in text: String) -> [String] {
        let parts = text.components(separatedBy: "```")
        guard parts.count >= 3 else { return [] }
        var blocks: [String] = []
        var index = 1
        // Ungerade Abschnitte liegen zwischen zwei Fences. Ein letzter offener Block zählt nicht.
        while index < parts.count - 1 {
            var block = parts[index]
            if let newline = block.firstIndex(of: "\n") {
                let firstLine = block[..<newline]
                if !firstLine.contains("{") {
                    block = String(block[block.index(after: newline)...])
                }
            }
            blocks.append(block)
            index += 2
        }
        return blocks
    }

    /// Das erste vollständige `{…}`, Klammern in Strings werden ignoriert.
    static func firstBalancedObject(in text: String) -> String? {
        balancedObjects(in: text, limit: 1).first
    }

    /// Alle vollständigen `{…}` auf oberster Ebene, von links nach rechts.
    static func balancedObjects(in text: String, limit: Int = 20) -> [String] {
        let characters = Array(text)
        var objects: [String] = []
        var start = 0
        while objects.count < limit, let open = nextIndex(of: "{", in: characters, from: start) {
            if let close = matchingClose(in: characters, open: open) {
                objects.append(String(characters[open...close]))
                start = close + 1
            } else {
                start = open + 1
            }
        }
        return objects
    }

    private static func nextIndex(of target: Character, in characters: [Character], from start: Int) -> Int? {
        guard start < characters.count else { return nil }
        return characters[start...].firstIndex(of: target)
    }

    private static func matchingClose(in characters: [Character], open: Int) -> Int? {
        var depth = 0
        var inString = false
        var escaped = false
        var index = open
        while index < characters.count {
            let character = characters[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else {
                switch character {
                case "\"": inString = true
                case "{": depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 { return index }
                default: break
                }
            }
            index += 1
        }
        return nil
    }

    static func normalizingQuotes(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{201C}", with: "\"") // “
            .replacingOccurrences(of: "\u{201D}", with: "\"") // ”
            .replacingOccurrences(of: "\u{201E}", with: "\"") // „
            .replacingOccurrences(of: "\u{00AB}", with: "\"") // «
            .replacingOccurrences(of: "\u{00BB}", with: "\"") // »
    }
}
