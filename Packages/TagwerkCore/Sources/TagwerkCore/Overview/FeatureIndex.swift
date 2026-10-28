import Foundation

/// Wo eine Funktion in Orbit wohnt.
public enum FeatureArea: String, CaseIterable, Sendable, Identifiable {
    case today, planner, training, nutrition, health, settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .today: "Heute"
        case .planner: "Planer"
        case .training: "Training"
        case .nutrition: "Ernährung"
        case .health: "Gesundheit"
        case .settings: "Einstellungen"
        }
    }
}

/// Eine Funktion von Orbit: Name, Ort, Stichworte für die Suche.
public struct Feature: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let area: FeatureArea
    /// Wo sie zu finden ist, z. B. „Training → Statistik“.
    public let path: String
    public let symbol: String
    public let keywords: [String]
    /// Öffnet etwas zum Eintragen (statt einer Ansicht).
    public let isAction: Bool

    public init(_ id: String, _ title: String, area: FeatureArea, path: String, symbol: String, keywords: [String] = [], isAction: Bool = false) {
        self.id = id
        self.title = title
        self.area = area
        self.path = path
        self.symbol = symbol
        self.keywords = keywords
        self.isAction = isAction
    }
}

/// Verzeichnis aller Funktionen. Die Suche findet sie über Namen und Stichworte,
/// ohne Suchbegriff zeigt sie das ganze Verzeichnis nach Bereichen.
public enum FeatureIndex {
    public static let all: [Feature] = [
        // Heute
        Feature("quickAdd", "Neue Aufgabe", area: .today, path: "Heute → +", symbol: "plus.circle", keywords: ["aufgabe", "erfassen", "schnellerfassung", "notiz", "termin", "todo"], isAction: true),
        Feature("checkIn", "Check-in", area: .today, path: "Heute → Check-in", symbol: "heart.text.square", keywords: ["befinden", "stimmung", "schlaf", "energie", "stress", "laune"], isAction: true),
        Feature("review", "Wochenrückblick", area: .today, path: "Heute (sonntags)", symbol: "calendar.badge.checkmark", keywords: ["woche", "rückblick", "zusammenfassung", "statistik"]),
        Feature("periodReview", "Monats- und Jahresrückblick", area: .health, path: "Gesundheit → Einblicke → Monat und Jahr", symbol: "chart.xyaxis.line", keywords: ["monat", "jahr", "trend", "rückblick", "vergleich", "vormonat"]),
        Feature("journal", "Abend-Tagebuch", area: .today, path: "Heute (abends)", symbol: "book.closed", keywords: ["journal", "top 3", "morgen", "notiz", "dankbar"], isAction: true),
        Feature("dayClosing", "Tag abschließen", area: .today, path: "Heute (abends)", symbol: "moon.stars", keywords: ["abend", "abschluss", "verschieben", "morgen", "offen", "top 3"], isAction: true),
        Feature("weekPlanning", "Woche planen", area: .today, path: "Heute (sonntags)", symbol: "calendar.badge.plus", keywords: ["woche", "planen", "fokus", "trainingstage", "sonntag"], isAction: true),
        Feature("briefing", "Morgen-Briefing", area: .today, path: "Einstellungen → Erinnerungen", symbol: "sun.horizon", keywords: ["morgen", "briefing", "zusammenfassung", "mitteilung", "tagesüberblick"]),
        Feature("todayLayout", "Startseite anpassen", area: .today, path: "Heute → ganz unten oder Einstellungen → Startseite", symbol: "rectangle.3.group", keywords: ["karten", "reihenfolge", "ausblenden", "dashboard", "übersicht"]),
        Feature("claude", "Claude-Zentrale", area: .health, path: "Gesundheit → Einblicke", symbol: "sparkles", keywords: ["ki", "ai", "fragen", "plan anpassen", "rezeptideen"]),

        // Planer
        Feature("tasks", "Aufgaben und Listen", area: .planner, path: "Planer → Aufgaben", symbol: "checklist", keywords: ["liste", "heute", "geplant", "markiert", "erledigt", "eingang"]),
        Feature("agenda", "Agenda (14 Tage)", area: .planner, path: "Planer → Agenda", symbol: "list.bullet.rectangle", keywords: ["termine", "kalender", "vorschau", "nächste tage"]),
        Feature("week", "Wochenansicht", area: .planner, path: "Planer → Woche", symbol: "calendar", keywords: ["woche", "kalender", "verschieben"]),
        Feature("life", "Leben", area: .planner, path: "Planer → Leben", symbol: "leaf", keywords: ["routinen", "gewohnheiten", "verträge", "fristen", "geburtstage"]),
        Feature("habits", "Routinen und Gewohnheiten", area: .planner, path: "Planer → Leben", symbol: "repeat", keywords: ["routine", "gewohnheit", "serie", "streak", "morgenroutine"]),
        Feature("contracts", "Verträge und Fristen", area: .planner, path: "Planer → Leben", symbol: "doc.text", keywords: ["vertrag", "abo", "kündigung", "kosten", "tüv", "ausweis", "versicherung", "frist"]),
        Feature("birthdays", "Geburtstage", area: .planner, path: "Planer → Leben", symbol: "gift", keywords: ["geburtstag", "geschenk", "jahrestag"]),
        Feature("reminderImport", "Aus Apple Erinnerungen übernehmen", area: .planner, path: "Einstellungen → Daten und Sicherung", symbol: "square.and.arrow.down.on.square", keywords: ["import", "erinnerungen", "reminders", "übernehmen"]),

        // Training
        Feature("startWorkout", "Training starten", area: .training, path: "Training", symbol: "play.circle", keywords: ["einheit", "gym", "workout", "fitness"], isAction: true),
        Feature("trainingPlan", "Trainingsplan", area: .training, path: "Training → Plan", symbol: "list.number", keywords: ["plan", "split", "tage", "sätze", "wiederholungen", "deload"]),
        Feature("coach", "Plan-Check", area: .training, path: "Training → Plan-Check", symbol: "wand.and.stars", keywords: ["coach", "vorschläge", "plan anpassen", "stillstand", "sätze", "wiederholungsbereich", "tauschen"]),
        Feature("trainingStats", "Statistik und Muskel-Karte", area: .training, path: "Training → Statistik", symbol: "chart.bar", keywords: ["volumen", "sätze", "muskel", "karte", "kraftverlauf", "maximum"]),
        Feature("exerciseLibrary", "Übungen", area: .training, path: "Training → Übungen", symbol: "books.vertical", keywords: ["übung", "bibliothek", "technik", "alternativen"]),
        Feature("trainingProgress", "Fortschritt je Übung", area: .training, path: "Training → Fortschritt", symbol: "chart.line.uptrend.xyaxis", keywords: ["fortschritt", "zu schnell", "zu langsam", "stagnation", "bewertung"]),
        Feature("photos", "Fortschrittsfotos", area: .training, path: "Training → Fortschritt → Fotos", symbol: "photo.on.rectangle", keywords: ["foto", "bild", "vergleich", "vorher nachher"]),
        Feature("body", "Körper: Gewicht und Maße", area: .training, path: "Training → Körper", symbol: "figure.arms.open", keywords: ["gewicht", "maße", "größe", "taille", "oberarm", "waage"]),
        Feature("workoutHistory", "Alle Einheiten", area: .training, path: "Training → Letzte Einheiten → Alle", symbol: "clock.arrow.circlepath", keywords: ["verlauf", "historie", "vergangene"]),

        // Ernährung
        Feature("logMeal", "Mahlzeit eintragen", area: .nutrition, path: "Ernährung → +", symbol: "fork.knife", keywords: ["essen", "mahlzeit", "frühstück", "mittagessen", "abendessen", "snack"], isAction: true),
        Feature("water", "Wasser trinken (+250 ml)", area: .nutrition, path: "Heute → Schnell erfassen", symbol: "drop", keywords: ["wasser", "trinken", "glas"], isAction: true),
        Feature("lexicon", "Lebensmittel-Lexikon", area: .nutrition, path: "Ernährung → Lexikon", symbol: "text.book.closed", keywords: ["histamin", "lebensmittel", "verträglich", "liste", "bewertung"]),
        Feature("ingredientCheck", "Barcode und Zutaten prüfen", area: .nutrition, path: "Ernährung → Zutaten prüfen", symbol: "barcode.viewfinder", keywords: ["scan", "scanner", "barcode", "zutatenliste", "e-nummer", "kamera"]),
        Feature("shopping", "Einkaufsliste", area: .nutrition, path: "Ernährung → Einkauf", symbol: "cart", keywords: ["einkaufen", "supermarkt", "liste"]),
        Feature("recipes", "Rezepte", area: .nutrition, path: "Ernährung → Rezepte", symbol: "book", keywords: ["kochen", "rezept", "histaminarm", "eiweiß"]),
        Feature("mealPlan", "Wochen-Essensplan", area: .nutrition, path: "Ernährung → Wochenplan", symbol: "calendar.day.timeline.left", keywords: ["essensplan", "planen", "meal prep"]),
        Feature("patterns", "Muster und Auslöser", area: .nutrition, path: "Ernährung → Muster", symbol: "waveform.path.ecg", keywords: ["auslöser", "analyse", "verdacht", "unverträglichkeit", "trigger"]),
        Feature("addSymptom", "Beschwerde eintragen", area: .nutrition, path: "Heute → Schnell erfassen", symbol: "bandage", keywords: ["symptom", "kopfschmerz", "bauch", "juckreiz", "übelkeit"], isAction: true),
        Feature("symptoms", "Beschwerden (Verlauf)", area: .health, path: "Gesundheit → Beschwerden", symbol: "list.bullet.clipboard", keywords: ["symptome", "verlauf", "beschwerden"]),
        Feature("nutritionSettings", "Ziele für Eiweiß und Wasser", area: .nutrition, path: "Ernährung → Einstellungen", symbol: "slider.horizontal.3", keywords: ["eiweiß", "protein", "wasserziel", "ziel", "dao"]),

        // Gesundheit
        Feature("medications", "Medikamente", area: .health, path: "Gesundheit", symbol: "pills", keywords: ["tabletten", "einnahme", "vorrat", "wecker", "dosis"]),
        Feature("addMedication", "Medikament hinzufügen", area: .health, path: "Gesundheit → +", symbol: "plus.circle", keywords: ["neues medikament", "tablette"], isAction: true),
        Feature("addPain", "Schmerz eintragen", area: .health, path: "Heute → Schnell erfassen", symbol: "figure.stand", keywords: ["schmerz", "rücken", "knie", "körperkarte", "kopf"], isAction: true),
        Feature("painHistory", "Schmerzen (Verlauf)", area: .health, path: "Gesundheit → Arzt-Tagebuch → Schmerzen", symbol: "chart.dots.scatter", keywords: ["schmerzen", "verlauf", "körperkarte"]),
        Feature("addActivity", "Bewegung eintragen", area: .health, path: "Heute → Schnell erfassen", symbol: "figure.walk", keywords: ["sport", "spazieren", "radfahren", "laufen", "schwimmen"], isAction: true),
        Feature("activityHistory", "Bewegung (Verlauf)", area: .health, path: "Gesundheit → Arzt-Tagebuch → Bewegung", symbol: "figure.run", keywords: ["bewegung", "minuten", "who", "schritte"]),
        Feature("doctorReport", "Arztbericht (PDF)", area: .health, path: "Gesundheit → Arzt-Tagebuch → Arztbericht", symbol: "doc.richtext", keywords: ["arzt", "bericht", "pdf", "praxis", "ernährungsberatung", "tagebuch", "paket", "zip"]),
        Feature("healthBridge", "Apple Health", area: .health, path: "Gesundheit → Apple Health", symbol: "heart.text.square", keywords: ["health", "schritte", "schlaf", "puls", "kurzbefehl"]),

        // Einstellungen
        Feature("backup", "Datensicherung und iCloud Drive", area: .settings, path: "Einstellungen → Daten und Sicherung", symbol: "externaldrive.badge.icloud", keywords: ["sicherung", "backup", "icloud", "wiederherstellen", "umzug"]),
        Feature("exportTables", "Alle Daten als Tabellen", area: .settings, path: "Einstellungen → Daten und Sicherung → Export", symbol: "tablecells", keywords: ["export", "csv", "excel", "numbers", "tabelle"]),
        Feature("notifications", "Erinnerungen und Mitteilungen", area: .settings, path: "Einstellungen → Erinnerungen", symbol: "bell", keywords: ["mitteilung", "benachrichtigung", "erinnerung", "uhrzeit"]),
        Feature("calendars", "Kalender auswählen", area: .settings, path: "Einstellungen → Kalender", symbol: "calendar.badge.plus", keywords: ["kalender", "termine", "ausblenden"]),
        Feature("privacy", "App-Sperre und Gym-Ankunft", area: .settings, path: "Einstellungen → Datenschutz und Gym", symbol: "lock", keywords: ["face id", "sperre", "privat", "gym", "standort", "ort"]),
        Feature("shortcuts", "Kurzbefehle einrichten", area: .settings, path: "Einstellungen → Kurzbefehle", symbol: "square.stack.3d.up", keywords: ["kurzbefehl", "automation", "claude", "health", "siri"]),
        Feature("roadmap", "Fahrplan", area: .settings, path: "Einstellungen → Über Orbit", symbol: "map", keywords: ["phasen", "neu", "version", "pläne"]),
        Feature("systemCheck", "Systemcheck", area: .settings, path: "Einstellungen → Über Orbit", symbol: "checkmark.seal", keywords: ["test", "fehler", "signatur", "widget"]),
    ]

    public static func feature(id: String) -> Feature? {
        all.first { $0.id == id }
    }

    /// Nach Bereichen gruppiert, in fester Bereichs-Reihenfolge.
    public static var grouped: [(area: FeatureArea, features: [Feature])] {
        FeatureArea.allCases.compactMap { area in
            let items = all.filter { $0.area == area }
            return items.isEmpty ? nil : (area, items)
        }
    }

    /// Treffer nach Güte: Titelanfang vor Wortanfang vor Stichwort vor „enthält“.
    /// Mehrere Wörter müssen alle passen. Umlaute dürfen fehlen („uebungen“, „ubungen“).
    public static func search(_ query: String, limit: Int = 8) -> [Feature] {
        let words = normalize(query).split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }
        let scored = all.compactMap { feature -> (Feature, Int)? in
            let title = normalize(feature.title)
            let keywords = feature.keywords.map(normalize)
            let area = normalize(feature.area.title)
            var total = 0
            for word in words {
                let score = Self.score(word, title: title, keywords: keywords, area: area)
                guard score > 0 else { return nil }
                total += score
            }
            return (feature, total)
        }
        return scored
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : all.firstIndex(of: $0.0)! < all.firstIndex(of: $1.0)! }
            .prefix(limit)
            .map(\.0)
    }

    private static func score(_ word: String, title: String, keywords: [String], area: String) -> Int {
        if title.hasPrefix(word) { return 6 }
        let titleWords = title.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if titleWords.contains(where: { $0.hasPrefix(word) }) { return 5 }
        if keywords.contains(where: { $0.hasPrefix(word) }) { return 4 }
        if keywords.contains(where: { keyword in keyword.split(separator: " ").contains { $0.hasPrefix(word) } }) { return 3 }
        if word.count >= 3, title.contains(word) || keywords.contains(where: { $0.contains(word) }) { return 2 }
        if area.hasPrefix(word) { return 1 }
        return 0
    }

    /// Kleinbuchstaben, ohne Akzente, „ae/oe/ue“ wie „ä/ö/ü“.
    static func normalize(_ text: String) -> String {
        text.lowercased()
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .replacingOccurrences(of: "ae", with: "a")
            .replacingOccurrences(of: "oe", with: "o")
            .replacingOccurrences(of: "ue", with: "u")
            .replacingOccurrences(of: "ß", with: "ss")
    }
}
