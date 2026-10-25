import SwiftUI
import TagwerkCore

/// Ruhige Inhaltskarte mit weichem Eckenradius.
public struct Card<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    public init(padding: CGFloat = Spacing.m, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(
                Color.tagwerkCard,
                in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            )
    }
}

/// Kleine Überschrift über einer Karte oder Liste.
public struct SectionHeader: View {
    private let title: String
    private let systemImage: String?
    private let tint: Color

    public init(_ title: String, systemImage: String? = nil, tint: Color = .secondary) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
            }
            Text(title.uppercased())
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .font(.caption.weight(.semibold))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Icon in einer weich eingefärbten Fläche, z. B. vor Listeneinträgen.
public struct IconBadge: View {
    private let systemImage: String
    private let tint: Color
    private let size: CGFloat

    public init(systemImage: String, tint: Color, size: CGFloat = 36) {
        self.systemImage = systemImage
        self.tint = tint
        self.size = size
    }

    public var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Status eines Systemcheck-Tests als farbige Kapsel.
public struct SystemCheckStatePill: View {
    private let state: SystemCheckState

    public init(_ state: SystemCheckState) {
        self.state = state
    }

    public var body: some View {
        Label(state.label, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }

    private var symbol: String {
        switch state {
        case .pending: "circle"
        case .running: "arrow.triangle.2.circlepath"
        case .waitingForUser: "hourglass"
        case .passed: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .unavailable: "minus.circle"
        }
    }

    private var color: Color {
        switch state {
        case .pending: Color.secondary
        case .running: Color.blue
        case .waitingForUser: Color.orange
        case .passed: Color.green
        case .failed: Color.red
        case .unavailable: Color.gray
        }
    }
}

/// Platzhalter für Bereiche, die in einer späteren Phase gebaut werden.
public struct ModulePlaceholderView: View {
    private let module: TagwerkModule

    public init(module: TagwerkModule) {
        self.module = module
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: Spacing.l) {
                Image(systemName: module.systemImage)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(module.accent)
                    .frame(width: 96, height: 96)
                    .background(module.accent.opacity(0.14), in: Circle())
                    .padding(.top, Spacing.xl)
                    .accessibilityHidden(true)

                VStack(spacing: Spacing.xxs) {
                    Text(module.title)
                        .font(.title2.bold())
                    Text("Kommt in Phase \(module.plannedPhase)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Card {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        SectionHeader("Geplant", systemImage: "sparkles", tint: module.accent)
                        ForEach(module.upcomingFeatures, id: \.self) { feature in
                            Label {
                                Text(feature)
                            } icon: {
                                Image(systemName: "circle.dotted")
                                    .foregroundStyle(module.accent)
                            }
                            .font(.body)
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.xl)
        }
        .background(Color.tagwerkPage)
    }
}
