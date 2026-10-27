# Phase 6 auf dem iPhone testen

Version 0.7.0. Etwa 25 Minuten. Bitte melde, was nicht klappt (Screenshot reicht).

## Vorbereitung

1. Release **0.7.0** installieren (über iloader, wie bisher). Alles aus 0.6 muss danach noch da
   sein. Die Datenbank wird beim ersten Start erweitert (Kopie: `Tagwerk-vor-v6.store`).
2. Mitteilungen für Orbit sind erlaubt.

## Training: dein Plan und Fortschritt

| # | Test | Erwartung |
|---|---|---|
| 1 | Alles nach dem Update da? | Aufgaben, Medikamente, alte Einheiten, Mahlzeiten, Check-ins unverändert |
| 2 | **Training** | aktiver Plan „Oberkörper 4er – meine Übungen“, der alte steht unter **Pläne** |
| 3 | **Starten** (Push) | Butterfly 93 kg, Brustpresse 35 kg (Untertitel „Gewicht je Seite“), Schulterpresse 27 kg, alle 3 × 7–10 |
| 4 | **Übungen → Butterfly** | Feld **Startgewicht** 93 kg, Abschnitt **Fortschritt** |
| 5 | **Training → Körper → Größe eintragen** | Größe in cm, danach BMI unter Körper |
| 6 | **Training → Fortschritt** | Tempo je Übung (nach ein paar Einheiten), Körpergewicht, Maße |
| 7 | **Fortschrittsfotos → +** | Kamera oder Mediathek, Ansicht und Gewicht wählen, Foto erscheint im Raster |
| 8 | Zweites Foto, dann **Vergleichen** | beide übereinander, Schieberegler blendet über |
| 9 | **Claude** bei den Fotos | Teilen-Menü mit Fotos und Text, in der Claude-App senden, Antwort kopieren und in Orbit **Einfügen** |
| 10 | **Fortschritt → Mit Claude bewerten** | Anfrage über den Kurzbefehl, Text-Antwort kommt zurück |

## Leben

| # | Test | Erwartung |
|---|---|---|
| 11 | **Planer → Leben** | Bereiche Routinen, Verträge, Geburtstage, Tagebuch, Haushalt |
| 12 | **+** bei Routinen → **Morgenroutine** | Routine erscheint, morgens auch auf **Heute** |
| 13 | Routine auf **Heute** antippen, Schritte abhaken | „Geschafft!“, Karte zeigt erledigt |
| 14 | **Verträge → + → Fitnessstudio**: Betrag, Beginn, Mindestlaufzeit, Frist | Status z. B. „kündbar bis …“, Fixkosten oben |
| 15 | **Personalausweis** mit Ablaufdatum | „läuft ab am …“, Frist steht in der Agenda |
| 16 | **Geburtstage → Aus Kontakten übernehmen** | gewählte Kontakte mit Datum und Alter |
| 17 | Abends **Heute → Tagebuch**, Top 3 für morgen eintragen | morgen im Fokus auf **Heute** |
| 18 | **Haushalt → Bad putzen** | neue Aufgabe ab heute, alle 7 Tage nach Erledigung |

## iPhone-Integration

| # | Test | Erwartung |
|---|---|---|
| 19 | Widget **Heute** (mittel) hinzufügen | Datum, Zähler, Als Nächstes, Aufgaben |
| 20 | Widget **Aufgaben** hinzufügen, Kreis antippen | Aufgabe verschwindet sofort, ist in Orbit erledigt |
| 21 | Sperrbildschirm: **Heute** rechteckig | nächster Termin oder Aufgaben offen |
| 22 | Kontrollzentrum: **Neue Aufgabe** und **Check-in** | Orbit öffnet Schnellerfassung bzw. Check-in |
| 23 | Spotlight: „Butterfly“, „Avocado“ oder eine Aufgabe suchen | Treffer von Orbit, Antippen öffnet die Stelle |
| 24 | **Einstellungen → Fokus → Arbeit → Fokusfilter → Orbit**: Training ausblenden, Liste wählen; Fokus an | **Heute** zeigt „Fokus: …“, nur die Liste, keine Trainingskarte |
| 25 | **Orbit → Einstellungen → App-Sperre** an, App verlassen, wieder öffnen | Sichtschutz, Face ID entsperrt |
| 26 | Im Gym: **Einstellungen → Gym-Ankunft → Ort speichern**, Mitteilung an, Ortszugriff „Immer“ | Beim nächsten Ankommen „Du bist im Gym – … starten?“ |
| 27 | Hinweise (Tipps) | erscheinen einmal, Kreuz schließt sie |

## Wenn etwas nicht geht

- **Widget zeigt alte Daten:** Orbit einmal öffnen, dann aktualisieren sich die Widgets.
- **Abhaken im Widget ohne Wirkung:** Orbit öffnen. Was im Widget abgehakt wurde, übernimmt die
  App beim Start.
- **Gym-Ankunft meldet sich nicht:** Ortszugriff muss **Immer** sein, Mitteilungen erlaubt. Mit
  kostenloser Apple-ID kann iOS Hintergrund-Ortung einschränken. Dann klappt es nur, solange Orbit
  im Hintergrund noch läuft.
- **Daten weg nach dem Update:** App nicht löschen! Melde dich. Die Kopie `Tagwerk-vor-v6.store`
  und die tägliche Sicherung (Dateien-App → Orbit → Backups) sind noch da.
