import SwiftUI
import TagwerkCore
import TagwerkKit

/// Muskel-Karte: Figur vorne und hinten, jeder Muskel gefärbt nach Wochensätzen gegen den Zielbereich.
struct MuscleMapView: View {
    let volume: [MuscleVolume]

    var body: some View {
        VStack(spacing: Spacing.s) {
            HStack(alignment: .top, spacing: Spacing.l) {
                ForEach(BodyMapSide.allCases) { side in
                    VStack(spacing: Spacing.xxs) {
                        MuscleFigure(side: side, volume: volume)
                        Text(side.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
            }
            .frame(maxWidth: 320, maxHeight: 300)
            .frame(maxWidth: .infinity)
            MuscleLegend()
        }
        .padding(.vertical, Spacing.xs)
    }
}

/// Eine Figur (vorne oder hinten) mit eingefärbten Muskeln.
struct MuscleFigure: View {
    let side: BodyMapSide
    let volume: [MuscleVolume]

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let centerX = proxy.size.width / 2
            ZStack {
                BodySilhouette()
                    .fill(Color(uiColor: .systemGray5))
                ZStack {
                    ForEach(Array(MuscleMap.patches(on: side).enumerated()), id: \.offset) { _, patch in
                        patchView(patch, height: height, centerX: centerX)
                    }
                }
                .clipShape(BodySilhouette())
                BodySilhouette()
                    .stroke(Color(uiColor: .systemGray3), lineWidth: 1)
            }
        }
        .aspectRatio(BodyMapView.aspect, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MuscleMap.accessibilityText(side: side, volumes: volume))
        .accessibilityIdentifier("muscleMap.\(side.rawValue)")
    }

    private func patchView(_ patch: MusclePatch, height: CGFloat, centerX: CGFloat) -> some View {
        let item = MuscleMap.volume(of: patch.muscle, in: volume)
        let fill = MuscleColor.fill(for: item)
        return ForEach(Array(patch.placements.enumerated()), id: \.offset) { _, placement in
            Ellipse()
                .fill(fill)
                .overlay(Ellipse().strokeBorder(Color(uiColor: .systemBackground).opacity(0.6), lineWidth: 0.75))
                .frame(width: CGFloat(patch.width) * height, height: CGFloat(patch.height) * height)
                .rotationEffect(.degrees(placement.angle))
                .position(x: centerX + CGFloat(placement.dx) * height, y: CGFloat(patch.y) * height)
        }
    }
}

/// Farben wie bei den Volumen-Balken: orange zu wenig, grün im Ziel, rot viel, grau nicht trainiert.
enum MuscleColor {
    static func color(_ level: MuscleMap.Level) -> Color {
        switch level {
        case .none: Color(uiColor: .systemGray3)
        case .low: .orange
        case .inRange: .green
        case .high: .red
        }
    }

    static func fill(for volume: MuscleVolume) -> Color {
        let level = MuscleMap.level(volume)
        return level == .none ? color(level).opacity(0.7) : color(level).opacity(MuscleMap.intensity(volume))
    }
}

/// Legende unter der Karte.
struct MuscleLegend: View {
    var body: some View {
        FlowLayout(spacing: Spacing.s) {
            ForEach([MuscleMap.Level.low, .inRange, .high, .none], id: \.self) { level in
                HStack(spacing: 4) {
                    Circle()
                        .fill(MuscleColor.color(level))
                        .frame(width: 10, height: 10)
                    Text(level.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
