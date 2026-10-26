import ActivityKit
import AlarmKit
import SwiftUI
import TagwerkKit
import WidgetKit

/// Darstellung von Tagwerk-Weckern auf Sperrbildschirm und in der Dynamic Island,
/// z. B. während eines Schlummer-Countdowns.
struct AlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<TagwerkAlarmMetadata>.self) { context in
            HStack(spacing: 12) {
                Image(systemName: context.attributes.metadata?.purpose == "medication" ? "pills.fill" : "alarm.fill")
                    .font(.title2)
                    .foregroundStyle(context.attributes.tintColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.presentation.alert.title)
                        .font(.headline)
                    if let detail = context.attributes.metadata?.detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "alarm.fill")
                        .foregroundStyle(context.attributes.tintColor)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.presentation.alert.title)
                        .font(.headline)
                }
            } compactLeading: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(context.attributes.tintColor)
            } compactTrailing: {
                Text("Tagwerk")
                    .font(.caption2)
            } minimal: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(context.attributes.tintColor)
            }
        }
    }
}
