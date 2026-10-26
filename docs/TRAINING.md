# Training in Orbit

Ab Version 0.4 (Phase 3). Alles liegt im Tab **Training**.

## Der Startplan

Beim ersten Start legt Orbit den Plan **„Oberkörper 4er – Hypertrophie“** an. Er baut auf deinem
bisherigen Split auf. Die Einheiten laufen als **Rotation** A → B → C → D: Orbit zeigt immer die
*nächste* Einheit. Fällt ein Tag aus, verschiebt sich nichts.

| Tag | Inhalt |
|---|---|
| A · Push | Bankdrücken, Schrägbank KH, Schulterdrücken KH, Kabel-Fliegende, Seitheben, Trizeps Seil |
| B · Pull | Klimmzüge, Brustgestütztes Rudern, Latzug eng, Kabelrudern, Face Pulls, SZ-Curls, Hammercurls |
| C · Arme & Schultern | Enges Bankdrücken, zwei Supersätze (Curls + Trizeps, Seitheben + Reverse Butterfly), Scottcurls, optional Reverse Curls |
| D · Brust & Rücken | Schrägbank LH, T-Bar-Rudern, Dips, Latzug breit, Butterfly, Kabel-Pullover, Seitheben |
| + · Beine & Rumpf | optional, ca. 20 Min.: Beinpresse, Rumänisches Kreuzheben, Wadenheben, Cable Crunch |

Das Modul „Beine & Rumpf“ hängst du beim Start einer Einheit per Schalter an.

## Eine Einheit

**Training → Starten** (oder Heute-Karte, Widget, Kontrollzentrum, Siri) öffnet die Einheit im
Vollbild. Oben stehen Dauer, Fortschritt und die Übungen als Chips. Wischen blättert zwischen
den Übungen.

Pro Übung siehst du:

- **Ziel**: Sätze × Wiederholungen bei Ziel-RIR (Wiederholungen im Tank)
- **Letztes Mal**: z. B. „80 × 8 · 80 × 8 · 80 × 7“
- **Vorschlag**: Gewicht für heute (siehe Progression)
- die Sätze mit Gewicht, Wiederholungen und RIR, vorausgefüllt

Einen Satz antippen öffnet große Regler für kg, Wiederholungen und RIR. Der Haken rechts schließt
ihn mit den vorausgefüllten Werten ab. Ändert sich dabei das Gewicht, übernehmen die folgenden
Sätze den neuen Wert.

Weitere Knöpfe: **+ Satz**, **Drop-Satz** (75 % Gewicht), **Übung tauschen** (passende
Alternativen für dieselben Muskeln stehen oben), **Übung hinzufügen** (letzte Seite).
Technik-Hinweise stehen unter den Sätzen.

**Aufwärmsätze** (50 % × 8, 70 % × 5, 85 % × 3) kommen automatisch vor die erste Grundübung des
Tages, sobald ein Arbeitsgewicht bekannt ist.

**Supersätze**: Nach dem ersten Partner springt Orbit nach 15 Sekunden zur zweiten Übung, erst
danach kommt die volle Pause.

### Pausen-Timer

Nach jedem Satz startet die Pause der Übung (Grundübungen 2–2:30 Min., Isolation 1–1:15 Min.):

- in der App als Leiste unten, mit **+30 s** und **Weiter**
- in der **Dynamic Island** und auf dem **Sperrbildschirm** als Live Activity, mit denselben
  Knöpfen und **Satz fertig**
- am Ende eine Mitteilung „Pause vorbei“, falls die App im Hintergrund ist

**Satz fertig** auf dem Sperrbildschirm schließt den nächsten offenen Satz mit den
vorausgefüllten Werten ab, ohne die App zu öffnen.

### Minimieren und abschließen

Der Pfeil nach unten (oben links) minimiert die Einheit. Sie läuft weiter, und über der Tab-Leiste sitzt ein
Mini-Player (Übung, Zeit, Pause). Ein Tipp darauf öffnet sie wieder.

**Beenden** schließt die Einheit ab und zeigt eine Zusammenfassung: Dauer, Sätze, Volumen,
Vergleich zur letzten Einheit desselben Tages und neue Rekorde. Nicht erledigte Sätze werden
dabei verworfen. Danach ist der nächste Tag dran. Über das Menü (⋯) lässt sich eine Einheit auch
verwerfen.

## Progression

Orbit rechnet mit **doppelter Progression**:

| Fall | Vorschlag |
|---|---|
| Erstes Mal | kein Gewicht, du trägst es selbst ein |
| Alle Arbeitssätze am oberen Ende des Bereichs | **+1 Schritt** (Langhantel und Kabel 2,5 kg, Kurzhantel 2 kg, Maschine 5 kg) |
| Sonst | Gewicht halten, mehr Wiederholungen |
| Zweimal hintereinander unter dem unteren Ende | etwa **−7,5 %** |
| Deload-Woche | gleiches Gewicht, halbe Sätze |

Bei assistierten Übungen (z. B. Klimmzüge mit Gegengewicht) geht der Vorschlag andersherum:
weniger Unterstützung = Fortschritt. Den Steigerungsschritt stellst du pro Übung ein
(**Übungen → Übung → Steigerung**), passend zu den Gewichten in deinem Gym.

### 6-Wochen-Zyklus

| Woche | RIR |
|---|---|
| 1 | Plan + 1 (Einstieg) |
| 2–3 | wie geplant |
| 4–5 | Plan − 1, bei Isolationsübungen letzter Satz bis 0 |
| 6 | **Deload**: halbe Sätze, RIR 4 |

Eine Woche ist vorbei, wenn alle vier Tage einmal dran waren. Stagnieren mindestens zwei
Grundübungen (geschätztes Maximum steigt in den letzten zwei Einheiten nicht), schlägt Orbit
auf der Zyklus-Karte einen früheren Deload vor.

## Plan bearbeiten

**Training → Plan** öffnet den Editor:

- Name, aktuelle Woche, nächste Einheit
- Tage umsortieren, umbenennen, hinzufügen, löschen
- pro Tag Übungen hinzufügen, umsortieren, Sätze, Wiederholungen, RIR, Pause, Superset-Gruppe,
  Notiz
- Modul (z. B. „Beine & Rumpf“) wählen
- **Wunsch-Wochentage** und Uhrzeit für Erinnerungen (Standard: Mo, Di, Do, Sa)
- **Zyklus neu starten**, Startplan neu anlegen
- **Teilen** exportiert den Plan als JSON

### Plan importieren (z. B. von Claude)

**Plan → Importieren** nimmt JSON im Format `orbit.plan.v1` an, eingefügt oder als Datei.
Codeblöcke und Text drumherum stören nicht. Übungsnamen werden unscharf der Bibliothek
zugeordnet („Bankdrücken LH“ → „Bankdrücken (Langhantel)“). Unbekannte Namen zeigt die Vorschau
und legt sie beim Übernehmen als eigene Übungen an.

```json
{
  "format": "orbit.plan.v1",
  "name": "Oberkörper 4er",
  "mesoWeeks": 6,
  "days": [
    { "name": "Push", "exercises": [
      { "name": "Bankdrücken (Langhantel)", "sets": 4, "reps": "6-8", "rir": 2, "rest": 150 }
    ]}
  ]
}
```

`reps` geht auch als `repMin`/`repMax`, `rest` auch als `restSec`. Das ältere Format
`tagwerk.plan.v1` wird weiter gelesen.

## Übungen, Statistik, Körper

- **Übungen**: 93 Übungen nach Muskelgruppe, mit Suche, Technik-Hinweisen, Verlauf und
  Höchstwerten. Eigene Übungen über **+**.
- **Statistik**: Arbeitssätze pro Muskel und Woche gegen den Zielbereich (Hauptmuskel zählt 1,
  Nebenmuskel ½), Einheiten pro Woche, Verlauf des geschätzten Maximums (Epley) der
  Grundübungen, alle Einheiten mit Details.
- **Körper**: Gewicht und Maße (Brust, Taille, Oberarm, Schultern, Oberschenkel, Körperfett) mit
  Verlauf.

## Außerhalb der App

| Wo | Was |
|---|---|
| **Heute** | Karte mit der nächsten Einheit und **Starten** |
| **Planer → Agenda / Woche** | geplante Einheiten an den Wunsch-Wochentagen |
| **Mitteilung** | an Wunsch-Wochentagen zur gewählten Uhrzeit „Heute: Pull“ |
| **Widget Training** | klein: nächste Einheit, Dauer, letztes Training. Sperrbildschirm rechteckig und als Zeile |
| **Kontrollzentrum** | **Training starten** öffnet die nächste Einheit |
| **Live Activity** | Pause, Übung und Knöpfe während der Einheit |
| **Siri** | „Starte mein Training in Orbit“, „Was trainiere ich als Nächstes in Orbit“ |
| **URL** | `tagwerk://training`, `tagwerk://training/start` |

## Noch nicht dabei

- **Apple Health** (Workouts, Gewicht): kommt mit dem Developer-Account, siehe
  [`PHASE0-ERGEBNIS.md`](PHASE0-ERGEBNIS.md). Bis dahin speichert Orbit alles selbst.
- **Fortschrittsfotos** und **Muskel-Karte**: Phase 6.
- **Plan mit Claude anpassen** über den Kurzbefehl: Phase 5. Der Import oben funktioniert schon.

## Daten

Pläne, Einheiten, eigene Übungen und Körperwerte stehen in der täglichen Sicherung
(Dateien → Orbit → Backups) und lassen sich mit ihr wiederherstellen. Vor dem Update auf 0.4
kopiert Orbit die Datenbank nach `Tagwerk-vor-v3.store`.
