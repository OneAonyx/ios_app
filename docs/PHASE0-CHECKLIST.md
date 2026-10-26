# Phase 0 – Checkliste für dein iPhone

Ziel: herausfinden, was mit einer **kostenlosen Apple-ID über SideStore** funktioniert. Danach
entscheiden wir, welche Funktionen im kostenlosen Betrieb aktiv sind.

In der App: **Heute → Systemcheck → Öffnen**. Am Ende **„Bericht kopieren“** und den Text an Claude
schicken.

| # | Test | So geht's | Erwartet |
|---|---|---|---|
| 0 | Installation | App per SideStore installieren ([SIDELOAD.md](SIDELOAD.md)) | App startet, Tab-Leiste mit Heute, Planer, Training, Ernährung, Gesundheit. Suche über die Lupe oben auf „Heute“ |
| 1 | Installation & Signatur | „Tests 1–3 starten“ | ✅ mit „Kostenlose Apple-ID (7 Tage), noch X Tage“. Zeigt auch, ob die Signatur Health-Recht und App Group enthält |
| 2 | Apple Health | läuft bei „Tests 1–3“ mit, Health-Dialog bestätigen | ✅ „heute N Schritte gelesen“ **oder** ❌ mit Fehler (dann ist Health mit der kostenlosen ID nicht möglich) |
| 3 | Widget-Daten (App Group) | läuft mit. Danach das Widget **„Orbit Systemcheck“** auf den Home-Bildschirm legen | Widget zeigt dieselbe Nummer wie die App (z. B. #1). Dann „Hat geklappt“ tippen |
| 4 | Wecker (AlarmKit) | „Testen“ → Wecker erlauben → iPhone **stumm schalten und sperren** | Nach 1 Minute klingelt ein Wecker trotz Stummschaltung. Zurück in der App bestätigen |
| 5 | Mitteilungen mit Aktionen | „Testen“ → Mitteilungen erlauben → iPhone sperren | Nach 10 Sekunden kommt eine Mitteilung. **Gedrückt halten** → „Genommen“ tippen. Test wird ✅, ohne dass du die App öffnest |
| 6 | Claude-Brücke | Kurzbefehl einrichten ([CLAUDE-BRIDGE.md](CLAUDE-BRIDGE.md)) → „Kurzbefehl starten“ | Kurzbefehle öffnet sich, fragt Claude, springt zurück. Test wird ✅. Sonst den Ausweichweg mit Kopieren und Einfügen testen |

## Zusätzlich ausprobieren

- **Siri:** „Orbit Systemcheck“ sagen. Die App öffnet den Systemcheck.
- **Dunkelmodus und große Schrift:** sieht alles sauber aus?
- **Signatur-Hinweis:** Erscheint auf „Heute“ ab 2 Tagen vor Ablauf. Lässt sich nur abwarten.

## Was danach passiert

| Ergebnis | Entscheidung |
|---|---|
| Health ✅ | Health-Funktionen kommen schon im kostenlosen Betrieb (Phase 5) |
| Health ❌ | Health-Funktionen werden erst mit Developer-Account aktiv. Alles andere läuft lokal |
| Widget ❌ | Widgets zeigen nur statische Infos, bis zum Developer-Account |
| Wecker ❌ | Medikamenten-Erinnerungen nur als Mitteilung |
| Claude per Kurzbefehl ❌ | Claude-Brücke nutzt Kopieren/Einfügen |
