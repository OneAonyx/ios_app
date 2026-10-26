import ActivityKit
import AppIntents
import SwiftUI
import TagwerkCore
import TagwerkKit
import WidgetKit

/// Training auf Sperrbildschirm und in der Dynamic Island: Zeit, Übung, Pause, Knöpfe.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenWorkoutView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.65))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "\(TagwerkIDs.urlScheme)://training"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.state.sessionStart, style: .timer)
                            .monospacedDigit()
                    } icon: {
                        Image(systemName: "figure.strengthtraining.traditional")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.doneSets)/\(context.state.totalSets)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.state.exerciseName)
                            .font(.headline)
                            .lineLimit(1)
                        Text(context.state.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    WorkoutControls(state: context.state, isStale: context.isStale)
                }
            } compactLeading: {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                RestOrElapsed(state: context.state, isStale: context.isStale)
                    .frame(maxWidth: 52)
            } minimal: {
                if let end = context.state.restEndsAt, !context.isStale {
                    Text(timerInterval: Date.now...max(end, Date.now), countsDown: true)
                        .monospacedDigit()
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .foregroundStyle(.orange)
                }
            }
            .widgetURL(URL(string: "\(TagwerkIDs.urlScheme)://training"))
        }
    }
}

private struct LockScreenWorkoutView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(context.attributes.title, systemImage: "figure.strengthtraining.traditional")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Spacer()
                Text(context.state.sessionStart, style: .timer)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80, alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(context.state.exerciseName)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(context.state.detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
            }
            WorkoutControls(state: context.state, isStale: context.isStale)
        }
        .padding()
    }
}

/// Pause mit Countdown und Knöpfen, sonst „Satz fertig“.
private struct WorkoutControls: View {
    let state: WorkoutActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        HStack(spacing: 8) {
            if let end = state.restEndsAt, !isStale, end > .now {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Pause")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(timerInterval: Date.now...max(end, Date.now), countsDown: true)
                        .font(.system(.title2, design: .rounded, weight: .bold).monospacedDigit())
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button(intent: AddRestIntent()) {
                    Text("+30 s")
                }
                .tint(.gray)
                Button(intent: SkipRestIntent()) {
                    Text("Weiter")
                }
                .tint(.orange)
            } else {
                Text(state.restEndsAt != nil ? "Pause vorbei" : "\(state.doneSets) von \(state.totalSets) Sätzen")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(state.restEndsAt != nil ? .green : .secondary)
                Spacer()
                if state.doneSets < state.totalSets {
                    Button(intent: CompleteSetIntent()) {
                        Label("Satz fertig", systemImage: "checkmark")
                    }
                    .tint(.orange)
                }
            }
        }
        .buttonStyle(.borderedProminent)
        .font(.subheadline.weight(.semibold))
    }
}

private struct RestOrElapsed: View {
    let state: WorkoutActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        if let end = state.restEndsAt, !isStale {
            Text(timerInterval: Date.now...max(end, Date.now), countsDown: true)
                .monospacedDigit()
                .foregroundStyle(.orange)
        } else {
            Text(state.sessionStart, style: .timer)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
