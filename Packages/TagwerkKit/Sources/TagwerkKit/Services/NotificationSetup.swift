import Foundation
import TagwerkCore
import UserNotifications

/// Mitteilungs-Kategorien mit Aktionsknöpfen und der Phase-0-Testmitteilung.
public enum NotificationSetup {
    /// Einmal beim App-Start aufrufen.
    public static func registerCategories() {
        let actions = [
            UNNotificationAction(
                identifier: NotificationIDs.Action.taken,
                title: "Genommen",
                options: [],
                icon: UNNotificationActionIcon(systemImageName: "checkmark.circle")
            ),
            UNNotificationAction(
                identifier: NotificationIDs.Action.snooze10,
                title: "In 10 Min",
                options: [],
                icon: UNNotificationActionIcon(systemImageName: "clock.arrow.circlepath")
            ),
            UNNotificationAction(
                identifier: NotificationIDs.Action.skip,
                title: "Auslassen",
                options: [.destructive],
                icon: UNNotificationActionIcon(systemImageName: "xmark.circle")
            ),
        ]
        let categories: Set<UNNotificationCategory> = [
            UNNotificationCategory(
                identifier: NotificationIDs.Category.systemCheck,
                actions: actions,
                intentIdentifiers: [],
                options: [.customDismissAction]
            ),
            UNNotificationCategory(
                identifier: NotificationIDs.Category.medication,
                actions: actions,
                intentIdentifiers: [],
                options: [.customDismissAction]
            ),
            UNNotificationCategory(
                identifier: NotificationIDs.Category.task,
                actions: taskActions,
                intentIdentifiers: [],
                options: []
            ),
        ]
        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }

    private static var taskActions: [UNNotificationAction] {
        [
            UNNotificationAction(
                identifier: NotificationIDs.Action.complete,
                title: "Erledigt",
                options: [],
                icon: UNNotificationActionIcon(systemImageName: "checkmark.circle")
            ),
            UNNotificationAction(
                identifier: NotificationIDs.Action.tomorrow,
                title: "Morgen",
                options: [],
                icon: UNNotificationActionIcon(systemImageName: "arrow.turn.up.right")
            ),
        ]
    }

    /// `true`, wenn Mitteilungen erlaubt sind (auch „vorläufig“).
    public static func isAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    public static func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    public static func scheduleSystemCheckNotification(after seconds: TimeInterval = 10) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Tagwerk Systemcheck"
        content.body = "Test-Erinnerung: Halte die Mitteilung gedrückt und wähle einen Knopf."
        content.sound = .default
        content.categoryIdentifier = NotificationIDs.Category.systemCheck
        content.interruptionLevel = .active

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(
            identifier: NotificationIDs.systemCheckRequest,
            content: content,
            trigger: trigger
        )
        try await UNUserNotificationCenter.current().add(request)
    }
}

/// Welcher Knopf in einer Mitteilung gedrückt wurde.
public struct NotificationActionRecord: Codable, Sendable, Equatable {
    public var actionIdentifier: String
    public var receivedAt: Date

    public init(actionIdentifier: String, receivedAt: Date = .now) {
        self.actionIdentifier = actionIdentifier
        self.receivedAt = receivedAt
    }

    public var title: String {
        switch actionIdentifier {
        case NotificationIDs.Action.taken: "Genommen"
        case NotificationIDs.Action.snooze10: "In 10 Min"
        case NotificationIDs.Action.skip: "Auslassen"
        case UNNotificationDefaultActionIdentifier: "Mitteilung geöffnet"
        case UNNotificationDismissActionIdentifier: "Mitteilung verworfen"
        default: actionIdentifier
        }
    }

    /// `true` für die drei eigenen Knöpfe (nicht für Öffnen/Verwerfen).
    public var isCustomAction: Bool {
        [NotificationIDs.Action.taken, NotificationIDs.Action.snooze10, NotificationIDs.Action.skip]
            .contains(actionIdentifier)
    }
}
