import Foundation
import SwiftData

/// Erstellt den SwiftData-Speicher.
///
/// Liegt im App-Group-Container. Fehlt die App Group, landet er im normalen App-Container.
/// iCloud-Sync ist aus, bis ein Developer-Account vorhanden ist (siehe docs/PHASE0-ERGEBNIS.md).
public enum TagwerkStore {
    public static let fileName = "Tagwerk.store"
    /// Aktuelle Schema-Version. Ändert sie sich, wird der Speicher vorher kopiert.
    public static let schemaVersion = 4
    static let schemaVersionKey = "tagwerk.store.schemaVersion"

    public static var storeURL: URL? {
        AppGroup.containerURL?.appendingPathComponent(fileName)
    }

    @MainActor
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let url = inMemory ? nil : (storeURL ?? defaultStoreURL)
        return try makeContainer(at: url)
    }

    /// `url == nil` erstellt einen Speicher nur im Arbeitsspeicher (UI-Tests, Vorschauen).
    @MainActor
    public static func makeContainer(at url: URL?, defaults: UserDefaults = .standard) throws -> ModelContainer {
        let schema = Schema(versionedSchema: TagwerkSchemaV4.self)
        let configuration: ModelConfiguration
        if let url {
            copyBeforeMigrationIfNeeded(storeURL: url, defaults: defaults)
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        }
        let container = try ModelContainer(
            for: schema,
            migrationPlan: TagwerkMigrationPlan.self,
            configurations: [configuration]
        )
        if url != nil {
            defaults.set(schemaVersion, forKey: schemaVersionKey)
        }
        return container
    }

    /// Standardort, falls die App Group fehlt.
    static var defaultStoreURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("default.store")
    }

    /// Kopiert die Datenbank (inkl. `-wal`/`-shm`) einmal vor einer Schema-Änderung,
    /// z. B. nach „Tagwerk-vor-v2.store“ (interner Dateiname). Die Kopie bleibt liegen, bis die nächste
    /// Migration sie ersetzt.
    static func copyBeforeMigrationIfNeeded(storeURL: URL, defaults: UserDefaults) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: storeURL.path) else { return }
        let stored = defaults.integer(forKey: schemaVersionKey)
        // 0 = noch nie gesetzt: Speicher stammt aus Version 0.2 (Schema 1).
        guard stored < schemaVersion else { return }

        let folder = storeURL.deletingLastPathComponent()
        let base = storeURL.deletingPathExtension().lastPathComponent
        for suffix in ["", "-wal", "-shm"] {
            let source = folder.appendingPathComponent(storeURL.lastPathComponent + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let target = folder.appendingPathComponent("\(base)-vor-v\(schemaVersion).store\(suffix)")
            try? fileManager.removeItem(at: target)
            try? fileManager.copyItem(at: source, to: target)
        }
    }
}
