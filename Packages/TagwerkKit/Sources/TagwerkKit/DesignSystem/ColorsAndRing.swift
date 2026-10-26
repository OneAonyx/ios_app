import SwiftUI

/// Farben, die man Listen geben kann. Gespeichert wird der Name.
public enum ListColor: String, CaseIterable, Identifiable, Sendable {
    case indigo, blue, teal, green, yellow, orange, red, pink, purple, gray

    public var id: String { rawValue }

    public var color: Color {
        switch self {
        case .indigo: .indigo
        case .blue: .blue
        case .teal: .teal
        case .green: .green
        case .yellow: .yellow
        case .orange: .orange
        case .red: .red
        case .pink: .pink
        case .purple: .purple
        case .gray: .gray
        }
    }

    public static func color(named name: String) -> Color {
        (ListColor(rawValue: name) ?? .indigo).color
    }
}

/// Symbole, die man Listen geben kann.
public enum ListSymbol {
    public static let all = [
        "list.bullet", "person", "house", "briefcase", "cart", "heart",
        "graduationcap", "car", "airplane", "gift", "leaf", "pawprint",
        "book", "wrench.and.screwdriver", "banknote", "star",
    ]
}

public extension Color {
    /// Farbe aus „#RRGGBB“, sonst Akzentfarbe.
    init(hex: String?) {
        guard let hex, hex.hasPrefix("#"), hex.count == 7, let value = Int(hex.dropFirst(), radix: 16) else {
            self = .accentColor
            return
        }
        self = Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// Fortschrittsring, z. B. „3 von 5 Aufgaben erledigt“.
public struct ProgressRing<Label: View>: View {
    private let fraction: Double
    private let tint: Color
    private let lineWidth: CGFloat
    private let label: Label

    public init(fraction: Double, tint: Color, lineWidth: CGFloat = 8, @ViewBuilder label: () -> Label) {
        self.fraction = min(max(fraction, 0), 1)
        self.tint = tint
        self.lineWidth = lineWidth
        self.label = label()
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: fraction)
            label
        }
        .accessibilityElement(children: .combine)
    }
}
