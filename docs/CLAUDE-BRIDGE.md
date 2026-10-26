# Claude-Brücke

> **Umbenannt:** Hast du den Kurzbefehl schon als „Tagwerk Claude“ angelegt, benenne ihn in der
> Kurzbefehle-App in **„Orbit Claude“** um (lange drücken → Umbenennen).

Orbit nutzt Claude **ohne API-Key und ohne Zusatzkosten**: Anfragen laufen über die Aktion
„Ask Claude“ der offiziellen Claude-App in der Kurzbefehle-App, also über dein normales Claude-Konto.
Anfragen zählen zu deinem normalen Nutzungslimit.

## Einmalig einrichten

1. **Claude-App** aus dem App Store installieren und anmelden.
2. **Kurzbefehle-App** öffnen → **+** → Name genau: **`Orbit Claude`**.
3. Aktion **„Ask Claude“** (Claude-App) hinzufügen, auf Deutsch eventuell „Claude fragen“.
   Als Nachricht die Variable **„Kurzbefehleingabe“** einsetzen.
4. Aktion **„Claude-Antwort übernehmen“** (Orbit) hinzufügen. Als *Antwort* das Ergebnis von
   „Ask Claude“ wählen.
5. Als letzte Aktion **„Stoppen und ausgeben“** (englisch „Stop and Output“) hinzufügen, ebenfalls
   mit dem Ergebnis von „Ask Claude“.

Fertig. Der Kurzbefehl hat damit drei Aktionen:

```
[Ask Claude: Kurzbefehleingabe] → [Claude-Antwort übernehmen: Antwort] → [Stoppen und ausgeben: Antwort]
```

Die Anleitung steht auch in der App: Systemcheck → Claude-Brücke → „Anleitung: Kurzbefehl anlegen“.

## So läuft eine Anfrage

1. Orbit baut die Anfrage und öffnet
   `shortcuts://x-callback-url/run-shortcut?name=Orbit%20Claude&input=text&text=…&x-success=tagwerk://claude/success/<id>`.
2. Der Kurzbefehl fragt Claude und gibt die Antwort auf zwei Wegen zurück:
   - über die Orbit-Aktion „Claude-Antwort übernehmen“ (Briefkasten in der App)
   - über „Stoppen und ausgeben“ → Rücksprung `tagwerk://claude/success/<id>?result=…`
3. Orbit sucht in der Antwort das JSON, prüft Format und Kennung und zeigt das Ergebnis.

Der Phase-0-Test schickt nur eine Zufallskennung (z. B. `7F3A9C21`) und erwartet
`{"format":"tagwerk.ping.v1","ok":true,"echo":"7F3A9C21"}` zurück.

## Ausweichweg ohne Kurzbefehl

Systemcheck → Claude-Brücke → **„Anfrage kopieren“** → in der Claude-App einfügen →
Antwort kopieren → in Orbit **„Einfügen“** tippen.

## Fehlerbilder

| Meldung | Ursache und Lösung |
|---|---|
| „Kurzbefehl meldet einen Fehler“ | Kurzbefehl heißt nicht exakt `Orbit Claude` oder eine Aktion fehlt |
| „lief, gab aber keine Antwort zurück“ | Schritt 4 oder 5 fehlt, oder die Aktionen nutzen nicht das Ergebnis von „Ask Claude“ |
| „In der Antwort war kein gültiges JSON“ | Claude hat frei formuliert. Erneut versuchen; Orbit liest JSON auch aus Codeblöcken |
| „Kennung passt nicht“ | Eine alte Antwort kam an. Test neu starten |

## Später (Phase 3 und 5)

Dieselbe Brücke liefert Trainingspläne (`tagwerk.plan.v1`), Lebensmittel (`tagwerk.food.v1`),
Rezepte (`tagwerk.recipe.v1`) und Wochenrückblicke. Vor jedem Senden zeigt Orbit, welche Daten
an Claude gehen.
