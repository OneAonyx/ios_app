import Foundation

/// Fläche eines Muskels auf der Körperfigur (vorne oder hinten).
/// Waagerecht: Abstand der Mitte zur Körpermitte in Körperhöhen (wie die Figur gezeichnet wird).
/// Senkrecht: Anteil der Höhe. Breite und Höhe ebenfalls in Körperhöhen.
public struct MusclePatch: Sendable, Hashable {
    public var muscle: MuscleGroup
    public var side: BodyMapSide
    public var dx: Double
    public var y: Double
    public var width: Double
    public var height: Double
    /// Drehung in Grad für die rechte Bildhälfte (positiv = im Uhrzeigersinn). Die Spiegelung dreht andersherum.
    public var angle: Double
    /// Zusätzlich gespiegelt auf der anderen Körperseite.
    public var mirrored: Bool

    public init(_ muscle: MuscleGroup, _ side: BodyMapSide, dx: Double, y: Double, width: Double, height: Double, angle: Double = 0, mirrored: Bool = true) {
        self.muscle = muscle
        self.side = side
        self.dx = dx
        self.y = y
        self.width = width
        self.height = height
        self.angle = angle
        self.mirrored = mirrored
    }

    /// Beide Körperseiten als (Abstand, Drehung).
    public var placements: [(dx: Double, angle: Double)] {
        mirrored && dx != 0 ? [(dx, angle), (-dx, -angle)] : [(dx, angle)]
    }
}

/// Muskel-Karte: welche Muskeln diese Woche im Zielbereich trainiert wurden.
public enum MuscleMap {
    public enum Level: String, Sendable, CaseIterable {
        case none, low, inRange, high

        public var title: String {
            switch self {
            case .none: "nicht trainiert"
            case .low: "zu wenig"
            case .inRange: "im Ziel"
            case .high: "viel"
            }
        }
    }

    // Oberarm läuft leicht nach außen (ca. 8,5°), Latissimus nach innen.
    public static let patches: [MusclePatch] = [
        // Vorne
        MusclePatch(.chest, .front, dx: 0.052, y: 0.255, width: 0.088, height: 0.07),
        MusclePatch(.frontDelts, .front, dx: 0.118, y: 0.205, width: 0.042, height: 0.048),
        MusclePatch(.sideDelts, .front, dx: 0.142, y: 0.222, width: 0.026, height: 0.05),
        MusclePatch(.biceps, .front, dx: 0.146, y: 0.3, width: 0.032, height: 0.085, angle: -8.5),
        MusclePatch(.forearms, .front, dx: 0.17, y: 0.465, width: 0.028, height: 0.085, angle: -8.7),
        MusclePatch(.abs, .front, dx: 0, y: 0.385, width: 0.075, height: 0.13, mirrored: false),
        MusclePatch(.obliques, .front, dx: 0.083, y: 0.405, width: 0.026, height: 0.09),
        MusclePatch(.quads, .front, dx: 0.066, y: 0.635, width: 0.046, height: 0.15),
        MusclePatch(.adductors, .front, dx: 0.031, y: 0.6, width: 0.018, height: 0.075),
        // Hinten
        MusclePatch(.traps, .back, dx: 0, y: 0.195, width: 0.12, height: 0.055, mirrored: false),
        MusclePatch(.rearDelts, .back, dx: 0.122, y: 0.21, width: 0.04, height: 0.045),
        MusclePatch(.sideDelts, .back, dx: 0.142, y: 0.222, width: 0.026, height: 0.05),
        MusclePatch(.upperBack, .back, dx: 0, y: 0.27, width: 0.085, height: 0.07, mirrored: false),
        MusclePatch(.lats, .back, dx: 0.068, y: 0.32, width: 0.048, height: 0.12, angle: 10),
        MusclePatch(.triceps, .back, dx: 0.146, y: 0.3, width: 0.032, height: 0.085, angle: -8.5),
        MusclePatch(.forearms, .back, dx: 0.17, y: 0.465, width: 0.028, height: 0.085, angle: -8.7),
        MusclePatch(.lowerBack, .back, dx: 0, y: 0.435, width: 0.06, height: 0.075, mirrored: false),
        MusclePatch(.glutes, .back, dx: 0.048, y: 0.535, width: 0.075, height: 0.07),
        MusclePatch(.hamstrings, .back, dx: 0.058, y: 0.655, width: 0.05, height: 0.13),
        MusclePatch(.calves, .back, dx: 0.056, y: 0.82, width: 0.045, height: 0.1),
    ]

    public static func patches(on side: BodyMapSide) -> [MusclePatch] {
        patches.filter { $0.side == side }
    }

    /// Muskeln einer Ansicht ohne Doppelte, in der üblichen Reihenfolge.
    public static func muscles(on side: BodyMapSide) -> [MuscleGroup] {
        Array(Set(patches(on: side).map(\.muscle))).sorted()
    }

    /// Volumen eines Muskels, auch wenn er in der Liste fehlt (dann 0 Sätze).
    public static func volume(of muscle: MuscleGroup, in volumes: [MuscleVolume]) -> MuscleVolume {
        volumes.first { $0.muscle == muscle } ?? MuscleVolume(muscle: muscle, sets: 0, target: muscle.weeklyTarget)
    }

    /// Farbe auf der Karte. Pflichtmuskeln ohne Sätze sind „zu wenig“, freiwillige ohne Sätze grau.
    public static func level(_ volume: MuscleVolume) -> Level {
        switch volume.status {
        case .low: .low
        case .inRange: .inRange
        case .high: .high
        case .optional: .none
        }
    }

    /// Farbstärke 0,35…1: je näher an der Obergrenze, desto kräftiger.
    public static func intensity(_ volume: MuscleVolume) -> Double {
        guard volume.sets > 0 else { return 0.35 }
        let upper = Double(max(volume.target.upperBound, 1))
        return 0.35 + 0.65 * min(1, volume.sets / upper)
    }

    /// „Im Ziel: Brust, Latissimus. Zu wenig: Bizeps. Viel: Trizeps.“
    public static func summary(_ volumes: [MuscleVolume]) -> String {
        let all = MuscleGroup.allCases.map { volume(of: $0, in: volumes) }
        var parts: [String] = []
        for level in [Level.inRange, .low, .high] {
            let names = all.filter { self.level($0) == level }.map(\.muscle.title)
            guard !names.isEmpty else { continue }
            let title = level.title.prefix(1).uppercased() + level.title.dropFirst()
            parts.append("\(title): \(names.joined(separator: ", ")).")
        }
        return parts.isEmpty ? "Diese Woche noch keine Sätze." : parts.joined(separator: " ")
    }

    /// Für VoiceOver: „Vorne: Brust im Ziel, 14 Sätze; Bizeps zu wenig, 4 Sätze; …“
    public static func accessibilityText(side: BodyMapSide, volumes: [MuscleVolume]) -> String {
        let items = muscles(on: side).map { muscle -> String in
            let item = volume(of: muscle, in: volumes)
            return "\(muscle.title) \(level(item).title), \(WeightFormat.number(item.sets)) Sätze"
        }
        return "\(side.title): " + items.joined(separator: "; ")
    }
}
