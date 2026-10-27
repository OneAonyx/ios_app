# Einblicke

Phase 5 bringt vier Dinge zusammen: tägliche Check-ins, einen Wochenrückblick, einen Arztbericht
als PDF und die Claude-Brücke für alle Anwendungsfälle. Alles liegt unter **Gesundheit → Einblicke**.

> **Apple Health** ist noch nicht dabei: Mit der kostenlosen Apple-ID gibt iOS keine Health-Rechte
> (Ergebnis aus Phase 0). Die Anbindung kommt mit dem Developer-Account (Phase 7). Bis dahin
> erfasst Orbit alles selbst.

## Check-in

| Wann | Fragen | Wo |
|---|---|---|
| morgens (4–12 Uhr) | Schlaf, Energie | Karte auf **Heute** |
| abends (ab 17 Uhr) | Stimmung, Stress | Karte auf **Heute** |
| jederzeit | alle vier, Schlafdauer, Notiz | **Gesundheit → Check-in heute**, Siri: „Check-in in Orbit“ |

- Jede Frage hat fünf Stufen mit Emoji. Nochmal tippen nimmt den Wert zurück.
- Ist alles beantwortet, klappt die Karte zu einer Zeile zusammen („Ändern“ öffnet sie wieder).
- **Befinden** zeigt den Verlauf je Skala (14, 30, 90 Tage), die Durchschnitte und alle Tage.
  Ein Tag lässt sich nachträglich bearbeiten.
- Die Karte auf „Heute“ lässt sich in den Einstellungen unter **Einblicke** ausblenden.

**Für die Muster-Auswertung** zählen zwei Umstände mit: *Schlecht geschlafen* (Schlaf 1–2) und
*Viel Stress* (Stress 4–5). Sie stehen unter **Muster** wie Lebensmittel, mit eigenem Symbol
(Bett bzw. Welle), wenn an solchen Tagen auffällig oft Beschwerden kamen.

## Wochenrückblick

Montag bis Sonntag, mit Pfeilen zu früheren Wochen. Abschnitte erscheinen nur, wenn es Daten gibt:

| Abschnitt | Inhalt |
|---|---|
| Aufgaben | erledigt, überfällig |
| Medikamente | Einnahmetreue, verpasst, ausgelassen |
| Training | Einheiten (gegen Wunsch-Wochentage), Arbeitssätze, Volumen, neue Höchstgewichte |
| Ernährung | Ø Histamin-Tageslast, Ø Eiweiß, Ø Wasser |
| Beschwerden | Tage mit Beschwerden, Ø Stärke |
| Befinden | Durchschnitte aus den Check-ins |
| Körper | Gewicht und Veränderung zur Vorwoche |

- Oben stehen die **Höhepunkte** (z. B. „Alle 4 geplanten Einheiten geschafft“, „Eine Woche ohne
  Beschwerden“, neue Höchstgewichte).
- **Sonntags ab 18 Uhr** kommt eine Mitteilung, sonntags ab 12 Uhr bis Montagmittag steht eine
  Karte auf „Heute“. Die Erinnerung lässt sich in den Einstellungen abschalten.
- **Mit Claude besprechen** schickt nur die Kennzahlen (keine Namen, keine Einzeleinträge).
- **Teilen** gibt die Kurzfassung als Text weiter.

## Arztbericht

**Gesundheit → Arztbericht**: Zeitraum (4 Wochen bis 6 Monate) und optional einen Namen wählen,
**PDF erstellen**, ansehen und über das Teilen-Menü weitergeben (Mail, Nachrichten, Drucken,
Dateien).

| Seite | Inhalt |
|---|---|
| 1 | Medikamente mit Plan und Einnahmetreue, Beschwerden je Woche (Diagramm) und nach Art |
| 2 | Ernährung und mögliche Auslöser (Muster), gemiedene Lebensmittel, Befinden, Gewichtsverlauf |
| 3 ff. | Beschwerde-Protokoll: Datum, Art, Stärke, Dauer, Notiz (30 Zeilen je Seite) |

Das PDF entsteht auf dem iPhone. Es enthält nur, was du eingetragen hast, und ist als
Selbstauskunft ohne Diagnose gekennzeichnet.

## Claude

Fünf Anwendungsfälle, alle unter **Gesundheit → Claude** und direkt an der passenden Stelle:

| Anfrage | Einstieg | Ergebnis |
|---|---|---|
| Trainingsplan anpassen | Training → Plan → **Mit Claude anpassen** | neuer Plan, nach Vorschau übernehmen |
| Wochenrückblick besprechen | Wochenrückblick → **Besprechen** | Text mit Tipps |
| Lebensmittel bewerten | Lexikon ohne Treffer → **Claude fragen**, Barcode nicht gefunden, Zutaten prüfen | Bewertung 0–3 mit Markierungen, ins Lexikon übernehmen |
| Rezeptideen | Rezepte → **Neue Rezeptideen von Claude** | 1–5 Rezepte, speichern (unbekannte Zutaten werden eigene Lebensmittel) |
| Muster deuten | Muster → **Mit Claude besprechen** | Einordnung und Testplan |

Vor dem Senden zeigt Orbit **„Das geht an Claude“** (Liste der Daten) und auf Wunsch die ganze
Anfrage. Danach steht jede Anfrage im **Verlauf** mit Status (wartet, Antwort da, übernommen,
gelesen, verworfen). Einrichtung und Technik: [`CLAUDE-BRIDGE.md`](CLAUDE-BRIDGE.md).
