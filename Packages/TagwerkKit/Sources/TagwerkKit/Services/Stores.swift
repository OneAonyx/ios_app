import Foundation
import TagwerkCore
import WidgetKit

/// Daten, die App und Widget über die App Group teilen.
public enum WidgetDataStore {
    public enum StoreError: LocalizedError {
        case appGroupUnavailable
        case readBackMismatch

        public var errorDescription: String? {
            switch self {
            case .appGroupUnavailable:
                "Kein gemeinsamer Speicher für „\(AppGroup.identifier)“: Die Signatur enthält diese App Group nicht."
            case .readBackMismatch:
                "Der geschriebene Wert konnte nicht wieder gelesen werden."
            }
        }
    }

    /// Schreibt einen neuen Zählerstand, liest ihn zur Kontrolle zurück und aktualisiert die Widgets.
    @discardableResult
    public static func writeSystemCheckSnapshot(now: Date = .now) throws -> SystemCheckWidgetSnapshot {
        guard let defaults = AppGroup.defaults else { throw StoreError.appGroupUnavailable }
        let snapshot = SystemCheckWidgetSnapshot(
            writtenAt: now,
            counter: (readSystemCheckSnapshot()?.counter ?? 0) + 1,
            appGroupID: AppGroup.identifier
        )
        defaults.set(try snapshot.encoded(), forKey: SharedKeys.widgetSnapshot)
        guard readSystemCheckSnapshot() == snapshot else { throw StoreError.readBackMismatch }
        WidgetCenter.shared.reloadAllTimelines()
        return snapshot
    }

    public static func readSystemCheckSnapshot() -> SystemCheckWidgetSnapshot? {
        guard let data = AppGroup.defaults?.data(forKey: SharedKeys.widgetSnapshot) else { return nil }
        return try? SystemCheckWidgetSnapshot.decode(data)
    }
}

/// Ergebnisse des Systemchecks und Mitteilungs-Antworten (nur App, nicht geteilt).
public enum SystemCheckStore {
    public static func load(defaults: UserDefaults = .standard) -> [SystemCheckResult] {
        guard
            let data = defaults.data(forKey: SharedKeys.systemCheckResults),
            let stored = try? SharedCoding.decoder.decode([SystemCheckResult].self, from: data)
        else {
            return SystemCheckResult.initial()
        }
        // Neue Tests, die es beim Speichern noch nicht gab, als „offen“ ergänzen.
        return SystemCheckID.allCases.map { id in
            stored.first { $0.id == id } ?? SystemCheckResult(id: id)
        }
    }

    public static func save(_ results: [SystemCheckResult], defaults: UserDefaults = .standard) {
        if let data = try? SharedCoding.encoder.encode(results) {
            defaults.set(data, forKey: SharedKeys.systemCheckResults)
        }
    }

    public static func recordNotificationAction(_ record: NotificationActionRecord, defaults: UserDefaults = .standard) {
        if let data = try? SharedCoding.encoder.encode(record) {
            defaults.set(data, forKey: SharedKeys.notificationActionLog)
        }
    }

    public static func lastNotificationAction(defaults: UserDefaults = .standard) -> NotificationActionRecord? {
        guard let data = defaults.data(forKey: SharedKeys.notificationActionLog) else { return nil }
        return try? SharedCoding.decoder.decode(NotificationActionRecord.self, from: data)
    }
}

/// Briefkasten für Claude-Antworten, die der Kurzbefehl über den App Intent abgibt.
public enum ClaudeBridgeInbox {
    public static func store(_ response: String) {
        UserDefaults.standard.set(response, forKey: SharedKeys.pendingClaudeResponse)
        AppGroup.defaults?.set(response, forKey: SharedKeys.pendingClaudeResponse)
    }

    /// Holt die wartende Antwort ab und leert den Briefkasten.
    public static func take() -> String? {
        let stores = [UserDefaults.standard] + [AppGroup.defaults].compactMap { $0 }
        let response = stores.lazy.compactMap { $0.string(forKey: SharedKeys.pendingClaudeResponse) }.first
        stores.forEach { $0.removeObject(forKey: SharedKeys.pendingClaudeResponse) }
        return response
    }
}
