import Foundation
import SwiftData
import TagwerkCore
import WidgetKit

/// Schreibt Tageslast, Eiweiß und Wasser für Widget, Kontrollzentrum und Siri in den gemeinsamen Speicher.
@MainActor
public enum NutritionSnapshotWriter {
    public static func write(context: ModelContext, now: Date = .now, calendar: Calendar) {
        write(NutritionActions.snapshot(now: now, calendar: calendar, in: context))
    }

    public static func write(_ snapshot: NutritionWidgetSnapshot) {
        guard let defaults = AppGroup.defaults, let data = try? JSONEncoder.widget.encode(snapshot) else { return }
        var previous = read()
        previous.writtenAt = snapshot.writtenAt
        defaults.set(data, forKey: SharedKeys.nutritionSnapshot)
        if previous != snapshot {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.nutrition)
            ControlCenter.shared.reloadControls(ofKind: WidgetKinds.waterControl)
        }
    }

    public nonisolated static func read() -> NutritionWidgetSnapshot {
        guard let data = AppGroup.defaults?.data(forKey: SharedKeys.nutritionSnapshot),
              let snapshot = try? JSONDecoder.widget.decode(NutritionWidgetSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }

    /// Wasser sofort im Widget anzeigen, auch bevor die App es übernommen hat.
    nonisolated static func addWaterOptimistically(_ milliliters: Int, now: Date = .now) {
        guard let defaults = AppGroup.defaults else { return }
        var snapshot = read().current(now: now, calendar: GermanCalendar.make())
        snapshot.waterML += milliliters
        snapshot.writtenAt = now
        if let data = try? JSONEncoder.widget.encode(snapshot) {
            defaults.set(data, forKey: SharedKeys.nutritionSnapshot)
        }
    }
}

/// Wasser aus Widget, Kontrollzentrum oder Siri. In der App verarbeitet `handler` es sofort,
/// sonst landet es in einer Warteschlange, die die App beim Öffnen übernimmt.
public enum NutritionActionCenter {
    @MainActor public static var handler: (@MainActor (Int) async -> Void)?

    @MainActor
    public static func submit(_ milliliters: Int, at date: Date = .now) async {
        if let handler {
            await handler(milliliters)
            return
        }
        guard let defaults = AppGroup.defaults else { return }
        var queued = decodeQueue(defaults.data(forKey: SharedKeys.pendingWater))
        queued.append(PendingWater(date: date, milliliters: milliliters))
        if let data = try? JSONEncoder.widget.encode(Array(queued.suffix(40))) {
            defaults.set(data, forKey: SharedKeys.pendingWater)
        }
        NutritionSnapshotWriter.addWaterOptimistically(milliliters, now: date)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.nutrition)
        ControlCenter.shared.reloadControls(ofKind: WidgetKinds.waterControl)
    }

    public static func takeQueued() -> [PendingWater] {
        guard let defaults = AppGroup.defaults else { return [] }
        let queued = decodeQueue(defaults.data(forKey: SharedKeys.pendingWater))
        defaults.removeObject(forKey: SharedKeys.pendingWater)
        return queued
    }

    private static func decodeQueue(_ data: Data?) -> [PendingWater] {
        guard let data else { return [] }
        return (try? JSONDecoder.widget.decode([PendingWater].self, from: data)) ?? []
    }

    /// In der App gesetzt: öffnet die Symptom-Erfassung (Siri, Kontrollzentrum).
    @MainActor public static var symptomHandler: (@MainActor () -> Void)?
    static let pendingSymptomKey = "tagwerk.nutrition.pendingSymptom"

    @MainActor
    public static func requestSymptomEntry() async {
        if let symptomHandler {
            symptomHandler()
        } else {
            UserDefaults.standard.set(true, forKey: pendingSymptomKey)
        }
    }

    public static func takePendingSymptomEntry() -> Bool {
        let pending = UserDefaults.standard.bool(forKey: pendingSymptomKey)
        UserDefaults.standard.removeObject(forKey: pendingSymptomKey)
        return pending
    }
}

extension JSONEncoder {
    /// Datumsformat für Daten im gemeinsamen Speicher.
    static var widget: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }
}

extension JSONDecoder {
    static var widget: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
