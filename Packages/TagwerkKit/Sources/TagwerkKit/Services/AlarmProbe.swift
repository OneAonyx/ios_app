import ActivityKit
import AlarmKit
import Foundation
import SwiftUI

/// Zusatzdaten zu einem Tagwerk-Wecker. App und Widget-Extension müssen denselben Typ nutzen.
public struct TagwerkAlarmMetadata: AlarmMetadata {
    public var purpose: String

    public init(purpose: String = "systemcheck") {
        self.purpose = purpose
    }
}

/// Phase-0-Test für AlarmKit: echter Wecker, der Stumm- und Fokusmodus durchbricht.
public enum AlarmProbe {
    /// Fragt die Wecker-Berechtigung an, falls noch nicht geschehen.
    public static func requestAuthorization() async throws -> Bool {
        let manager = AlarmManager.shared
        let state: AlarmManager.AuthorizationState
        if manager.authorizationState == .notDetermined {
            state = try await manager.requestAuthorization()
        } else {
            state = manager.authorizationState
        }
        return state == .authorized
    }

    @discardableResult
    public static func scheduleTestAlarm(in seconds: TimeInterval = 60) async throws -> UUID {
        let id = UUID()
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            // Ab iOS 26.1 stellt das System den Stopp-Knopf selbst bereit.
            alert = AlarmPresentation.Alert(title: "Tagwerk Testwecker")
        } else {
            alert = AlarmPresentation.Alert(
                title: "Tagwerk Testwecker",
                stopButton: AlarmButton(text: "Stopp", textColor: .white, systemImageName: "stop.circle"),
                secondaryButton: nil,
                secondaryButtonBehavior: nil
            )
        }
        let attributes = AlarmAttributes<TagwerkAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert, countdown: nil, paused: nil),
            metadata: TagwerkAlarmMetadata(),
            tintColor: .mint
        )
        let configuration = AlarmManager.AlarmConfiguration<TagwerkAlarmMetadata>.alarm(
            schedule: .fixed(Date.now.addingTimeInterval(seconds)),
            attributes: attributes,
            stopIntent: nil,
            secondaryIntent: nil,
            sound: .default
        )
        _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
        return id
    }
}
