# Apple Health über Kurzbefehle

Ab Version 0.9 (Phase 8). Orbit darf Apple Health ohne Developer-Account nicht selbst lesen.
Die Kurzbefehle-App darf es und gibt die Werte an Orbit weiter. Kosten: keine.

## Was übertragen wird

| Richtung | Werte | Wo in Orbit |
|---|---|---|
| Health → Orbit | Schritte, Strecke (km), Stockwerke | Gesundheit → Apple Health, Bewegung, Tagebuch, Arztbericht |
| Health → Orbit | Schlaf (Stunden oder Minuten) | Check-in des Tages (nur wenn dort noch nichts steht) |
| Health → Orbit | Gewicht | Training → Körper (gleicher Wert am gleichen Tag nur einmal) |
| Health → Orbit | Ruhepuls | Apple Health, Arztbericht (ohne Apple Watch meist leer) |
| Orbit → Health | Wasser | nur was seit dem letzten Lauf dazukam |
| Orbit → Health | Gewicht | nur neue Werte, die du in Orbit eingetragen hast |

Unplausible Werte (z. B. 500.000 Schritte, Gewicht über 300 kg) überspringt Orbit und sagt es.

## Kurzbefehl „Orbit Health“ anlegen

Die Anleitung steht auch in Orbit: **Gesundheit → Apple Health → Kurzbefehl einrichten**.

1. Kurzbefehle-App → **+** → Name genau **Orbit Health**.
2. **Schritte:** „Health-Proben suchen“ (Find Health Samples), Typ *Schritte*, Startdatum *ist
   heute*. Danach „Statistik berechnen“ (Calculate Statistics): *Summe*.
3. **Strecke** (freiwillig): wie 2 mit *Gehen + Laufen Distanz* in km.
4. **Gewicht** (freiwillig, nur mit Waage, die in Health schreibt): „Health-Proben suchen“, Typ
   *Gewicht*, neueste zuerst, Limit 1.
5. **Schlaf** (freiwillig, nur wenn Health Schlafdaten hat): *Schlafanalyse* der letzten 24 Stunden,
   Dauer summieren.
6. **„Health-Werte an Orbit“** (Orbit): Schritte, Strecke, Gewicht, Schlaf eintragen. Leere Felder
   sind in Ordnung.
7. Einmal mit ▶︎ ausführen und den Health-Zugriff für Kurzbefehle erlauben.

### Zurück nach Health (freiwillig)

- „Wasser für Health“ (Orbit) → „Health-Probe protokollieren“: *Wasser*, Wert = Ergebnis, ml.
- „Gewicht für Health“ (Orbit) → „Wenn Ergebnis größer als 0“ → „Health-Probe protokollieren“:
  *Gewicht*, Wert = Ergebnis, kg.

## Jeden Abend automatisch

Kurzbefehle → **Automation** → **+** → **Tageszeit** 21:30, täglich → **Sofort ausführen** →
„Kurzbefehl ausführen“ → *Orbit Health*. Eine zweite Automation morgens holt den Schlaf.

## In Orbit

- **Gesundheit → Apple Health:** Werte von heute, die letzten 30 Tage, **Jetzt aus Health holen**
  (startet den Kurzbefehl und springt zurück).
- **Tagebuch:** Schritte zählen als Bewegung („7.400 Schritte“), auch ohne eigenen Eintrag.
- **Bewegung:** Schritte heute und im 7-Tage-Schnitt.
- **Arztbericht:** Ø Schritte am Tag, Schritte je Tag in der Tag-für-Tag-Tabelle, Ruhepuls.

URL für den Rücksprung: `tagwerk://healthbridge/success`, `…/cancel`, `…/error`.

## Wenn etwas nicht geht

| Problem | Lösung |
|---|---|
| „Fehler im Kurzbefehl“ | Heißt er genau *Orbit Health*? Einmal in der Kurzbefehle-App ausführen und Health erlauben |
| Schritte bleiben leer | In Schritt 2 „Statistik berechnen“ mit *Summe* nutzen und das Ergebnis bei *Schritte* einsetzen |
| Schlaf viel zu hoch | Orbit rechnet Minuten in Stunden um. Werte über 24 Stunden werden übersprungen |
| Automation fragt jedes Mal nach | In der Automation „Sofort ausführen“ wählen |

## Daten

Die Health-Tageswerte stehen in der täglichen Sicherung. Vor dem Update auf 0.9 kopiert Orbit die
Datenbank nach `Tagwerk-vor-v8.store`.
