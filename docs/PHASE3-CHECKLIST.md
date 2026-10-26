# Phase 3 auf dem iPhone testen

Version 0.4.0. Ein Teil geht zu Hause in 10 Minuten, der Rest beim nächsten Training im Gym.
Bitte melde, was nicht klappt (Screenshot reicht).

## Vorbereitung

1. Release **0.4.0** installieren (über iloader, wie bisher). Aufgaben und Medikamente müssen
   danach noch da sein. Das ist der wichtigste Test: Die Datenbank wird beim ersten Start erweitert.
2. Tab **Training** öffnen. Der Plan „Oberkörper 4er – Hypertrophie“ ist schon angelegt.
3. **Training → Plan**: Wunsch-Wochentage und Uhrzeit für die Erinnerung prüfen (Standard Mo, Di,
   Do, Sa). Die nächste Einheit auf den Tag setzen, mit dem du weitermachen willst.

## Zu Hause (10 Minuten)

| # | Test | Erwartung |
|---|---|---|
| 1 | Aufgaben und Medikamente nach dem Update | alles noch da |
| 2 | **Starten** auf der Training-Karte | Einheit öffnet im Vollbild, erste Übung mit Zielbereich |
| 3 | Ersten Satz antippen, Gewicht und Wdh. eintragen, **Abschließen** | Haken, Pause startet unten |
| 4 | iPhone sperren | Sperrbildschirm zeigt Übung und Pausen-Countdown |
| 5 | Dort **+30 s** | Countdown springt 30 Sekunden weiter |
| 6 | Pause ablaufen lassen | Mitteilung „Pause vorbei“, Live Activity zeigt **Satz fertig** |
| 7 | **Satz fertig** auf dem Sperrbildschirm | nächster Satz abgehakt, neue Pause läuft |
| 8 | App entsperren, nach oben wischen (Home) | Dynamic Island zeigt den Countdown, lange drücken zeigt die Knöpfe |
| 9 | In Orbit: Pfeil nach unten oben links | Mini-Player über der Tab-Leiste, Tipp darauf öffnet die Einheit wieder |
| 10 | ⋯ → **Einheit verwerfen** | Einheit weg, Live Activity verschwindet, Plan steht wieder bei derselben Einheit |

## Im Gym (ein echtes Training)

| # | Test | Erwartung |
|---|---|---|
| 11 | Ganze Einheit durchziehen, Gewichte anpassen | Sätze danach übernehmen das geänderte Gewicht |
| 12 | Eine Übung **tauschen** (z. B. Klimmzüge → Latzug breit) | Alternativen für dieselben Muskeln oben, Sätze bleiben |
| 13 | **Beenden** | Zusammenfassung mit Dauer, Sätzen, Volumen; danach ist die nächste Einheit dran |
| 14 | Widget **Training** (klein) auf den Home-Bildschirm | nächste Einheit und „heute trainiert“ |
| 15 | Kontrollzentrum → Steuerelement **Training starten** hinzufügen, antippen | Orbit öffnet die nächste Einheit |
| 16 | Siri: „Was trainiere ich als Nächstes in Orbit?“ | Siri nennt Einheit, Anzahl Übungen, Dauer und wann du zuletzt trainiert hast |
| 17 | Eine Woche später dieselbe Einheit starten | Vorschlag: gleiches Gewicht oder +1 Schritt, wenn alle Sätze oben waren; Aufwärmsätze vor der ersten Grundübung |
| 18 | **Statistik** | Arbeitssätze pro Muskel in dieser Woche, Verlauf beim Bankdrücken |
| 19 | **Planer → Agenda** | Trainings an den Wunsch-Wochentagen |
| 20 | Wunsch-Wochentag, gewählte Uhrzeit | Mitteilung „Training heute: …“ |

## Wenn etwas nicht geht

- **Keine Live Activity:** Einstellungen → Orbit → Live-Aktivitäten einschalten.
- **Kein Mini-Player:** braucht iOS 26.1 oder neuer. Die laufende Einheit steht sonst als Karte
  oben im Tab Training.
- **Steigerung passt nicht zu deinem Gym:** Übungen → Übung → Steigerung (z. B. 1 kg bei
  Kurzhanteln).
- **Daten weg nach dem Update:** App nicht löschen! Melde dich. Die Kopie `Tagwerk-vor-v3.store`
  und die tägliche Sicherung (Dateien-App → Orbit → Backups) sind noch da.
