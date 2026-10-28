# Phase 9 auf dem iPhone testen

Version 1.0.0. Etwa 15 Minuten. Bitte melde, was nicht klappt (Screenshot reicht).

Die Datenbank ändert sich in dieser Phase nicht (bleibt Schema 8). Ein Update ist also besonders
unkritisch.

## Vorbereitung

1. Release **1.0.0** installieren (über iloader, wie bisher). Alles aus 0.9 muss danach noch da sein.

## Test

| # | Test | Erwartung |
|---|---|---|
| 1 | Alles nach dem Update da? | Tagebuch, Training, Mahlzeiten, Health-Werte unverändert |
| 2 | **Einstellungen → Datensicherung → Zusätzlich in iCloud Drive sichern …** | Dateien-Dialog öffnet sich |
| 3 | In iCloud Drive einen Ordner wählen (z. B. neuen Ordner „Orbit“ anlegen) | Zeile „Zweiter Ort: Orbit“, Stand „gerade eben“ |
| 4 | Dateien-App → iCloud Drive → Orbit | Eine Datei `Orbit-Backup-….json` |
| 5 | Am nächsten Tag App öffnen | Neue Sicherung auch im iCloud-Ordner, höchstens 14 bleiben |
| 6 | **Planer → Aufgaben → Aus Erinnerungen übernehmen** | Erklärung und Knopf „Zugriff erlauben“ |
| 7 | **Zugriff erlauben** → „Vollzugriff“ bestätigen | Deine Listen mit Anzahl „… offen, … erledigt“ |
| 8 | Listen auswählen, **… Erinnerungen übernehmen** | „… Erinnerungen in … Listen übernommen“ |
| 9 | Planer → Listen | Gleichnamige Listen mit den Aufgaben, Fälligkeit und Wiederholung stimmen |
| 10 | Import noch einmal starten | Knopf zeigt „Nichts Neues zu übernehmen“ (nichts doppelt) |
| 11 | Ein Training abschließen, dann **Training → Statistik** | Muskel-Karte vorne/hinten: grün im Ziel, orange zu wenig, rot viel |
| 12 | Eine Woche zurückblättern | Karte und Balken passen zur gewählten Woche |
| 13 | Optional: VoiceOver an (Einstellungen → Bedienungshilfen) | Karte, Diagramme und Knöpfe werden verständlich vorgelesen |
| 14 | Allgemeines Tempo: Heute, Ernährung, Gesundheit durchblättern | Flüssig, keine Wartezeit |

## Gut zu wissen

- Der Import aus Erinnerungen ist einmalig: Orbit ändert in Apple Erinnerungen nichts, und neue
  Erinnerungen kommen erst beim nächsten Import mit. Unteraufgaben und Orte werden nicht übernommen.
- Die Sicherung im zweiten Ordner läuft mit der täglichen Sicherung beim Öffnen der App. Ist der
  Ordner nicht erreichbar (z. B. gelöscht), zeigt die Einstellung einen Hinweis. Dann den Ordner neu
  wählen.

## Wenn etwas nicht geht

- **Kein Zugriff auf Erinnerungen:** Einstellungen → Apps → Orbit → Erinnerungen → „Vollzugriff“.
- **Daten weg nach dem Update:** App nicht löschen! Melde dich. Die tägliche Sicherung liegt in der
  Dateien-App (Orbit → Backups) und jetzt auch im gewählten iCloud-Ordner.
