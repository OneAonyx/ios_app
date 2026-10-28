import Foundation
import Testing
@testable import TagwerkCore

@Suite("Startseite und Funktions-Verzeichnis")
struct OverviewTests {
    @Test("Standard zeigt alle Karten in fester Reihenfolge")
    func standardLayout() {
        let layout = TodayLayout.standard
        #expect(layout.visibleCards == TodayCard.allCases)
        #expect(layout.visibleCards.first == .quickCapture)
        #expect(layout.isStandard)
    }

    @Test("Ausblenden, Verschieben, Speichern und Laden")
    func layoutRoundTrip() {
        var layout = TodayLayout.standard
        layout.setVisible(.nutrition, false)
        layout.move(fromOffsets: IndexSet(integer: TodayCard.allCases.firstIndex(of: .training)!), toOffset: 0)
        #expect(layout.visibleCards.first == .training)
        #expect(!layout.visibleCards.contains(.nutrition))
        #expect(!layout.isStandard)

        let text = layout.encoded
        #expect(text.hasPrefix("training,quickCapture"))
        #expect(text.contains("-nutrition"))
        #expect(TodayLayout.decode(text) == layout)
    }

    @Test("Unbekanntes wird übersprungen, neue Karten kommen hinten dazu, nichts doppelt")
    func decodeIsTolerant() {
        let layout = TodayLayout.decode("tasks,gibtsnicht,tasks,-journal")
        #expect(layout.order.first == .tasks)
        #expect(layout.order.count == TodayCard.allCases.count)
        #expect(Set(layout.order).count == TodayCard.allCases.count)
        #expect(layout.hidden == [.journal])
        #expect(TodayLayout.decode("") == .standard)
    }

    @Test("Verschieben nach hinten")
    func moveDown() {
        var layout = TodayLayout(order: [.tasks, .nextUp, .quickCapture])
        layout.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(Array(layout.order.prefix(3)) == [.nextUp, .quickCapture, .tasks])
    }

    @Test("Jede Funktion einmal, jeder Bereich gefüllt")
    func indexIsComplete() {
        let ids = FeatureIndex.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(FeatureIndex.grouped.map(\.area) == FeatureArea.allCases)
        #expect(FeatureIndex.all.allSatisfy { !$0.path.isEmpty && !$0.symbol.isEmpty })
    }

    @Test("Suche über Namen, Stichworte und ohne Umlaute")
    func search() {
        #expect(FeatureIndex.search("arzt").first?.id == "doctorReport")
        #expect(FeatureIndex.search("pdf").first?.id == "doctorReport")
        #expect(FeatureIndex.search("icloud").first?.id == "backup")
        #expect(FeatureIndex.search("uebungen").first?.id == "exerciseLibrary")
        #expect(FeatureIndex.search("Übungen").first?.id == "exerciseLibrary")
        #expect(FeatureIndex.search("muskel karte").first?.id == "trainingStats")
        #expect(FeatureIndex.search("kündigung").first?.id == "contracts")
        #expect(FeatureIndex.search("face id").first?.id == "privacy")
        #expect(FeatureIndex.search("wasser").first?.id == "water")
        #expect(FeatureIndex.search("import").contains { $0.id == "reminderImport" })
        #expect(FeatureIndex.search("").isEmpty)
        #expect(FeatureIndex.search("xyzqq").isEmpty)
        #expect(FeatureIndex.search("e", limit: 3).count <= 3)
    }
}
