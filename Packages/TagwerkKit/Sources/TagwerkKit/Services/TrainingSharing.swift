import Foundation
import SwiftData
import TagwerkCore
import WidgetKit

/// Schreibt die nächste Einheit für Widget, Kontrollzentrum und Siri in den gemeinsamen Speicher.
@MainActor
public enum TrainingSnapshotWriter {
    public static func write(context: ModelContext, now: Date = .now) {
        write(TrainingActions.snapshot(now: now, in: context))
    }

    public static func write(_ snapshot: TrainingWidgetSnapshot) {
        guard let defaults = AppGroup.defaults, let data = try? snapshot.encoded() else { return }
        var previous = read()
        previous.writtenAt = snapshot.writtenAt
        defaults.set(data, forKey: SharedKeys.trainingSnapshot)
        if previous != snapshot {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.training)
            ControlCenter.shared.reloadControls(ofKind: WidgetKinds.trainingControl)
        }
    }

    public nonisolated static func read() -> TrainingWidgetSnapshot {
        TrainingWidgetSnapshot.decode(AppGroup.defaults?.data(forKey: SharedKeys.trainingSnapshot)) ?? .empty
    }
}

/// Befehle aus der Live Activity des Trainings.
public enum WorkoutCommand: String, Codable, Sendable {
    /// Pause um 30 Sekunden verlängern.
    case addRest
    /// Pause beenden.
    case skipRest
    /// Nächsten offenen Satz mit den vorgeschlagenen Werten abhaken.
    case completeSet
}

/// Nimmt Befehle aus der Live Activity entgegen. In der App verarbeitet `handler` sie sofort,
/// sonst landen sie in einer Warteschlange, die die App beim Öffnen übernimmt.
public enum WorkoutActionCenter {
    @MainActor public static var handler: (@MainActor (WorkoutCommand) async -> Void)?

    @MainActor
    public static func submit(_ command: WorkoutCommand) async {
        if let handler {
            await handler(command)
            return
        }
        guard let defaults = AppGroup.defaults else { return }
        var queued = defaults.stringArray(forKey: SharedKeys.pendingWorkoutCommands) ?? []
        queued.append(command.rawValue)
        defaults.set(Array(queued.suffix(20)), forKey: SharedKeys.pendingWorkoutCommands)
    }

    /// In der App gesetzt: startet die nächste Einheit (Siri, Kontrollzentrum).
    @MainActor public static var startHandler: (@MainActor () -> Void)?
    static let pendingStartKey = "tagwerk.training.pendingStart"

    @MainActor
    public static func requestStart() async {
        if let startHandler {
            startHandler()
        } else {
            UserDefaults.standard.set(true, forKey: pendingStartKey)
        }
    }

    /// `true`, wenn ein Start angefragt wurde, bevor die App bereit war (wird zurückgesetzt).
    public static func takePendingStart() -> Bool {
        let pending = UserDefaults.standard.bool(forKey: pendingStartKey)
        UserDefaults.standard.removeObject(forKey: pendingStartKey)
        return pending
    }

    public static func takeQueued() -> [WorkoutCommand] {
        guard let defaults = AppGroup.defaults else { return [] }
        let queued = (defaults.stringArray(forKey: SharedKeys.pendingWorkoutCommands) ?? []).compactMap(WorkoutCommand.init(rawValue:))
        defaults.removeObject(forKey: SharedKeys.pendingWorkoutCommands)
        return queued
    }
}
