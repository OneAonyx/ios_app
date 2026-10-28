# Arzt-Tagebuch

Ab Version 0.8 (Phase 7). Alles für den Arzttermin an einem Ort: Essen, Beschwerden, Schmerzen,
Bewegung, Medikamente, Schlaf und Stress. Daraus entsteht der Arztbericht als PDF.

## Was du erfassen solltest

| Bereich | Wie in Orbit | Warum |
|---|---|---|
| Essen und Trinken mit Uhrzeit | **Ernährung → +** (auch Reste, Aufgewärmtes, Alkohol) | Grundlage für Histamin-Muster |
| Beschwerden | **Beschwerde +** (Stärke 1–5, Dauer) | Was, wann, wie stark |
| Beschwerdefreie Tage | **Keine Beschwerden** antippen | Sonst sieht der Arzt nicht, ob nichts war oder nichts eingetragen wurde |
| Schmerzen | **Schmerz +** mit Körperkarte, Stärke 0–10 | Ort, Stärke, Art, Dauer, Auslöser, was geholfen hat |
| Medikamente | wie bisher, auch **Bei Bedarf** (DAO, Antihistaminika, Schmerzmittel) | Einnahme mit Uhrzeit |
| Bewegung und Sport | **Bewegung +**, Gym zählt automatisch | Anstrengung kann Histamin freisetzen und Schmerzen auslösen |
| Ruhetage | **Ruhetag** antippen | Lücken von Ruhetagen unterscheiden |
| Schlaf und Stress | Check-in morgens und abends | Umstände für die Muster |

Ideal sind 2–4 Wochen ohne Lücken. Was genau dein Arzt sehen will, kann er dir sagen; das ist der
übliche Umfang bei Histamin-Intoleranz und Schmerzen.

## Tagebuch heute

Auf **Heute** und im Tab **Gesundheit** zeigt die Karte **Tagebuch heute**, was noch fehlt:
Essen, Beschwerden, Bewegung, Medikamente, Check-in. Ein Tipp auf einen Punkt öffnet die passende
Erfassung. Darunter die Schnellknöpfe **Keine Beschwerden**, **Schmerz**, **Beschwerde**,
**Bewegung** und **Ruhetag**.

**Erinnerung:** Standardmäßig um 20:30 Uhr, nur wenn Essen, Beschwerden oder Bewegung noch fehlen.
Ändern unter **Einstellungen → Einblicke → Abends an Tagebuch erinnern**.

## Schmerzen

- **Körperkarte** vorne und hinten: Stellen antippen, mehrere sind möglich. Vorne liegt deine linke
  Seite rechts im Bild (wie beim Gegenüber). Alternativ **Aus Liste wählen**.
- **Stärke 0–10**: 0 kein Schmerz, 1–3 leicht, 4–6 mittel, 7–9 stark, 10 unerträglich. Diese Skala
  (NRS) nutzen auch Praxen und Kliniken.
- **Art**: stechend, dumpf, ziehend, brennend, pochend, krampfartig, drückend, ausstrahlend.
- **Beginn und Dauer**, **möglicher Auslöser** (Training, Heben, Sitzen, Schlafen, Essen, Stress)
  und **was geholfen hat** (Schmerzmittel, Ruhe, Wärme, Kälte, Bewegung, nichts), dazu eine Notiz.

**Gesundheit → Schmerzen** zeigt die letzten 30 Tage: Anzahl, Durchschnitt, höchster Wert, eine
Körperkarte mit den häufigsten Stellen und alle Einträge. Antippen zum Bearbeiten, wischen zum
Löschen.

## Bewegung

Spazieren, Laufen, Radfahren, Schwimmen, Wandern, Ballsport, Tennis, Yoga, Dehnen, Training
zuhause, Klettern, Tanzen, Kampfsport und Sonstiges, jeweils mit Dauer und Anstrengung (leicht,
mittel, intensiv). **Gym-Einheiten** aus dem Training zählen automatisch mit.

**Gesundheit → Bewegung** zeigt die Woche gegen die WHO-Empfehlung: 150 Minuten mittlere Bewegung
pro Woche, intensive Minuten zählen doppelt, leichte nicht. Darunter die letzten 8 Wochen.

## Arztbericht

**Gesundheit → Arztbericht**

1. **Zeitraum**: 2 Wochen bis 6 Monate.
2. **Vollständigkeit**: an wie vielen Tagen Essen und Beschwerden (auch „keine“) eingetragen sind.
3. **Inhalt**: Teile einzeln abwählbar (Medikamente, Beschwerden, Schmerzen, Ernährung und Muster,
   Bewegung, Befinden und Schlaf, Gewicht, Tag-für-Tag-Tabelle, Protokoll).
4. **Fragen an den Arzt**: stehen auf der ersten Seite und bleiben gespeichert.
5. **PDF erstellen** → Vorschau → **Teilen** (Mail, AirDrop, Dateien, Drucken).

Seiten im PDF:

| Seite | Inhalt |
|---|---|
| 1 | Überblick mit Vollständigkeit, Fragen an den Arzt, Medikamente mit Einnahmetreue |
| 2 | Beschwerden je Woche und Art, Bewegung je Woche und Art |
| 3 | Schmerzen: Körperkarte, Orte mit Anzahl und Stärke, Verlauf, Art, Auslöser, was geholfen hat |
| 4 | Ernährung und mögliche Auslöser, Befinden und Schlaf, Gewicht |
| ab 5 | Tag-für-Tag-Tabelle: Essen, Beschwerden und Schmerzen, Medikamente, Bewegung, Befinden |
| danach | Protokoll aller Beschwerden und Schmerzen |

## Muster

In **Muster** zählt jetzt auch **Sport oder Training** als möglicher Umstand (bis 6 Stunden nach
dem Ende), wie schon „schlecht geschlafen“ und „viel Stress“.

## Kurzbefehle

In der Kurzbefehle-App unter **Orbit**:

- **Bewegung eintragen** (Art, Minuten, Anstrengung), z. B. als Automation nach dem Radfahren
- **Schmerz eintragen** (öffnet die Körperkarte)
- **Heute keine Beschwerden**

URLs: `tagwerk://schmerz`, `tagwerk://bewegung`, `tagwerk://tagebuch`.

## Daten

Schmerzen, Bewegung und Tages-Vermerke stehen in der täglichen Sicherung. Vor dem Update auf 0.8
kopiert Orbit die Datenbank nach `Tagwerk-vor-v7.store`.

Orbit ist kein Medizinprodukt. Der Bericht zeigt selbst erfasste Daten, keine Diagnose.
