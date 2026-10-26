import Foundation

/// Die sechs Testläufe aus Phase 0.
public enum SystemCheckID: String, CaseIterable, Codable, Sendable, Identifiable {
    case installation
    case healthKit
    case appGroup
    case alarmKit
    case notifications
    case claudeBridge

    public var id: String { rawValue }

    public var number: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }

    public var title: String {
        switch self {
        case .installation: "Installation & Signatur"
        case .healthKit: "Apple Health"
        case .appGroup: "Widget-Daten (App Group)"
        case .alarmKit: "Wecker (AlarmKit)"
        case .notifications: "Mitteilungen mit Aktionen"
        case .claudeBridge: "Claude-Brücke"
        }
    }

    /// Was geprüft wird, in einem Satz.
    public var summary: String {
        switch self {
        case .installation:
            "Zeigt, wie die App signiert ist und wann die Signatur abläuft."
        case .healthKit:
            "Fragt die Health-Berechtigung an und liest deine heutigen Schritte."
        case .appGroup:
            "Schreibt einen Wert in den gemeinsamen Speicher, den das Widget anzeigt."
        case .alarmKit:
            "Stellt einen Testwecker in 1 Minute. Er soll auch im Stummmodus klingeln."
        case .notifications:
            "Schickt in 10 Sekunden eine Mitteilung mit den Knöpfen „Genommen“, „In 10 Min“ und „Auslassen“."
        case .claudeBridge:
            "Schickt eine Testanfrage über den Kurzbefehl „\(TagwerkIDs.claudeShortcutName)“ an Claude und prüft die Antwort."
        }
    }

    /// SF-Symbol für die Liste.
    public var systemImage: String {
        switch self {
        case .installation: "checkmark.seal"
        case .healthKit: "heart"
        case .appGroup: "square.on.square"
        case .alarmKit: "alarm"
        case .notifications: "bell.badge"
        case .claudeBridge: "sparkles"
        }
    }
}

public enum SystemCheckState: Codable, Sendable, Equatable {
    case pending
    case running
    /// Der Test läuft, wartet aber auf dich (z. B. „Tippe auf einen Knopf in der Mitteilung“).
    case waitingForUser(String)
    case passed(String)
    case failed(String)
    /// Auf diesem Gerät oder mit dieser Signatur nicht möglich.
    case unavailable(String)

    public var symbol: String {
        switch self {
        case .pending: "○"
        case .running: "…"
        case .waitingForUser: "⏳"
        case .passed: "✅"
        case .failed: "❌"
        case .unavailable: "➖"
        }
    }

    public var label: String {
        switch self {
        case .pending: "Offen"
        case .running: "Läuft"
        case .waitingForUser: "Wartet auf dich"
        case .passed: "OK"
        case .failed: "Fehlgeschlagen"
        case .unavailable: "Nicht verfügbar"
        }
    }

    public var detail: String? {
        switch self {
        case .pending, .running: nil
        case .waitingForUser(let text), .passed(let text), .failed(let text), .unavailable(let text): text
        }
    }

    public var isFinal: Bool {
        switch self {
        case .passed, .failed, .unavailable: true
        case .pending, .running, .waitingForUser: false
        }
    }
}

public struct SystemCheckResult: Codable, Sendable, Equatable, Identifiable {
    public var id: SystemCheckID
    public var state: SystemCheckState
    public var updatedAt: Date?

    public init(id: SystemCheckID, state: SystemCheckState = .pending, updatedAt: Date? = nil) {
        self.id = id
        self.state = state
        self.updatedAt = updatedAt
    }

    /// Ein Ergebnis pro Test, alle offen.
    public static func initial() -> [SystemCheckResult] {
        SystemCheckID.allCases.map { SystemCheckResult(id: $0) }
    }
}

/// Angaben zum Gerät und zur App für den Bericht.
public struct SystemCheckEnvironment: Sendable, Equatable {
    public var appVersion: String
    public var buildNumber: String
    public var osVersion: String
    public var deviceModel: String
    public var bundleIdentifier: String
    public var signing: String

    public init(
        appVersion: String,
        buildNumber: String,
        osVersion: String,
        deviceModel: String,
        bundleIdentifier: String,
        signing: String
    ) {
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.bundleIdentifier = bundleIdentifier
        self.signing = signing
    }
}

/// Text-Bericht zum Kopieren, damit du die Ergebnisse an Claude schicken kannst.
public enum SystemCheckReport {
    public static func render(
        results: [SystemCheckResult],
        environment: SystemCheckEnvironment,
        generatedAt: Date,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = timeZone
        formatter.dateFormat = "dd.MM.yyyy HH:mm"

        var lines: [String] = [
            "Orbit Systemcheck – \(formatter.string(from: generatedAt))",
            "App \(environment.appVersion) (\(environment.buildNumber)) · iOS \(environment.osVersion) · \(environment.deviceModel)",
            "Bundle-ID: \(environment.bundleIdentifier)",
            "Signatur: \(environment.signing)",
            "",
        ]

        let byID = Dictionary(results.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        for id in SystemCheckID.allCases {
            let state = byID[id]?.state ?? .pending
            var line = "\(state.symbol) \(id.number). \(id.title): \(state.label)"
            if let detail = state.detail, !detail.isEmpty {
                line += " – \(detail)"
            }
            lines.append(line)
        }

        let passed = results.filter { if case .passed = $0.state { true } else { false } }.count
        lines.append("")
        lines.append("\(passed) von \(SystemCheckID.allCases.count) Tests bestanden.")
        return lines.joined(separator: "\n")
    }
}
