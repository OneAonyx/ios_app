import Foundation
import TagwerkCore

/// Zweiter Speicherort für die Sicherung, z. B. ein Ordner in iCloud Drive.
///
/// Der Ordner wird einmal im Dateien-Dialog gewählt und als Lesezeichen gemerkt. Jede Sicherung
/// wird danach zusätzlich dorthin kopiert; auch dort bleiben die letzten 14. iCloud Drive lädt die
/// Dateien selbst hoch, ein Developer-Account ist dafür nicht nötig.
@MainActor
public enum ExternalBackup {
    static let bookmarkKey = "tagwerk.backup.externalBookmark"
    static let nameKey = "tagwerk.backup.externalName"
    static let lastKey = "tagwerk.backup.externalLastAt"
    static let errorKey = "tagwerk.backup.externalError"

    private static var defaults: UserDefaults { .standard }

    public static var isConfigured: Bool { defaults.data(forKey: bookmarkKey) != nil }

    /// Name des Ordners, z. B. „Orbit“.
    public static var folderName: String? { defaults.string(forKey: nameKey) }

    public static var lastCopy: Date? {
        let value = defaults.double(forKey: lastKey)
        return value > 0 ? Date(timeIntervalSince1970: value) : nil
    }

    public static var lastError: String? { defaults.string(forKey: errorKey) }

    /// Ordner aus dem Dateien-Dialog merken.
    public static func setFolder(_ url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(data, forKey: bookmarkKey)
        defaults.set(url.lastPathComponent, forKey: nameKey)
        defaults.removeObject(forKey: errorKey)
        defaults.removeObject(forKey: lastKey)
    }

    public static func remove() {
        for key in [bookmarkKey, nameKey, lastKey, errorKey] {
            defaults.removeObject(forKey: key)
        }
    }

    /// Kopiert eine Sicherung in den Ordner und räumt dort alte Stände auf.
    @discardableResult
    public static func copy(_ file: URL, now: Date = .now) -> Bool {
        guard let bookmark = defaults.data(forKey: bookmarkKey) else { return false }
        do {
            var isStale = false
            let folder = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
            let accessing = folder.startAccessingSecurityScopedResource()
            defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
            if isStale, let fresh = try? folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                defaults.set(fresh, forKey: bookmarkKey)
            }

            let target = folder.appendingPathComponent(file.lastPathComponent)
            var coordinationError: NSError?
            var writeError: Error?
            NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordinationError) { url in
                do {
                    let manager = FileManager.default
                    if manager.fileExists(atPath: url.path) {
                        try manager.removeItem(at: url)
                    }
                    try manager.copyItem(at: file, to: url)
                } catch {
                    writeError = error
                }
            }
            if let error = coordinationError ?? writeError {
                throw error
            }

            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            for name in BackupRetention.filesToDelete(names, keep: BackupService.keepCount) {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
            }
            defaults.set(now.timeIntervalSince1970, forKey: lastKey)
            defaults.removeObject(forKey: errorKey)
            return true
        } catch {
            defaults.set(error.localizedDescription, forKey: errorKey)
            return false
        }
    }
}
