# Phase 4 auf dem iPhone testen

Version 0.5.0. Etwa 15 Minuten zu Hause, der Rest nebenbei über ein paar Tage.
Bitte melde, was nicht klappt (Screenshot reicht).

## Vorbereitung

1. Release **0.5.0** installieren (über iloader, wie bisher). Aufgaben, Medikamente und Training
   müssen danach noch da sein. Die Datenbank wird beim ersten Start erweitert.
2. **Training → Körper**: Gewicht eintragen, falls noch nicht geschehen (für das Eiweiß-Ziel).
3. Dein DAO-Enzym (oder ein anderes Medikament) unter **Gesundheit** auf den Hinweis
   **Vor dem Essen** stellen.

## Zu Hause

| # | Test | Erwartung |
|---|---|---|
| 1 | Aufgaben, Medikamente, Training nach dem Update | alles noch da |
| 2 | Tab **Ernährung** öffnen | Tagesansicht mit Tageslast „ruhig“, Eiweiß- und Wasser-Ring |
| 3 | **+** → Mahlzeit | oben „Vor dem Essen: DAO … Schon genommen?“ mit Knopf |
| 4 | **Lebensmittel hinzufügen** → „Hähnchen“ suchen, antippen, Menge anpassen, **Sichern** | Mahlzeit steht im Tagebuch, Eiweiß steigt |
| 5 | Zweite Mahlzeit mit „Tomate“ und Zubereitung **Aufgewärmt** | Tageslast wird „erhöht“, „Vor allem: Tomate …“ |
| 6 | **Lexikon** → Tomate → **Bei mir: Bei mir ok** | Tageslast sinkt wieder |
| 7 | **Glas Wasser** zweimal | Wasser 0,5 l, Rückgängig-Pfeil nimmt ein Glas zurück |
| 8 | Lexikon → Barcode-Symbol → Barcode eines Produkts aus deinem Schrank | Produkt mit Name, Bewertung und Zutaten-Prüfung |
| 9 | **Zutatenliste prüfen** → **Kamera** auf eine Zutatenliste halten → **Übernehmen** | kritische Zutaten werden mit Begründung gelistet |
| 10 | **Rezepte** → ein Rezept → **Zutaten auf die Einkaufsliste** | Einkaufsliste nach Bereichen sortiert |
| 11 | **Wochenplan** → zwei Rezepte setzen → **Einkaufsliste füllen** | Mengen zusammengefasst, nichts doppelt |
| 12 | **Beschwerden → Eintragen** (Kopfschmerz, Stärke 3) | erscheint unter Ernährung und Gesundheit |
| 13 | Widget **Ernährung** (klein) auf den Home-Bildschirm, dort **+** | Wasser steigt sofort, App zeigt es auch |
| 14 | Kontrollzentrum → **Glas Wasser** hinzufügen und antippen | +250 ml |
| 15 | Siri: „Histamin-Check in Orbit“ → „Avocado“ | Siri nennt Bewertung und Markierungen |
| 16 | Siri: „Wasser trinken in Orbit“ | Siri bestätigt und nennt den Tagesstand |
| 17 | **Suche** (Lupe auf Heute) nach „Quark“ | Lebensmittel und Rezepte erscheinen |

## Über ein paar Tage

| # | Test | Erwartung |
|---|---|---|
| 18 | Mahlzeiten und Beschwerden ehrlich eintragen | nach 10 Mahlzeiten und 3 Beschwerden zeigt **Muster** erste Ergebnisse |
| 19 | Ein Lebensmittel als **Meiden** markieren | in Rezepten und auf der Einkaufsliste mit 3 und Warnzeichen |

## Wenn etwas nicht geht

- **Kamera bleibt schwarz:** Einstellungen → Orbit → Kamera erlauben.
- **Barcode nicht gefunden:** Nicht jedes Produkt steht bei Open Food Facts. Zutatenliste per
  Kamera prüfen und als eigenes Lebensmittel anlegen.
- **Kein Netz beim Scannen:** Die Zutaten-Prüfung per Kamera funktioniert offline.
- **Daten weg nach dem Update:** App nicht löschen! Melde dich. Die Kopie `Tagwerk-vor-v4.store`
  und die tägliche Sicherung (Dateien-App → Orbit → Backups) sind noch da.
