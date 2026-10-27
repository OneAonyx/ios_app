import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Ziele innerhalb des Training-Tabs.
enum TrainingRoute: Hashable {
    case plan
    case library
    case stats
    case body
    case progress
    case photos
    case history
    case session(String)
    case exercise(String)
    case day(String)
}

/// Symbol für eine Übung (Grundübung oder Isolation).
struct ExerciseSymbol: View {
    let exercise: ExerciseInfo
    var size: CGFloat = 36

    var body: some View {
        IconBadge(
            systemImage: exercise.isCompound ? "figure.strengthtraining.traditional" : "dumbbell.fill",
            tint: ModuleAccent.training,
            size: size
        )
    }
}

/// Kennzahl in einer kleinen Kachel.
struct StatTile: View {
    let title: String
    let value: String
    var detail: String?
    var tint: Color = ModuleAccent.training

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(tint)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.s)
        .background(Color.tagwerkPage, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Wochen des Zyklus als Punkte (letzte = Deload).
struct CycleDots: View {
    let cycle: Mesocycle
    let week: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...cycle.length, id: \.self) { index in
                let isDeload = cycle.isDeload(week: index)
                ZStack {
                    Circle()
                        .fill(index < week ? ModuleAccent.training : (index == week ? ModuleAccent.training.opacity(0.35) : Color.secondary.opacity(0.15)))
                    if isDeload {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(index <= week ? Color.white : Color.secondary)
                    } else {
                        Text("\(index)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(index <= week ? Color.white : Color.secondary)
                    }
                }
                .frame(width: 22, height: 22)
                .overlay {
                    if index == week {
                        Circle().strokeBorder(ModuleAccent.training, lineWidth: 2)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cycle.label(week: week))
    }
}

/// Balken für das Wochenvolumen einer Muskelgruppe mit Zielbereich.
struct VolumeBar: View {
    let volume: MuscleVolume

    var body: some View {
        let upper = Double(max(volume.target.upperBound, 1))
        let maxValue = max(upper * 1.15, volume.sets)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(volume.muscle.title)
                    .font(.subheadline)
                Spacer()
                Text("\(WeightFormat.number(volume.sets)) / \(volume.target.lowerBound)–\(volume.target.upperBound)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.12))
                    // Zielbereich
                    Capsule()
                        .fill(Color.green.opacity(0.18))
                        .frame(width: width * CGFloat((upper - Double(volume.target.lowerBound)) / maxValue))
                        .offset(x: width * CGFloat(Double(volume.target.lowerBound) / maxValue))
                    Capsule()
                        .fill(color)
                        .frame(width: max(4, width * CGFloat(min(volume.sets, maxValue) / maxValue)))
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(volume.muscle.title): \(volume.label)")
    }

    private var color: Color {
        switch volume.status {
        case .low: .orange
        case .inRange: .green
        case .high: .red
        case .optional: .secondary
        }
    }
}

extension Date {
    /// „Mo, 26. Okt.“ bzw. „Heute“ / „Gestern“.
    func trainingDayLabel(now: Date = .now) -> String {
        DueFormatter.dayLabel(for: self, now: now, calendar: AppModel.calendar)
    }
}
