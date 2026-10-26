# Phase 0 – Ergebnis auf dem iPhone

Erster Systemcheck am 26.10.2026: Tagwerk 0.1.0 (Build 1), iOS 27.0.1, iPhone 15 (`iPhone15,4`),
kostenlose Apple-ID, Bundle-ID `de.tagwerk.app.L6STM8N2CH`.

| # | Test | Ergebnis | Folge |
|---|---|---|---|
| 1 | Installation & Signatur | ✅ 7-Tage-Signatur. Profil enthält **kein** Health-Recht, aber die App Group `group.de.tagwerk.app.L6STM8N2CH` | – |
| 2 | Apple Health | ❌ „Missing com.apple.developer.healthkit entitlement“ | **Health erst mit Developer-Account.** Bis dahin laufen Gewicht, Schritte & Co. als lokale Daten in Tagwerk, ohne Health-Abgleich |
| 3 | Widget-Daten (App Group) | ❌ im Build 0.1.0, **Fehler in Tagwerk**: Die umbenannte App-Group-ID wurde nur in `ALTAppGroups` gesucht. iloader schreibt sie aber nur ins Profil | Behoben ab 0.1.1: ID wird auch aus dem Profil gelesen. Test wiederholen |
| 4 | Wecker (AlarmKit) | ✅ klingelt im Stummmodus | Medikamenten-Wecker sind im kostenlosen Betrieb möglich (Phase 2) |
| 5 | Mitteilungen mit Aktionen | ✅ „Genommen“ kam ohne App-Start an | Medikamenten-Erinnerungen mit Knöpfen sind möglich (Phase 2) |
| 6 | Claude-Brücke | ⏳ Kurzbefehl gestartet, keine Rückmeldung | offen |

## Erkenntnisse

- **Installation:** Die Anmeldung in SideStore auf dem iPhone scheitert derzeit bei vielen Nutzern
  (Apple-seitig, siehe SideStore-Issues). Die Installation direkt über **iloader** am PC funktioniert.
- **Signatur-Werkzeuge benennen App Groups um**, schreiben die neue ID aber unterschiedlich ab.
  Tagwerk liest deshalb beide Quellen (`AppGroupResolver`).
- **Kostenlose Apple-ID:** Wecker und Mitteilungen gehen, Apple Health nicht. Das ist der wichtigste
  Unterschied zum Developer-Account (99 €/Jahr).

## Offene Punkte

- [ ] Test 3 mit Tagwerk 0.1.1 wiederholen
- [ ] Test 6: Was passiert nach „Kurzbefehl starten“? Notfalls den Weg „Anfrage kopieren“ → „Einfügen“ testen
