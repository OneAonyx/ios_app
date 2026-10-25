# Architektur

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

## Regeln ab Phase 1 (SwiftData, CloudKit-tauglich)

- keine `@Attribute(.unique)`, Eindeutigkeit über `stableID: String`
- jede Eigenschaft optional oder mit Standardwert
- alle Beziehungen optional, keine `.deny`-Löschregel
- versioniertes Schema (`VersionedSchema` + `SchemaMigrationPlan`) von Anfang an

## URL-Schema

| URL | Wirkung |
|---|---|
| `tagwerk://systemcheck` | öffnet den Systemcheck |
| `tagwerk://claude/success/<id>?result=…` | Rücksprung aus dem Kurzbefehl „Tagwerk Claude“ |
| `tagwerk://claude/cancel/<id>`, `tagwerk://claude/error/<id>?errorMessage=…` | Abbruch oder Fehler im Kurzbefehl |

## Screenshots im CI

`UITests/ScreenshotTests.swift` startet die App mit `-uiTesting` und erzwingt Sprache (`de`),
Erscheinungsbild (`-forceLight` / `-forceDark`) und Schriftgröße. Die Screenshots landen als
Artefakt `screenshots` im Lauf von `ios.yml` und tragen lesbare Namen wie `01-heute-hell.png`.
