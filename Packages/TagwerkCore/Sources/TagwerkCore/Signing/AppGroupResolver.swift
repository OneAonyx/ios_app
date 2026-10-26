import Foundation

/// Findet die App-Group-ID, die zur Laufzeit wirklich gilt.
///
/// Beim Signieren mit einer kostenlosen Apple-ID werden App Groups umbenannt
/// (z. B. `group.de.tagwerk.app.ABCDE12345`). SideStore und AltStore schreiben die
/// neuen IDs in den Info.plist-Schlüssel `ALTAppGroups`. Andere Werkzeuge wie iloader
/// tun das nicht, dort steht die ID nur im eingebetteten Provisioning-Profil.
/// Deshalb werden beide Quellen geprüft. Ohne Umbenennung gilt die feste ID.
public enum AppGroupResolver {
    public static let sideloadInfoKey = "ALTAppGroups"

    public static func resolve(
        infoDictionary: [String: Any]?,
        profileAppGroups: [String] = [],
        defaultIdentifier: String = TagwerkIDs.appGroup
    ) -> String {
        let sideloaded = infoDictionary?[sideloadInfoKey] as? [String] ?? []
        // Platzhalter wie `group.*` sind keine nutzbaren IDs.
        let candidates = (sideloaded + profileAppGroups).filter { !$0.contains("*") }
        if let match = candidates.first(where: {
            $0 == defaultIdentifier || $0.hasPrefix(defaultIdentifier + ".")
        }) {
            return match
        }
        return candidates.first ?? defaultIdentifier
    }

    /// `true`, wenn die App über SideStore/AltStore umbenannte App Groups hat.
    public static func isSideloaded(infoDictionary: [String: Any]?) -> Bool {
        !(infoDictionary?[sideloadInfoKey] as? [String] ?? []).isEmpty
    }
}
