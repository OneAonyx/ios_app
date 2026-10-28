# Orbit

Persönliche Alltags-App fürs iPhone: Aufgaben, Kalender, Medikamente, Apple Health,
Histamin-Tagebuch, Gym-Training und mehr. Native SwiftUI-App, tief ins iPhone integriert
(Widgets, Sperrbildschirm, Dynamic Island, Wecker, Siri und Kurzbefehle).

**Stand: Phase 6 – Leben & Feinschliff.** Routinen und Gewohnheiten mit Serien, Verträge und
Fristen mit Kündigungs-Erinnerung, Geburtstage, Tagebuch mit Top 3 für morgen. Dein eigener
Trainingsplan mit Startgewichten, Fortschritts-Bewertung je Übung, Fortschrittsfotos mit Vergleich.
Widgets „Heute“ und „Aufgaben“ (abhakbar), Spotlight, Fokus-Filter, App-Sperre mit Face ID,
Gym-Ankunft. Aus Phase 5: Check-ins, Wochenrückblick, Arztbericht als PDF und die Claude-Brücke
(über die Claude-App, ohne API-Key). Dazu aus Phase 4: Ernährung mit Histamin-Lexikon, Scanner, Tagebuch, Mustern,
Einkauf und Rezepten; aus Phase 3: Training mit Progression und Pausen-Timer in der Dynamic Island;
aus Phase 2: Medikamente mit Erinnerungen und Wecker; aus Phase 1: Aufgaben, Schnellerfassung,
Agenda, tägliche Datensicherung. Orbit läuft dauerhaft mit kostenloser Apple-ID (kein Developer-Account).
Der vollständige Plan steht in [`docs/PLAN.md`](docs/PLAN.md).

## Schnellstart

| Was | Wo |
|---|---|
| Neueste App-Version (`Orbit.ipa`) | [Releases](https://github.com/OneAonyx/ios_app/releases/latest) |
| App aufs iPhone bringen | [`docs/SIDELOAD.md`](docs/SIDELOAD.md) |
| Was die Schnellerfassung versteht | [`docs/SCHNELLERFASSUNG.md`](docs/SCHNELLERFASSUNG.md) |
| Medikamente, Erinnerungen, Widget | [`docs/MEDIKAMENTE.md`](docs/MEDIKAMENTE.md) |
| Routinen, Verträge, Geburtstage, Widgets, Fokus, App-Sperre | [`docs/LEBEN.md`](docs/LEBEN.md) |
| Phase 6 auf dem iPhone testen | [`docs/PHASE6-CHECKLIST.md`](docs/PHASE6-CHECKLIST.md) |
| Check-in, Wochenrückblick, Arztbericht, Claude | [`docs/EINBLICKE.md`](docs/EINBLICKE.md) |
| Phase 5 auf dem iPhone testen | [`docs/PHASE5-CHECKLIST.md`](docs/PHASE5-CHECKLIST.md) |
| Ernährung, Histamin, Scanner, Muster | [`docs/ERNAEHRUNG.md`](docs/ERNAEHRUNG.md) |
| Phase 4 auf dem iPhone testen | [`docs/PHASE4-CHECKLIST.md`](docs/PHASE4-CHECKLIST.md) |
| Training, eigener Plan, Fortschritt, Fotos | [`docs/TRAINING.md`](docs/TRAINING.md) |
| Phase 3 auf dem iPhone testen | [`docs/PHASE3-CHECKLIST.md`](docs/PHASE3-CHECKLIST.md) |
| Phase 2 auf dem iPhone testen | [`docs/PHASE2-CHECKLIST.md`](docs/PHASE2-CHECKLIST.md) |
| Phase-0-Tests durchführen | [`docs/PHASE0-CHECKLIST.md`](docs/PHASE0-CHECKLIST.md) |
| Phase-0-Ergebnis | [`docs/PHASE0-ERGEBNIS.md`](docs/PHASE0-ERGEBNIS.md) |
| Claude-Brücke: Kurzbefehl, Anfragen, Formate | [`docs/CLAUDE-BRIDGE.md`](docs/CLAUDE-BRIDGE.md) |
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
App/                 App-Target (SwiftUI): Heute, Planer mit Leben, Training, Ernährung, Gesundheit, Einstellungen, App Intents
Shared/              Was App und Widget gemeinsam brauchen (Abhaken, Wasser, Live-Activity-Knöpfe)
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
