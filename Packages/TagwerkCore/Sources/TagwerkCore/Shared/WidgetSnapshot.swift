import Foundation

/// Was die App für das Systemcheck-Widget in den gemeinsamen Speicher schreibt.
public struct SystemCheckWidgetSnapshot: Codable, Sendable, Equatable {
    public var writtenAt: Date
    public var counter: Int
    public var appGroupID: String

    public init(writtenAt: Date, counter: Int, appGroupID: String) {
        self.writtenAt = writtenAt
        self.counter = counter
        self.appGroupID = appGroupID
    }

    public func encoded() throws -> Data {
        try SharedCoding.encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> SystemCheckWidgetSnapshot {
        try SharedCoding.decoder.decode(SystemCheckWidgetSnapshot.self, from: data)
    }
}

/// Gemeinsame JSON-Einstellungen für App und Widget, damit beide gleich kodieren.
public enum SharedCoding {
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
