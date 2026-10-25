import Foundation

/// Verbindungstest der Claude-Brücke: Tagwerk schickt eine Zufallskennung,
/// Claude soll sie in einem festen JSON-Format zurückgeben.
public enum ClaudePing {
    public static let format = "tagwerk.ping.v1"

    public struct Payload: Codable, Sendable, Equatable {
        public var format: String
        public var ok: Bool
        public var echo: String

        public init(format: String = ClaudePing.format, ok: Bool = true, echo: String) {
            self.format = format
            self.ok = ok
            self.echo = echo
        }
    }

    public enum Verification: Sendable, Equatable {
        case ok
        case noJSON
        case wrongFormat(String)
        case wrongNonce(expected: String, received: String)

        public var isOK: Bool { self == .ok }

        public var message: String {
            switch self {
            case .ok: "Antwort von Claude empfangen und geprüft."
            case .noJSON: "In der Antwort war kein gültiges JSON."
            case .wrongFormat(let format): "Unerwartetes Format: \(format)"
            case .wrongNonce(let expected, let received):
                "Kennung passt nicht (erwartet \(expected), erhalten \(received))."
            }
        }
    }

    /// 8 Zeichen, gut lesbar, z. B. `7F3A9C21`.
    public static func makeNonce() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8))
    }

    public static func prompt(nonce: String) -> String {
        """
        Das ist ein technischer Verbindungstest der App „Tagwerk“. \
        Antworte ausschließlich mit genau diesem JSON-Objekt, ohne weiteren Text und ohne Codeblock:
        {"format":"\(format)","ok":true,"echo":"\(nonce)"}
        """
    }

    public static func verify(response: String, nonce: String) -> Verification {
        guard let payload = ClaudeResponseExtractor.decodeFirst(Payload.self, from: response) else {
            return .noJSON
        }
        guard payload.format == format, payload.ok else {
            return .wrongFormat(payload.format)
        }
        guard payload.echo == nonce else {
            return .wrongNonce(expected: nonce, received: payload.echo)
        }
        return .ok
    }
}
