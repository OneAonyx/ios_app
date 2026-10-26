# Plan: „Tagwerk“ – persönliche Alltags-App fürs iPhone

> **Hinweis:** „Tagwerk“ war der Arbeitstitel. Seit Version 0.4 heißt die App **Orbit**.

*(Arbeitstitel. Name lässt sich jederzeit ändern.)*

---

## 1. Kontext

**Ziel:** Eine native iPhone-App, die den ganzen Tag an einem Ort bündelt: Aufgaben, Kalender der nächsten Tage, Medikamente, Gesundheitsdaten (Apple Health), Histamin-Intoleranz (Ernährungs- und Symptomtagebuch), Gym-Tracking mit eigenem Trainingsplan und weitere Alltagsbereiche. Sie soll tief ins iPhone integriert sein: Widgets, Sperrbildschirm, Dynamic Island, Siri/Kurzbefehle, Wecker, Health und Kalender. Die Oberfläche soll modern, klar und aufgeräumt sein.

**Rahmenbedingungen (aus deinen Antworten):**

| Punkt | Stand | Folge für den Plan |
|---|---|---|
| Gerät | iPhone 15 (kein Pro), keine Apple Watch | Keine Apple-KI auf dem Gerät, kein Action Button. Dynamic Island, Widgets, Live Activities und StandBy gibt es. Ohne Watch kein Puls. |
| Rechner | Kein Mac | Die App wird in der Cloud gebaut (GitHub Actions mit macOS-Runner). Die Logik wird so getrennt, dass sie auch unter Linux testbar ist. |
| Installation | Erst kostenlos, später Developer-Account | Phase A: unsignierte IPA → **SideStore** mit kostenloser Apple-ID. Phase B: **TestFlight** mit Apple Developer Program (99 €/Jahr). Die App erkennt selbst, was in der jeweiligen Phase verfügbar ist. |
| KI | Claude, aber ohne API-Key und ohne Zusatzkosten | 1) Claude erstellt bei der Entwicklung alle Inhalte (Lebensmittel-Datenbank, Übungen, Rezepte, Startplan). 2) In der App gibt es feste Regeln, die ohne KI laufen. 3) Die **„Claude-Brücke“** nutzt die Kurzbefehl-Aktion „Ask Claude“ der Claude-App, also dein normales Claude-Konto. |
| Unverträglichkeit | Nur Histamin | Das Datenmodell bleibt offen für weitere Unverträglichkeiten (generische „Unverträglichkeits-Profile“). |
| Training | Muskelaufbau, ca. 1 Jahr Erfahrung, 4×/Woche Oberkörper. Bisheriger Split: Push / Pull / Arme / Brust+Rücken | Der Startplan baut genau auf diesem Split auf (siehe Abschnitt 9). |

**Was du vorbereiten musst (einmalig):** GitHub-Account, Apple-ID, einmalig einen Windows- oder Linux-PC (oder einen geliehenen Mac) für die SideStore-Einrichtung, und auf dem iPhone den Entwicklermodus (Einstellungen → Datenschutz & Sicherheit → Entwicklermodus). Für die Claude-Brücke die Claude-App auf dem iPhone.

---

## 2. Grundprinzipien

1. **Local-first & privat:** Alle Daten liegen auf dem iPhone (verschlüsselt per Data Protection). Es gibt keinen eigenen Server und kein Tracking. Netzwerk wird nur genutzt für (a) Barcode-Abfragen bei Open Food Facts und (b) die Claude-Brücke. Beides löst du selbst aus, und bei Claude siehst du vorher, welche Daten rausgehen.
2. **Alles ist „heute“-zentriert:** Die Startseite beantwortet: *Was steht an? Was ist als Nächstes fällig? Wie geht's mir?*
3. **Eine Logik, viele Vorlagen:** Aufgaben, Routinen, Fristen, Verträge und Geburtstage laufen über **eine** Aufgaben- und Wiederholungs-Engine, nur mit verschiedenen Vorlagen. Das hält die App schlank und einheitlich.
4. **Robust bei fehlenden Berechtigungen:** Jede Funktion prüft, ob sie verfügbar ist (Health erlaubt? App Group da? Wecker erlaubt?). Fehlt etwas, bietet die Oberfläche eine Alternative an statt eines Fehlers. So läuft dieselbe App kostenlos und mit Account.
5. **Kein Medizinprodukt:** Histamin-Bewertungen sind Orientierung, Erinnerungen ersetzen keinen Arzt. Ein kurzer, klarer Hinweis steht im Onboarding und in den Lebensmittel-Details.

---

## 3. Tech-Stack

| Bereich | Technik | Warum |
|---|---|---|
| Sprache/UI | **Swift 6** (strikte Nebenläufigkeit), **SwiftUI**, Observation (`@Observable`) | Native Integration, neues iOS-Design automatisch |
| Mindest-iOS | **iOS 26.0** (gebaut mit aktuellem Xcode 26.x/27). iOS-27-Extras per `if #available` | AlarmKit, Medications-API, neues Design. Das iPhone 15 unterstützt das. |
| Daten | **SwiftData** mit versioniertem Schema (`VersionedSchema` + `SchemaMigrationPlan`) von Anfang an | Apple-nativ, später mit CloudKit synchronisierbar |
| Diagramme | **Swift Charts** | Gewicht, Volumen, Symptome, Einnahmetreue |
| Gesundheit | **HealthKit** (inkl. Medications-API ab iOS 26, nur lesend) | Schritte, Gewicht, Schlaf, Symptome, Stimmung, Workouts, Ernährung |
| Kalender | **EventKit** | Termine lesen und anlegen |
| Erinnerungen | **UserNotifications** (mit Aktionsknöpfen) + **AlarmKit** (echter Wecker, der Stumm- und Fokusmodus durchbricht) | Medikamente zuverlässig |
| Systemintegration | **WidgetKit** (inkl. interaktiv, Sperrbildschirm, StandBy), **ActivityKit** (Live Activities/Dynamic Island), **Controls** (Kontrollzentrum), **App Intents** (Siri, Kurzbefehle, Spotlight, Fokus-Filter) | „Tief im iPhone“ |
| Scannen | **VisionKit DataScanner** (Barcode), **Vision** Texterkennung (Zutatenlisten) | Läuft auf dem iPhone 15 ohne Apple-KI |
| Onboarding-Tipps | **TipKit** | Dezente Hinweise statt Tutorial-Wand |
| Tests | **Swift Testing** (Logik, unter Linux), XCUITest (Screenshots im CI) | Prüfbar ohne Mac |
| Projekt | **XcodeGen** (`project.yml`) – keine `.xcodeproj` im Git | Projektdatei wird im CI erzeugt, also kein Xcode nötig |
| Abhängigkeiten | **Keine Fremdbibliotheken** (nur Apple-Frameworks + URLSession) | Wartungsarm, sicher |

---

## 4. Architektur

### 4.1 Projektstruktur (neues GitHub-Repo `tagwerk-ios`, privat)

```
tagwerk-ios/
├── project.yml                     # XcodeGen: App-Target + 1 Widget-Extension
├── App/
│   ├── TagwerkApp.swift            # Einstieg, ModelContainer, Dependency-Setup
│   ├── RootView.swift              # TabView (5 Tabs), Suche als Lupe auf „Heute“
│   ├── Features/
│   │   ├── Today/                  # Heute-Dashboard
│   │   ├── Planner/                # Aufgaben, Agenda, Woche
│   │   ├── Training/               # Pläne, Session, Bibliothek, Statistik, Körper
│   │   ├── Nutrition/              # Tagebuch, Lebensmittel, Scanner, Einkauf, Rezepte
│   │   ├── Health/                 # Medikamente, Symptome, Check-in, Health-Daten, Berichte
│   │   ├── Life/                   # Routinen, Fristen/Verträge, Geburtstage
│   │   ├── ClaudeBridge/           # Anfrage bauen, Vorschau, Import
│   │   ├── Search/                 # Globale Suche
│   │   ├── Onboarding/
│   │   └── Settings/
│   ├── Intents/                    # App Intents, App Shortcuts, Entities, Fokus-Filter
│   └── Resources/                  # Assets, Localizable.xcstrings (de), Seed-JSON
├── Widgets/                        # EINE Extension: Widgets, Live Activities, Controls, AlarmKit-UI
├── Packages/
│   ├── TagwerkCore/                # Reines Swift, Linux-kompatibel (keine Apple-Frameworks)
│   │   ├── Sources/TagwerkCore/
│   │   │   ├── Recurrence/         # Wiederholungsregeln (Aufgaben, Routinen, Medis)
│   │   │   ├── DateParsing/        # Deutscher Schnell-Eingabe-Parser
│   │   │   ├── Medication/         # Einnahmezeiten, Vorrat-Prognose, Bedarfs-Regeln
│   │   │   ├── Training/           # Progression, e1RM, Aufwärmen, Volumen, Deload
│   │   │   ├── Histamine/          # Zutaten-Parser, Scoring, Tageslast
│   │   │   ├── Insights/           # Symptom-Lebensmittel-Korrelation, Wochenstatistik
│   │   │   ├── ClaudeBridge/       # Prompt-Vorlagen, Antwort-Parser, Validierung
│   │   │   └── Notifications/      # Rollierende Planung (64er-Limit)
│   │   └── Tests/TagwerkCoreTests/
│   └── TagwerkKit/                 # Apple-spezifisch
│       ├── Models/                 # SwiftData @Model-Klassen + Schema-Versionen
│       ├── Services/               # Health, Calendar, Notification, Alarm, FoodLookup, Backup, Capabilities
│       └── DesignSystem/           # Farben, Typo, Abstände, Komponenten
├── Content/                        # Von Claude erstellte, versionierte Inhalte (JSON)
│   ├── foods.de.json               # ~400 Lebensmittel mit Histamin-Bewertung
│   ├── ingredient-rules.de.json    # ~150 Zutaten-Stichworte und E-Nummern
│   ├── exercises.de.json           # ~120 Übungen
│   ├── recipes.de.json             # ~30 histaminarme, proteinreiche Rezepte
│   └── plans/upper-4day.json       # Dein Startplan
├── Scripts/validate_content.swift  # Prüft Inhalte (Schema, Duplikate, Wertebereiche)
├── .github/workflows/
│   ├── core.yml                    # Linux: swift test + Content-Validierung (günstig)
│   ├── ios.yml                     # macOS: Build, UI-Tests, Screenshots, IPA
│   └── release.yml                 # Tag → IPA als GitHub-Release (später: TestFlight)
└── docs/ ARCHITECTURE.md · CONTENT.md · SIDELOAD.md · CLAUDE-BRIDGE.md
```

### 4.2 Schichten

- **TagwerkCore** enthält die gesamte Fachlogik als reine Funktionen und Structs, ohne SwiftUI, SwiftData oder HealthKit. Dadurch kann ich sie hier in der Linux-Umgebung kompilieren und testen.
- **TagwerkKit** enthält die Persistenz (SwiftData) und Services als Protokolle mit Live- und Mock-Implementierung (`HealthService`, `CalendarService`, `NotificationService`, `AlarmService`, `FoodLookupService`, `BackupService`, `ClaudeBridgeService`). Die Mocks werden für SwiftUI-Previews und UI-Tests im Simulator gebraucht.
- **App/Features** besteht aus SwiftUI-Views pro Feature. Ein `@Observable`-ViewModel gibt es nur, wo echte Logik nötig ist. Services kommen über das SwiftUI-Environment.
- **Capabilities-Registry** (`Capabilities.swift`): Sie prüft zur Laufzeit HealthKit, App Group, AlarmKit, Mitteilungen, Kalender und Kamera und steuert danach die Oberfläche. Zusätzlich liest sie das Ablaufdatum der Signatur aus `embedded.mobileprovision` und zeigt im SideStore-Betrieb einen Hinweis wie „App läuft in 2 Tagen ab – in SideStore aktualisieren“.
- **App-Group-Auflösung:** SideStore ändert Bundle-ID und App-Group-IDs (hängt die Team-ID an). `AppGroupResolver` liest deshalb zuerst den Info.plist-Schlüssel `ALTAppGroups`, den SideStore/AltStore setzen, und fällt sonst auf die feste ID zurück. Das wird in Phase 0 geprüft.
- **Nebenläufigkeit:** UI arbeitet mit dem Main-`ModelContext`. Importe, Seed-Daten und Backups laufen über einen `@ModelActor` im Hintergrund.

### 4.3 Datenmodell (SwiftData, von Anfang an CloudKit-tauglich)

**CloudKit-Regeln ab Tag 1**, damit der spätere Sync ohne Umbau geht: keine `@Attribute(.unique)`, jede Eigenschaft optional oder mit Standardwert, alle Beziehungen optional, keine `.deny`-Löschregel. Eindeutigkeit wird über ein `stableID: String` und eigene Deduplizierung gelöst.

| Entität | Wichtige Felder | Hinweise |
|---|---|---|
| `TaskItem` | title, notes, dueDate, dueTimeSet, priority (0–3), isFlagged, isDone, completedAt, estimateMin, list, tags, subtasks, recurrence, reminderOffsets, kind (`task`/`routine`/`deadline`/`contract`/`birthday`), meta (z. B. Kosten/Monat, Kündigungsfrist) | Eine Engine für alles |
| `TaskList` | name, icon, color, order, isArea | z. B. Persönlich, Haushalt, Arbeit |
| `RecurrenceRule` (Codable-Wert) | freq (täglich/wöchentlich/monatlich/jährlich), interval, weekdays, monthDay, mode (`fixed` / `afterCompletion`), end | „jeden 2. Di“, „3 Tage nach Erledigung“ |
| `Habit` + `HabitLog` | name, icon, target (Anzahl/Menge), schedule; date, value | Wasser, Dehnen, Lesen … |
| `Medication` | name, wirkstoff, form, strength+unit, appearance (Farbe/Form fürs Icon), instructions (nüchtern / vor dem Essen / mit Wasser), schedule, startDate, endDate, stock, refillThreshold, reminderStyle (`notification`/`alarm`), isCritical, linkedToMeals (z. B. DAO vor dem Essen), healthKitMedID | |
| `MedicationSchedule` (Codable) | type: `fixedTimes` / `weekdays` / `everyNDays` / `interval(h)` / `asNeeded(maxPerDay, minGapH)` / `cycle(on, off)` / `taper(steps)`; times (Uhrzeit als Stunde+Minute, Ortszeit) | Uhrzeiten als lokale Uhrzeit gespeichert, damit Sommer-/Winterzeit stimmt |
| `DoseLog` | medication, scheduledAt, takenAt, status (genommen / ausgelassen / verschoben), amount, note, source (app/health) | |
| `FoodItem` | stableID, name, aliases, category, histamineScore (0–3), flags (H/A/L/B), personalTolerance (unbekannt/ok/vorsicht/meiden), freshnessHint, notes, barcode, nutrition/100 g, source (`builtin`/`user`/`openfoodfacts`) | Eigene Bewertung hat Vorrang |
| `MealEntry` + `MealItem` | timestamp, mealType, items (Lebensmittel+Menge), freshness (frisch/Reste/aufgewärmt), place (zuhause/auswärts), photo, note | Reste und Aufgewärmtes sind bei Histamin relevant |
| `SymptomEntry` | timestamp, type, severity (1–5), durationMin, note, healthKitUUID | Teilweise nach HealthKit gespiegelt |
| `CheckIn` | date, mood (1–5), energy, stress, sleepQuality, note | Stimmung → HealthKit State of Mind |
| `Exercise` | stableID, name, primaryMuscles, secondaryMuscles, equipment, mechanic (Grund-/Isolationsübung), unilateral, cues, increment (kg), defaultRest | |
| `WorkoutPlan` → `PlanDay` → `PlanExercise` | Plan: name, mesoWeeks, deloadRule, rotationIndex, currentWeek; Tag: name, order; Übung: exercise, sets, repMin, repMax, targetRIR, restSec, supersetGroup, note | |
| `WorkoutSession` → `SetLog` | Session: start, end, planDay, note, bodyweight, healthKitWorkoutID; Satz: exercise, index, weight, reps, rir, type (Aufwärmen/Arbeit/Drop), completedAt | |
| `BodyMetric` | date, type (Gewicht/Taille/Brust/Oberarm …), value, source | Gewicht ↔ HealthKit |
| `ShoppingItem` | name, category, qty, isDone, food (optional), source (manuell/Rezept) | Warnsymbol bei kritischen Lebensmitteln |
| `Recipe` | stableID, title, servings, ingredients (→ FoodItem), steps, tags, protein/Portion, histamineMax | |
| `JournalEntry` | date, wentWell, notes, tomorrowTop3 | Abendrückblick |
| `ClaudeExchange` | createdAt, kind (Plan/Wochenrückblick/Lebensmittel/Rezept/Analyse), promptHash, responseText, status (angewendet/verworfen) | Verlauf der Claude-Antworten |
| `AppSettings` (1 Datensatz) | Profil (Name, Größe, Geburtsjahr, Ziel), Module an/aus, Dashboard-Reihenfolge, Erinnerungs-Standardwerte, Kalenderauswahl, App-Sperre | |

**Seed-Daten:** Die JSON-Dateien aus `Content/` werden mit der App ausgeliefert. Beim ersten Start und bei jeder neuen Content-Version werden sie per `stableID` eingespielt, ohne dass deine eigenen Änderungen (z. B. persönliche Verträglichkeit) überschrieben werden.

---

## 5. Navigation & Design

### 5.1 Struktur

`TabView` mit iOS-26-Tab-Leiste (Liquid Glass):

| Tab | Inhalt |
|---|---|
| **Heute** | Dashboard (anpassbar) |
| **Planer** | Segment: Aufgaben · Agenda (14 Tage) · Woche |
| **Training** | Nächste Einheit, Pläne, Verlauf, Bibliothek, Körper |
| **Ernährung** | Tagebuch, Histamin-Tageslast, Lebensmittel-Lexikon, Einkauf, Rezepte |
| **Gesundheit** | Medikamente, Symptome, Check-ins, Health-Daten, Berichte |
| 🔍 **Suche** (Lupe oben auf „Heute“) | Durchsucht Aufgaben, Lebensmittel, Übungen, Medikamente, Rezepte. *Kein eigener Tab: Auf dem iPhone passen nur 5 Einträge in die Leiste, ein sechster landet unter „Mehr“ (im ersten CI-Lauf gesehen).* |

- **Tab-Bar-Zubehör** (`tabViewBottomAccessory`): Während eines Trainings sitzt über der Tab-Leiste ein Mini-Player, ähnlich wie bei Apple Music: „Push · 34:12 · Pause 1:15“. Ein Tipp darauf öffnet die Session.
- **Schnellerfassung:** Ein „+“ in der Toolbar jedes Tabs öffnet ein universelles Sheet mit Texterkennung, z. B. „morgen 10 uhr zahnarzt“ → Termin/Aufgabe, „ibu 400“ → Bedarfsmedikament, „kopfschmerz 3“ → Symptom. Der Parser liegt in `TagwerkCore/DateParsing` und erkennt: heute, morgen, übermorgen, Mo–So, „nächste Woche“, „in 2 Std“, Uhrzeiten, „jeden Montag“.
- **Einstellungen:** über das Profilbild oben rechts im Tab „Heute“.

### 5.2 Design-System (`TagwerkKit/DesignSystem`)

- **Material:** Liquid Glass nur für die Navigationsebene (Tab-Leiste, Toolbars, schwebende Buttons, Mini-Player). Inhalte liegen auf ruhigen, soliden Karten (`secondarySystemGroupedBackground`, Eckenradius 22, `continuous`). Das entspricht Apples Richtlinien und bleibt gut lesbar.
- **Farben je Bereich** (als Akzent, nie als Fläche): Aufgaben = Indigo · Kalender = Blau · Medikamente = Mint · Training = Coral/Rot · Ernährung = Orange · Gesundheit = Pink · Schlaf = Lila.
- **Histamin-Skala:** 0 grün · 1 gelb · 2 orange · 3 rot, **immer zusammen mit Zahl und Symbol**, damit sie auch bei Farbschwäche lesbar ist.
- **Typografie:** SF Pro mit Dynamic Type. Zahlen in SF Rounded (`.fontDesign(.rounded)`), Timer mit `monospacedDigit()`. Große, fette Titel.
- **Icons:** SF Symbols 7 mit Animationen (`symbolEffect(.bounce)` beim Abhaken).
- **Haptik:** `.sensoryFeedback(.success)` bei Medikament genommen und Aufgabe erledigt, `.impact` bei Satz abgeschlossen.
- **Abstände:** 4-pt-Raster (4/8/12/16/24/32). Mindestgröße für Tippflächen 44 pt, im Gym-Modus 56 pt (Bedienung mit einer Hand, verschwitzte Finger).
- **Komponenten:** `Card`, `SectionHeader`, `ProgressRing`, `StatTile`, `Chip`, `TimelineRow`, `EmptyState`, `BigNumberStepper` (kg/Wdh.), `ScoreBadge` (Histamin), `ConfirmCheck` (animierter Haken).
- **Qualität:** Dark Mode vollständig, Dynamic Type bis zu den Bedienungshilfe-Größen, VoiceOver-Beschriftungen, „Bewegung reduzieren“ wird beachtet. Deutsch als Hauptsprache (String Catalog), Englisch später möglich.

### 5.3 Schlüssel-Screens (Skizzen)

**Heute** (Reihenfolge und Sichtbarkeit der Karten anpassbar):
```
┌──────────────────────────────────┐
│ Sonntag, 25. Okt.          (👤)  │
│ Guten Morgen                      │
│ ◯ Aufgaben 2/5  ◯ Medis 1/3  ◯ 💧 │
├──────────────────────────────────┤
│ ALS NÄCHSTES                      │
│ 💊 DAO-Enzym · vor dem Mittagessen│
│                     [Genommen ✓]  │
├──────────────────────────────────┤
│ MEDIKAMENTE  08:00 ✓  13:00 ○  21:00 ○
├──────────────────────────────────┤
│ FOKUS HEUTE  ○ Rezept abholen     │
│              ○ Steuer-Unterlagen  │
│              + Aufgabe            │
├──────────────────────────────────┤
│ ZEITSTRAHL  10:00 Zahnarzt        │
│             13:00 💊  18:00 🏋️    │
├──────────────────────────────────┤
│ 🏋️ PULL · 7 Übungen · ~70 min  [Start] │
├──────────────────────────────────┤
│ 🍽 Histamin-Tageslast ▂▃▅ ruhig    │
│ Protein 96/150 g                  │
├──────────────────────────────────┤
│ Wie geht's dir?  😣 😕 😐 🙂 😄    │
└──────────────────────────────────┘
```
Abends wechselt die Ansicht automatisch auf den **Abendrückblick** (Stimmung, Symptome heute, was lief gut, Top 3 für morgen).

**Training-Session** (Vollbild, große Bedienelemente):
```
┌──────────────────────────────────┐
│ Push · Woche 2 · Ziel-RIR 2  ⏱ 23:41│
│ Bankdrücken (Langhantel)   1/6 ▸  │
│ Letztes Mal: 80×8 · 80×8 · 80×7   │
│ Vorschlag:   80 kg × 8 (Ziel 6–8) │
│ ─────────────────────────────────│
│ Satz  kg     Wdh   RIR            │
│ W1    40     8     –     ✓        │
│ W2    60     5     –     ✓        │
│ 1     80     8     2     ✓        │
│ 2    [80]   [ ]   [ ]    ○        │
│ ─────────────────────────────────│
│        Pause  1:48  [+30s] [Skip] │
│ [Übung tauschen] [Notiz] [+ Satz] │
└──────────────────────────────────┘
```
Die Pause läuft parallel als Live Activity auf Sperrbildschirm und Dynamic Island.

---

## 6. Module im Detail

### 6.1 Aufgaben (Planer)

- **Intelligente Listen:** Eingang, Heute, Geplant, Markiert, Überfällig, Erledigt. Dazu eigene Listen und Bereiche.
- Priorität, Tags, Unteraufgaben, Notizen, Schätzdauer, Erinnerungen (mehrere Vorlaufzeiten).
- **Wiederholungen:** feste Termine oder „X Tage nach Erledigung“ (z. B. Bettwäsche).
- **Wischgesten:** erledigt · morgen · verschieben. Ziehen zum Sortieren. **„Fokus 3“** markiert bis zu 3 Hauptaufgaben des Tages.
- **Optional:** einmaliger Import aus Apple Erinnerungen (EventKit). Kein Zwei-Wege-Sync (zu fehleranfällig).

### 6.2 Agenda & Woche (Kalender)

- **Agenda:** die nächsten 14 Tage untereinander. Pro Tag gemischt: **Kalendertermine** (EventKit, wählbare Kalender), Aufgaben mit Datum, **Medikamenten-Einnahmen**, geplante Trainings und Fristen.
- **Woche:** 7-Tage-Übersicht. Aufgaben lassen sich per Ziehen auf einen Tag verschieben.
- **Termine anlegen:** über die Schnellerfassung oder ein Formular, gespeichert direkt in Apple Kalender (EventKit). Optional: eine Aufgabe als Zeitblock in den Kalender legen.
- **Geburtstage:** aus dem Geburtstagskalender von iOS (EventKit), mit Erinnerung X Tage vorher.

### 6.3 Medikamente (Gesundheit)

- **Anlegen:** Name, Form, Stärke, Aussehen (eigenes Icon in Farbe und Form), Hinweise. **Zeitplan-Typen:** feste Uhrzeiten · bestimmte Wochentage · alle N Tage · Intervall (alle 8 h) · **bei Bedarf** (mit „max. X pro Tag / mind. Y h Abstand“-Warnung) · zyklisch (z. B. 21 an / 7 aus) · Ausschleichen in Stufen.
- **Mahlzeit-gekoppelt:** z. B. DAO-Enzym „15 min vor dem Essen“. Wenn du eine Mahlzeit anfängst zu loggen, fragt die App nach: „DAO schon genommen?“. Passt genau zur Histamin-Intoleranz.
- **Einnahmeplan-Kalender:** Wochen-/Monatsansicht pro Medikament mit Status je Einnahme (✓ genommen, ✕ ausgelassen, ○ offen) und Einnahmetreue in %.
- **Erinnerungen:** pro Medikament wählbar: *Mitteilung* (mit Knöpfen „Genommen“ · „In 10 Min“ · „Auslassen“, ohne App zu öffnen) oder *Wecker* (AlarmKit, klingelt auch bei Stummschaltung und Fokus, für wichtige Medikamente).
- **Vorrat:** Bestand zählt automatisch runter. Prognose „reicht bis 12. Nov.“ und Nachfüll-Erinnerung X Tage vorher. Auf Wunsch wird automatisch die Aufgabe „Rezept holen“ angelegt.
- **Health-Abgleich (iOS 26 Medications-API, nur lesend):** Medikamente, die du schon in der Health-App pflegst, lassen sich importieren. Dort geloggte Einnahmen werden erkannt, damit nichts doppelt gezählt wird. Einnahmen *in* Health schreiben erlaubt Apple Fremd-Apps nicht. Tagwerk führt deshalb das eigene Protokoll.
- **Technik:** iOS erlaubt nur 64 geplante Mitteilungen gleichzeitig. `TagwerkCore/Notifications` plant deshalb rollierend die nächsten 48–72 h (Medikamente haben Vorrang vor Aufgaben). Neu geplant wird bei jedem App-Start, nach jeder Änderung und per Hintergrundaktualisierung (`BGAppRefreshTask`). Sommer- und Winterzeit werden mit Zeitzone Europe/Berlin getestet.

### 6.4 Ernährung & Histamin

- **Lebensmittel-Lexikon (~400 Einträge, Deutsch):** Kategorie, **Histamin-Bewertung 0–3** (0 gut verträglich · 1 mäßig · 2 schlecht · 3 sehr schlecht) und **Markierungen**: H = histaminreich/verderblich · A = andere biogene Amine · L = Histaminliberator · B = hemmt den Histaminabbau (DAO). Dazu Frische-Tipps, z. B. „Fleisch frisch kaufen, einfrieren statt Reste im Kühlschrank“. Die Inhalte erstellt Claude bei der Umsetzung als eigene Einschätzungen, mit gleicher Skalen-Logik wie in DACH üblich, ohne fremde Listen zu kopieren. Sie sind als Orientierung gekennzeichnet.
- **Persönliche Verträglichkeit:** Pro Lebensmittel setzt du „bei mir ok / Vorsicht / meiden“. Das hat immer Vorrang vor der Standardbewertung, weil Histamin-Toleranz sehr individuell ist.
- **Ernährungstagebuch:** Mahlzeit erfassen über Suche, Favoriten, „Zuletzt“, Mahlzeit-Vorlagen, Rezepte oder Barcode. Pro Mahlzeit: frisch / Reste / aufgewärmt, zuhause / auswärts.
- **Barcode-Scan:** VisionKit-Scanner → **Open Food Facts** (kostenlos, ohne Key, eigener User-Agent, Ergebnis wird lokal gespeichert). Die Zutatenliste wird automatisch geprüft.
- **Zutatenliste scannen (offline):** Kamera → Texterkennung (Vision, läuft auf dem iPhone 15) → `HistamineEngine` gleicht ~150 Stichworte und E-Nummern ab (z. B. Hefeextrakt, Essig, Tomate, gereifter Käse, Sulfite E220–E228, Benzoate E210–E213) → kritische Zutaten werden farbig markiert. Ohne KI, ohne Internet.
- **Histamin-Tageslast:** Aus den geloggten Mahlzeiten (Bewertung × Portionsfaktor + Aufschlag für Reste/Aufgewärmtes) ergibt sich eine Tagesanzeige: *ruhig · erhöht · hoch*. Klar als Orientierung beschriftet.
- **Symptomtagebuch:** Schnellerfassung (Kopfschmerz, Hautrötung/Flush, Juckreiz, Quaddeln, Blähungen, Bauchschmerz, Durchfall, Übelkeit, Herzrasen, verstopfte/laufende Nase, Müdigkeit, Schwindel …) mit Stärke 1–5. Symptome, die HealthKit kennt (z. B. Kopfschmerz, Blähungen, Übelkeit, Durchfall, Herzrasen, laufende Nase, Müdigkeit), werden nach Health geschrieben. Andere (Juckreiz, Quaddeln, Flush) bleiben in der App.
- **Auslöser-Analyse (`TagwerkCore/Insights`, ohne KI):** Für jedes Symptom prüft sie die Lebensmittel der 0–24 h davor, gewichtet nach Zeitabstand (Schwerpunkt 15 min–3 h). Pro Lebensmittel: wie oft gegessen, wie oft danach Symptome, verglichen mit deiner Grundrate. Angezeigt wird ein Lebensmittel erst ab mindestens 3 Vorkommen, z. B. „Auffällig: Tomate – 5 von 6 Mal Symptome innerhalb von 3 h“. Weitere Faktoren: Reste, Alkohol, kurzer Schlaf, Stress (aus dem Check-in). Formulierungen bleiben vorsichtig („Muster“, keine Diagnose).
- **Protein-Ziel** (wegen Muskelaufbau): Orientierung 1,6–2,2 g pro kg Körpergewicht. Kalorien und Makros sind optional zuschaltbar. Werte gehen auf Wunsch nach Health (Energie, Protein, Wasser).
- **Wasser:** Schnelltaste +250 ml, auch über Widget, Kontrollzentrum und Siri.
- **Einkaufsliste:** nach Kategorien sortiert (Obst/Gemüse, Frischfleisch & Fisch, Kühlregal …), Warnsymbol bei kritischen Lebensmitteln, Übernahme aus Rezepten und Wochenplan.
- **Rezepte (~30 mitgeliefert):** histaminarm und proteinreich, von Claude erstellt. Eigene Rezepte möglich. Ein **Wochen-Essensplan** befüllt die Einkaufsliste.

### 6.5 Training

- **Übungsbibliothek (~120 Übungen, Deutsch):** Muskelgruppen (primär/sekundär), Gerät, Grund- oder Isolationsübung, Technik-Hinweise, Steigerungsschritt. Eigene Übungen möglich.
- **Pläne:** Dein Startplan ist vorinstalliert (Abschnitt 9). Der Planeditor erlaubt Tage und Übungen umsortieren, Supersätze, Sätze, Wiederholungsbereich, Ziel-RIR und Pause. Plan-Import aus der Claude-Brücke kommt dazu.
- **Rotation statt fester Wochentage:** Die App zeigt immer die *nächste* Einheit (A → B → C → D). Ein verpasster Tag bringt den Plan nicht durcheinander. Optional gibt es Wunsch-Wochentage für Erinnerungen.
- **Session-Tracking:** „Letztes Mal“ pro Übung, automatischer **Gewichtsvorschlag**, automatische Aufwärmsätze, Pausen-Timer (Grundübungen 2–3 min, Isolation 60–90 s) als **Live Activity**, Übung tauschen (passende Alternativen aus derselben Muskelgruppe), Notizen, Drop-Sätze, Supersätze. Abschluss-Zusammenfassung mit Dauer, Volumen, neuen Rekorden und Vergleich zur letzten Einheit.
- **Progressions-Engine (`TagwerkCore/Training`):** doppelte Progression, RIR-Wellen im Mesozyklus, Deload-Erkennung, e1RM (Epley) für Rekorde. Regeln in Abschnitt 9.
- **Statistik:** Wochensätze pro Muskelgruppe gegen Zielbereich (Balken: zu wenig / im Ziel / viel), e1RM-Verlauf pro Übung, Trainingsfrequenz, Rekorde. Später eine Muskel-Karte (Körper-Silhouette mit Farbintensität).
- **Health:** Jede Session wird als Workout „Krafttraining“ gespeichert (Dauer, geschätzte Energie). Ab iOS 26 sind Workout-Sessions auch auf dem iPhone möglich.
- **Körper:** Gewicht (aus und nach Health), Maße (Oberarm, Brust, Taille, Schultern), optionale Fortschrittsfotos. Die Fotos bleiben privat in der App, nicht in der Fotomediathek.
- **Gym-Ankunft (optional):** Ortsbasierte Erinnerung „Du bist im Gym – Pull starten?“ (CoreLocation-Bereichsüberwachung). Oder du nutzt dafür eine Kurzbefehl-Automation.

### 6.6 Gesundheit & Health-Daten

- **Lesen aus Health:** Schritte, Gehstrecke, Stockwerke, Gewicht, Schlaf (falls eine Quelle schreibt; ohne Watch nur eingeschränkt), Achtsamkeitsminuten, Medikamente und Einnahmen (iOS 26), Workouts.
- **Schreiben nach Health:** Workouts, Gewicht, Wasser, Energie und Protein (optional), Symptome, **Stimmung** (State of Mind aus dem Check-in).
- **Check-in:** morgens 10 Sekunden (Schlafgefühl, Energie) und abends (Stimmung, Stress, Symptome). Die Werte fließen in die Auslöser-Analyse ein.
- **Berichte:**
  - **Wochenrückblick** (jeden Sonntag): Aufgaben erledigt, Einnahmetreue, Trainingsvolumen und Rekorde, Symptomtage, Histamin-Auffälligkeiten, Gewichtstrend.
  - **Arztbericht als PDF:** Zeitraum wählen → Medikamentenplan und Einnahmetreue, Symptomverlauf (Diagramm), auffällige Lebensmittel, Gewicht. Wird in der App erzeugt und über das Teilen-Menü versendet. Ideal für Arzt oder Ernährungsberatung.

### 6.7 Leben (weitere Alltagsbereiche, über die Aufgaben-Engine)

- **Routinen:** Morgen- und Abendroutine als abhakbare Checklisten (z. B. Medikamente → Wasser → 5 min Dehnen) mit Serien.
- **Gewohnheiten:** mit Zielwert und Serienzähler.
- **Fristen & Dokumente:** Ablaufdaten (Personalausweis, Führerschein, TÜV, Versicherungen) mit Vorab-Erinnerung.
- **Verträge & Abos:** Kosten pro Monat/Jahr, Kündigungsfrist mit Erinnerung rechtzeitig vorher, Summe aller Fixkosten.
- **Geburtstage:** siehe 6.2.
- **Haushalt:** Vorlagen wie „Bad putzen alle 7 Tage nach Erledigung“ oder „Pflanzen gießen“.
- **Journal:** kurze Tagesnotiz im Abendrückblick.

---

## 7. iPhone-Integration

*(Alles mit **einer** Widget-Extension, wegen des App-Limits bei kostenlosem SideStore-Betrieb, siehe 10.)*

| Bereich | Umfang |
|---|---|
| **Home-Bildschirm-Widgets** | *Medikamente* (klein/mittel, interaktiver „Genommen“-Knopf) · *Heute* (mittel/groß: Als Nächstes + Zeitstrahl) · *Aufgaben* (mittel, abhakbar) · *Training* (klein: nächste Einheit, Tage seit letztem Training) · *Histamin-Tageslast* (klein) |
| **Sperrbildschirm-Widgets** | Rund: Medis 1/3, Wasser, Tageslast · Rechteckig: „Als Nächstes“ · Inline: nächster Termin |
| **StandBy** | Heute-Widget im Querformat beim Laden |
| **Kontrollzentrum** (Controls) | Medikament genommen · Schnell-Aufgabe · Training starten · Symptom erfassen · Wasser +250 ml |
| **Live Activities / Dynamic Island** | Training läuft (Zeit, aktuelle Übung, Pausen-Countdown, Knopf „Satz fertig“) · Wecker-Darstellung bei Medikamenten mit Countdown |
| **AlarmKit** | Wichtige Medikamente als echter Wecker mit Schlummern |
| **Mitteilungen mit Aktionen** | Medikament (Genommen / 10 Min / Auslassen) · Aufgabe (Erledigt / Morgen) · Nachfüllen · Abend-Check-in |
| **Siri & Kurzbefehle** (App Intents + App Shortcuts, deutsche Sätze) | „Medikamente in Tagwerk abhaken“ · „Habe ich heute meine Tabletten genommen?“ · „Neue Aufgabe in Tagwerk“ · „Was steht heute an?“ · „Starte mein Training“ · „Symptom erfassen“ · „Ist Avocado histaminarm?“ (Antwort offline aus dem Lexikon) · „Wasser trinken“ |
| **Spotlight** | Aufgaben, Lebensmittel, Übungen und Rezepte als durchsuchbare Einträge (`IndexedEntity`). Mit iOS 27 optional Entity-Schemas für die semantische Siri-Suche |
| **Fokus-Filter** | z. B. im Fokus „Arbeit“ nur die Arbeitsliste anzeigen, im Fokus „Schlafen“ Training und Ernährung ausblenden |
| **Kurzbefehl-Automationen** | Alle Intents sind in Automationen nutzbar (Uhrzeit, Ort, Wecker gestoppt, Fokus an …) |
| **App-Sperre** | Optional per Face ID (LocalAuthentication), wegen der Gesundheitsdaten |
| **Dateien-App** | Automatische Backups liegen sichtbar im App-Ordner in der Dateien-App |

---

## 8. KI ohne API-Key: die „Claude-Brücke“

### 8.1 Drei Ebenen

1. **Claude bei der Entwicklung:** Ich erstelle alle Inhalte (Lebensmittel-Lexikon, Zutatenregeln, Übungsbibliothek, Rezepte, deinen Startplan, Hilfetexte). Sie werden fest in die App eingebaut. Kostet nichts zur Laufzeit.
2. **Regeln in der App (immer verfügbar, offline):** Progression, Deload-Vorschläge, Auslöser-Analyse, Tageslast, Vorrat-Prognose, Wochenstatistik.
3. **Claude-Brücke (bei Bedarf):** Die App baut eine fertige Anfrage mit deinen Daten, schickt sie über die Kurzbefehl-Aktion **„Ask Claude“** der offiziellen Claude-App und übernimmt die Antwort strukturiert. Das läuft über dein normales Claude-Konto (zählt zu deinem Nutzungslimit), ohne API-Key und ohne Zusatzkosten.

### 8.2 Ablauf

```
Tagwerk: „Plan mit Claude anpassen“
   │ 1. Prompt wird gebaut (TagwerkCore/ClaudeBridge/PromptBuilder)
   │ 2. Vorschau: „Diese Daten gehen an Claude“ (Name optional anonymisiert)
   ▼
Kurzbefehl „Tagwerk ↔ Claude“ (einmal anlegen, Anleitung in der App)
   [Kurzbefehl-Eingabe] → [Ask Claude] → [Tagwerk: Claude-Antwort übernehmen]
   ▼
Tagwerk: Antwort prüfen (JSON-Schema) → Vorschau/Unterschiede → „Übernehmen“ / „Verwerfen“
```

- **Start:** Die App öffnet `shortcuts://x-callback-url/run-shortcut?name=…&input=clipboard&x-success=tagwerk://claude-result`. Die Antwort kommt über die letzte Aktion des Kurzbefehls (eigener App Intent `ImportClaudeResponseIntent`) und/oder den x-success-Rückruf.
- **Ausweichweg (immer verfügbar):** „Anfrage kopieren“ → in der Claude-App einfügen → Antwort kopieren → in Tagwerk über den `PasteButton` einfügen (keine Rückfrage zur Zwischenablage).
- **Antwortformat:** Jede Anfrage fordert eine Antwort in einem festen, versionierten JSON-Format, z. B. `tagwerk.plan.v1`:
  ```json
  {"format":"tagwerk.plan.v1","name":"Oberkörper 4er","mesoWeeks":5,"deloadWeek":6,
   "days":[{"name":"Push","exercises":[{"name":"Bankdrücken (Langhantel)","sets":4,
   "repMin":6,"repMax":8,"rir":2,"restSec":150,"note":"…"}]}]}
  ```
  Der Parser ist tolerant (zieht JSON auch aus Codeblöcken), prüft streng und ordnet Übungsnamen unscharf der Bibliothek zu. Unbekannte Übungen werden als eigene angelegt, mit Rückfrage. Freitext-Antworten (z. B. Wochenrückblick) werden als Markdown gespeichert und angezeigt.

### 8.3 Anwendungsfälle

| Fall | Daten an Claude | Ergebnis |
|---|---|---|
| Trainingsplan erstellen/anpassen | Profil, Ziel, Split-Wunsch, Geräte, Top-Sätze der letzten 4–6 Wochen, Stagnationen, Notizen | `tagwerk.plan.v1` → Vorschau → Übernehmen |
| Wochenrückblick „mit Claude“ | Zusammenfassung der Woche (Kennzahlen, keine Rohdaten) | Text mit Tipps, im Rückblick gespeichert |
| Lebensmittel nicht im Lexikon | Name + Zutaten (falls gescannt) | `tagwerk.food.v1` → als eigenes Lebensmittel speichern |
| Rezeptideen | Vorräte/Wünsche, verträgliche Lebensmittel, Protein-Ziel | `tagwerk.recipe.v1` → Rezept + Einkaufsliste |
| Symptom-Muster deuten | Ergebnis der lokalen Auslöser-Analyse + Kontext | Erklärender Text (vorsichtig formuliert) |

Die Prompt-Vorlagen sind versioniert in `TagwerkCore/ClaudeBridge/Templates` und unter Linux getestet: Prompt-Aufbau, Parser, Validierung und Beispielantworten.

---

## 9. Dein Startplan: „Oberkörper 4er – Hypertrophie“

**Basis:** dein bisheriger Split Push / Pull / Arme / Brust+Rücken, ausgewogen nach Wochenvolumen und Erholung. Erfahrung ca. 1 Jahr → moderates bis hohes Volumen, doppelte Progression, RIR-Steuerung.

**Rotation & Woche:** A Push → B Pull → C Arme & Schultern → D Brust & Rücken.
Vorschlag: **Mo A · Di B · Do C · Sa D**. Mi, Fr und So frei. Die Rotation passt sich an, wenn sich Tage verschieben.

### A – Push (Brust-Schwerpunkt)
| Übung | Sätze × Wdh. | RIR | Pause |
|---|---|---|---|
| Bankdrücken (Langhantel) | 4 × 6–8 | 2 | 2:30 |
| Schrägbankdrücken Kurzhantel (30°) | 3 × 8–10 | 2 | 2:00 |
| Schulterdrücken Kurzhantel sitzend | 3 × 8–10 | 2 | 2:00 |
| Kabel-Fliegende (mittlere Höhe) | 2 × 12–15 | 1 | 1:15 |
| Seitheben Kurzhantel | 4 × 12–15 | 1 | 1:00 |
| Trizepsdrücken am Kabel (Seil) | 3 × 10–12 | 1 | 1:15 |

### B – Pull (Rücken-Breite & -Dicke)
| Übung | Sätze × Wdh. | RIR | Pause |
|---|---|---|---|
| Klimmzüge (ggf. assistiert) oder Latzug breit | 4 × 6–10 | 2 | 2:30 |
| Brustgestütztes Rudern (Maschine/T-Bar) | 3 × 8–10 | 2 | 2:00 |
| Latzug eng, neutraler Griff | 3 × 10–12 | 2 | 1:45 |
| Kabelrudern sitzend | 2 × 10–12 | 1 | 1:30 |
| Face Pulls | 3 × 12–15 | 1 | 1:00 |
| SZ-Curls | 3 × 8–10 | 1 | 1:30 |
| Hammercurls | 2 × 10–12 | 1 | 1:00 |

### C – Arme & Schultern (als Supersätze möglich)
| Übung | Sätze × Wdh. | RIR | Pause |
|---|---|---|---|
| Enges Bankdrücken | 3 × 6–8 | 2 | 2:00 |
| Schrägbank-Kurzhantelcurls | 3 × 10–12 | 1 | 1:15 |
| Überkopf-Trizepsstrecken am Kabel | 3 × 10–12 | 1 | 1:15 |
| Scottcurls (Maschine/SZ) | 3 × 10–12 | 1 | 1:15 |
| Seitheben am Kabel | 4 × 12–15 | 1 | 1:00 |
| Reverse Butterfly | 3 × 12–15 | 1 | 1:00 |
| *(optional)* Reverse Curls | 2 × 12–15 | 1 | 1:00 |

### D – Brust & Rücken (andere Winkel, als Antagonisten-Supersätze möglich)
| Übung | Sätze × Wdh. | RIR | Pause |
|---|---|---|---|
| Schrägbankdrücken (Langhantel/Maschine) | 3 × 6–10 | 2 | 2:30 |
| Langhantel- oder T-Bar-Rudern | 3 × 8–10 | 2 | 2:00 |
| Dips (Brust-Fokus, ggf. mit Gewicht) | 3 × 8–12 | 2 | 2:00 |
| Latzug breit | 3 × 10–12 | 2 | 1:45 |
| Butterfly-Maschine | 2 × 12–15 | 1 | 1:15 |
| Kabel-Pullover (Lat) | 2 × 12–15 | 1 | 1:15 |
| Seitheben (Kurzhantel oder Kabel) | 3 × 15–20 | 0–1 | 1:00 |

**Direkte Wochensätze (Richtwert):** Brust ~17 · Rücken/Lat ~20 · seitliche Schulter ~11 (+ Drücken) · hintere Schulter ~6 (+ Rudern) · Bizeps ~11 · Trizeps ~9 (+ Drücken/Dips). Das liegt im Hypertrophie-Bereich (~10–20 Sätze pro Muskel und Woche). Die App zeigt das live in der Volumen-Statistik.

**Progression & Mesozyklus (in der App automatisiert):**
- **Mesozyklus 6 Wochen:** Woche 1 RIR 3 (Einstieg) · Wochen 2–3 RIR 2 · Wochen 4–5 RIR 1 (bei Isolationsübungen letzter Satz RIR 0) · **Woche 6 Deload** (Sätze halbieren, gleiches Gewicht, RIR 4).
- **Doppelte Progression:** Das Gewicht bleibt, bis *alle* Arbeitssätze das obere Ende des Wiederholungsbereichs beim Ziel-RIR erreichen. Dann geht es beim nächsten Mal hoch: Langhantel +2,5 kg · Kurzhantel nächste Stufe (+1–2 kg) · Kabel/Maschine nächste Stufe. Die Steigerungsschritte sind pro Übung und pro Gym einstellbar.
- **Rückschritt:** Unter dem unteren Ende in 2 Einheiten hintereinander → −5–10 % Gewicht plus Technik-Hinweis.
- **Früher Deload:** Stagnieren ≥ 2 Hauptübungen über 2 Wochen, schlägt die App einen früheren Deload vor.
- **Aufwärmen** (automatisch vor der ersten Grundübung des Tages): 50 % × 8 · 70 % × 5 · 85 % × 2–3.
- **Neuer Zyklus:** Nach dem Deload kann die App 1–2 Übungen tauschen, um Abwechslung zu schaffen. Auf Wunsch mit Claude-Vorschlag über die Brücke.

**Optionaler Zusatz (bewusst nicht Pflicht):** Der Plan ist wie gewünscht reiner Oberkörper. Für Haltung, Gesamtkraft und Hormonhaushalt bietet die App ein optionales **20-Minuten-Modul „Beine & Rumpf“** an, das du an Tag B oder D anhängen kannst (z. B. Beinpresse, Rumänisches Kreuzheben, Wadenheben, Cable Crunch). Es ist standardmäßig aus.

**Ernährung zum Ziel (Orientierung):** 1,6–2,2 g Protein pro kg Körpergewicht, leichter Überschuss (ca. +250–300 kcal). Histaminarme Proteinquellen wie frisches Geflügel, frischer Fisch (sofort verarbeitet), Eier (Eigelb), junger Käse/Quark (je nach persönlicher Verträglichkeit) stehen im Lexikon und in den Rezepten.

---

## 10. Bauen & Installieren ohne Mac

### 10.1 Pipeline

| Workflow | Runner | Auslöser | Schritte |
|---|---|---|---|
| `core.yml` | Ubuntu (günstig) | jeder Push | `swift test` für TagwerkCore + Content-Validierung |
| `ios.yml` | macOS (`macos-26`) | Push auf `main`, PRs mit App-Änderungen (Pfad-Filter) | XcodeGen installieren → `xcodegen generate` → `xcodebuild test` im iPhone-15-Simulator → UI-Test läuft alle Screens ab (hell/dunkel, große Schrift) und speichert **Screenshots** als Artefakt |
| `release.yml` | macOS | Git-Tag `v*` | Archiv **unsigniert** (`CODE_SIGNING_ALLOWED=NO`) → `Payload/` → `Tagwerk.ipa` → GitHub-Release. Später zusätzlich: fastlane + App-Store-Connect-API-Key → TestFlight |

- **Kosten:** Ein privates Repo hat im GitHub-Free-Plan 2000 Minuten pro Monat. macOS-Minuten zählen zehnfach, also bleiben effektiv ca. 200 macOS-Minuten. Deshalb laufen die Logiktests unter Linux, macOS-Builds nur bei Bedarf, und es gibt Caching. Reicht das nicht: Repo öffentlich machen (es enthält keine persönlichen Daten, macOS-Minuten sind dann frei) oder auf Codemagic ausweichen (Gratis-Kontingent für macOS).
- **Prüfen ohne Mac:** Ich kann Logiktests hier in der Linux-Umgebung ausführen und mir CI-Ergebnisse und Screenshots über `gh` holen und ansehen. So lässt sich das Design prüfen, bevor du installierst.

### 10.2 Phase A – kostenlos per SideStore

1. Einmalig: SideStore mit einem Windows- oder Linux-PC einrichten (Pairing-Datei erstellen). Entwicklermodus am iPhone aktivieren.
2. IPA aus dem GitHub-Release auf dem iPhone laden → in SideStore öffnen → SideStore signiert mit deiner Apple-ID.
3. **Alle 7 Tage** neu signieren. SideStore kann das per Kurzbefehl-Automation im Hintergrund. Tagwerk zeigt vorher an, wann die Signatur abläuft.
4. **Grenzen mit kostenloser Apple-ID:** max. 3 aktive Apps (inkl. SideStore; Erweiterungen zählen nach aktuellem Stand mit). Deshalb hat Tagwerk genau **eine** Widget-Extension: SideStore + App + Widget = 3. Außerdem gibt es kein iCloud/CloudKit, und HealthKit ist **unsicher** (wird in Phase 0 getestet). Fehlt HealthKit, laufen alle Funktionen mit lokalen Daten weiter.

### 10.3 Phase B – Apple Developer Program (99 €/Jahr)

- TestFlight-Installation direkt aus dem CI. Builds halten 90 Tage, das CI erneuert sie regelmäßig.
- Alle Funktionen voll verfügbar: HealthKit, App Groups, **iCloud-Sync** (SwiftData + CloudKit, private Datenbank), zeitkritische Mitteilungen, Siri.
- **Daten-Umzug:** Die Bundle-ID ändert sich (SideStore hatte die Team-ID angehängt). Deshalb gibt es in der alten App „Umzugs-Export“ (komplette JSON-Datei) und in der neuen App „Import“. Ein Probelauf ist Teil von Phase 7.

### 10.4 Datensicherung (ab Phase 1)

- Automatisches tägliches JSON-Backup im App-Ordner (sichtbar in der Dateien-App), die letzten 14 Stück werden behalten. Vor jeder Schema-Migration gibt es ein zusätzliches Backup.
- Manueller Export und Import (z. B. nach iCloud Drive). Der Import ist versioniert und mit `TagwerkCore`-Tests abgesichert (Hin- und Rückweg).

---

## 11. Umsetzungsphasen

Jede Phase endet mit einer installierbaren Version und einem kurzen Testlauf auf deinem iPhone.

**Phase 0 – Fundament & Machbarkeit**
- Repo, XcodeGen-Projekt, drei CI-Workflows, leere App mit Tab-Gerüst, Design-System-Grundlagen.
- **Testläufe auf dem iPhone über SideStore:** (1) Installation klappt, (2) HealthKit-Berechtigung mit kostenloser Apple-ID, (3) App Group zwischen App und Widget (`ALTAppGroups`), (4) AlarmKit-Wecker, (5) Mitteilung mit Aktionsknöpfen, (6) „Ask Claude“-Kurzbefehl gibt die Antwort an Tagwerk zurück.
- **Entscheidung danach:** Welche Funktionen im kostenlosen Betrieb aktiv sind. Die Capabilities-Registry wird entsprechend eingestellt.

**Phase 1 – Kern: Heute, Aufgaben, Agenda**
- SwiftData-Schema v1 (alle Entitäten angelegt), Seed-Mechanismus, Backup/Export/Import.
- Aufgaben vollständig (Listen, Wiederholungen, Erinnerungen, Wischgesten, Fokus 3), Schnellerfassung mit deutschem Parser.
- Agenda und Woche mit EventKit. Heute-Dashboard (erste Karten), Onboarding, Einstellungen, Suche (Grundversion).

**Phase 2 – Medikamente**
- Medikamente und alle Zeitplan-Typen, Einnahme-Protokoll, Einnahmeplan-Kalender, Vorrat und Nachfüllen.
- Rollierende Mitteilungen mit Aktionen, AlarmKit für kritische Medikamente.
- Widgets (Medikamente, Heute), Sperrbildschirm, Kontrollzentrum, Siri-Intents für Medikamente.

**Phase 3 – Training**
- Übungsbibliothek und Startplan (Content), Planeditor, Session-Tracking, Pausen-Live-Activity, Mini-Player in der Tab-Leiste.
- Progressions-Engine, Statistik, Rekorde, Körper-Daten, Workout nach Health.
- Plan-Import aus JSON (einfügen), also die erste Stufe der Claude-Brücke.

**Phase 4 – Ernährung & Histamin**
- Lebensmittel-Lexikon und Zutatenregeln (Content), persönliche Verträglichkeit, Ernährungstagebuch.
- Barcode-Scan (Open Food Facts), Zutatenlisten-Scan (Texterkennung), Tageslast, Protein und Wasser.
- Symptomtagebuch, Auslöser-Analyse, DAO-Mahlzeit-Kopplung, Einkaufsliste, Rezepte, Wochen-Essensplan.

**Phase 5 – Health-Integration, Einblicke & Claude-Brücke**
- HealthKit lesen/schreiben (inkl. Medications-API-Import, State of Mind), Check-ins, Wochenrückblick, Arztbericht-PDF.
- Claude-Brücke vollständig: Kurzbefehl-Anleitung, alle Anwendungsfälle, Datenvorschau, Verlauf.

**Phase 6 – Leben & Feinschliff**
- Routinen, Gewohnheiten, Fristen und Verträge, Geburtstage, Journal.
- Alle übrigen Widgets und Controls, Spotlight, Fokus-Filter, Gym-Ankunft, App-Sperre, TipKit.
- Durchgang für Bedienungshilfen und Performance (große Datenmengen, schnelles Scrollen), App-Icon und Feinschliff der Animationen.

**Phase 7 – Upgrade auf Developer-Account** (sobald du so weit bist)
- TestFlight-Pipeline (fastlane + API-Key als GitHub-Secrets), iCloud-Sync einschalten, zeitkritische Mitteilungen, Probelauf für den Daten-Umzug.
- Optional später: Watch-App, englische Sprache.

---

## 12. Risiken & Gegenmaßnahmen

| Risiko | Gegenmaßnahme |
|---|---|
| HealthKit geht mit kostenloser Apple-ID nicht | Capabilities-Registry: lokale Daten als Ersatz, Health-Funktionen werden mit Phase B aktiv |
| App läuft nach 7 Tagen ab | SideStore-Automation, Ablauf-Hinweis in Tagwerk. Daten bleiben beim Neu-Signieren erhalten |
| Datenverlust (Bundle-ID-Wechsel, Löschen) | Tägliche Backups in der Dateien-App, Umzugs-Export/-Import, Backup vor jeder Migration |
| „Ask Claude“ gibt keine Antwort an den Kurzbefehl zurück | Ausweichweg über die Zwischenablage ist von Anfang an eingebaut |
| CI-Minuten reichen nicht | Linux-Tests, Pfad-Filter, Caching. Sonst Repo öffentlich oder Codemagic |
| 64er-Limit für Mitteilungen | Rollierende Planung mit Vorrang für Medikamente |
| Histamin-Bewertungen passen nicht zu dir | Persönliche Verträglichkeit hat Vorrang, Auslöser-Analyse zeigt deine eigenen Muster, klare Kennzeichnung als Orientierung |
| Zu großer Umfang | Feste Phasen, jede Phase ist für sich nutzbar. Neue Ideen kommen in ein Backlog statt in die laufende Phase |

---

## 13. Prüfung (Verifikation)

**Automatisch (bei jeder Änderung):**
- `swift test` in `Packages/TagwerkCore` (hier unter Linux und im CI). Abgedeckt: Wiederholungsregeln, deutscher Datumsparser, Medikamenten-Zeitpläne inkl. Sommer-/Winterzeit (Europe/Berlin), Bedarfs-Warnungen, Vorrat-Prognose, rollierende Mitteilungsplanung, Progression/Deload/e1RM/Aufwärmen, Histamin-Zutatenparser und Tageslast, Auslöser-Analyse (mit synthetischen Testdaten), Claude-Prompt-Bau und Antwort-Parser (gültige, kaputte und Codeblock-Antworten), Backup-Hin-und-Rückweg.
- `Scripts/validate_content.swift`: Content-Dateien gegen das Schema prüfen (keine Duplikate, Werte 0–3, jede Übung im Plan existiert in der Bibliothek).
- CI-macOS: Build, Unit- und UI-Tests im iPhone-15-Simulator. Danach Durchsicht der Screenshots in hell, dunkel und großer Schrift.

**Manuell auf deinem iPhone (Checkliste pro Phase):**
- Phase 0: Installation über SideStore, die 6 Testläufe aus Phase 0.
- Phase 1: Aufgabe per Schnellerfassung „morgen 10 uhr …“ landet richtig. Kalendertermin erscheint in Apple Kalender. Backup exportieren → App-Daten löschen → Import → alles wieder da.
- Phase 2: Mitteilung kommt bei gesperrtem iPhone pünktlich. „Genommen“ aus der Mitteilung heraus aktualisiert Widget und App. Ein AlarmKit-Wecker klingelt im Stumm- und Fokusmodus. Der Vorrat zählt runter.
- Phase 3: Ein komplettes Training im Gym. Pausen-Timer in der Dynamic Island und auf dem Sperrbildschirm. Gewichtsvorschlag in der Folgewoche stimmt. Das Workout erscheint in Health (falls verfügbar).
- Phase 4: Barcode eines echten Produkts scannen, Zutatenliste fotografieren, kritische Zutaten werden markiert. Nach einigen Tagen Daten erscheint die Auslöser-Analyse plausibel.
- Phase 5: Claude-Brücke einmal komplett: Plan anpassen → Vorschau → übernehmen. Arztbericht-PDF öffnen und teilen.
- Phase 6/7: Alle Widgets und Controls, Siri-Sätze, Fokus-Filter, App-Sperre. Daten-Umzug auf die TestFlight-Version.

---

## 14. Nach Freigabe als Erstes

1. GitHub-Repo `tagwerk-ios` anlegen (oder du gibst mir ein bestehendes) und diese Session mit Schreibzugriff verbinden.
2. Phase 0 umsetzen: Gerüst, CI und Test-App für die 6 Testläufe.
3. Kurze Anleitung `docs/SIDELOAD.md` für deine SideStore-Einrichtung.
