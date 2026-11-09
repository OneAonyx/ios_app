import Foundation
import Testing
@testable import TagwerkCore

@Suite("Leben: Tier-Maker")
struct TierListTests {
    @Test func addMoveAndShift() throws {
        var list = TierList(title: "Snacks")
        #expect(list.tiers.map(\.label) == ["S", "A", "B", "C", "D"])
        let chipsItem = list.addItem(title: "Chips", emoji: "🥔")
        let chips = try #require(chipsItem)
        let pizzaItem = list.addItem(title: "Pizza", emoji: "🍕")
        let pizza = try #require(pizzaItem)
        let nutsItem = list.addItem(title: "Nüsse")
        let nuts = try #require(nutsItem)
        let empty = list.addItem(title: "  ")
        #expect(empty == nil)
        #expect(list.unrankedCount == 3)

        let s = list.tiers[0].id
        list.move(itemID: pizza.id, to: s)
        list.move(itemID: chips.id, to: s)
        #expect(list.items(in: s).map(\.title) == ["Pizza", "Chips"])
        list.shift(itemID: chips.id, by: -1)
        #expect(list.items(in: s).map(\.title) == ["Chips", "Pizza"])
        list.move(itemID: nuts.id, to: s, position: 1)
        #expect(list.items(in: s).map(\.title) == ["Chips", "Nüsse", "Pizza"])
        #expect(list.unrankedCount == 0)

        list.step(itemID: pizza.id, by: 1)
        #expect(list.items(in: list.tiers[1].id).map(\.title) == ["Pizza"])
        list.step(itemID: chips.id, by: -1)
        #expect(list.items(in: s).first?.title == "Chips", "Oben bleibt oben")
        #expect(list.summary.hasPrefix("S: 🥔 Chips, Nüsse\nA: 🍕 Pizza"))

        list.resetRanking()
        #expect(list.unrankedCount == 3)
        list.step(itemID: nuts.id, by: -1)
        #expect(list.items(in: list.tiers.last?.id).map(\.title) == ["Nüsse"], "Aus dem Stapel in die unterste Stufe")
    }

    @Test func tiersCanChange() throws {
        var list = TierList(title: "Filme")
        let duneItem = list.addItem(title: "Dune", tierID: list.tiers[2].id)
        let item = try #require(duneItem)
        let removed = list.tiers[2].id
        list.removeTier(id: removed)
        #expect(list.tiers.count == 4)
        #expect(list.items.first { $0.id == item.id }?.tierID == nil)
        list.addTier(label: "F")
        #expect(list.tiers.last?.label == "F")
        #expect(list.tiers.last?.colorName != "red")
        let last = try #require(list.tiers.last)
        list.moveTier(id: last.id, by: -1)
        #expect(list.tiers[list.tiers.count - 2].label == "F")
        var one = TierList(title: "x", tiers: [TierRow(label: "S", colorName: "red")])
        one.removeTier(id: one.tiers[0].id)
        #expect(one.tiers.count == 1, "Die letzte Stufe bleibt")
    }

    @Test func storageRoundTrip() throws {
        var list = TierList(title: "Gym-Übungen")
        list.addItem(title: "Bankdrücken", emoji: "🏋️", imageData: Data([1, 2, 3]))
        let text = TierList.encode([list])
        let decoded = TierList.decode(text)
        #expect(decoded == [list])
        #expect(TierList.decode("").isEmpty)
        #expect(TierList.decode("kaputt").isEmpty)
    }
}
