import Foundation

/// Feste Kennungen der App. Bei SideStore-Installationen können Bundle- und
/// App-Group-ID zur Laufzeit abweichen (Team-ID wird angehängt), siehe `AppGroupResolver`.
public enum TagwerkIDs {
    public static let bundleIdentifier = "de.tagwerk.app"
    public static let widgetBundleIdentifier = "de.tagwerk.app.widgets"
    public static let appGroup = "group.de.tagwerk.app"
    public static let urlScheme = "tagwerk"
    /// Name des Kurzbefehls, den die Claude-Brücke aufruft.
    public static let claudeShortcutName = "Tagwerk Claude"
}

/// Schlüssel für die gemeinsamen UserDefaults (App Group) und die App-eigenen Defaults.
public enum SharedKeys {
    public static let widgetSnapshot = "tagwerk.widget.systemcheck.snapshot"
    public static let pendingClaudeResponse = "tagwerk.claude.pendingResponse"
    public static let systemCheckResults = "tagwerk.systemcheck.results"
    public static let notificationActionLog = "tagwerk.systemcheck.notificationAction"
}

/// Kennungen für Mitteilungen und ihre Aktionsknöpfe.
public enum NotificationIDs {
    public enum Category {
        public static let systemCheck = "tagwerk.category.systemcheck"
        public static let medication = "tagwerk.category.medication"
    }

    public enum Action {
        public static let taken = "tagwerk.action.taken"
        public static let snooze10 = "tagwerk.action.snooze10"
        public static let skip = "tagwerk.action.skip"
    }

    public static let systemCheckRequest = "tagwerk.systemcheck.notification"
}
