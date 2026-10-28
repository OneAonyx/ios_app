import SwiftUI
import TagwerkCore
import TagwerkKit

/// Körperkarte zum Antippen. Vorne liegt die linke Körperseite rechts im Bild (wie beim Gegenüber).
struct BodyMapView: View {
    let view: BodyView
    var selected: Set<BodyRegion> = []
    /// Anzahl je Region für die Übersicht (größere, kräftigere Punkte).
    var counts: [BodyRegion: Int] = [:]
    var onTap: ((BodyRegion) -> Void)?

    static let aspect: CGFloat = 0.55

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                BodySilhouette()
                    .fill(Color(uiColor: .systemGray5))
                BodySilhouette()
                    .stroke(Color(uiColor: .systemGray3), lineWidth: 1)
                ForEach(BodyRegion.regions(on: view)) { region in
                    if let point = region.positions[view] {
                        spot(region)
                            .position(x: point.x * size.width, y: point.y * size.height)
                    }
                }
            }
        }
        .aspectRatio(Self.aspect, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(view == .front ? "Körper von vorne" : "Körper von hinten")
    }

    @ViewBuilder
    private func spot(_ region: BodyRegion) -> some View {
        let isSelected = selected.contains(region)
        let count = counts[region] ?? 0
        let maxCount = max(counts.values.max() ?? 1, 1)
        let heat = counts.isEmpty ? 0 : Double(count) / Double(maxCount)
        let diameter: CGFloat = counts.isEmpty ? 26 : 16 + CGFloat(heat) * 18
        let marker = ZStack {
            Circle()
                .fill(isSelected ? Color.red : (count > 0 ? Color.red.opacity(0.25 + heat * 0.6) : Color.primary.opacity(0.06)))
            Circle()
                .strokeBorder(isSelected ? Color.red : Color.red.opacity(count > 0 ? 0.8 : 0.45), lineWidth: isSelected ? 0 : 1.5)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            } else if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: diameter, height: diameter)

        if let onTap {
            Button {
                onTap(region)
            } label: {
                marker
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(region.title)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("body.\(region.rawValue)")
        } else {
            marker
                .accessibilityLabel(count > 0 ? "\(region.title): \(count)" : region.title)
        }
    }
}

/// Schlichte Figur: Kopf, Rumpf, Arme, Beine. Maße relativ zur Höhe, Lage relativ zur Breite.
/// Die Teile werden vereinigt, damit Füllung und Umriss sauber bleiben.
struct BodySilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let cx = rect.minX + w / 2
        func y(_ value: CGFloat) -> CGFloat { rect.minY + value * h }
        var parts: [Path] = []

        // Kopf und Hals
        parts.append(Path(ellipseIn: CGRect(x: cx - 0.05 * h, y: y(0.015), width: 0.1 * h, height: 0.11 * h)))
        parts.append(Path(roundedRect: CGRect(x: cx - 0.024 * h, y: y(0.11), width: 0.048 * h, height: 0.07 * h), cornerRadius: 6))

        // Rumpf (Schultern breiter als Hüfte)
        var torso = Path()
        torso.move(to: CGPoint(x: cx - 0.125 * h, y: y(0.18)))
        torso.addQuadCurve(to: CGPoint(x: cx + 0.125 * h, y: y(0.18)), control: CGPoint(x: cx, y: y(0.16)))
        torso.addLine(to: CGPoint(x: cx + 0.1 * h, y: y(0.4)))
        torso.addLine(to: CGPoint(x: cx + 0.11 * h, y: y(0.53)))
        torso.addQuadCurve(to: CGPoint(x: cx - 0.11 * h, y: y(0.53)), control: CGPoint(x: cx, y: y(0.56)))
        torso.addLine(to: CGPoint(x: cx - 0.1 * h, y: y(0.4)))
        torso.closeSubpath()
        parts.append(torso)

        // Arme und Beine als dicke Linien mit runden Enden, dazu Hände und Füße
        for side: CGFloat in [-1, 1] {
            var arm = Path()
            arm.move(to: CGPoint(x: cx + side * 0.13 * h, y: y(0.2)))
            arm.addLine(to: CGPoint(x: cx + side * 0.16 * h, y: y(0.4)))
            arm.addLine(to: CGPoint(x: cx + side * 0.18 * h, y: y(0.53)))
            parts.append(arm.strokedPath(StrokeStyle(lineWidth: 0.05 * h, lineCap: .round, lineJoin: .round)))
            parts.append(Path(ellipseIn: CGRect(x: cx + side * 0.183 * h - 0.025 * h, y: y(0.535), width: 0.05 * h, height: 0.06 * h)))

            var leg = Path()
            leg.move(to: CGPoint(x: cx + side * 0.058 * h, y: y(0.53)))
            leg.addLine(to: CGPoint(x: cx + side * 0.055 * h, y: y(0.74)))
            leg.addLine(to: CGPoint(x: cx + side * 0.055 * h, y: y(0.93)))
            parts.append(leg.strokedPath(StrokeStyle(lineWidth: 0.075 * h, lineCap: .round, lineJoin: .round)))
            parts.append(Path(
                roundedRect: CGRect(x: cx + side * 0.06 * h - 0.035 * h, y: y(0.935), width: 0.07 * h, height: 0.04 * h),
                cornerRadius: 0.02 * h
            ))
        }
        return parts.dropFirst().reduce(parts[0]) { $0.union($1) }
    }
}

/// Vorne und hinten nebeneinander (Übersicht ohne Antippen).
struct BodyHeatMap: View {
    let counts: [BodyRegion: Int]

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            ForEach(BodyView.allCases) { side in
                VStack(spacing: Spacing.xxs) {
                    BodyMapView(view: side, counts: counts)
                    Text(side.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
