# Phase 2 auf dem iPhone testen

Version 0.3.0. Etwa 20 Minuten, verteilt über einen Tag. Bitte melde, was nicht klappt
(Screenshot reicht).

## Vorbereitung

1. Release **0.3.0** installieren (über iloader, wie bisher). Deine Aufgaben müssen danach noch
   da sein. Das ist der wichtigste Test: Die Datenbank wird beim ersten Start erweitert.
2. **Gesundheit → +** und ein Testmedikament anlegen:
   - Name „Test“, Form Tablette, **Täglich**, Uhrzeit **in 3 Minuten**
   - Erinnerung **Mitteilung**, **Vorrat mitzählen** mit 10
3. Ein zweites Medikament „Test Wecker“ mit Uhrzeit **in 5 Minuten** und Erinnerung **Wecker**.
   iOS fragt nach der Wecker-Erlaubnis → erlauben.

## Tests

| # | Test | Erwartung |
|---|---|---|
| 1 | Aufgaben nach dem Update | alle Aufgaben und Listen sind noch da |
| 2 | iPhone sperren, auf „Test“ warten | Mitteilung kommt pünktlich |
| 3 | Mitteilung lange drücken → **Genommen** | App zeigt „genommen“, Vorrat 9 |
| 4 | iPhone **stumm** schalten, auf „Test Wecker“ warten | Wecker klingelt trotzdem |
| 5 | Am Wecker **Genommen** | Einnahme abgehakt, keine Nachfrage nach 30 Min. |
| 6 | Widget **Medikamente** (klein) auf den Home-Bildschirm | zeigt die nächste Einnahme |
| 7 | Im Editor eine Uhrzeit in 2 Min. ergänzen, dann im Widget **Genommen** | Widget zeigt sofort abgehakt, App ebenso |
| 8 | Kontrollzentrum → Steuerelement **Medikament genommen** hinzufügen und antippen | fällige Einnahme wird abgehakt |
| 9 | Siri: „Habe ich heute meine Tabletten in Orbit genommen?“ | Siri nennt erledigte und offene |
| 10 | Mitteilung → **In 10 Min** | 10 Minuten später kommt sie noch einmal |
| 11 | Einnahme offen lassen | nach 30 Min. Nachfrage „Noch offen: …“ |
| 12 | Vorrat auf 3 setzen | „Vorrat knapp“ erscheint, am nächsten Morgen um 9 Uhr ein Hinweis |
| 13 | **Planer → Agenda** | Einnahmen stehen zwischen Terminen und Aufgaben |

Zum Schluss die Testmedikamente löschen (Detail → Bearbeiten → Medikament löschen) und deine
echten Medikamente anlegen.

## Wenn etwas nicht geht

- **Keine Mitteilung:** Einstellungen → Mitteilungen → Orbit → erlauben. Auf „Gesundheit“
  erscheint sonst ein Hinweis.
- **Kein Wecker:** Einstellungen → Orbit → Wecker erlauben. Ohne Erlaubnis kommt eine Mitteilung.
- **Aufgaben weg nach dem Update:** App nicht löschen! Melde dich, die Kopie
  `Tagwerk-vor-v2.store` und die tägliche Sicherung (Dateien-App → Orbit → Backups) sind noch da.
