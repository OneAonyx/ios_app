import Foundation
import SwiftData

/// Erstellt den SwiftData-Speicher.
///
/// Liegt im App-Group-Container, damit Widgets später mitlesen können. Fehlt die
/// App Group, landet er im normalen App-Container. iCloud-Sync ist aus, bis ein
/// Developer-Account vorhanden ist (siehe docs/PHASE0-ERGEBNIS.md).
public enum TagwerkStore {
    public static let fileName = "Tagwerk.store"

    public static var storeURL: URL? {
        AppGroup.containerURL?.appendingPathComponent(fileName)
    }

    @MainActor
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: TagwerkSchemaV1.self)
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else if let url = storeURL {
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        }
        return try ModelContainer(
            for: schema,
            migrationPlan: TagwerkMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
