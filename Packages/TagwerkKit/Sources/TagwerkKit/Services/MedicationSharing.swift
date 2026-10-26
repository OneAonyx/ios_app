import Foundation
import SwiftData
import TagwerkCore
import UserNotifications
import WidgetKit

/// Schreibt die Einnahmen von heute und morgen in den gemeinsamen Speicher, damit
/// Widgets, Kontrollzentrum und Siri sie ohne Datenbank lesen können.
@MainActor
public enum MedicationSnapshotWriter {
    public static func makeSnapshot(medications: [Medication], now: Date = .now, calendar: Calendar) -> MedicationWidgetSnapshot {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 2, to: start) ?? start.addingTimeInterval(2 * 86_400)
        var doses: [MedicationWidgetSnapshot.Dose] = []
        var lowStock: [String] = []
        for medication in medications where medication.isActive {
            for entry in medication.entries(from: start, to: end, now: now, calendar: calendar) {
                let state: MedicationWidgetSnapshot.Dose.State
                switch entry.state {
                case .taken: state = .taken
                case .skipped: state = .skipped
                default: state = .open
                }
                doses.append(MedicationWidgetSnapshot.Dose(
                    id: entry.id,
                    medicationID: medication.stableID,
                    name: medication.displayName,
                    detail: medication.detail(for: entry.dose.amount),
                    time: entry.dose.date,
                    colorName: medication.colorName,
                    symbol: medication.symbol,
                    state: state
                ))
            }
            if let forecast = medication.forecast(now: now, calendar: calendar), forecast.needsRefill {
                lowStock.append(medication.displayName)
            }
        }
        return MedicationWidgetSnapshot(writtenAt: now, doses: doses, lowStock: lowStock)
    }

    /// Schreibt den Stand und aktualisiert Widgets nur, wenn sich etwas geändert hat
    /// (Widgets haben ein begrenztes Aktualisierungs-Budget).
    public static func write(context: ModelContext, now: Date = .now, calendar: Calendar) {
        let snapshot = makeSnapshot(medications: MedicationActions.fetchAll(in: context), now: now, calendar: calendar)
        write(snapshot)
    }

    public static func write(_ snapshot: MedicationWidgetSnapshot) {
        guard let defaults = AppGroup.defaults, let data = try? snapshot.encoded() else { return }
        let previous = read()
        defaults.set(data, forKey: SharedKeys.medicationSnapshot)
        if previous.doses != snapshot.doses || previous.lowStock != snapshot.lowStock {
            reloadWidgets()
        }
    }

    public nonisolated static func read() -> MedicationWidgetSnapshot {
        MedicationWidgetSnapshot.decode(AppGroup.defaults?.data(forKey: SharedKeys.medicationSnapshot)) ?? .empty
    }

    public nonisolated static func reloadWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.medication)
        ControlCenter.shared.reloadControls(ofKind: WidgetKinds.medicationControl)
    }
}

/// Nimmt Einnahmen von außerhalb der App entgegen (Widget, Kontrollzentrum, Siri, Wecker,
/// Mitteilung).
///
/// Läuft der Code in der App, verarbeitet `handler` die Einnahme sofort (Datenbank,
/// Erinnerungen, Wecker). In der Widget-Erweiterung landet sie in einer Warteschlange,
/// die die App beim nächsten Öffnen übernimmt; das Widget zeigt sie sofort als erledigt.
public enum DoseActionCenter {
    @MainActor public static var handler: (@MainActor (PendingDoseAction) async -> Void)?
    /// In der App gesetzt: schreibt den Stand für Widgets neu (z. B. vor einer Siri-Antwort).
    @MainActor public static var refreshSnapshot: (@MainActor () -> Void)?

    /// Aktueller Stand für Siri und Kontrollzentrum, in der App vorher frisch geschrieben.
    @MainActor
    public static func currentSnapshot() -> MedicationWidgetSnapshot {
        refreshSnapshot?()
        return MedicationSnapshotWriter.read()
    }

    @MainActor
    public static func submit(_ action: PendingDoseAction) async {
        if let handler {
            await handler(action)
        } else {
            enqueue(action)
        }
    }

    /// Warteschlange + sofortige Anzeige im Widget + Mitteilungen dieser Einnahme entfernen.
    @MainActor
    public static func enqueue(_ action: PendingDoseAction) {
        if let defaults = AppGroup.defaults {
            let data = PendingDoseQueue.appending(action, to: defaults.data(forKey: SharedKeys.pendingDoseActions))
            defaults.set(data, forKey: SharedKeys.pendingDoseActions)
        }
        var snapshot = MedicationSnapshotWriter.read()
        if snapshot.apply(action) {
            MedicationSnapshotWriter.write(snapshot)
        }
        MedicationNotifications.removeNotifications(forDose: action.doseID)
    }

    /// Holt die Warteschlange ab und leert sie.
    public static func takeQueued() -> [PendingDoseAction] {
        guard let defaults = AppGroup.defaults else { return [] }
        let actions = PendingDoseQueue.decode(defaults.data(forKey: SharedKeys.pendingDoseActions))
        defaults.removeObject(forKey: SharedKeys.pendingDoseActions)
        return actions
    }
}

/// Hilfen für Medikamenten-Mitteilungen.
public enum MedicationNotifications {
    /// Entfernt geplante und angezeigte Mitteilungen einer Einnahme.
    public static func removeNotifications(forDose doseID: String) {
        let ids = [
            NotificationIDs.Prefix.medication + doseID,
            NotificationIDs.Prefix.medicationFollowUp + doseID,
            NotificationIDs.Prefix.snooze + doseID,
        ]
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    /// „In 10 Min“: dieselbe Mitteilung noch einmal.
    public static func snooze(doseID: String, title: String, body: String, minutes: Int = 10) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = NotificationIDs.Category.medication
        content.threadIdentifier = "tagwerk.medication"
        content.userInfo = [NotificationIDs.doseIDKey: doseID]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(1, minutes) * 60), repeats: false)
        let request = UNNotificationRequest(identifier: NotificationIDs.Prefix.snooze + doseID, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
