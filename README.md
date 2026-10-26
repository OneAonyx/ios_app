# Tagwerk

Persönliche Alltags-App fürs iPhone: Aufgaben, Kalender, Medikamente, Apple Health,
Histamin-Tagebuch, Gym-Training und mehr. Native SwiftUI-App, tief ins iPhone integriert
(Widgets, Sperrbildschirm, Dynamic Island, Wecker, Siri und Kurzbefehle).

**Stand: Phase 0 – Fundament & Systemcheck.** Die App hat das Tab-Gerüst, das Design-System
und einen Systemcheck mit 6 Tests. Er klärt, was mit einer kostenlosen Apple-ID per SideStore
auf deinem iPhone funktioniert. Der vollständige Plan steht in [`docs/PLAN.md`](docs/PLAN.md).

## Schnellstart

| Was | Wo |
|---|---|
| Neueste App-Version (`Tagwerk.ipa`) | [Releases](https://github.com/OneAonyx/ios_app/releases/latest) |
| App aufs iPhone bringen | [`docs/SIDELOAD.md`](docs/SIDELOAD.md) |
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
| `release.yml` | macOS | manuell („Run workflow“) oder Tag `v*` | `Tagwerk.ipa` als GitHub-Release für SideStore |

Neue Version veröffentlichen: GitHub → **Actions** → **Release (IPA für SideStore)** → **Run workflow**
→ Version eingeben (z. B. `0.1.0`) → **Run workflow**. Nach etwa 15 Minuten liegt `Tagwerk.ipa`
unter [Releases](https://github.com/OneAonyx/ios_app/releases/latest).

Nach jedem Lauf liegen Log, Fehlerauszug und Screenshots zusätzlich auf den Branches `ci-ios`
und `ci-release`.

Logiktests lokal (ohne Mac, mit Docker):

```bash
docker run --rm -v "$PWD/Packages/TagwerkCore:/pkg" -w /pkg swift:6.2-noble swift test
```

## Struktur

```
App/                 App-Target (SwiftUI): Heute, Systemcheck, Einstellungen, App Intents
Widgets/             Einzige Extension: Widgets, Live Activities (später auch Controls)
UITests/             Screenshot-Tests für das CI
Packages/TagwerkCore Fachlogik, plattformunabhängig, unter Linux getestet
Packages/TagwerkKit  Design-System und iOS-Dienste (Health, Wecker, Mitteilungen, App Group)
Scripts/ci/          Hilfsskripte für die Workflows
docs/                Plan, Anleitungen, Architektur
```

## Hinweis

Tagwerk ist kein Medizinprodukt. Histamin-Bewertungen sind eine Orientierung, und Erinnerungen
ersetzen keine ärztliche Beratung. Alle Daten bleiben auf dem iPhone.
