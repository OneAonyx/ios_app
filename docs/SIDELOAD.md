# Tagwerk per SideStore installieren (kostenlos)

Mit SideStore läuft Tagwerk auf deinem iPhone, ohne Developer-Account. Die App wird mit deiner
normalen Apple-ID signiert und muss **alle 7 Tage aufgefrischt** werden. Deine Daten bleiben dabei
erhalten.

## Was du brauchst

- iPhone mit iOS 26 oder neuer (dein iPhone 15 passt)
- deine Apple-ID (kostenlos)
- **einmalig** einen Computer (Windows, Linux oder Mac) und ein USB-Kabel für die SideStore-Einrichtung
- Zugang zum GitHub-Repo `tagwerk-ios` (für den Download der App)

## 1. Entwicklermodus einschalten

Einstellungen → Datenschutz & Sicherheit → **Entwicklermodus** → an → iPhone neu starten → bestätigen.

> Der Schalter erscheint oft erst, nachdem die erste selbst signierte App installiert wurde.
> Dann diesen Schritt nach Schritt 2 wiederholen.

## 2. SideStore einrichten (einmalig)

Folge der offiziellen Anleitung auf **[docs.sidestore.io](https://docs.sidestore.io)** (Abschnitt
„Installation“). Sie ändert sich gelegentlich, deshalb steht sie hier nicht im Detail. Am Ende hast du:

- die SideStore-App auf dem iPhone, angemeldet mit deiner Apple-ID
- eine Pairing-Datei, damit SideStore direkt auf dem iPhone signieren kann (dafür brauchst du den Computer)
- die in der Anleitung genannte VPN-Hilfs-App, über die SideStore auf dem Gerät signiert

## 3. Tagwerk installieren

1. Auf dem iPhone in Safari das Repo öffnen und bei GitHub angemeldet sein (das Repo ist privat).
2. **Releases** → neueste Version → `Tagwerk.ipa` laden.
3. Die Datei in der Dateien-App antippen → **Teilen** → **SideStore**.
   Alternativ in SideStore: „Meine Apps“ → **+** → `Tagwerk.ipa` wählen.
4. Falls iOS beim ersten Start meldet, dass dem Entwickler nicht vertraut wird:
   Einstellungen → Allgemein → **VPN & Geräteverwaltung** → deine Apple-ID → **Vertrauen**.

## 4. Alle 7 Tage auffrischen

- In SideStore: „Meine Apps“ → **Refresh All**.
- Bequemer: In der Kurzbefehle-App eine **Automation** anlegen (z. B. täglich um 3 Uhr, wenn das
  iPhone lädt) mit der SideStore-Aktion zum Auffrischen.
- Tagwerk zeigt auf „Heute“ einen Hinweis, sobald die Signatur in weniger als 2 Tagen abläuft.

## 5. Updates

Neue `Tagwerk.ipa` aus dem neuesten Release genauso in SideStore öffnen. Die Daten bleiben erhalten,
solange du Tagwerk nicht löschst.

## Grenzen mit kostenloser Apple-ID

| Grenze | Folge für Tagwerk |
|---|---|
| höchstens 3 aktive Apps (inkl. SideStore, Erweiterungen zählen mit) | Tagwerk hat genau **eine** Erweiterung (Widgets). SideStore + Tagwerk + Widget = 3 |
| höchstens 10 neue App-IDs pro 7 Tage | Nicht ständig neu installieren, lieber „Refresh“ nutzen |
| kein iCloud/CloudKit | Datensicherung über Backups in der Dateien-App (ab Phase 1) |
| Apple Health eventuell nicht erlaubt | Test 2 im Systemcheck zeigt es. Ohne Health laufen alle Funktionen mit lokalen Daten weiter |

## Später: Wechsel zum Developer-Account

Mit dem Apple Developer Program (99 €/Jahr) kommt die App über TestFlight, hält 90 Tage und alle
Funktionen inkl. iCloud-Sync sind verfügbar. Weil sich dabei die Bundle-ID ändert, werden die Daten
per Export/Import umgezogen (Phase 7).
