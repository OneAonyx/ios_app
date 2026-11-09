import Foundation

/// Eine Stufe in einer Rangliste („S“, „A“ …).
public struct TierRow: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var label: String
    /// Farbname für die Oberfläche: red, orange, yellow, green, teal, blue, purple, gray.
    public var colorName: String

    public init(id: String = UUID().uuidString, label: String, colorName: String) {
        self.id = id
        self.label = label
        self.colorName = colorName
    }

    public static let colorNames = ["red", "orange", "yellow", "green", "teal", "blue", "purple", "gray"]
}

/// Ein Eintrag: Name, optional Emoji oder kleines Bild.
public struct TierItem: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var emoji: String
    /// Kleines JPEG (Vorschaubild), `nil` ohne Bild.
    public var imageData: Data?
    /// Stufe, `nil` = noch nicht eingeordnet.
    public var tierID: String?

    public init(id: String = UUID().uuidString, title: String, emoji: String = "", imageData: Data? = nil, tierID: String? = nil) {
        self.id = id
        self.title = title
        self.emoji = emoji
        self.imageData = imageData
        self.tierID = tierID
    }
}

/// Rangliste im Stil eines Tier-Makers. Reihenfolge innerhalb einer Stufe = Reihenfolge in `items`.
public struct TierList: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var tiers: [TierRow]
    public var items: [TierItem]
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, title: String, tiers: [TierRow] = TierList.standardTiers(), items: [TierItem] = [], createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.tiers = tiers
        self.items = items
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    /// S, A, B, C, D in Rot bis Blau.
    public static func standardTiers() -> [TierRow] {
        zip(["S", "A", "B", "C", "D"], ["red", "orange", "yellow", "green", "blue"]).map { TierRow(label: $0, colorName: $1) }
    }

    /// Einträge einer Stufe (`nil` = nicht eingeordnet), in Reihenfolge.
    public func items(in tierID: String?) -> [TierItem] {
        items.filter { $0.tierID == tierID }
    }

    public var unrankedCount: Int { items(in: nil).count }

    /// „S: Pizza, Döner · A: …“ (für Teilen als Text und VoiceOver).
    public var summary: String {
        tiers.compactMap { tier -> String? in
            let names = items(in: tier.id).map { $0.emoji.isEmpty ? $0.title : "\($0.emoji) \($0.title)" }
            return names.isEmpty ? nil : "\(tier.label): \(names.joined(separator: ", "))"
        }
        .joined(separator: "\n")
    }

    // MARK: Einträge

    @discardableResult
    public mutating func addItem(title: String, emoji: String = "", imageData: Data? = nil, tierID: String? = nil, now: Date = .now) -> TierItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !emoji.isEmpty else { return nil }
        let item = TierItem(title: trimmed, emoji: String(emoji.prefix(2)), imageData: imageData, tierID: tiers.contains { $0.id == tierID } ? tierID : nil)
        items.append(item)
        updatedAt = now
        return item
    }

    public mutating func updateItem(_ item: TierItem, now: Date = .now) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
        updatedAt = now
    }

    public mutating func removeItem(id: String, now: Date = .now) {
        items.removeAll { $0.id == id }
        updatedAt = now
    }

    /// Eintrag in eine Stufe legen (ans Ende oder an `position` innerhalb der Stufe).
    public mutating func move(itemID: String, to tierID: String?, position: Int? = nil, now: Date = .now) {
        guard var item = items.first(where: { $0.id == itemID }) else { return }
        let target = tierID.flatMap { id in tiers.contains { $0.id == id } ? id : nil }
        items.removeAll { $0.id == itemID }
        item.tierID = target
        let siblings = items.enumerated().filter { $0.element.tierID == target }.map(\.offset)
        if let position, position < siblings.count {
            items.insert(item, at: siblings[max(0, position)])
        } else if let last = siblings.last {
            items.insert(item, at: last + 1)
        } else {
            items.append(item)
        }
        updatedAt = now
    }

    /// Innerhalb der Stufe nach vorn (−1) oder hinten (+1).
    public mutating func shift(itemID: String, by offset: Int, now: Date = .now) {
        guard let item = items.first(where: { $0.id == itemID }) else { return }
        let siblings = items(in: item.tierID)
        guard let index = siblings.firstIndex(where: { $0.id == itemID }) else { return }
        let target = index + offset
        guard siblings.indices.contains(target) else { return }
        move(itemID: itemID, to: item.tierID, position: target, now: now)
    }

    /// Eine Stufe höher (−1) oder tiefer (+1). Ganz oben bleibt oben; von „nicht eingeordnet“ geht es in die unterste Stufe.
    public mutating func step(itemID: String, by offset: Int, now: Date = .now) {
        guard let item = items.first(where: { $0.id == itemID }) else { return }
        guard let current = item.tierID, let index = tiers.firstIndex(where: { $0.id == current }) else {
            if let last = tiers.last { move(itemID: itemID, to: last.id, now: now) }
            return
        }
        let target = min(max(index + offset, 0), tiers.count - 1)
        guard target != index else { return }
        move(itemID: itemID, to: tiers[target].id, now: now)
    }

    /// Alle Einträge zurück in „nicht eingeordnet“.
    public mutating func resetRanking(now: Date = .now) {
        for index in items.indices { items[index].tierID = nil }
        updatedAt = now
    }

    // MARK: Stufen

    public mutating func addTier(label: String, now: Date = .now) {
        let used = Set(tiers.map(\.colorName))
        let color = TierRow.colorNames.first { !used.contains($0) } ?? "gray"
        tiers.append(TierRow(label: String(label.prefix(12)), colorName: color))
        updatedAt = now
    }

    public mutating func updateTier(_ tier: TierRow, now: Date = .now) {
        guard let index = tiers.firstIndex(where: { $0.id == tier.id }) else { return }
        tiers[index] = tier
        updatedAt = now
    }

    /// Stufe löschen; ihre Einträge werden „nicht eingeordnet“.
    public mutating func removeTier(id: String, now: Date = .now) {
        guard tiers.count > 1 else { return }
        tiers.removeAll { $0.id == id }
        for index in items.indices where items[index].tierID == id { items[index].tierID = nil }
        updatedAt = now
    }

    public mutating func moveTier(id: String, by offset: Int, now: Date = .now) {
        guard let index = tiers.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard tiers.indices.contains(target) else { return }
        tiers.swapAt(index, target)
        updatedAt = now
    }

    // MARK: Speichern

    public static func encode(_ lists: [TierList]) -> String {
        guard let data = try? JSONEncoder().encode(lists) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    public static func decode(_ text: String) -> [TierList] {
        guard !text.isEmpty, let lists = try? JSONDecoder().decode([TierList].self, from: Data(text.utf8)) else { return [] }
        return lists
    }
}
