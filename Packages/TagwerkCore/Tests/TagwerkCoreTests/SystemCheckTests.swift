import Foundation
import Testing
@testable import TagwerkCore

@Suite("Systemcheck")
struct SystemCheckTests {
    private let environment = SystemCheckEnvironment(
        appVersion: "0.1.0",
        buildNumber: "7",
        osVersion: "26.1",
        deviceModel: "iPhone15,4",
        bundleIdentifier: "de.tagwerk.app.ABCDE12345",
        signing: "Kostenlose Apple-ID (7 Tage), noch 6 Tage"
    )

    @Test func hasSixChecksInPlanOrder() {
        #expect(SystemCheckID.allCases.map(\.number) == [1, 2, 3, 4, 5, 6])
        #expect(SystemCheckID.claudeBridge.summary.contains(TagwerkIDs.claudeShortcutName))
        #expect(SystemCheckResult.initial().allSatisfy { $0.state == .pending })
    }

    @Test func stateHelpers() {
        #expect(SystemCheckState.passed("x").isFinal)
        #expect(!SystemCheckState.waitingForUser("x").isFinal)
        #expect(SystemCheckState.failed("Grund").detail == "Grund")
        #expect(SystemCheckState.pending.detail == nil)
    }

    @Test func resultsRoundTripThroughJSON() throws {
        let results = [
            SystemCheckResult(id: .healthKit, state: .failed("Berechtigung fehlt"), updatedAt: Date(timeIntervalSince1970: 100)),
            SystemCheckResult(id: .alarmKit, state: .waitingForUser("Wecker gestellt"), updatedAt: nil),
        ]
        let data = try SharedCoding.encoder.encode(results)
        let decoded = try SharedCoding.decoder.decode([SystemCheckResult].self, from: data)
        #expect(decoded == results)
    }

    @Test func reportListsEveryCheck() throws {
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        // 26.10.2026 21:10 UTC = 22:10 Winterzeit in Berlin.
        let date = Date(timeIntervalSince1970: 1_793_049_000)
        let results = [
            SystemCheckResult(id: .installation, state: .passed("Signatur gültig")),
            SystemCheckResult(id: .healthKit, state: .unavailable("Kein HealthKit-Recht in der Signatur")),
            SystemCheckResult(id: .notifications, state: .failed("Mitteilungen abgelehnt")),
        ]
        let report = SystemCheckReport.render(results: results, environment: environment, generatedAt: date, timeZone: berlin)
        let lines = report.components(separatedBy: "\n")

        #expect(lines[0] == "Orbit Systemcheck – 26.10.2026 22:10")
        #expect(report.contains("App 0.1.0 (7) · iOS 26.1 · iPhone15,4"))
        #expect(report.contains("✅ 1. Installation & Signatur: OK – Signatur gültig"))
        #expect(report.contains("➖ 2. Apple Health: Nicht verfügbar – Kein HealthKit-Recht in der Signatur"))
        #expect(report.contains("○ 3. Widget-Daten (App Group): Offen"))
        #expect(report.contains("❌ 5. Mitteilungen mit Aktionen: Fehlgeschlagen – Mitteilungen abgelehnt"))
        #expect(report.contains("○ 6. Claude-Brücke: Offen"))
        #expect(report.hasSuffix("1 von 6 Tests bestanden."))
    }

    @Test func reportDateUsesGivenTimeZone() throws {
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        // 1. Juli 2026, 10:00 UTC = 12:00 Sommerzeit in Berlin.
        let date = Date(timeIntervalSince1970: 1_782_900_000)
        let report = SystemCheckReport.render(results: [], environment: environment, generatedAt: date, timeZone: berlin)
        #expect(report.hasPrefix("Orbit Systemcheck – 01.07.2026 12:00"))
    }
}

@Suite("Tageszeit & Widget-Daten")
struct SharedTests {
    @Test(arguments: [
        (3, DayPeriod.night), (5, .morning), (10, .morning), (11, .midday),
        (14, .afternoon), (18, .evening), (22, .evening), (23, .night),
    ])
    func dayPeriodFromHour(hour: Int, expected: DayPeriod) {
        #expect(DayPeriod(hour: hour) == expected)
    }

    @Test func greetings() {
        #expect(DayPeriod.morning.greeting == "Guten Morgen")
        #expect(DayPeriod.evening.greeting == "Guten Abend")
        #expect(DayPeriod.evening.prefersEveningReview)
        #expect(!DayPeriod.afternoon.prefersEveningReview)
    }

    @Test func widgetSnapshotRoundTrip() throws {
        let snapshot = SystemCheckWidgetSnapshot(
            writtenAt: Date(timeIntervalSince1970: 1_793_049_000),
            counter: 3,
            appGroupID: "group.de.tagwerk.app.ABCDE12345"
        )
        #expect(try SystemCheckWidgetSnapshot.decode(snapshot.encoded()) == snapshot)
    }
}
