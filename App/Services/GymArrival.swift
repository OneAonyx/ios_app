import CoreLocation
import Foundation
import TagwerkCore
import TagwerkKit
import UserNotifications

/// Gym-Ankunft: Erreichst du den gespeicherten Ort, kommt einmal am Tag eine Mitteilung
/// „Du bist im Gym – Pull starten?“. Braucht den Ortszugriff „Immer“.
@MainActor
@Observable
final class GymArrival {
    static let shared = GymArrival()

    private static let monitorName = "OrbitGym"
    private static let conditionID = "gym"
    static let radius: CLLocationDistance = 150

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var monitor: CLMonitor?
    @ObservationIgnored private var eventsTask: Task<Void, Never>?

    private(set) var authorization: CLAuthorizationStatus

    private init() {
        authorization = manager.authorizationStatus
    }

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: SettingsKeys.gymArrival) }

    var gymLocation: CLLocationCoordinate2D? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: SettingsKeys.gymLatitude) != nil else { return nil }
        return CLLocationCoordinate2D(latitude: defaults.double(forKey: SettingsKeys.gymLatitude), longitude: defaults.double(forKey: SettingsKeys.gymLongitude))
    }

    var hasAlwaysAccess: Bool { authorization == .authorizedAlways }

    func refreshAuthorization() {
        authorization = manager.authorizationStatus
    }

    /// Beim App-Start: Überwachung wieder aufnehmen, damit Ereignisse aus dem Hintergrund ankommen.
    func startIfEnabled() {
        guard isEnabled, gymLocation != nil, !AppInfo.isUITesting else { return }
        Task { await startMonitoring() }
    }

    /// Aktuellen Standort als Gym speichern. Fragt nach dem Ortszugriff.
    func saveCurrentLocation() async -> Bool {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if let location = update.location, location.horizontalAccuracy < 200 {
                    let defaults = UserDefaults.standard
                    defaults.set(location.coordinate.latitude, forKey: SettingsKeys.gymLatitude)
                    defaults.set(location.coordinate.longitude, forKey: SettingsKeys.gymLongitude)
                    refreshAuthorization()
                    return true
                }
                if update.authorizationDenied || update.authorizationDeniedGlobally {
                    refreshAuthorization()
                    return false
                }
            }
        } catch {
            return false
        }
        return false
    }

    /// Einschalten: Ortszugriff „Immer“ anfragen und den Bereich überwachen.
    func enable() async {
        UserDefaults.standard.set(true, forKey: SettingsKeys.gymArrival)
        if manager.authorizationStatus != .authorizedAlways {
            manager.requestAlwaysAuthorization()
        }
        await startMonitoring()
    }

    func disable() async {
        UserDefaults.standard.set(false, forKey: SettingsKeys.gymArrival)
        eventsTask?.cancel()
        eventsTask = nil
        if let monitor {
            await monitor.remove(Self.conditionID)
        }
    }

    private func startMonitoring() async {
        guard let center = gymLocation else { return }
        let monitor: CLMonitor
        if let existing = self.monitor {
            monitor = existing
        } else {
            monitor = await CLMonitor(Self.monitorName)
            self.monitor = monitor
        }
        let condition = CLMonitor.CircularGeographicCondition(center: center, radius: Self.radius)
        await monitor.add(condition, identifier: Self.conditionID, assuming: .unsatisfied)
        guard eventsTask == nil else { return }
        eventsTask = Task { [weak self] in
            do {
                for try await event in await monitor.events where event.identifier == Self.conditionID && event.state == .satisfied {
                    await self?.arrived(at: event.date)
                }
            } catch {}
        }
    }

    private func arrived(at date: Date) async {
        let calendar = AppModel.calendar
        let defaults = UserDefaults.standard
        let dayKey = Self.dayKey(date, calendar: calendar)
        guard defaults.string(forKey: SettingsKeys.gymLastNotified) != dayKey else { return }
        defaults.set(dayKey, forKey: SettingsKeys.gymLastNotified)
        if TrainingActions.activeSession(in: AppModel.shared.context) != nil { return }

        let snapshot = TrainingSnapshotWriter.read()
        let content = UNMutableNotificationContent()
        content.title = "Du bist im Gym"
        content.body = snapshot.nextDayName.isEmpty ? "Training starten?" : "\(snapshot.nextDayName) starten?"
        content.sound = .default
        content.userInfo = [NotificationIDs.trainingKey: "gym"]
        let request = UNNotificationRequest(identifier: "gym.arrival.\(dayKey)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}
