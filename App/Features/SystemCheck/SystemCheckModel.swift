import Foundation
import Observation
import TagwerkCore
import TagwerkKit
import UIKit
import UserNotifications

/// Führt die sechs Phase-0-Tests aus und merkt sich die Ergebnisse.
@MainActor
@Observable
final class SystemCheckModel {
    private(set) var results: [SystemCheckResult]
    private(set) var widgetSnapshot: SystemCheckWidgetSnapshot?
    private(set) var lastClaudeResponse: String?

    @ObservationIgnored private var claudeNonce: String?
    @ObservationIgnored private var notificationRequestedAt: Date?

    private static let nonceKey = "tagwerk.systemcheck.claudeNonce"

    init() {
        results = SystemCheckStore.load()
        widgetSnapshot = WidgetDataStore.readSystemCheckSnapshot()
        claudeNonce = UserDefaults.standard.string(forKey: Self.nonceKey)
    }

    // MARK: - Zustand

    func state(for id: SystemCheckID) -> SystemCheckState {
        results.first { $0.id == id }?.state ?? .pending
    }

    var passedCount: Int {
        results.filter { result in
            if case .passed = result.state { return true }
            return false
        }.count
    }

    func needsConfirmation(_ id: SystemCheckID) -> Bool {
        guard id == .appGroup || id == .alarmKit else { return false }
        if case .waitingForUser = state(for: id) { return true }
        return false
    }

    private func set(_ id: SystemCheckID, _ state: SystemCheckState) {
        if let index = results.firstIndex(where: { $0.id == id }) {
            results[index].state = state
            results[index].updatedAt = .now
        } else {
            results.append(SystemCheckResult(id: id, state: state, updatedAt: .now))
        }
        SystemCheckStore.save(results)
    }

    // MARK: - Tests

    func run(_ id: SystemCheckID) async {
        set(id, .running)
        switch id {
        case .installation: runInstallation()
        case .healthKit: await runHealthKit()
        case .appGroup: runAppGroup()
        case .alarmKit: await runAlarmKit()
        case .notifications: await runNotifications()
        case .claudeBridge: await startClaudeBridge()
        }
    }

    /// Die Tests 1–3 brauchen nur eine Bestätigung im Health-Dialog.
    func runQuickChecks() async {
        await run(.installation)
        await run(.healthKit)
        await run(.appGroup)
    }

    private func runInstallation() {
        let now = Date.now
        guard let profile = SigningInfo.loadProfile() else {
            if AppInfo.isSimulator {
                set(.installation, .unavailable("Im Simulator gibt es kein Provisioning-Profil."))
            } else {
                set(.installation, .passed("Kein Profil eingebettet, vermutlich TestFlight oder App Store."))
            }
            return
        }
        let status = SigningStatus(profile: profile)
        let rights = "Health-Recht: \(profile.hasHealthKit ? "ja" : "nein") · App Group: \(profile.appGroups.first ?? "keine")"
        if status.level(now: now) == .expired {
            set(.installation, .failed("Signatur abgelaufen. \(rights)"))
        } else {
            set(.installation, .passed("\(profile.kind.displayName), \(status.remainingText(now: now)). \(rights)"))
        }
    }

    private func runHealthKit() async {
        guard HealthProbe.isHealthDataAvailable else {
            set(.healthKit, .unavailable("Apple Health ist auf diesem Gerät nicht verfügbar."))
            return
        }
        do {
            let steps = try await HealthProbe.requestStepsAccessAndReadToday()
            set(.healthKit, .passed(
                "Berechtigung angefragt, heute \(Int(steps)) Schritte gelesen. (0 kann auch heißen, dass Lesen abgelehnt wurde.)"
            ))
        } catch {
            set(.healthKit, .failed(error.localizedDescription))
        }
    }

    private func runAppGroup() {
        do {
            let snapshot = try WidgetDataStore.writeSystemCheckSnapshot()
            widgetSnapshot = snapshot
            set(.appGroup, .waitingForUser(
                "Wert #\(snapshot.counter) gespeichert in \(snapshot.appGroupID). Füge das Widget „Tagwerk Systemcheck“ zum Home-Bildschirm hinzu: Es sollte #\(snapshot.counter) zeigen."
            ))
        } catch {
            set(.appGroup, .failed(error.localizedDescription))
        }
    }

    private func runAlarmKit() async {
        do {
            guard try await AlarmProbe.requestAuthorization() else {
                set(.alarmKit, .failed("Wecker-Berechtigung abgelehnt. Ändern unter Einstellungen → Apps → Tagwerk."))
                return
            }
            let fireDate = Date.now.addingTimeInterval(60)
            try await AlarmProbe.scheduleTestAlarm(in: 60)
            set(.alarmKit, .waitingForUser(
                "Testwecker für \(fireDate.formatted(date: .omitted, time: .shortened)) gestellt. Schalte das iPhone stumm, sperre es und bestätige danach, ob er geklingelt hat."
            ))
        } catch {
            set(.alarmKit, .failed(error.localizedDescription))
        }
    }

    private func runNotifications() async {
        do {
            guard try await NotificationSetup.requestAuthorization() else {
                set(.notifications, .failed("Mitteilungen abgelehnt. Ändern unter Einstellungen → Apps → Tagwerk → Mitteilungen."))
                return
            }
            notificationRequestedAt = .now
            try await NotificationSetup.scheduleSystemCheckNotification(after: 10)
            set(.notifications, .waitingForUser(
                "Mitteilung kommt in 10 Sekunden. Sperre das iPhone, halte die Mitteilung gedrückt und tippe auf „Genommen“, „In 10 Min“ oder „Auslassen“."
            ))
        } catch {
            set(.notifications, .failed(error.localizedDescription))
        }
    }

    func handleNotificationAction(_ record: NotificationActionRecord) {
        if record.isCustomAction {
            set(.notifications, .passed("Knopf „\(record.title)“ kam in der App an."))
        } else if record.actionIdentifier == UNNotificationDefaultActionIdentifier {
            set(.notifications, .waitingForUser(
                "Mitteilung kam an und wurde geöffnet. Für den vollen Test: erneut testen, Mitteilung gedrückt halten und einen Knopf wählen."
            ))
        } else {
            set(.notifications, .waitingForUser("Mitteilung wurde verworfen. Bitte erneut testen und einen Knopf wählen."))
        }
    }

    /// Bestätigung für Tests, die nur du sehen kannst (Widget, Wecker).
    func confirm(_ id: SystemCheckID, worked: Bool) {
        switch id {
        case .appGroup:
            set(.appGroup, worked
                ? .passed("Widget zeigt den Wert aus der App (#\(widgetSnapshot?.counter ?? 0)).")
                : .failed("Widget zeigt den Wert nicht."))
        case .alarmKit:
            set(.alarmKit, worked
                ? .passed("Wecker hat im Stummmodus geklingelt.")
                : .failed("Wecker hat nicht geklingelt."))
        default:
            set(id, worked ? .passed("Von dir bestätigt.") : .failed("Von dir als nicht funktionierend markiert."))
        }
    }

    // MARK: - Claude-Brücke

    func startClaudeBridge() async {
        let nonce = makeNonce()
        _ = ClaudeBridgeInbox.take()
        let request = ShortcutRunRequest(input: .text(ClaudePing.prompt(nonce: nonce)), requestID: UUID().uuidString)
        set(.claudeBridge, .waitingForUser(
            "Kurzbefehl „\(TagwerkIDs.claudeShortcutName)“ läuft. Danach springt die Kurzbefehle-App zurück zu Tagwerk."
        ))
        let opened = await UIApplication.shared.open(request.url())
        if !opened {
            set(.claudeBridge, .failed("Die Kurzbefehle-App ließ sich nicht öffnen."))
        }
    }

    func handleClaudeCallback(_ callback: ClaudeCallback) {
        switch callback.outcome {
        case .cancel:
            set(.claudeBridge, .failed("Kurzbefehl abgebrochen."))
        case .error:
            set(.claudeBridge, .failed(
                callback.errorMessage ?? "Kurzbefehl meldet einen Fehler. Gibt es einen Kurzbefehl mit dem Namen „\(TagwerkIDs.claudeShortcutName)“?"
            ))
        case .success:
            let inbox = ClaudeBridgeInbox.take()
            if let result = callback.result, !result.isEmpty {
                verifyClaude(result, via: "Rückgabe des Kurzbefehls")
            } else if let inbox {
                verifyClaude(inbox, via: "Aktion „Claude-Antwort übernehmen“")
            } else {
                set(.claudeBridge, .failed(
                    "Der Kurzbefehl lief, gab aber keine Antwort zurück. Prüfe die letzten Aktionen in der Anleitung."
                ))
            }
        }
    }

    /// Ausweichweg: Anfrage kopieren, in der Claude-App einfügen, Antwort zurück einfügen.
    func copyClaudePrompt() {
        let nonce = claudeNonce ?? makeNonce()
        UIPasteboard.general.string = ClaudePing.prompt(nonce: nonce)
        set(.claudeBridge, .waitingForUser(
            "Anfrage kopiert. Füge sie in der Claude-App ein, kopiere Claudes Antwort und tippe hier auf „Einfügen“."
        ))
    }

    func verifyPasted(_ text: String) {
        verifyClaude(text, via: "Einfügen")
    }

    private func verifyClaude(_ text: String, via source: String) {
        lastClaudeResponse = text
        guard let nonce = claudeNonce else {
            set(.claudeBridge, .failed("Kein laufender Test. Starte den Test erneut."))
            return
        }
        let verification = ClaudePing.verify(response: text, nonce: nonce)
        if verification.isOK {
            set(.claudeBridge, .passed("Claude hat geantwortet, Kennung stimmt (\(source))."))
        } else {
            set(.claudeBridge, .failed("\(verification.message) (\(source))"))
        }
    }

    private func makeNonce() -> String {
        let nonce = ClaudePing.makeNonce()
        claudeNonce = nonce
        UserDefaults.standard.set(nonce, forKey: Self.nonceKey)
        return nonce
    }

    // MARK: - Rückkehr in die App, Bericht, Zurücksetzen

    /// Beim Zurückkehren in die App: Widget-Wert, Mitteilungs-Antwort und Claude-Briefkasten prüfen.
    func refreshOnActivate() {
        widgetSnapshot = WidgetDataStore.readSystemCheckSnapshot()
        if let record = SystemCheckStore.lastNotificationAction(),
           case .waitingForUser = state(for: .notifications),
           record.receivedAt > (notificationRequestedAt ?? .distantPast) {
            handleNotificationAction(record)
        }
        if let pending = ClaudeBridgeInbox.take() {
            verifyClaude(pending, via: "Aktion „Claude-Antwort übernehmen“")
        }
    }

    func reportText() -> String {
        let environment = SystemCheckEnvironment(
            appVersion: AppInfo.version,
            buildNumber: AppInfo.build,
            osVersion: AppInfo.osVersion,
            deviceModel: AppInfo.deviceModel,
            bundleIdentifier: AppInfo.bundleIdentifier,
            signing: SigningInfo.describe()
        )
        return SystemCheckReport.render(results: results, environment: environment, generatedAt: .now)
    }

    func copyReport() {
        UIPasteboard.general.string = reportText()
    }

    func reset() {
        results = SystemCheckResult.initial()
        SystemCheckStore.save(results)
        lastClaudeResponse = nil
        claudeNonce = nil
        notificationRequestedAt = nil
        UserDefaults.standard.removeObject(forKey: Self.nonceKey)
    }
}
