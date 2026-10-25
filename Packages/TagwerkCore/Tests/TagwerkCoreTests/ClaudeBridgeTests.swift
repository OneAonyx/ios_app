import Foundation
import Testing
@testable import TagwerkCore

@Suite("Kurzbefehl-URL & Rücksprung")
struct ShortcutsURLTests {
    private func url(_ string: String) -> URL {
        guard let url = URL(string: string) else { fatalError("Ungültige Test-URL: \(string)") }
        return url
    }

    @Test func buildsRunShortcutURLWithStrictEncoding() throws {
        let request = ShortcutRunRequest(input: .text("Grüße & Test = 1+1\nZeile 2"), requestID: "ABC123")
        let url = request.url()
        let string = url.absoluteString

        #expect(string.hasPrefix("shortcuts://x-callback-url/run-shortcut?"))
        #expect(string.contains("name=Tagwerk%20Claude"))
        #expect(string.contains("input=text"))
        #expect(string.contains("text=Gr%C3%BC%C3%9Fe%20%26%20Test%20%3D%201%2B1%0AZeile%202"))
        #expect(string.contains("x-success=tagwerk%3A%2F%2Fclaude%2Fsuccess%2FABC123"))
        #expect(string.contains("x-cancel=tagwerk%3A%2F%2Fclaude%2Fcancel%2FABC123"))
        #expect(string.contains("x-error=tagwerk%3A%2F%2Fclaude%2Ferror%2FABC123"))

        // Der Text kommt beim Zurücklesen unverändert heraus.
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "text" }?.value == "Grüße & Test = 1+1\nZeile 2")
    }

    @Test func clipboardInputHasNoTextParameter() {
        let string = ShortcutRunRequest(input: .clipboard, requestID: "X").url().absoluteString
        #expect(string.contains("input=clipboard"))
        #expect(!string.contains("text="))
    }

    @Test func parsesSuccessCallbackWithResult() throws {
        let callback = try #require(ClaudeCallback.parse(url("tagwerk://claude/success/ABC123?result=%7B%22ok%22%3Atrue%7D")))
        #expect(callback.outcome == .success)
        #expect(callback.requestID == "ABC123")
        #expect(callback.result == "{\"ok\":true}")
    }

    @Test func parsesCancelAndError() throws {
        let cancel = try #require(ClaudeCallback.parse(url("tagwerk://claude/cancel/ID1")))
        #expect(cancel.outcome == .cancel)
        #expect(cancel.requestID == "ID1")
        #expect(cancel.result == nil)

        let error = try #require(ClaudeCallback.parse(url("tagwerk://claude/error/ID2?errorMessage=Kurzbefehl%20fehlt")))
        #expect(error.outcome == .error)
        #expect(error.errorMessage == "Kurzbefehl fehlt")
    }

    @Test func callbackRoundTripsThroughRequest() throws {
        let request = ShortcutRunRequest(input: .none, requestID: "R-42")
        let back = try #require(ClaudeCallback.parse(request.callbackURL(.success)))
        #expect(back.requestID == "R-42")
    }

    @Test func ignoresForeignURLs() {
        #expect(ClaudeCallback.parse(url("https://claude/success/1")) == nil)
        #expect(ClaudeCallback.parse(url("tagwerk://today")) == nil)
        #expect(ClaudeCallback.parse(url("tagwerk://claude/unknown/1")) == nil)
    }
}

@Suite("Claude-Antworten auslesen")
struct ClaudeResponseExtractorTests {
    private struct Sample: Decodable, Equatable {
        var a: Int
        var text: String?
    }

    @Test func plainJSON() {
        #expect(ClaudeResponseExtractor.decodeFirst(Sample.self, from: #"{"a":1}"#) == Sample(a: 1))
    }

    @Test func jsonInsideFencedBlockWithProse() {
        let text = """
        Klar, hier ist dein Ergebnis:

        ```json
        {"a": 2, "text": "Hallo"}
        ```

        Viel Erfolg!
        """
        #expect(ClaudeResponseExtractor.decodeFirst(Sample.self, from: text) == Sample(a: 2, text: "Hallo"))
    }

    @Test func bracesInsideStringsDoNotBreakMatching() {
        let text = #"Vorher {kein json} dann {"a":3,"text":"Klammer } und \" Zitat {"} danach"#
        #expect(ClaudeResponseExtractor.decodeFirst(Sample.self, from: text) == Sample(a: 3, text: "Klammer } und \" Zitat {"))
    }

    @Test func nestedObjects() {
        let text = #"Antwort: {"outer":{"inner":{"x":1}},"a":4}"#
        #expect(ClaudeResponseExtractor.firstBalancedObject(in: text) == #"{"outer":{"inner":{"x":1}},"a":4}"#)
        #expect(ClaudeResponseExtractor.decodeFirst(Sample.self, from: text) == Sample(a: 4))
    }

    @Test func typographicQuotesAreRepaired() {
        let text = "{\u{201C}a\u{201D}: 5}"
        #expect(ClaudeResponseExtractor.decodeFirst(Sample.self, from: text) == Sample(a: 5))
    }

    @Test func noJSONReturnsNil() {
        #expect(ClaudeResponseExtractor.decodeFirst(Sample.self, from: "Leider kann ich das nicht.") == nil)
        #expect(ClaudeResponseExtractor.decodeFirst(Sample.self, from: "{ unvollständig") == nil)
    }

    @Test func unclosedFenceIsIgnored() {
        #expect(ClaudeResponseExtractor.fencedBlocks(in: "```json\n{\"a\":1}") == [])
    }
}

@Suite("Claude-Verbindungstest")
struct ClaudePingTests {
    @Test func promptContainsNonceAndFormat() {
        let prompt = ClaudePing.prompt(nonce: "7F3A9C21")
        #expect(prompt.contains(#""echo":"7F3A9C21""#))
        #expect(prompt.contains(ClaudePing.format))
    }

    @Test func nonceHasEightCharacters() {
        let nonce = ClaudePing.makeNonce()
        #expect(nonce.count == 8)
        #expect(nonce != ClaudePing.makeNonce())
    }

    @Test func verifiesCorrectAnswer() {
        let answer = #"{"format":"tagwerk.ping.v1","ok":true,"echo":"AB12CD34"}"#
        #expect(ClaudePing.verify(response: answer, nonce: "AB12CD34") == .ok)
    }

    @Test func verifiesAnswerWithChatter() {
        let answer = "Gern!\n```json\n{\"format\":\"tagwerk.ping.v1\",\"ok\":true,\"echo\":\"AB12CD34\"}\n```"
        #expect(ClaudePing.verify(response: answer, nonce: "AB12CD34").isOK)
    }

    @Test func detectsProblems() {
        #expect(ClaudePing.verify(response: "Hallo", nonce: "X") == .noJSON)
        #expect(
            ClaudePing.verify(response: #"{"format":"anders","ok":true,"echo":"X"}"#, nonce: "X")
                == .wrongFormat("anders")
        )
        #expect(
            ClaudePing.verify(response: #"{"format":"tagwerk.ping.v1","ok":true,"echo":"Y"}"#, nonce: "X")
                == .wrongNonce(expected: "X", received: "Y")
        )
    }
}
