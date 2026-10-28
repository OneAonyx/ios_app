# Phase 8 auf dem iPhone testen

Version 0.9.0. Etwa 15 Minuten. Bitte melde, was nicht klappt (Screenshot reicht).

## Vorbereitung

1. Release **0.9.0** installieren (über iloader, wie bisher). Alles aus 0.8 muss danach noch da
   sein (Kopie: `Tagwerk-vor-v8.store`).
2. Kurzbefehl **Orbit Health** nach [`HEALTH-KURZBEFEHL.md`](HEALTH-KURZBEFEHL.md) anlegen.

## Test

| # | Test | Erwartung |
|---|---|---|
| 1 | Alles nach dem Update da? | Tagebuch, Training, Mahlzeiten, Routinen unverändert |
| 2 | **Gesundheit → Apple Health** | „noch nie“ übernommen, Link zur Anleitung |
| 3 | Kurzbefehl in der Kurzbefehle-App ausführen | Meldung „Orbit hat übernommen: … Schritte …“ |
| 4 | Zurück in Orbit: **Apple Health** | Schritte von heute, „zuletzt vor 1 Min.“ |
| 5 | **Jetzt aus Health holen** | Kurzbefehl läuft, Orbit springt zurück, Hinweis „Werte aus Health übernommen“ |
| 6 | **Heute → Tagebuch heute** | Bewegung zeigt die Schritte, falls kein Sport eingetragen ist |
| 7 | **Gesundheit → Bewegung** | Zeile „Heute … Schritte · Ø … in 7 Tagen“ |
| 8 | Optional Gewicht: Waage schreibt in Health, Kurzbefehl ausführen | Gewicht unter Training → Körper, beim zweiten Lauf nicht doppelt |
| 9 | Optional Wasser: 2 Gläser in Orbit, Kurzbefehl mit „Wasser für Health“ | 500 ml in Health; zweiter Lauf ohne neues Wasser trägt nichts ein |
| 10 | Automation 21:30 anlegen, abwarten | Werte kommen ohne Nachfrage |
| 11 | **Arztbericht** erstellen | Bewegung mit „Ø … Schritte am Tag“, Tabelle mit Schritten je Tag |

## Wenn etwas nicht geht

- Schritt 3 meldet einen Fehler: Den Text der Meldung schicken. Die Namen der Aktionen weichen je
  nach iOS-Version leicht ab.
- **Daten weg nach dem Update:** App nicht löschen! Melde dich. Die Kopie `Tagwerk-vor-v8.store`
  und die tägliche Sicherung (Dateien-App → Orbit → Backups) sind noch da.
