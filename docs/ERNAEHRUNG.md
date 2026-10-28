# Ernährung und Histamin in Orbit

Ab Version 0.5 (Phase 4). Alles liegt im Tab **Ernährung**, Beschwerden auch unter **Gesundheit**.

> Orbit ist kein Medizinprodukt. Die Bewertungen sind eine Orientierung nach der in DACH-Listen
> üblichen Skala, eigene Einschätzungen von Claude, keine Kopie fremder Listen. Histamin-Verträglichkeit
> ist sehr individuell. Deine eigene Einschätzung hat in Orbit immer Vorrang.

## Die Skala

| Wert | Bedeutung |
|---|---|
| **0** | gut verträglich |
| **1** | mäßig verträglich, in üblichen Mengen oft in Ordnung |
| **2** | schlecht verträglich |
| **3** | sehr schlecht verträglich |

Dazu Markierungen: **histaminreich** oder schnell verderblich (H), **andere biogene Amine** (A),
**Liberator**, setzt körpereigenes Histamin frei (L), **hemmt den Abbau** über das Enzym DAO (B).
Farben gibt es nur zusätzlich: Zahl und Symbol stehen immer daneben.

## Lexikon

**Ernährung → Lebensmittel-Lexikon**: 350 Lebensmittel in 20 Kategorien mit Bewertung,
Markierungen, Eiweiß, Kalorien, üblicher Portion und Frische-Tipps. Filter nach 0–3 und
„Meine“ (eigene Einschätzung, Favoriten, eigene Lebensmittel).

Auf der Detailseite stellst du unter **Deine Erfahrung** ein:

| Einstellung | Gerechnet wird mit |
|---|---|
| Noch nicht eingeschätzt | der Standardbewertung |
| Bei mir ok | 0 |
| Vorsicht | mindestens 2 |
| Meiden | 3 |

Das gilt überall: Tageslast, Mahlzeiten, Rezepte, Einkaufsliste, Siri.

Fehlt etwas, legst du es über **+** als eigenes Lebensmittel an.

## Tagebuch

**+** oben rechts oder **Mahlzeit** auf „Heute“ öffnet den Editor:

- Mahlzeit (Frühstück, Mittag, Abend, Snack) und Uhrzeit
- Lebensmittel aus **Favoriten**, **Zuletzt**, Lexikon-Suche oder per **Barcode**. Antippen übernimmt
  die übliche Portion, die Menge stellst du danach ein.
- **Zubereitung**: frisch, Reste oder aufgewärmt
- **Ort**: zuhause oder auswärts

**Medikamente vor dem Essen:** Hast du ein Medikament mit dem Hinweis „vor dem Essen“ (z. B.
DAO-Enzym), fragt der Editor: „Schon genommen?“ Ein Tipp auf **Genommen** hakt die Einnahme ab.
Abschalten lässt sich das unter **Ernährung → Ziele und Einstellungen**.

## Tageslast

Aus den Mahlzeiten des Tages rechnet Orbit eine grobe Histamin-Tageslast:

- je Lebensmittel: Bewertung (0 → 0, 1 → 1, 2 → 3, 3 → 6 Punkte) × Menge (100 g = 1, höchstens 3)
- Reste ×1,5 und +1, aufgewärmt ×1,5 und +1,5, auswärts +1
- **ruhig** unter 4 Punkten, **erhöht** ab 4, **hoch** ab 10

Darunter steht, was am meisten beigetragen hat. Die Zahl ist eine Orientierung: Wie viel Histamin
tatsächlich drin war, hängt von Frische, Lagerung und Zubereitung ab.

## Eiweiß und Wasser

- **Eiweiß-Ziel**: 1,8 g je kg Körpergewicht (einstellbar 1,2–2,6). Das Gewicht kommt aus
  **Training → Körper**, sonst rechnet Orbit mit 80 kg.
- **Wasser-Ziel**: 2,5 l (einstellbar). **Glas Wasser** trägt 250 ml ein, auch über Widget,
  Kontrollzentrum und Siri.

## Barcode und Zutatenliste

- **Barcode**: Im Lexikon oder in der Lebensmittel-Auswahl auf das Barcode-Symbol tippen. Orbit fragt
  das Produkt bei **Open Food Facts** ab (kostenlos, ohne Konto) und prüft die Zutatenliste. Das
  Produkt wird als eigenes Lebensmittel gespeichert, beim nächsten Scan braucht es kein Netz mehr.
- **Zutaten prüfen**: Liste abtippen, einfügen oder mit der Kamera erkennen. Orbit erkennt rund
  230 Stichworte (z. B. Hefeextrakt, Essig, Tomate, gereifter Käse, Wein) und 51 E-Nummern
  (z. B. Sulfite E220–E228, Benzoate E210–E213, Glutamat E620–E625, Azofarbstoffe).
  Das läuft auf dem iPhone, ohne Internet und ohne Apple-KI.

## Beschwerden und Muster

**Beschwerden** trägst du unter Ernährung oder Gesundheit ein: Art (Kopfschmerz, Hautrötung,
Juckreiz, Quaddeln, Blähungen, Bauchschmerz, Durchfall, Übelkeit, Herzrasen, Nase, Müdigkeit,
Schwindel …), Stärke 1–5, Beginn und Dauer.

**Muster** sucht Lebensmittel und Umstände, nach denen auffällig oft Beschwerden kamen:

- gezählt werden Beschwerden bis 24 Std. nach dem Essen, am stärksten 15 Min. bis 3 Std. danach
- verglichen wird mit der Grundrate aller Mahlzeiten
- ein Lebensmittel erscheint erst ab 3 Mahlzeiten, die Auswertung erst ab 10 Mahlzeiten und
  3 Beschwerden
- auch **Reste oder Aufgewärmtes** und **auswärts gegessen** werden geprüft
- Lebensmittel, die immer zusammen gegessen wurden (z. B. Nudeln, Tomate, Mozzarella), erscheinen
  als ein Eintrag. Vorn steht das mit der höchsten Bewertung, die anderen als „Immer zusammen mit …“.
  Welches davon der Auslöser ist, zeigt erst ein gezielter Test.

Beispiel: „Tomate · 5 von 6 Mal Beschwerden innerhalb von 3 Std. · etwa 2,5× so oft wie nach
anderen Mahlzeiten“. Das ist ein Hinweis, keine Diagnose. Verdächtiges gezielt testen, am besten
mit ärztlicher Begleitung.

## Einkauf, Rezepte, Wochenplan

- **Einkaufsliste**: nach Bereichen im Supermarkt sortiert. „500 g Quark“ wird zu Menge und Name
  getrennt. Kritische Lebensmittel (ab 2) bekommen ein Warnzeichen.
- **Rezepte**: 32 histaminarme Rezepte, die meisten mit 30–50 g Eiweiß pro Portion. Portionen
  umrechnen, **als Mahlzeit eintragen**, **Zutaten auf die Einkaufsliste**, **in den Wochenplan**.
- **Wochenplan**: Mittag und Abend für sieben Tage. **Einkaufsliste für diese Woche füllen**
  fasst alle Zutaten zusammen und rechnet die Portionen um.

## Außerhalb der App

| Wo | Was |
|---|---|
| **Heute** | Karte mit Tageslast, Eiweiß, Wasser, **Mahlzeit** und **Wasser** |
| **Widget Ernährung** | klein: Tageslast, Eiweiß, Wasser mit **+**-Knopf. Sperrbildschirm: rund (Wasser), rechteckig, Zeile |
| **Kontrollzentrum** | **Glas Wasser** (+250 ml) |
| **Siri** | „Wasser trinken in Orbit“, „Symptom in Orbit erfassen“, „Histamin-Check in Orbit“ (fragt nach dem Lebensmittel) |
| **Kurzbefehle** | zusätzlich „Ernährung heute“ (Tageslast, Eiweiß, Wasser) |
| **Suche** | Lebensmittel, Rezepte und Übungen |
| **URL** | `tagwerk://ernaehrung`, `tagwerk://mahlzeit`, `tagwerk://wasser`, `tagwerk://symptom` |

## Noch nicht dabei

- **Apple Health** (Wasser schreiben): über Kurzbefehle in Phase 8.
- **Abendrückblick, Check-ins, Arztbericht als PDF, Claude-Rezeptideen**: Phase 5.

## Daten

Mahlzeiten, Beschwerden, Wasser, Einschätzungen, gescannte Produkte, Einkaufsliste und
Wochenplan stehen in der täglichen Sicherung. Vor dem Update auf 0.5 kopiert Orbit die
Datenbank nach `Tagwerk-vor-v4.store`.
