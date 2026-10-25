import Foundation

/// Baut den Aufruf eines Kurzbefehls über `shortcuts://x-callback-url/run-shortcut`.
///
/// Die Kurzbefehle-App ruft danach eine der drei Rücksprung-URLs auf:
/// `tagwerk://claude/success/<id>?result=…`, `…/cancel/<id>` oder
/// `…/error/<id>?errorMessage=…`. Die Request-ID steht im Pfad, damit sie
/// erhalten bleibt, egal wie Kurzbefehle die Parameter anhängt.
public struct ShortcutRunRequest: Sendable, Equatable {
    public enum Input: Sendable, Equatable {
        case none
        case text(String)
        case clipboard
    }

    public var shortcutName: String
    public var input: Input
    public var requestID: String
    public var callbackScheme: String

    public init(
        shortcutName: String = TagwerkIDs.claudeShortcutName,
        input: Input,
        requestID: String,
        callbackScheme: String = TagwerkIDs.urlScheme
    ) {
        self.shortcutName = shortcutName
        self.input = input
        self.requestID = requestID
        self.callbackScheme = callbackScheme
    }

    public func callbackURL(_ outcome: ClaudeCallback.Outcome) -> URL {
        let id = URLEncoding.strict(requestID)
        // Nur unreservierte Zeichen, daher immer eine gültige URL.
        return URL(string: "\(callbackScheme)://claude/\(outcome.rawValue)/\(id)")!
    }

    public func url() -> URL {
        var parameters: [(String, String)] = [("name", shortcutName)]
        switch input {
        case .none:
            break
        case .text(let text):
            parameters.append(("input", "text"))
            parameters.append(("text", text))
        case .clipboard:
            parameters.append(("input", "clipboard"))
        }
        parameters.append(("x-success", callbackURL(.success).absoluteString))
        parameters.append(("x-cancel", callbackURL(.cancel).absoluteString))
        parameters.append(("x-error", callbackURL(.error).absoluteString))

        let query = parameters
            .map { "\($0.0)=\(URLEncoding.strict($0.1))" }
            .joined(separator: "&")
        return URL(string: "shortcuts://x-callback-url/run-shortcut?\(query)")!
    }
}

/// Ein Rücksprung von der Kurzbefehle-App zu Tagwerk.
public struct ClaudeCallback: Sendable, Equatable {
    public enum Outcome: String, Sendable, Equatable {
        case success
        case cancel
        case error
    }

    public var outcome: Outcome
    public var requestID: String?
    public var result: String?
    public var errorMessage: String?

    public init(outcome: Outcome, requestID: String?, result: String? = nil, errorMessage: String? = nil) {
        self.outcome = outcome
        self.requestID = requestID
        self.result = result
        self.errorMessage = errorMessage
    }

    /// Liest `tagwerk://claude/<outcome>/<id>?result=…`. Andere URLs ergeben `nil`.
    public static func parse(_ url: URL, expectedScheme: String = TagwerkIDs.urlScheme) -> ClaudeCallback? {
        guard url.scheme?.lowercased() == expectedScheme.lowercased(), url.host == "claude" else {
            return nil
        }
        let segments = url.pathComponents.filter { $0 != "/" }
        guard let first = segments.first, let outcome = Outcome(rawValue: first) else {
            return nil
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return ClaudeCallback(
            outcome: outcome,
            requestID: segments.count > 1 ? segments[1] : nil,
            result: items.first { $0.name == "result" }?.value,
            errorMessage: items.first { $0.name == "errorMessage" }?.value
        )
    }
}

public enum URLEncoding {
    /// Nur RFC-3986-unreservierte ASCII-Zeichen bleiben stehen. Alles andere,
    /// auch Umlaute, `&`, `+`, `=` und Zeilenumbrüche, wird kodiert.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    public static func strict(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }
}
