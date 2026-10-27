# Phase 5 auf dem iPhone testen

Version 0.6.0. Etwa 20 Minuten, die Claude-Tests brauchen den Kurzbefehl „Orbit Claude“ aus Phase 0.
Bitte melde, was nicht klappt (Screenshot reicht).

## Vorbereitung

1. Release **0.6.0** installieren (über iloader, wie bisher). Aufgaben, Medikamente, Training und
   Ernährung müssen danach noch da sein. Die Datenbank wird beim ersten Start erweitert.
2. Mitteilungen für Orbit sind erlaubt (für die Sonntags-Erinnerung).

## Check-in und Rückblick

| # | Test | Erwartung |
|---|---|---|
| 1 | Alles nach dem Update da? | Aufgaben, Medikamente, Training, Mahlzeiten unverändert |
| 2 | **Heute** morgens (bis 12 Uhr) bzw. abends (ab 17 Uhr) | Karte „Check-in“ mit zwei Fragen und Emojis |
| 3 | Beide Werte antippen | Karte klappt zu „Erledigt“ mit einer Zeile |
| 4 | **Gesundheit → Einblicke → Check-in heute**: Schlafdauer und Notiz, **Fertig** | Werte bleiben gespeichert |
| 5 | Siri: „Check-in in Orbit“ | Orbit öffnet den Check-in |
| 6 | **Befinden** | Diagramm, Durchschnitte, dein Tag in der Liste |
| 7 | **Wochenrückblick** | Abschnitte zu Aufgaben, Medikamenten, Training, Ernährung; Pfeil nach links zeigt die Vorwoche |
| 8 | Sonntag 18 Uhr abwarten | Mitteilung „Dein Wochenrückblick ist da“, Antippen öffnet ihn |

## Arztbericht

| # | Test | Erwartung |
|---|---|---|
| 9 | **Gesundheit → Arztbericht**, Zeitraum 8 Wochen | Inhalt zählt Medikamente, Beschwerden, Mahlzeiten |
| 10 | **PDF erstellen** | Vorschau mit 2 oder mehr Seiten, Diagramme lesbar |
| 11 | **Teilen** → In Dateien sichern oder per Mail an dich | PDF kommt an und lässt sich öffnen |

## Claude

| # | Test | Erwartung |
|---|---|---|
| 12 | **Training → Plan → Mit Claude anpassen**, Wunsch eintragen | „Das geht an Claude“ listet Plan, Top-Sätze …; „Ganze Anfrage ansehen“ zeigt den Text |
| 13 | **An Claude senden** | Kurzbefehl läuft, danach springt Orbit zurück und zeigt den Plan-Vorschlag |
| 14 | **Als neuen Plan übernehmen** | Training zeigt den neuen Plan, der alte steht unter Pläne |
| 15 | **Lexikon** → nach etwas Unbekanntem suchen → **Claude fragen** → senden | Bewertung mit Begründung, **Ins Lexikon übernehmen** |
| 16 | **Rezepte → Neue Rezeptideen von Claude** → senden | Rezepte mit Bewertung je Zutat, **Rezepte speichern** |
| 17 | **Muster → Mit Claude besprechen** | Text mit Einordnung und Testplan |
| 18 | **Wochenrückblick → Besprechen** | Text mit Tipps |
| 19 | Eine Anfrage mit **Stattdessen kopieren**, in der Claude-App einfügen, Antwort kopieren, in Orbit **Einfügen** | gleiche Vorschau wie über den Kurzbefehl |
| 20 | **Gesundheit → Claude** | alle Anfragen im Verlauf mit Status |

## Wenn etwas nicht geht

- **Kurzbefehl startet, aber Orbit zeigt weiter „Wartet“:** In der Kurzbefehle-App prüfen, ob die
  Aktionen „Claude-Antwort übernehmen“ und „Stoppen und ausgeben“ das Ergebnis von „Ask Claude“
  nutzen. Sonst Antwort kopieren und **Einfügen**.
- **Frage „Einfügen erlauben?“** beim Trainingsplan: Erlauben. Lange Anfragen gehen über die
  Zwischenablage.
- **Daten weg nach dem Update:** App nicht löschen! Melde dich. Die Kopie `Tagwerk-vor-v5.store`
  und die tägliche Sicherung (Dateien-App → Orbit → Backups) sind noch da.
