# Orbit

Persönliche Alltags-App fürs iPhone: Aufgaben, Kalender, Medikamente, Apple Health,
Histamin-Tagebuch, Gym-Training und mehr. Native SwiftUI-App, tief ins iPhone integriert
(Widgets, Sperrbildschirm, Dynamic Island, Wecker, Siri und Kurzbefehle).

**Stand: Phase 3 – Training.** Startplan „Oberkörper 4er“ als Rotation mit 6-Wochen-Zyklus und
Deload, Satz-Tracking mit „Letztes Mal“ und Gewichtsvorschlag (doppelte Progression),
automatische Aufwärmsätze, Supersätze, Pausen-Timer in Dynamic Island und auf dem
Sperrbildschirm, Planeditor und Plan-Import (JSON), 93 Übungen, Statistik und Körperwerte.
Dazu aus Phase 2: Medikamente mit Erinnerungen, Wecker, Vorrat und Widget; aus Phase 1:
Aufgaben, Schnellerfassung, Agenda und Woche mit Kalenderterminen, tägliche Datensicherung.
Der vollständige Plan steht in [`docs/PLAN.md`](docs/PLAN.md).

## Schnellstart

| Was | Wo |
|---|---|
| Neueste App-Version (`Orbit.ipa`) | [Releases](https://github.com/OneAonyx/ios_app/releases/latest) |
| App aufs iPhone bringen | [`docs/SIDELOAD.md`](docs/SIDELOAD.md) |
| Was die Schnellerfassung versteht | [`docs/SCHNELLERFASSUNG.md`](docs/SCHNELLERFASSUNG.md) |
| Medikamente, Erinnerungen, Widget | [`docs/MEDIKAMENTE.md`](docs/MEDIKAMENTE.md) |
| Training, Progression, Plan-Import | [`docs/TRAINING.md`](docs/TRAINING.md) |
| Phase 3 auf dem iPhone testen | [`docs/PHASE3-CHECKLIST.md`](docs/PHASE3-CHECKLIST.md) |
| Phase 2 auf dem iPhone testen | [`docs/PHASE2-CHECKLIST.md`](docs/PHASE2-CHECKLIST.md) |
| Phase-0-Tests durchführen | [`docs/PHASE0-CHECKLIST.md`](docs/PHASE0-CHECKLIST.md) |
| Phase-0-Ergebnis | [`docs/PHASE0-ERGEBNIS.md`](docs/PHASE0-ERGEBNIS.md) |
| Kurzbefehl für Claude einrichten | [`docs/CLAUDE-BRIDGE.md`](docs/CLAUDE-BRIDGE.md) |
| Aufbau des Codes | [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) |

## Ohne Mac bauen

Die `.xcodeproj` liegt nicht im Repo. [XcodeGen](https://github.com/yonaskolb/XcodeGen) erzeugt sie
im CI aus [`project.yml`](project.yml).

| Workflow | Läuft auf | Wann | Ergebnis |
|---|---|---|---|
| `core.yml` | Linux | Änderungen an `TagwerkCore` | Logiktests |
| `ios.yml` | macOS | Push auf `main` | Build, UI-Tests, Screenshots (Artefakt `screenshots`) |
| `release.yml` | macOS | manuell („Run workflow“) oder Tag `v*` | `Orbit.ipa` als GitHub-Release für SideStore |

Neue Version veröffentlichen: GitHub → **Actions** → **Release (IPA für SideStore)** → **Run workflow**
→ Version eingeben (z. B. `0.1.0`) → **Run workflow**. Nach etwa 15 Minuten liegt `Orbit.ipa`
unter [Releases](https://github.com/OneAonyx/ios_app/releases/latest).

Nach jedem Lauf liegen Log, Fehlerauszug und Screenshots zusätzlich auf den Branches `ci-ios`
und `ci-release`.

Logiktests lokal (ohne Mac, mit Docker):

```bash
docker run --rm -v "$PWD/Packages/TagwerkCore:/pkg" -w /pkg swift:6.2-noble swift test
```

## Struktur

```
App/                 App-Target (SwiftUI): Heute, Planer, Training, Gesundheit, Einstellungen, App Intents
Shared/              Was App und Widget gemeinsam brauchen (Abhaken, Live-Activity-Knöpfe)
Widgets/             Einzige Extension: Widgets, Live Activities, Kontrollzentrum
UITests/             Screenshot-Tests für das CI
Packages/TagwerkCore Fachlogik, plattformunabhängig, unter Linux getestet
Packages/TagwerkKit  Datenmodell (SwiftData), Design-System und iOS-Dienste (Wecker, Mitteilungen, App Group)
Scripts/ci/          Hilfsskripte für die Workflows
docs/                Plan, Anleitungen, Architektur
```

## Hinweis

Orbit ist kein Medizinprodukt. Histamin-Bewertungen sind eine Orientierung, und Erinnerungen
ersetzen keine ärztliche Beratung. Alle Daten bleiben auf dem iPhone.
