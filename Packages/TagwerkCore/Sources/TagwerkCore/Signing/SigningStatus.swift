import Foundation

/// Ablaufstatus der Signatur, für den Hinweis „App läuft bald ab“.
public struct SigningStatus: Sendable, Equatable {
    public enum Level: String, Sendable, Equatable {
        case ok
        case expiresSoon
        case expired
        /// Kein Ablaufdatum bekannt (z. B. Simulator oder TestFlight).
        case unknown
    }

    public let kind: SigningKind
    public let expirationDate: Date?

    public init(kind: SigningKind, expirationDate: Date?) {
        self.kind = kind
        self.expirationDate = expirationDate
    }

    public init(profile: ProvisioningProfile?) {
        self.init(kind: profile?.kind ?? .none, expirationDate: profile?.expirationDate)
    }

    public func remaining(now: Date) -> TimeInterval? {
        expirationDate.map { $0.timeIntervalSince(now) }
    }

    /// `expiresSoon`, sobald weniger als `warnBefore` Sekunden übrig sind (Standard: 2 Tage).
    public func level(now: Date, warnBefore: TimeInterval = 2 * 86_400) -> Level {
        guard let remaining = remaining(now: now) else { return .unknown }
        if remaining <= 0 { return .expired }
        if remaining <= warnBefore { return .expiresSoon }
        return .ok
    }

    /// Kurzer deutscher Text, z. B. „noch 3 Tage“ oder „abgelaufen“.
    public func remainingText(now: Date) -> String {
        guard let remaining = remaining(now: now) else { return "kein Ablaufdatum" }
        if remaining <= 0 { return "abgelaufen" }
        let days = Int(remaining / 86_400)
        if days >= 2 { return "noch \(days) Tage" }
        if days == 1 { return "noch 1 Tag" }
        let hours = Int(remaining / 3_600)
        if hours >= 1 { return "noch \(hours) Std." }
        return "unter 1 Std."
    }
}
