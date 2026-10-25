import Foundation

/// Die Felder einer `embedded.mobileprovision`, die Tagwerk braucht.
///
/// Die Datei ist ein signierter CMS-Container. Darin steckt eine XML-Plist,
/// die wir direkt herausschneiden, ohne die Signatur zu prüfen. Wir lesen nur
/// Ablaufdatum, Art der Signatur und Berechtigungen.
public struct ProvisioningProfile: Sendable, Equatable {
    public var name: String?
    public var teamName: String?
    public var teamIdentifiers: [String]
    public var creationDate: Date?
    public var expirationDate: Date?
    public var provisionsAllDevices: Bool
    public var provisionedDeviceCount: Int
    public var getTaskAllow: Bool
    public var appGroups: [String]
    public var entitlementKeys: Set<String>

    public init(
        name: String? = nil,
        teamName: String? = nil,
        teamIdentifiers: [String] = [],
        creationDate: Date? = nil,
        expirationDate: Date? = nil,
        provisionsAllDevices: Bool = false,
        provisionedDeviceCount: Int = 0,
        getTaskAllow: Bool = false,
        appGroups: [String] = [],
        entitlementKeys: Set<String> = []
    ) {
        self.name = name
        self.teamName = teamName
        self.teamIdentifiers = teamIdentifiers
        self.creationDate = creationDate
        self.expirationDate = expirationDate
        self.provisionsAllDevices = provisionsAllDevices
        self.provisionedDeviceCount = provisionedDeviceCount
        self.getTaskAllow = getTaskAllow
        self.appGroups = appGroups
        self.entitlementKeys = entitlementKeys
    }

    public var hasHealthKit: Bool { entitlementKeys.contains("com.apple.developer.healthkit") }
    public var hasAppGroups: Bool { !appGroups.isEmpty }

    /// Art der Signatur, abgeleitet aus den Profilfeldern.
    public var kind: SigningKind {
        if provisionsAllDevices { return .enterprise }
        if getTaskAllow {
            // Profile kostenloser Apple-IDs gelten höchstens 7 Tage.
            if let creationDate, let expirationDate,
               expirationDate.timeIntervalSince(creationDate) <= 7 * 86_400 + 3_600 {
                return .freeAppleID
            }
            return .development
        }
        return .adHoc
    }
}

public enum ProvisioningProfileError: Error, Equatable {
    case plistNotFound
    case invalidPlist
}

extension ProvisioningProfile {
    /// Liest ein Profil aus den Rohdaten einer `embedded.mobileprovision`.
    public static func parse(_ data: Data) throws -> ProvisioningProfile {
        guard
            let start = data.range(of: Data("<?xml".utf8)),
            let end = data.range(of: Data("</plist>".utf8), options: .backwards),
            start.lowerBound < end.upperBound
        else {
            throw ProvisioningProfileError.plistNotFound
        }

        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        let object = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)
        guard let dict = object as? [String: Any] else {
            throw ProvisioningProfileError.invalidPlist
        }

        let entitlements = dict["Entitlements"] as? [String: Any] ?? [:]

        return ProvisioningProfile(
            name: dict["Name"] as? String,
            teamName: dict["TeamName"] as? String,
            teamIdentifiers: dict["TeamIdentifier"] as? [String] ?? [],
            creationDate: dict["CreationDate"] as? Date,
            expirationDate: dict["ExpirationDate"] as? Date,
            provisionsAllDevices: dict["ProvisionsAllDevices"] as? Bool ?? false,
            provisionedDeviceCount: (dict["ProvisionedDevices"] as? [String])?.count ?? 0,
            getTaskAllow: entitlements["get-task-allow"] as? Bool ?? false,
            appGroups: entitlements["com.apple.security.application-groups"] as? [String] ?? [],
            entitlementKeys: Set(entitlements.keys)
        )
    }
}

/// Wie die laufende App signiert ist.
public enum SigningKind: String, Sendable, Codable, CaseIterable {
    /// Kostenlose Apple-ID, z. B. über SideStore. Läuft nach 7 Tagen ab.
    case freeAppleID
    /// Bezahlter Developer-Account, Development-Profil.
    case development
    case adHoc
    case enterprise
    /// Kein Profil in der App: Simulator, TestFlight oder App Store.
    case none

    public var displayName: String {
        switch self {
        case .freeAppleID: "Kostenlose Apple-ID (7 Tage)"
        case .development: "Developer-Account (Development)"
        case .adHoc: "Ad-hoc"
        case .enterprise: "Enterprise"
        case .none: "Kein Profil (Simulator, TestFlight oder App Store)"
        }
    }
}
