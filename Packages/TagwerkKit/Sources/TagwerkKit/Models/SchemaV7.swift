import Foundation
import SwiftData
import TagwerkCore

/// Version 7 des Datenmodells (Phase 7, Arzt-Tagebuch): Schmerzen, Bewegung und Tages-Vermerke
/// („keine Beschwerden“, „Ruhetag“). Alle Modelle aus V6 bleiben unverändert, deshalb ist der
/// Umstieg eine leichte Migration (nur neue Tabellen).
public enum TagwerkSchemaV7: VersionedSchema {
    public static let versionIdentifier = Schema.Version(7, 0, 0)

    public static var models: [any PersistentModel.Type] {
        TagwerkSchemaV6.models + [PainEntry.self, ActivityEntry.self, DiaryDay.self]
    }

    /// Ein Schmerz-Eintrag mit Körperregionen und Stärke 0–10.
    @Model
    public final class PainEntry {
        public var stableID: String = UUID().uuidString
        public var date: Date = Date()
        public var regionsRaw: [String] = []
        public var intensity: Int = 5
        public var qualitiesRaw: [String] = []
        public var durationMinutes: Int?
        public var triggersRaw: [String] = []
        public var reliefsRaw: [String] = []
        public var note: String = ""
        public var createdAt: Date = Date()

        public init(date: Date, regions: [BodyRegion] = [], intensity: Int = 5, stableID: String = UUID().uuidString, createdAt: Date = Date()) {
            self.stableID = stableID
            self.date = date
            self.regionsRaw = regions.map(\.rawValue)
            self.intensity = intensity
            self.createdAt = createdAt
        }
    }

    /// Bewegung oder Sport außerhalb des Gyms.
    @Model
    public final class ActivityEntry {
        public var stableID: String = UUID().uuidString
        public var date: Date = Date()
        public var kindRaw: String = ActivityKind.walking.rawValue
        public var minutes: Int = 30
        public var intensityRaw: Int = ActivityIntensity.moderate.rawValue
        public var note: String = ""
        public var createdAt: Date = Date()

        public init(date: Date, kind: ActivityKind, minutes: Int, intensity: ActivityIntensity, stableID: String = UUID().uuidString, createdAt: Date = Date()) {
            self.stableID = stableID
            self.date = date
            self.kindRaw = kind.rawValue
            self.minutes = minutes
            self.intensityRaw = intensity.rawValue
            self.createdAt = createdAt
        }
    }

    /// Vermerke für einen Tag: ausdrücklich keine Beschwerden, Ruhetag.
    @Model
    public final class DiaryDay {
        public var stableID: String = UUID().uuidString
        public var day: Date = Date()
        public var symptomFree: Bool = false
        public var restDay: Bool = false
        public var updatedAt: Date = Date()

        public init(day: Date, stableID: String = UUID().uuidString) {
            self.stableID = stableID
            self.day = day
        }
    }
}

public typealias PainEntry = TagwerkSchemaV7.PainEntry
public typealias ActivityEntry = TagwerkSchemaV7.ActivityEntry
public typealias DiaryDay = TagwerkSchemaV7.DiaryDay

public extension TagwerkSchemaV7.PainEntry {
    var regions: [BodyRegion] {
        get { regionsRaw.compactMap(BodyRegion.init(rawValue:)) }
        set { regionsRaw = newValue.map(\.rawValue) }
    }

    var qualities: [PainQuality] {
        get { qualitiesRaw.compactMap(PainQuality.init(rawValue:)) }
        set { qualitiesRaw = newValue.map(\.rawValue) }
    }

    var triggers: [PainTrigger] {
        get { triggersRaw.compactMap(PainTrigger.init(rawValue:)) }
        set { triggersRaw = newValue.map(\.rawValue) }
    }

    var reliefs: [PainRelief] {
        get { reliefsRaw.compactMap(PainRelief.init(rawValue:)) }
        set { reliefsRaw = newValue.map(\.rawValue) }
    }

    var fact: PainFact {
        PainFact(
            id: stableID, date: date, regions: regions, intensity: intensity, qualities: qualities,
            durationMinutes: durationMinutes, triggers: triggers, reliefs: reliefs, note: note
        )
    }
}

public extension TagwerkSchemaV7.ActivityEntry {
    var kind: ActivityKind {
        get { ActivityKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var intensity: ActivityIntensity {
        get { ActivityIntensity(rawValue: intensityRaw) ?? .moderate }
        set { intensityRaw = newValue.rawValue }
    }

    var fact: ActivityFact {
        ActivityFact(id: stableID, date: date, kind: kind, minutes: minutes, intensity: intensity, note: note)
    }
}
