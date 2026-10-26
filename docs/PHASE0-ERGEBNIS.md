# Phase 0 – Ergebnis auf dem iPhone

**Abgeschlossen am 26.10.2026: 5 von 6 Tests bestanden.**
Gerät: iPhone 15 (`iPhone15,4`), iOS 27.0.1, kostenlose Apple-ID, installiert über iloader.
Bundle-ID nach Umbenennung: `de.tagwerk.app.L6STM8N2CH`.

| # | Test | 0.1.0 | 0.1.1 | Folge |
|---|---|---|---|---|
| 1 | Installation & Signatur | ✅ | ✅ | 7-Tage-Signatur. Profil enthält App Group, aber **kein** Health-Recht |
| 2 | Apple Health | ❌ | ❌ | „Missing com.apple.developer.healthkit entitlement“ → **Health erst mit Developer-Account** |
| 3 | Widget-Daten (App Group) | ❌ | ✅ | Fehler in Orbit (umbenannte ID nur in `ALTAppGroups` gesucht), in 0.1.1 behoben. Widget zeigt den Wert aus der App |
| 4 | Wecker (AlarmKit) | ✅ | ✅ | Klingelt im Stummmodus |
| 5 | Mitteilungen mit Aktionen | ✅ | ✅ | „Genommen“ kommt ohne App-Start an |
| 6 | Claude-Brücke | ⏳ | ✅ | Antwort kam automatisch über „Stoppen und ausgeben“ zurück, Kennung stimmte |

## Entscheidungen für den kostenlosen Betrieb

| Bereich | Entscheidung |
|---|---|
| **Apple Health** | Aus. Orbit speichert Gewicht, Symptome, Stimmung, Wasser und Workouts selbst. Der Health-Abgleich (lesen und schreiben) wird mit dem Developer-Account eingeschaltet. Die Capabilities-Registry blendet Health-Funktionen bis dahin aus statt Fehler zu zeigen |
| **Widgets** | An. App und Widget teilen Daten über die App Group (ID wird aus Profil bzw. `ALTAppGroups` gelesen) |
| **Medikamenten-Erinnerungen** | An: Mitteilungen mit Knöpfen **und** AlarmKit-Wecker für wichtige Medikamente |
| **Claude-Brücke** | An, über den Kurzbefehl „Orbit Claude“. Kopieren/Einfügen bleibt als Ausweichweg |
| **Installation** | iloader am PC (SideStore-Anmeldung auf dem iPhone scheitert derzeit Apple-seitig). Auffrischen alle 7 Tage über iloader |
| **iCloud-Sync** | Aus (nur mit Developer-Account). Datensicherung über Backups in der Dateien-App (Phase 1) |

## Erkenntnisse

- Signatur-Werkzeuge benennen App Groups um, legen die neue ID aber an unterschiedlichen Stellen ab.
  Orbit liest beide Quellen (`AppGroupResolver`).
- Die Simulator-Screenshots im CI haben zwei Design-Fehler früh gezeigt (6. Tab unter „Mehr“,
  abgeschnittene Titel) – das bleibt der Standard-Check vor jedem Release.
- Der kostenlose Weg funktioniert, ist aber wackelig (7-Tage-Signatur, Anmeldeprobleme bei SideStore).
  Mit dem Developer-Account (99 €/Jahr) kämen Health, iCloud-Sync und TestFlight dazu.
