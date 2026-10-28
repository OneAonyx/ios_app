import Foundation
import Testing
@testable import TagwerkCore

@Suite("Muskel-Karte")
struct MuscleMapTests {
    @Test("Jeder Muskel hat eine Fläche auf der Figur")
    func everyMuscleHasPatch() {
        let covered = Set(MuscleMap.patches.map(\.muscle))
        #expect(covered == Set(MuscleGroup.allCases))
    }

    @Test("Flächen liegen innerhalb der Figur")
    func patchesInsideFigure() {
        for patch in MuscleMap.patches {
            // Die Figur ist inklusive Hände etwa ±0,21 Körperhöhen breit.
            #expect(abs(patch.dx) + patch.width / 2 <= 0.2, "\(patch.muscle) zu weit außen")
            #expect(patch.y - patch.height / 2 >= 0.15, "\(patch.muscle) zu weit oben")
            #expect(patch.y + patch.height / 2 <= 0.9, "\(patch.muscle) zu weit unten")
            #expect(patch.width > 0 && patch.height > 0)
        }
    }

    @Test("Gespiegelte Flächen erscheinen zweimal, mittige einmal")
    func placements() {
        let chest = MuscleMap.patches.first { $0.muscle == .chest }!
        #expect(chest.placements.count == 2)
        #expect(chest.placements[1].dx == -chest.dx)
        let core = MuscleMap.patches.first { $0.muscle == .abs }!
        #expect(core.placements.count == 1)
        let biceps = MuscleMap.patches.first { $0.muscle == .biceps }!
        #expect(biceps.placements[1].angle == -biceps.angle)
    }

    @Test("Vorne Brust und Bizeps, hinten Latissimus und Trizeps")
    func sides() {
        let front = MuscleMap.muscles(on: .front)
        let back = MuscleMap.muscles(on: .back)
        #expect(front.contains(.chest) && front.contains(.biceps) && !front.contains(.lats))
        #expect(back.contains(.lats) && back.contains(.triceps) && !back.contains(.chest))
        // Seitliche Schulter und Unterarme sieht man von beiden Seiten, aber nur einmal je Seite.
        #expect(front.filter { $0 == .sideDelts }.count == 1)
        #expect(back.contains(.forearms))
    }

    @Test("Farbe richtet sich nach dem Zielbereich")
    func levels() {
        let volumes = [
            MuscleVolume(muscle: .chest, sets: 14, target: MuscleGroup.chest.weeklyTarget),
            MuscleVolume(muscle: .biceps, sets: 4, target: MuscleGroup.biceps.weeklyTarget),
            MuscleVolume(muscle: .triceps, sets: 24, target: MuscleGroup.triceps.weeklyTarget),
        ]
        #expect(MuscleMap.level(MuscleMap.volume(of: .chest, in: volumes)) == .inRange)
        #expect(MuscleMap.level(MuscleMap.volume(of: .biceps, in: volumes)) == .low)
        #expect(MuscleMap.level(MuscleMap.volume(of: .triceps, in: volumes)) == .high)
        // Pflichtmuskel ohne Sätze: zu wenig. Freiwilliger ohne Sätze: grau.
        #expect(MuscleMap.level(MuscleMap.volume(of: .lats, in: volumes)) == .low)
        #expect(MuscleMap.level(MuscleMap.volume(of: .quads, in: volumes)) == .none)
    }

    @Test("Farbstärke steigt bis zur Obergrenze")
    func intensity() {
        let none = MuscleVolume(muscle: .chest, sets: 0, target: 10...20)
        let half = MuscleVolume(muscle: .chest, sets: 10, target: 10...20)
        let full = MuscleVolume(muscle: .chest, sets: 30, target: 10...20)
        #expect(MuscleMap.intensity(none) == 0.35)
        #expect(abs(MuscleMap.intensity(half) - 0.675) < 0.001)
        #expect(MuscleMap.intensity(full) == 1)
    }

    @Test("Zusammenfassung und VoiceOver-Text")
    func texts() {
        let volumes = [
            MuscleVolume(muscle: .chest, sets: 14, target: MuscleGroup.chest.weeklyTarget),
            MuscleVolume(muscle: .biceps, sets: 4.5, target: MuscleGroup.biceps.weeklyTarget),
        ]
        let summary = MuscleMap.summary(volumes)
        #expect(summary.hasPrefix("Im Ziel: Brust."))
        #expect(summary.contains("Zu wenig: Latissimus"))
        #expect(summary.contains("Bizeps"))
        #expect(!summary.contains("Viel:"))
        let spoken = MuscleMap.accessibilityText(side: .front, volumes: volumes)
        #expect(spoken.hasPrefix("Vorne: Brust im Ziel, 14 Sätze"))
        #expect(spoken.contains("Bizeps zu wenig, 4,5 Sätze"))
        #expect(MuscleMap.summary([]).contains("Zu wenig"))
    }
}
