import Foundation

/// Findet die App-Group-ID, die zur Laufzeit wirklich gilt.
///
/// SideStore und AltStore benennen App Groups beim Signieren mit einer
/// kostenlosen Apple-ID um (z. B. `group.de.tagwerk.app.ABCDE12345`) und
/// schreiben die neuen IDs in den Info.plist-Schlüssel `ALTAppGroups`.
/// Ohne Sideloading gilt die feste ID.
public enum AppGroupResolver {
    public static let sideloadInfoKey = "ALTAppGroups"

    public static func resolve(
        infoDictionary: [String: Any]?,
        defaultIdentifier: String = TagwerkIDs.appGroup
    ) -> String {
        let candidates = infoDictionary?[sideloadInfoKey] as? [String] ?? []
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
