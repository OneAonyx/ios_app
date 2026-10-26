import AlarmKit
import Foundation
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Stellt Wecker (AlarmKit) für Medikamente mit Erinnerungsart „Wecker“.
///
/// Rollierend für die nächsten 48 Stunden. Jede Einnahme bekommt eine feste UUID
/// (aus der `DoseID`), damit Abhaken in Widget, Mitteilung oder App den passenden
/// Wecker abbestellen kann. Der Wecker hat einen Knopf „Genommen“.
@MainActor
enum MedicationAlarmScheduler {
    static let horizon: TimeInterval = 48 * 3_600
    /// Eigene Wecker mit Inhalt (Titel), damit fremde (z. B. Testwecker) unberührt bleiben.
    private static let storedKey = "tagwerk.alarms.medication"

    static func reschedule(medications: [Medication], now: Date = .now, calendar: Calendar) async {
        guard AlarmProbe.isAuthorized else { return }
        var desired: [String: (dose: ScheduledDose, medication: Medication, signature: String)] = [:]
        for medication in medications where medication.isActive && medication.reminderStyle == .alarm && medication.schedule.isScheduled {
            let entries = medication.entries(from: now, to: now.addingTimeInterval(horizon), now: now, calendar: calendar)
            for entry in entries where entry.isOpen && entry.dose.date > now.addingTimeInterval(30) {
                let id = StableUUID.make(from: entry.id).uuidString
                let signature = "\(medication.displayName)|\(medication.detail(for: entry.dose.amount))|\(medication.colorName)"
                desired[id] = (entry.dose, medication, signature)
            }
        }

        let manager = AlarmManager.shared
        let scheduledIDs = Set(manager.alarms.map(\.id.uuidString))
        var stored = storedAlarms()

        // Nicht mehr gewünschte oder geänderte Wecker abbestellen.
        for (id, signature) in stored where desired[id]?.signature != signature {
            if let uuid = UUID(uuidString: id) {
                try? manager.cancel(id: uuid)
            }
            stored[id] = nil
        }

        for (id, item) in desired where stored[id] == nil || !scheduledIDs.contains(id) {
            guard let uuid = UUID(uuidString: id) else { continue }
            do {
                try await schedule(id: uuid, dose: item.dose, medication: item.medication)
                stored[id] = item.signature
            } catch {
                print("Tagwerk: Wecker konnte nicht gestellt werden: \(error)")
            }
        }
        saveStoredAlarms(stored)
    }

    /// Nach dem Abhaken: Wecker dieser Einnahme abbestellen.
    static func cancel(doseID: String) {
        let uuid = StableUUID.make(from: doseID)
        try? AlarmManager.shared.cancel(id: uuid)
        var stored = storedAlarms()
        stored[uuid.uuidString] = nil
        saveStoredAlarms(stored)
    }

    private static func schedule(id: UUID, dose: ScheduledDose, medication: Medication) async throws {
        let title = LocalizedStringResource("\(medication.displayName)")
        let takenButton = AlarmButton(text: "Genommen", textColor: .white, systemImageName: "checkmark.circle.fill")
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: title, secondaryButton: takenButton, secondaryButtonBehavior: .custom)
        } else {
            alert = AlarmPresentation.Alert(
                title: title,
                stopButton: AlarmButton(text: "Stopp", textColor: .white, systemImageName: "stop.circle"),
                secondaryButton: takenButton,
                secondaryButtonBehavior: .custom
            )
        }
        let attributes = AlarmAttributes<TagwerkAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert, countdown: nil, paused: nil),
            metadata: TagwerkAlarmMetadata(purpose: "medication", doseID: dose.id, detail: medication.detail(for: dose.amount)),
            tintColor: ListColor.color(named: medication.colorName)
        )
        let configuration = AlarmManager.AlarmConfiguration<TagwerkAlarmMetadata>.alarm(
            schedule: .fixed(dose.date),
            attributes: attributes,
            stopIntent: nil,
            secondaryIntent: TakeDoseIntent(doseID: dose.id, source: "alarm"),
            sound: .default
        )
        _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
    }

    private static func storedAlarms() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: storedKey) as? [String: String] ?? [:]
    }

    private static func saveStoredAlarms(_ alarms: [String: String]) {
        UserDefaults.standard.set(alarms, forKey: storedKey)
    }
}
