import Foundation
import TagwerkCore
import UIKit

/// Gemeinsamer Speicher von App und Widget.
///
/// Die ID wird einmal zur Laufzeit aufgelöst, weil sie beim Signieren mit einer
/// kostenlosen Apple-ID umbenannt wird. Quellen: `ALTAppGroups` in der Info.plist
/// (SideStore/AltStore) und das eingebettete Provisioning-Profil (z. B. iloader).
/// In der Widget-Extension wird zusätzlich die Info.plist der Haupt-App gelesen.
public enum AppGroup {
    public static let identifier: String = AppGroupResolver.resolve(
        infoDictionary: mergedInfoDictionary(),
        profileAppGroups: SigningInfo.loadProfile()?.appGroups ?? []
    )

    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    public static var isAvailable: Bool { containerURL != nil }

    /// `nil`, wenn die Signatur keine App Group enthält. Dann hätte `UserDefaults(suiteName:)`
    /// nur einen lokalen, nicht geteilten Speicher geliefert.
    public static var defaults: UserDefaults? {
        isAvailable ? UserDefaults(suiteName: identifier) : nil
    }

    /// `true` bei Installation über SideStore, AltStore oder iloader mit kostenloser Apple-ID.
    public static var isSideloaded: Bool {
        AppGroupResolver.isSideloaded(infoDictionary: mergedInfoDictionary())
            || SigningInfo.currentStatus().kind == .freeAppleID
    }

    static func mergedInfoDictionary() -> [String: Any] {
        var info = Bundle.main.infoDictionary ?? [:]
        let key = AppGroupResolver.sideloadInfoKey
        if info[key] == nil, Bundle.main.bundleURL.pathExtension == "appex" {
            // …/Tagwerk.app/PlugIns/TagwerkWidgets.appex → …/Tagwerk.app
            let hostURL = Bundle.main.bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            if let groups = Bundle(url: hostURL)?.infoDictionary?[key] {
                info[key] = groups
            }
        }
        return info
    }
}

/// Angaben zur laufenden App und zum Gerät.
public enum AppInfo {
    public static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    public static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    public static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "?"
    }

    @MainActor
    public static var osVersion: String {
        UIDevice.current.systemVersion
    }

    /// z. B. `iPhone15,4` für ein iPhone 15.
    public static var deviceModel: String {
        if let simulator = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "Simulator \(simulator)"
        }
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }

    public static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    /// `true`, wenn die UI-Tests die App gestartet haben (Screenshots im CI).
    public static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTesting")
    }
}

/// Liest das eingebettete Provisioning-Profil der App.
public enum SigningInfo {
    public static func loadProfile(bundle: Bundle = .main) -> ProvisioningProfile? {
        guard
            let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
            let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        return try? ProvisioningProfile.parse(data)
    }

    public static func currentStatus(bundle: Bundle = .main) -> SigningStatus {
        SigningStatus(profile: loadProfile(bundle: bundle))
    }

    /// Kurzbeschreibung für Einstellungen und Bericht.
    public static func describe(now: Date = .now) -> String {
        let status = currentStatus()
        switch status.kind {
        case .none:
            return AppInfo.isSimulator ? "Simulator (ohne Profil)" : SigningKind.none.displayName
        default:
            return "\(status.kind.displayName), \(status.remainingText(now: now))"
        }
    }
}
