# Medikamente in Orbit

Ab Version 0.3 (Phase 2). Alles liegt im Tab **Gesundheit**.

## Anlegen

**Gesundheit → +** öffnet den Editor:

| Feld | Wofür |
|---|---|
| Name, Stärke, Form | z. B. „DAO-Enzym“, „10.000 HDU“, Kapsel. Die Form bestimmt, wie Mengen heißen („½ Tablette“, „10 Tropfen“, „2 Hübe“, „5 ml“). |
| Zeitplan | siehe unten |
| Uhrzeiten | jede mit eigener Menge, z. B. morgens 1, abends ½ |
| Hinweis | vor dem Essen, zum Essen, nach dem Essen, nüchtern, vor dem Schlafen |
| Beginn / Enddatum | Ende optional. Beim Ausschleichen endet der Plan von selbst. |
| Erinnerung | Keine, Mitteilung oder Wecker |
| Vorrat | zählt bei „Genommen“ automatisch herunter |
| Aussehen | Farbe und Symbol, damit du Medikamente auf einen Blick erkennst |

### Zeitpläne

| Art | Beispiel |
|---|---|
| Täglich | 08:00 und 20:00 |
| An Wochentagen | Mo, Mi, Fr um 07:30 |
| Alle paar Tage | alle 3 Tage um 09:00, gezählt ab Beginn |
| Im Stundentakt | alle 8 Std. ab 06:00 → 06:00, 14:00, 22:00, jeden Tag gleich |
| Bei Bedarf | ohne feste Zeit, mit „höchstens 3× in 24 Std.“ und „mindestens 6 Std. Abstand“ |
| Einnahme und Pause | 21 Tage nehmen, 7 Tage Pause |
| Ausschleichen | Stufen, z. B. 5 Tage 2 Tabletten, 5 Tage 1, 5 Tage ½, danach Ende |

Uhrzeiten sind Ortszeit: 08:00 bleibt auch nach der Zeitumstellung 08:00.

## Abhaken

Überall, wo eine Einnahme steht, gibt es einen runden Knopf:

- **Heute**: Karte „Medikamente“, zweiter Ring oben, „Als Nächstes“
- **Gesundheit**: Karte „Heute“
- **Planer → Agenda**: Einnahmen zwischen Terminen und Aufgaben (in der Woche zusammengefasst)
- **Mitteilung**: lange drücken → **Genommen**, **In 10 Min**, **Auslassen**
- **Wecker**: Knopf **Genommen**
- **Widget** und **Kontrollzentrum**: siehe unten
- **Siri**: „Medikament in Orbit abhaken“

Lange drücken auf eine Einnahme bietet **Auslassen** und **Zurücksetzen**. Was du abhakst,
landet im Protokoll auf der Detailseite. Einträge lassen sich dort per langem Druck löschen.

**Zustände:** offen · *jetzt dran* (30 Min. vorher bis 1 Std. danach) · *überfällig* ·
*verpasst* (nach 12 Std.) · genommen · ausgelassen.

**Zusätzlich genommen:** Auf der Detailseite eines Medikaments mit festen Zeiten trägst du
eine Extra-Einnahme ein. Sie zählt beim Vorrat, aber nicht bei der Einnahmetreue.

## Bei Bedarf

Bei-Bedarf-Medikamente (z. B. Ibuprofen) stehen in der Karte **Bei Bedarf**. **Nehmen** zeigt,
wie oft du in den letzten 24 Stunden genommen hast. Überschreitet eine Einnahme deine
Höchstmenge oder deinen Mindestabstand, warnt Orbit und nennt, ab wann es wieder passt.
Eintragen kannst du trotzdem. Die Grenzen sind deine eigenen Angaben, keine Dosierempfehlung.

## Erinnerungen: Mitteilung oder Wecker

| | Mitteilung | Wecker |
|---|---|---|
| Wann | zur Einnahmezeit, nach 30 Min. noch einmal, falls offen | zur Einnahmezeit als echter Wecker |
| Stumm- und Fokusmodus | still (wie andere Mitteilungen) | klingelt trotzdem |
| Knöpfe | Genommen, In 10 Min, Auslassen | Genommen (Stopp beendet nur den Ton) |
| Gut für | Vitamine, Alltägliches | wichtige Medikamente |

Beim ersten Wecker fragt iOS nach der Erlaubnis. Ohne Erlaubnis bekommst du automatisch eine
Mitteilung.

**Wichtig:** iOS lässt Apps nur 64 Mitteilungen gleichzeitig vormerken. Orbit plant deshalb
immer die nächsten 3 Tage (Wecker: 2 Tage) und plant beim Öffnen, nach jedem Abhaken und per
Hintergrundaktualisierung nach. Wer die App mehrere Tage gar nicht öffnet und die
Hintergrundaktualisierung ausgeschaltet hat (Einstellungen → Allgemein →
Hintergrundaktualisierung), bekommt irgendwann keine Erinnerungen mehr. Einmal öffnen reicht.

## Vorrat

Mit **Vorrat mitzählen** zieht jede Einnahme die Menge ab, und Rückgängig gibt sie zurück.
Orbit rechnet aus, wie lange der Vorrat reicht („reicht bis Sa, 5. Dez.“). Ab der gewählten
Warnschwelle (Standard 7 Tage):

- erscheint das Medikament in **Vorrat knapp** auf „Gesundheit“,
- kommt morgens um 9 Uhr ein Hinweis,
- legt Orbit auf Wunsch die Aufgabe **„Nachschub besorgen: …“** an.

**Nachgefüllt** (Detailseite oder „Vorrat knapp“) erhöht den Vorrat und erledigt die
Nachschub-Aufgabe.

## Einnahmetreue

- **Gesundheit → Letzte 7 Tage**: Anteil genommener Einnahmen und ein Punkt pro Tag
- **Detailseite**: Ring für die letzten 30 Tage und Monatskalender
  (grün = alles, orange = teilweise, rot = nichts genommen)

Ausgelassene Einnahmen zählen als nicht genommen. Einnahmen vor dem Anlegen eines Medikaments
zählen nicht.

## Widget, Sperrbildschirm, Kontrollzentrum

**Widget hinzufügen:** Home-Bildschirm lange drücken → **Bearbeiten → Widget hinzufügen** →
Orbit → **Medikamente**.

| Größe | Inhalt |
|---|---|
| Klein | nächste Einnahme mit Knopf **Genommen** |
| Mittel | Ring und bis zu 4 Einnahmen von heute, jede zum Abhaken |
| Sperrbildschirm rund | Fortschritt „1/3“ |
| Sperrbildschirm rechteckig | Fortschritt und nächste Einnahme |
| Sperrbildschirm Zeile | nächste Einnahme |

**Kontrollzentrum:** Kontrollzentrum öffnen → **+** → **Steuerelement hinzufügen** → Orbit →
**Medikament genommen**. Ein Tipp hakt die Einnahme ab, die gerade dran ist (bis 2 Std. vorher,
Verpasstes bis 12 Std. danach).

Das Widget zeigt heute und morgen. Öffnest du die App länger nicht, fehlen danach Einträge,
bis du sie wieder öffnest.

## Siri und Kurzbefehle

| Satz | Wirkung |
|---|---|
| „Medikament in Orbit abhaken“ | hakt die fällige Einnahme ab |
| „Tablette in Orbit genommen“ | dasselbe |
| „Habe ich heute meine Tabletten in Orbit genommen?“ | sagt, was erledigt und was offen ist |

Beide Aktionen gibt es auch in der Kurzbefehle-App, z. B. für eine Automation „Wenn der Wecker
gestoppt wird → Medikamente heute“.

## Datensicherung

Medikamente und das komplette Protokoll sind in der täglichen Sicherung enthalten
(Dateien-App → Auf meinem iPhone → Orbit → Backups). Sicherungen aus Version 0.2 lassen sich
weiter einspielen: Sie ersetzen dann nur Aufgaben und Listen, vorhandene Medikamente bleiben.

Beim ersten Start von 0.3 erweitert Orbit die Datenbank. Vorher legt es eine Kopie an
(`Tagwerk-vor-v2.store` im App-Group-Ordner).

## Hinweis

Orbit erinnert und protokolliert. Es ersetzt keine ärztliche Beratung und prüft keine
Wechselwirkungen.
