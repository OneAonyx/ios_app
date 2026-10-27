import Foundation

/// Was Orbit im aktuellen Fokus-Modus zeigt (Einstellungen → Fokus → Orbit).
public struct FocusFilterState: Codable, Sendable, Equatable {
    public var hideTraining: Bool
    public var hideNutrition: Bool
    /// Nur Aufgaben dieser Liste auf „Heute“ (stableID), `nil` = alle.
    public var listID: String?
    public var listName: String?

    public init(hideTraining: Bool = false, hideNutrition: Bool = false, listID: String? = nil, listName: String? = nil) {
        self.hideTraining = hideTraining
        self.hideNutrition = hideNutrition
        self.listID = listID
        self.listName = listName
    }

    public static let none = FocusFilterState()

    public var isActive: Bool { self != .none }

    /// „Training und Ernährung ausgeblendet · nur Liste Arbeit“
    public var summary: String {
        var hidden: [String] = []
        if hideTraining { hidden.append("Training") }
        if hideNutrition { hidden.append("Ernährung") }
        var parts: [String] = []
        if !hidden.isEmpty {
            parts.append("\(hidden.joined(separator: " und ")) ausgeblendet")
        }
        if let listName { parts.append("nur Liste \(listName)") }
        return parts.isEmpty ? "alles sichtbar" : parts.joined(separator: " · ")
    }
}
