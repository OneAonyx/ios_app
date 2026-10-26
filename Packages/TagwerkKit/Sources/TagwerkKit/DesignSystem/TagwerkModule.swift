import SwiftUI

/// Die Hauptbereiche der App, wie sie in der Tab-Leiste erscheinen.
public enum TagwerkModule: String, CaseIterable, Identifiable, Hashable, Sendable {
    case today
    case planner
    case training
    case nutrition
    case health
    case search

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .today: "Heute"
        case .planner: "Planer"
        case .training: "Training"
        case .nutrition: "Ernährung"
        case .health: "Gesundheit"
        case .search: "Suche"
        }
    }

    public var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .planner: "checklist"
        case .training: "dumbbell"
        case .nutrition: "fork.knife"
        case .health: "heart"
        case .search: "magnifyingglass"
        }
    }

    public var accent: Color {
        switch self {
        case .today: ModuleAccent.today
        case .planner: ModuleAccent.tasks
        case .training: ModuleAccent.training
        case .nutrition: ModuleAccent.nutrition
        case .health: ModuleAccent.health
        case .search: Color.secondary
        }
    }

    /// In welcher Phase der Bereich gebaut wird (für die Platzhalter in Phase 0).
    public var plannedPhase: Int {
        switch self {
        case .today, .planner, .search: 1
        case .training: 3
        case .nutrition: 4
        case .health: 2
        }
    }

    /// Was hier entsteht, als kurze Liste für den Platzhalter.
    public var upcomingFeatures: [String] {
        switch self {
        case .today:
            ["Als Nächstes fällig", "Medikamente des Tages", "Fokus 3", "Zeitstrahl", "Abendrückblick"]
        case .planner:
            ["Aufgaben mit Listen und Wiederholungen", "Agenda der nächsten 14 Tage", "Wochenansicht", "Termine in Apple Kalender"]
        case .training:
            ["Dein Oberkörper-4er-Plan", "Satz-Tracking mit Gewichtsvorschlag", "Pausen-Timer in der Dynamic Island", "Volumen und Rekorde"]
        case .nutrition:
            ["Histamin-Lexikon mit Bewertung 0–3", "Barcode- und Zutatenlisten-Scan", "Ernährungstagebuch", "Einkaufsliste und Rezepte"]
        case .health:
            ["Medikamente mit Erinnerungen und Wecker", "Einnahmeplan-Kalender", "Symptomtagebuch", "Apple-Health-Daten"]
        case .search:
            ["Aufgaben, Lebensmittel, Übungen, Medikamente und Rezepte durchsuchen"]
        }
    }
}
