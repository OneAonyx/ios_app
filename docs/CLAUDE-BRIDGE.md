# Claude-Brücke

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

```
[Ask Claude: Kurzbefehleingabe] → [Claude-Antwort übernehmen: Antwort] → [Stoppen und ausgeben: Antwort]
```

Die Anleitung steht auch in der App: **Gesundheit → Claude → Kurzbefehl einrichten** oder
Einstellungen → Einblicke. Hast du den Kurzbefehl in Phase 0 angelegt, musst du nichts ändern.

## Anwendungsfälle

| Anfrage | Was an Claude geht | Antwortformat | In Orbit |
|---|---|---|---|
| Trainingsplan | Ziel, Erfahrung, aktueller Plan mit Übungsnamen, letzte Top-Sätze, stagnierende Übungen, Sätze je Muskel, Wunsch, Liste der Übungsnamen | `orbit.plan.v1` | Vorschau, „Als neuen Plan übernehmen“ (der alte bleibt erhalten) |
| Wochenrückblick | Kennzahlen der Woche als Kurzfassung, Wunsch | `orbit.text.v1` | Text mit fett und Listen |
| Lebensmittel | Name, Marke, Zutaten | `orbit.food.v1` | Bewertung, „Ins Lexikon übernehmen“ |
| Rezepte | Anzahl, Portionen, Eiweiß je Portion, gut verträgliche und gemiedene Lebensmittel, Wunsch | `orbit.recipes.v1` | Vorschau mit Bewertung je Zutat, „Rezepte speichern“ |
| Muster | Anzahl Mahlzeiten und Beschwerden, auffällige Lebensmittel und Umstände, häufigste Beschwerden, Befinden, gemiedene Lebensmittel, Frage | `orbit.text.v1` | Text |
| Fortschritt bewerten (ab 0.7) | Ziel, Erfahrung, Größe und Gewicht, Tempo je Übung (Kraftzuwachs pro Woche), Gewichtstempo, Maße, Trainingshäufigkeit, Frage | `orbit.text.v1` | Text: zu schnell, gut, zu langsam, was ändern |
| Fotos bewerten (ab 0.7) | Fotos mit Datum und Gewicht, dazu die Fortschritts-Kennzahlen | `orbit.text.v1` | Text, den du in Orbit einfügst |

**Fotos** passen nicht in einen Kurzbefehl-Link. Orbit öffnet deshalb das Teilen-Menü mit den
Fotos und der Anfrage: **Claude** wählen, senden, Claudes Antwort kopieren und in Orbit bei der
Anfrage **Einfügen**. Die Fotos selbst bleiben in Orbit und landen nicht in der Datensicherung.

**Nie dabei:** dein Name, Geburtsdatum, einzelne Einträge mit Datum, Notizen.

Jede Anfrage bekommt eine Kennung (6 Zeichen), die Claude im Feld `ref` zurückgibt. Daran ordnet
Orbit die Antwort der richtigen Anfrage zu, auch wenn mehrere offen sind.

## So läuft eine Anfrage

1. Anfrage zusammenstellen, Vorschau prüfen, **An Claude senden**.
2. Orbit öffnet
   `shortcuts://x-callback-url/run-shortcut?name=Orbit%20Claude&input=text&text=…&x-success=tagwerk://claude/success/<id>`.
   Lange Anfragen (über 8000 Zeichen, z. B. Trainingsplan) legt Orbit in die Zwischenablage und
   startet den Kurzbefehl mit `input=clipboard`. iOS fragt dann eventuell einmal, ob Kurzbefehle
   einfügen darf: **Erlauben**.
3. Der Kurzbefehl fragt Claude und gibt die Antwort auf zwei Wegen zurück:
   - über die Orbit-Aktion „Claude-Antwort übernehmen“ (Briefkasten in der App)
   - über „Stoppen und ausgeben“ → Rücksprung `tagwerk://claude/success/<id>?result=…`
4. Orbit springt zur Anfrage, liest das JSON (auch aus Codeblöcken oder mit typografischen
   Anführungszeichen) und zeigt die Vorschau. Übernommen wird erst auf deinen Tipp.

## Ausweichweg ohne Kurzbefehl

**Stattdessen kopieren** → in der Claude-App einfügen → Claudes Antwort kopieren → in Orbit
bei der Anfrage **Einfügen** tippen. Das geht auch später aus dem Verlauf.

## Fehlerbilder

| Meldung | Ursache und Lösung |
|---|---|
| „Senden hat nicht geklappt“ | Kurzbefehl heißt nicht exakt `Orbit Claude`, oder die Kurzbefehle-App ließ sich nicht öffnen |
| „Wartet auf Claudes Antwort“ bleibt stehen | Schritt 4 oder 5 fehlt. Antwort in der Kurzbefehle-App kopieren und **Einfügen** |
| „In der Antwort war kein passendes JSON“ | Claude hat frei formuliert. **Erneut senden** oder eine korrigierte Antwort einfügen |
| „Claude hat im falschen Format geantwortet“ | Antwort gehört zu einer anderen Art von Anfrage. Erneut senden |

## Systemcheck

Der Phase-0-Test (Systemcheck → Claude-Brücke) schickt nur eine Zufallskennung und erwartet
`{"format":"tagwerk.ping.v1","ok":true,"echo":"…"}` zurück. Er läuft unabhängig vom Verlauf.
