import Foundation
import TagwerkCore
import WidgetKit

/// Liest und schreibt den Stand für die Widgets „Heute“ und „Aufgaben“.
public enum TodaySnapshotStore {
    public static func read() -> TodayWidgetSnapshot? {
        TodayWidgetSnapshot.decode(AppGroup.defaults?.data(forKey: SharedKeys.todaySnapshot))
    }

    public static func write(_ snapshot: TodayWidgetSnapshot) {
        guard let defaults = AppGroup.defaults, let data = try? snapshot.encoded() else { return }
        if defaults.data(forKey: SharedKeys.todaySnapshot) == data { return }
        defaults.set(data, forKey: SharedKeys.todaySnapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.today)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.tasks)
    }
}

/// Aufgaben aus dem Widget abhaken: in der App direkt, sonst über eine Warteschlange.
public enum TaskActionCenter {
    @MainActor public static var handler: (@MainActor (String) async -> Void)?

    @MainActor
    public static func complete(taskID: String) async {
        if let handler {
            await handler(taskID)
        } else {
            enqueue(taskID)
        }
    }

    @MainActor
    public static func enqueue(_ taskID: String) {
        if let defaults = AppGroup.defaults {
            defaults.set(PendingTaskQueue.appending(taskID, to: defaults.data(forKey: SharedKeys.pendingTaskCompletions)), forKey: SharedKeys.pendingTaskCompletions)
        }
        if let snapshot = TodaySnapshotStore.read() {
            TodaySnapshotStore.write(snapshot.completing(taskID: taskID))
        }
    }

    public static func takeQueued() -> [String] {
        guard let defaults = AppGroup.defaults else { return [] }
        let ids = PendingTaskQueue.decode(defaults.data(forKey: SharedKeys.pendingTaskCompletions))
        defaults.removeObject(forKey: SharedKeys.pendingTaskCompletions)
        return ids
    }
}

/// Fokus-Filter: vom System gesetzt, von der App gelesen.
public enum FocusFilterStore {
    public static func read() -> FocusFilterState {
        let stores = [AppGroup.defaults, UserDefaults.standard].compactMap { $0 }
        for store in stores {
            if let data = store.data(forKey: SharedKeys.focusFilter), let state = try? JSONDecoder().decode(FocusFilterState.self, from: data) {
                return state
            }
        }
        return .none
    }

    public static func write(_ state: FocusFilterState) {
        let data = try? JSONEncoder().encode(state)
        for store in [AppGroup.defaults, UserDefaults.standard].compactMap({ $0 }) {
            store.set(data, forKey: SharedKeys.focusFilter)
        }
    }
}

/// Öffnet eine Stelle der App aus einem Intent (Kontrollzentrum). Läuft der Intent,
/// bevor die App bereit ist, wird das Ziel gemerkt und beim Aktivieren geöffnet.
public enum RouteCenter {
    @MainActor public static var handler: (@MainActor (URL) -> Void)?
    static let pendingKey = "tagwerk.route.pending"

    @MainActor
    public static func open(_ host: String) async {
        guard let url = URL(string: "\(TagwerkIDs.urlScheme)://\(host)") else { return }
        if let handler {
            handler(url)
        } else {
            for store in [AppGroup.defaults, UserDefaults.standard].compactMap({ $0 }) {
                store.set(url.absoluteString, forKey: pendingKey)
            }
        }
    }

    public static func takePending() -> URL? {
        var found: URL?
        for store in [AppGroup.defaults, UserDefaults.standard].compactMap({ $0 }) {
            if found == nil, let text = store.string(forKey: pendingKey) {
                found = URL(string: text)
            }
            store.removeObject(forKey: pendingKey)
        }
        return found
    }
}
