import Foundation
import SwiftData
import TagwerkCore

/// Version 8 des Datenmodells (Phase 8): Tageswerte aus Apple Health, die ein Kurzbefehl
/// an Orbit übergibt. Alle Modelle aus V7 bleiben unverändert (leichte Migration).
public enum TagwerkSchemaV8: VersionedSchema {
    public static let versionIdentifier = Schema.Version(8, 0, 0)

    public static var models: [any PersistentModel.Type] {
        TagwerkSchemaV7.models + [HealthDay.self]
    }

    /// Schritte, Strecke, Stockwerke, Schlaf und Ruhepuls eines Tages.
    @Model
    public final class HealthDay {
        public var stableID: String = UUID().uuidString
        public var day: Date = Date()
        public var steps: Int?
        public var distanceKm: Double?
        public var flights: Int?
        public var sleepHours: Double?
        public var restingHeartRate: Int?
        public var updatedAt: Date = Date()

        public init(day: Date, stableID: String = UUID().uuidString) {
            self.stableID = stableID
            self.day = day
        }
    }
}

public typealias HealthDay = TagwerkSchemaV8.HealthDay

public extension TagwerkSchemaV8.HealthDay {
    var fact: HealthDayFact {
        HealthDayFact(day: day, steps: steps, distanceKm: distanceKm, flights: flights, sleepHours: sleepHours, restingHeartRate: restingHeartRate)
    }

    func apply(_ fact: HealthDayFact) {
        steps = fact.steps
        distanceKm = fact.distanceKm
        flights = fact.flights
        sleepHours = fact.sleepHours
        restingHeartRate = fact.restingHeartRate
    }
}
