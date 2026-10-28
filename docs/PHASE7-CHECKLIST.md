# Phase 7 auf dem iPhone testen

Version 0.8.0. Etwa 15 Minuten, dazu zwei Wochen Tagebuch im Alltag. Bitte melde, was nicht klappt
(Screenshot reicht).

## Vorbereitung

1. Release **0.8.0** installieren (über iloader, wie bisher). Alles aus 0.7 muss danach noch da
   sein. Die Datenbank wird beim ersten Start erweitert (Kopie: `Tagwerk-vor-v7.store`).
2. Mitteilungen für Orbit sind erlaubt.

## Erfassen

| # | Test | Erwartung |
|---|---|---|
| 1 | Alles nach dem Update da? | Aufgaben, Medikamente, Training, Mahlzeiten, Routinen unverändert |
| 2 | **Heute** → Karte **Tagebuch heute** | Punkte Essen, Beschwerden, Bewegung, (Medikamente), Check-in mit Stand |
| 3 | **Keine Beschwerden** antippen | Punkt Beschwerden zeigt „keine“ mit Haken |
| 4 | **Schmerz** → Schulter rechts und Ellbogen rechts antippen, Stärke 6, stechend, Sichern | Eintrag unter **Gesundheit → Schmerzen** |
| 5 | Körperkarte **Hinten** → unterer Rücken | Region wird markiert |
| 6 | Eintrag in **Schmerzen** antippen, Stärke ändern | Änderung bleibt |
| 7 | **Bewegung** → Radfahren, 45 Min., mittel | Eintrag unter **Gesundheit → Bewegung**, Wochenring zählt mit |
| 8 | Ein Gym-Training beenden | erscheint automatisch unter Bewegung |
| 9 | **Ruhetag** an einem Tag ohne Sport | Punkt Bewegung zeigt „Ruhetag“ |
| 10 | Abends bis 20:30 Uhr nichts eintragen | Mitteilung „Tagebuch für heute“ mit dem, was fehlt |

## Arztbericht

| # | Test | Erwartung |
|---|---|---|
| 11 | **Gesundheit → Arztbericht** | Vollständigkeit mit Prozent, Inhalt mit Schaltern |
| 12 | **Fragen an den Arzt** eintragen | stehen im PDF auf Seite 1 |
| 13 | **PDF erstellen** | Seiten zu Beschwerden, Bewegung, Schmerzen (mit Körperkarte), Ernährung, Tag-für-Tag-Tabelle |
| 14 | Einen Teil abwählen (z. B. Gewicht), neu erstellen | Teil fehlt im PDF |
| 15 | **Teilen** → per Mail an dich | PDF kommt an und ist lesbar |

## Kurzbefehle

| # | Test | Erwartung |
|---|---|---|
| 16 | Kurzbefehle-App → neue Aktion → Orbit → **Bewegung eintragen** (Laufen, 30, intensiv) ausführen | „Laufen 30 Min., intensiv eingetragen.“ |
| 17 | **Heute keine Beschwerden** ausführen | Vermerk erscheint auf **Heute** |

## Wenn etwas nicht geht

- **Erinnerung kommt nicht:** Einstellungen → Einblicke → „Abends an Tagebuch erinnern“ an, und
  Mitteilungen für Orbit erlaubt. Sie kommt nur, wenn noch etwas fehlt.
- **Daten weg nach dem Update:** App nicht löschen! Melde dich. Die Kopie `Tagwerk-vor-v7.store`
  und die tägliche Sicherung (Dateien-App → Orbit → Backups) sind noch da.
