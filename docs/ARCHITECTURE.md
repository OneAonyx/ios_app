# Architektur

> **Name:** Die App heißt seit Version 0.4 **Orbit** (vorher Arbeitstitel „Tagwerk“). Interne
> Namen bleiben: Module `TagwerkCore`/`TagwerkKit`, Xcode-Target `Tagwerk`, Bundle-ID
> `de.tagwerk.app`, App Group, URL-Schema `tagwerk://` und Datenbank `Tagwerk.store`. So bleiben
> Daten, Signatur und Verknüpfungen erhalten. Sichtbar ist nur noch „Orbit“.

## Schichten

```
┌───────────────────────────────┐   ┌──────────────────────────────┐
│ App (SwiftUI)                 │   │ Widgets (WidgetKit-Extension) │
│ Features, App Intents         │   │ Widgets, Live Activities      │
└──────────────┬────────────────┘   └──────────────┬───────────────┘
               │                                   │
               ▼                                   ▼
┌─────────────────────────────────────────────────────────────────┐
│ TagwerkKit (nur iOS)                                             │
│ Design-System · AppGroup · HealthProbe · AlarmProbe ·            │
│ NotificationSetup · Stores · SigningInfo                         │
└──────────────────────────────┬──────────────────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ TagwerkCore (plattformunabhängig, unter Linux getestet)          │
│ Signatur/Profil · App-Group-Auflösung · Claude-Brücke ·          │
│ Systemcheck-Modell · Tageszeit · gemeinsame Kodierung            │
└─────────────────────────────────────────────────────────────────┘
```

- **TagwerkCore** enthält alle Fachlogik ohne Apple-Frameworks. Tests mit Swift Testing laufen im
  Container (`swift:6.2-noble`) und im CI auf Linux. Swift-6-Sprachmodus.
- **TagwerkKit** kapselt die iOS-Frameworks. App und Widget nutzen es gemeinsam. Kein
  `UIApplication.shared`, damit es in Extensions erlaubt ist.
- **App** besteht aus SwiftUI-Views pro Bereich und einem zentralen `AppModel` (`@Observable`).

## Entscheidungen in Phase 0

| Entscheidung | Grund |
|---|---|
| Projekt per XcodeGen (`project.yml`), keine `.xcodeproj` im Git | Kein Mac nötig, keine Merge-Konflikte in Projektdateien |
| Genau **eine** App-Extension | Kostenlose Apple-ID: max. 3 aktive Apps inkl. SideStore und Extensions |
| App-Group-ID zur Laufzeit auflösen (`ALTAppGroups`) | SideStore benennt App Groups um (Team-ID wird angehängt) |
| Ad-hoc-Signatur mit Berechtigungen in `release.yml` | SideStore liest die Berechtigungen aus der Signatur der IPA |
| Swift-5-Modus für App, Widget und TagwerkKit | Ohne Mac kostet jeder Compiler-Fehler einen CI-Lauf. Nebenläufigkeit erst als Warnung, Umstellung auf Swift 6 in Phase 1 |
| `AlarmPresentation.Alert` mit `#available(iOS 26.1, *)` | Ab 26.1 stellt iOS den Stopp-Knopf selbst, der alte Initializer ist veraltet |
| Mindest-iOS 26.0 | AlarmKit, Medications-API, Liquid Glass |

## Phase 1: Datenmodell und Dienste

| Teil | Wo | Aufgabe |
|---|---|---|
| `TagwerkSchemaV1` | `Packages/TagwerkKit/…/Models/SchemaV1.swift` | `TaskItem`, `Subtask`, `TaskList` |
| `TagwerkStore` | `…/Models/TagwerkStore.swift` | Speicher im App-Group-Container, sonst App-Container |
| `TaskActions` | `…/Models/TaskActions.swift` | Alle Änderungen an Aufgaben (App, Mitteilungen, Siri) |
| `CalendarService` | `…/Services/CalendarService.swift` | EventKit lesen/schreiben |
| `ReminderScheduler` (bis 0.2: `TaskReminderScheduler`) | `…/Services/ReminderScheduler.swift` | Mitteilungen rollierend (72 h, max. 60) |
| `BackupService` | `…/Services/BackupService.swift` | JSON-Sicherung in `Documents/Backups` |

Die Logik dahinter (Wiederholungen, Parser, Listen, Agenda, Backup-Format, Erinnerungsplanung)
liegt testbar in `TagwerkCore`.

**Abweichungen vom Plan:**
- Das Schema enthält nur die Phase-1-Modelle. Weitere Bereiche kommen als neue Schema-Versionen
  dazu (Hinzufügen von Modellen ist eine leichte Migration). Das hält jede Phase für sich testbar.
- App, Widget und TagwerkKit bleiben vorerst im Swift-5-Sprachmodus. Ohne Mac kostet jeder
  Compiler-Fehler einen CI-Lauf; die Umstellung auf Swift 6 folgt, wenn die Oberfläche steht.
  `TagwerkCore` läuft bereits im Swift-6-Modus.

## Phase 2: Medikamente

| Teil | Wo | Aufgabe |
|---|---|---|
| Zeitpläne, Einnahmen, Treue, Vorrat, Bei Bedarf | `TagwerkCore/Medication/` | reine Logik, unter Linux getestet (`MedicationTests.swift`) |
| `TagwerkSchemaV2` | `TagwerkKit/…/Models/SchemaV2.swift` | `Medication`, `DoseLog`; Aufgaben-Modelle aus V1 übernommen |
| `TagwerkMigrationPlan` | ebenda | V1 → V2 als leichte Migration (nur neue Tabellen) |
| `TagwerkStore` | `…/Models/TagwerkStore.swift` | kopiert die Datenbank vor jeder Schema-Änderung (`Tagwerk-vor-v2.store`) |
| `MedicationActions` | `…/Models/MedicationActions.swift` | Abhaken, Auslassen, Rückgängig, Bei Bedarf, Vorrat, Nachschub-Aufgabe |
| `ReminderScheduler` | `…/Services/ReminderScheduler.swift` | Aufgaben und Medikamente gemeinsam, Medikamente zuerst |
| `MedicationSnapshotWriter`, `DoseActionCenter` | `…/Services/MedicationSharing.swift` | Widget-Daten im App-Group-Speicher, Einnahmen von außerhalb |
| `MedicationAlarmScheduler` | `App/Services/` | AlarmKit-Wecker rollierend (48 h), Knopf „Genommen“ |
| `TakeDoseIntent`, `TakeNextDoseIntent` | `Shared/MedicationIntents.swift` | in App **und** Widget kompiliert |

**Eine Einnahme von außerhalb der App** (Widget, Kontrollzentrum, Wecker, Siri, Mitteilung):

```
Knopf im Widget ──► TakeDoseIntent (LiveActivityIntent)
                        │  iOS führt ihn im App-Prozess aus
                        ▼
                DoseActionCenter.submit
                 ├─ App läuft:  AppModel.handleDoseAction
                 │              → DoseLog speichern, Vorrat, Mitteilungen + Wecker
                 │                abbestellen, Widget-Daten neu, alles neu planen
                 └─ sonst:      Warteschlange (App Group) + Widget sofort abgehakt
                                → App übernimmt beim nächsten Öffnen
```

Jede geplante Einnahme hat eine feste Kennung `DoseID` = `<Medikament>|<Unix-Sekunden>`.
Daraus entstehen die Mitteilungs-IDs (`med.…`, `medlate.…`, `medsnooze.…`) und die Wecker-UUID
(`StableUUID`), damit alle Stellen dieselbe Einnahme wiederfinden.

**Hintergrundaktualisierung** (`BGAppRefreshTask` `de.tagwerk.app.refresh`) plant Mitteilungen
und Wecker auch ohne Öffnen der App nach.

**Selbsttest im CI:** Was unter Linux nicht testbar ist (Migration einer echten V1-Datenbank,
Medikamenten-Aktionen, Sicherung mit Medikamenten, Widget-Daten), prüft `App/Features/Support/SelfTest.swift`.
Der UI-Test `testSelfTest` startet die App mit `-selfTest` und erwartet „Alle … bestanden“.
Ein eigenes Unit-Test-Target hätte die Pakete ein zweites Mal gelinkt (doppelte SwiftData-Klassen).

## Phase 3: Training

| Teil | Wo | Aufgabe |
|---|---|---|
| Übungen, Startplan | `TagwerkCore/Resources/exercises.de.json`, `plan-upper-4day.json` | als SPM-Ressourcen (`Bundle.module`), unter Linux geprüft |
| Katalog, Plan-Format, Import | `TagwerkCore/Training/ExerciseCatalog.swift`, `PlanTemplate.swift` | Muskelgruppen mit Zielbereichen, `orbit.plan.v1`, unscharfe Namenszuordnung |
| Progression, Zyklus, Aufwärmen, Volumen, Rekorde, Rotation | `TagwerkCore/Training/TrainingLogic.swift` | reine Logik (`TrainingTests.swift`) |
| `TagwerkSchemaV3` | `TagwerkKit/…/Models/SchemaV3.swift` | `WorkoutPlan`, `PlanDay`, `PlanExercise`, `WorkoutSession`, `SetLog`, `CustomExercise`, `ExercisePreference`, `BodyMetric`; V2 → V3 leicht |
| `TrainingActions` | `…/Models/TrainingActions.swift` | Startplan, Einheit starten/abschließen, nächster Satz (Supersätze), Tauschen, Statistik, Agenda, Erinnerungen |
| `TrainingSnapshotWriter`, `WorkoutActionCenter` | `…/Services/TrainingSharing.swift` | Widget-Daten, Befehle aus der Live Activity |
| `TrainingBackupMapper` | `…/Services/TrainingBackupMapper.swift` | Training in der Sicherung |
| `WorkoutRunner` | `App/Services/WorkoutRunner.swift` | Pausen-Timer, Live Activity, Mitteilung „Pause vorbei“ |
| `WorkoutActivityAttributes`, Knopf-Intents | `Shared/WorkoutActivity.swift` | in App **und** Widget kompiliert |
| Training-Tab, Einheit, Editor, Statistik | `App/Features/Training/` | SwiftUI |

**Eine Einheit** ist eine `WorkoutSession` ohne `endedAt`. Beim Start werden alle Sätze als
`SetLog` mit Zielwerten angelegt (Gewicht aus dem Vorschlag, Aufwärmsätze davor). Abhaken setzt
Ist-Werte und `completedAt`. Beim Abschließen fallen offene Sätze weg, und der Plan rückt
eine Einheit weiter (`PlanProgress`). Die Vorgeschichte für Vorschläge liest `TrainingActions`
aus abgeschlossenen Einheiten und reicht sie als Werte an `TagwerkCore`.

**Knopf in der Live Activity:**

```
„Satz fertig“ ──► CompleteSetIntent (LiveActivityIntent, läuft im App-Prozess)
                     ▼
              WorkoutActionCenter.submit
               ├─ App läuft:  AppModel.handleWorkoutCommand
               │              → Satz abhaken, Pause starten, Live Activity aktualisieren
               └─ sonst:      Warteschlange (App Group), App übernimmt beim Öffnen
```

Die Live Activity setzt `staleDate` auf das Pausenende. Danach zeigt sie „Pause vorbei“ statt
eines Countdowns, auch wenn die App nicht mehr läuft.

**Selbsttest:** Migration V1 → V3 und V2 → V3 (Medikamente bleiben), eine Einheit mit Abschluss
und Vorschlag für die nächste (Steigerung, Aufwärmsätze), Sicherung mit Training.

## Phase 4: Ernährung und Histamin

| Teil | Wo | Aufgabe |
|---|---|---|
| Lexikon, Zutatenregeln, Rezepte | `TagwerkCore/Resources/foods.de.json`, `ingredient-rules.de.json`, `recipes.de.json` | 350 Lebensmittel, 87 Regeln (230 Stichworte, 51 E-Nummern), 32 Rezepte |
| Katalog, Verträglichkeit, Siri-Antwort | `TagwerkCore/Nutrition/FoodCatalog.swift` | Suche mit Mehrzahl, eigene Einschätzung vor Standard |
| Zutaten-Check | `…/Nutrition/IngredientAnalyzer.swift` | längstes Stichwort je Wort, Ausnahmen, `^` Wortanfang, `=` ganzes Wort, E-Nummern |
| Tageslast, Ziele, Mahlzeiten | `…/Nutrition/NutritionLogic.swift` | Punkte je Bewertung × Menge, Zuschläge für Reste/Aufgewärmt/Auswärts |
| Beschwerden, Muster | `…/Nutrition/Symptoms.swift` | Gewicht nach Zeitabstand, Grundrate, Mindestmengen |
| Rezepte, Einkauf | `…/Nutrition/Recipes.swift` | Portionen, Zusammenfassen, Supermarkt-Bereiche |
| Barcode, Open Food Facts | `…/Nutrition/OpenFoodFacts.swift` | Prüfziffer, Antwort auslesen (unter Linux getestet) |
| `TagwerkSchemaV4` | `TagwerkKit/…/Models/SchemaV4.swift` | `MealEntry`, `MealItem`, `SymptomEntry`, `WaterLog`, `ShoppingItem`, `MealPlanEntry`, `CustomFood`, `CustomRecipe`, `FoodPreference`; V3 → V4 leicht |
| `NutritionActions` | `…/Models/NutritionActions.swift` | Tagebuch, Tageswerte, Muster, Einkauf, Wochenplan, Medikamente „vor dem Essen“ |
| `FoodLookupService` | `…/Services/FoodLookupService.swift` | Open Food Facts mit eigenem User-Agent, Ergebnis als eigenes Lebensmittel |
| `NutritionSnapshotWriter`, `NutritionActionCenter` | `…/Services/NutritionSharing.swift` | Widget-Daten, Wasser aus Widget und Kontrollzentrum |
| `AddWaterIntent`, `LogSymptomIntent` | `Shared/NutritionIntents.swift` | in App **und** Widget kompiliert |
| Tab, Editor, Scanner, Listen | `App/Features/Nutrition/` | SwiftUI, VisionKit `DataScannerViewController` |

**Inhalte bleiben im Paket:** Lexikon, Regeln und Rezepte liegen als JSON in `TagwerkCore` und
werden nicht in die Datenbank kopiert. Die Datenbank speichert nur, was du selbst anlegst oder
einstellst (Mahlzeiten, Einschätzungen, gescannte Produkte). Neue Inhalte kommen mit einem Update,
ohne Migration. Mahlzeiten speichern den Namen jedes Lebensmittels mit, falls es später fehlt.

**Wasser von außerhalb** läuft wie die Einnahmen aus Phase 2: `AddWaterIntent` ist ein
`LiveActivityIntent`, iOS führt ihn im App-Prozess aus. Läuft er doch in der Erweiterung,
landet das Glas in einer Warteschlange (App Group) und das Widget zeigt es sofort.

**Selbsttest:** Migration V1/V2/V3 → V4, Ernährungs-Ablauf (Muster, Tageslast mit Einschätzung,
Wasser, Einkauf aus dem Wochenplan ohne Doppelte), Sicherung mit Ernährung.

## Phase 5: Einblicke und Claude-Brücke

| Teil | Wo | Aufgabe |
|---|---|---|
| Check-ins, Umstände | `TagwerkCore/Insights/CheckIns.swift` | Skalen 1–5, Morgen/Abend, „Schlecht geschlafen“ und „Viel Stress“ als `DayFactor` für die Muster |
| Wochenrückblick | `…/Insights/WeeklyReview.swift` | Abschnitte, Höhepunkte, Kurzfassung ohne Namen, Sonntags-Erinnerung |
| Arztbericht | `…/Insights/DoctorReport.swift` | Medikamente mit Treue, Beschwerden je Woche und Art, Muster, Gewicht, Befinden |
| Claude-Anfragen und -Antworten | `…/ClaudeBridge/ClaudeTasks.swift` | Prompt je Anwendungsfall mit Liste der enthaltenen Daten, Parser für `orbit.plan.v1`, `orbit.text.v1`, `orbit.food.v1`, `orbit.recipes.v1` |
| `TagwerkSchemaV5` | `TagwerkKit/…/Models/SchemaV5.swift` | `DailyCheckIn`, `ClaudeExchange`; V4 → V5 leicht |
| `InsightsActions` | `…/Models/InsightsActions.swift` | Check-ins, Daten für Rückblick und Bericht aus allen Bereichen, Verlauf |
| `ClaudeBridgeActions` | `…/Models/ClaudeBridgeActions.swift` | Daten für die Anfragen sammeln, Antwort zuordnen, Plan/Lebensmittel/Rezepte übernehmen |
| Sicherung | `…/Services/InsightsBackupMapper.swift` | Check-ins und Claude-Verlauf (Sicherungen vor 0.6 lassen sie stehen) |
| Oberfläche | `App/Features/Insights/` | Check-in, Befinden, Rückblick, Arztbericht (PDF per `ImageRenderer` in einen PDF-Kontext, A4), Claude-Zentrale |

**Antwort zuordnen:** Der Kurzbefehl-Aufruf trägt die `stableID` der Anfrage als Rückruf-ID
(`tagwerk://claude/success/<stableID>`). Kommt die Antwort nur über den Briefkasten, zählt zuerst
die Kennung `ref` in der Antwort, dann ein wartender Systemcheck, dann die zuletzt abgeschickte
Anfrage. Lange Anfragen (über 8000 Zeichen) gehen über die Zwischenablage (`input=clipboard`).

**Siri:** Bei 10 App-Kurzbefehlen ist Schluss. „Check-in“ ersetzt den Systemcheck, der als Aktion
in der Kurzbefehle-App bleibt.

**Selbsttest:** Migration V1/V2/V3/V4 → V5, Check-ins als Umstände, Rückblick ohne Namen,
Arztbericht mit 3 PDF-Seiten, Claude-Ablauf (Zuordnung über `ref`, Lebensmittel, Plan mit
unbekannter Übung, Rezept mit neuer Zutat), Sicherung mit Einblicken.

## Phase 6: Leben und Feinschliff

| Teil | Wo | Aufgabe |
|---|---|---|
| Routinen und Gewohnheiten | `TagwerkCore/Life/Habits.swift` | Zeitplan (täglich, Wochentage, x-mal pro Woche), Schritte, Serien, Quote, Erinnerungen |
| Verträge und Fristen | `…/Life/Contracts.swift` | Kosten pro Monat, Laufzeit, Verlängerung, nächste erreichbare Kündigungsfrist, Ablauf von Dokumenten |
| Geburtstage, Tagebuch | `…/Life/Birthdays.swift` | nächster Termin (29.2. → 28.2.), Alter, Fragen fürs Tagebuch |
| Vorlagen | `…/Life/LifeTemplates.swift` | Haushalt, Routinen, Verträge und Dokumente |
| Fortschritt | `…/Training/ProgressAssessment.swift` | Trend des e1RM je Übung (lineare Regression, % pro Woche), Gewichtstempo |
| Widget-Stand „Heute“, Fokus | `…/Life/TodaySnapshot.swift`, `…/Life/FocusFilter.swift` | Stand für zwei Widgets, Warteschlange fürs Abhaken, Fokus-Filter |
| `TagwerkSchemaV6` | `TagwerkKit/…/Models/SchemaV6.swift` | `Habit`, `HabitLog`, `Contract`, `Birthday`, `JournalEntry`, `ProgressPhoto` (Bild als externe Datei), `ExercisePreference` mit Startgewicht; V5 → V6 leicht |
| `LifeActions`, `ProgressActions` | `…/Models/` | Abhaken, Agenda, Erinnerungen, Top 3 für morgen, Fotos |
| Sicherung | `…/Services/LifeBackupMapper.swift` | Leben-Daten (ohne Fotos) |
| Widgets | `Widgets/TodayWidget.swift` | „Heute“ (klein bis groß, Sperrbildschirm), „Aufgaben“ mit `CompleteTaskIntent`, Controls „Neue Aufgabe“ und „Check-in“ |
| iPhone-Integration | `App/Services/` | `SpotlightIndexer` (CoreSpotlight), `AppLock` (LocalAuthentication, eigenes Fenster über allem), `GymArrival` (`CLMonitor`), `TodayWidgetWriter` |
| Fokus-Filter | `App/Intents/FocusFilterIntent.swift` | `SetFocusFilterIntent` mit Listen-Entity |
| Tipps | `App/Features/OrbitTips.swift` | TipKit, im UI-Test ausgeblendet |

**Widget-Bündel:** Ein `WidgetBundle` nimmt höchstens zehn Einträge direkt auf. Heute, Aufgaben
und die zwei neuen Controls stehen deshalb in `DailyWidgets`.

**Selbsttest:** zusätzlich Migration V5 → V6 (Startgewicht leer, Steigerung bleibt), eigener Plan
mit Startgewichten, Leben-Ablauf, Sicherung mit Leben.

## Regeln ab Phase 1 (SwiftData, CloudKit-tauglich)

- keine `@Attribute(.unique)`, Eindeutigkeit über `stableID: String`
- jede Eigenschaft optional oder mit Standardwert
- alle Beziehungen optional, keine `.deny`-Löschregel
- versioniertes Schema (`VersionedSchema` + `SchemaMigrationPlan`) von Anfang an

## URL-Schema

| URL | Wirkung |
|---|---|
| `tagwerk://systemcheck` | öffnet den Systemcheck |
| `tagwerk://neu` | öffnet die Schnellerfassung |
| `tagwerk://gesundheit` | öffnet den Tab „Gesundheit“ (Medikamenten-Widget) |
| `tagwerk://training` | öffnet den Tab „Training“ (Widget, Live Activity) |
| `tagwerk://training/start` | startet die nächste Einheit |
| `tagwerk://ernaehrung` | öffnet den Tab „Ernährung“ (Widget) |
| `tagwerk://mahlzeit` | öffnet den Mahlzeit-Editor |
| `tagwerk://wasser` | trägt ein Glas Wasser ein |
| `tagwerk://symptom` | öffnet die Erfassung von Beschwerden |
| `tagwerk://checkin` | öffnet den Check-in des Tages |
| `tagwerk://rueckblick` | öffnet den Wochenrückblick |
| `tagwerk://claude` | öffnet die Claude-Zentrale |
| `tagwerk://leben` | öffnet Planer → Leben |
| `tagwerk://heute`, `tagwerk://aufgaben` | öffnet „Heute“ bzw. Planer → Aufgaben (Widgets) |
| `tagwerk://claude/success/<id>?result=…` | Rücksprung aus dem Kurzbefehl „Orbit Claude“ (Anfrage oder Systemcheck) |
| `tagwerk://claude/cancel/<id>`, `tagwerk://claude/error/<id>?errorMessage=…` | Abbruch oder Fehler im Kurzbefehl |

## Screenshots im CI

`UITests/ScreenshotTests.swift` startet die App mit `-uiTesting` und erzwingt Sprache (`de`),
Erscheinungsbild (`-forceLight` / `-forceDark`) und Schriftgröße. Die Screenshots landen als
Artefakt `screenshots` im Lauf von `ios.yml` und tragen lesbare Namen wie `01-heute-hell.png`.
