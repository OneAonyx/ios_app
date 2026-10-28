# Orbit per SideStore installieren (kostenlos)

Mit SideStore läuft Orbit auf deinem iPhone, ohne Developer-Account. Die App wird mit deiner
normalen Apple-ID signiert und muss **alle 7 Tage aufgefrischt** werden. Deine Daten bleiben dabei
erhalten.

## Was du brauchst

- iPhone mit iOS 26 oder neuer (dein iPhone 15 passt)
- deine Apple-ID (kostenlos)
- **einmalig** einen Computer (Windows, Linux oder Mac) und ein USB-Kabel für die SideStore-Einrichtung
- das GitHub-Repo [OneAonyx/ios_app](https://github.com/OneAonyx/ios_app) (öffentlich, kein Login nötig)

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

## 3. Orbit installieren

1. Auf dem iPhone in Safari **[github.com/OneAonyx/ios_app/releases/latest](https://github.com/OneAonyx/ios_app/releases/latest)** öffnen.
2. Unter „Assets“ `Orbit.ipa` antippen und laden.
3. Die Datei in der Dateien-App antippen → **Teilen** → **SideStore**.
   Alternativ in SideStore: „Meine Apps“ → **+** → `Orbit.ipa` wählen.
4. Falls iOS beim ersten Start meldet, dass dem Entwickler nicht vertraut wird:
   Einstellungen → Allgemein → **VPN & Geräteverwaltung** → deine Apple-ID → **Vertrauen**.

### Alternative: direkt mit iloader vom PC (wenn die SideStore-Anmeldung scheitert)

Die Anmeldung in SideStore auf dem iPhone schlägt derzeit oft fehl (Apple-seitig, z. B. Fehler
`-80045`). iloader am PC kann Orbit direkt installieren:

1. `Orbit.ipa` aus den [Releases](https://github.com/OneAonyx/ios_app/releases/latest) auf den PC laden.
2. iPhone per USB anschließen, iloader öffnen, mit der Apple-ID anmelden.
3. Die Option zum Installieren einer eigenen App/IPA wählen und `Orbit.ipa` auswählen.

Die Daten bleiben bei einem Update erhalten, solange dieselbe Apple-ID genutzt wird (gleiche Bundle-ID).
Auffrischen alle 7 Tage geht dann ebenfalls über iloader am PC.

## 4. Alle 7 Tage auffrischen

- In SideStore: „Meine Apps“ → **Refresh All**.
- Bequemer: In der Kurzbefehle-App eine **Automation** anlegen (z. B. täglich um 3 Uhr, wenn das
  iPhone lädt) mit der SideStore-Aktion zum Auffrischen.
- Orbit zeigt auf „Heute“ einen Hinweis, sobald die Signatur in weniger als 2 Tagen abläuft.

## 5. Updates

Neue `Orbit.ipa` aus dem neuesten Release genauso in SideStore öffnen. Die Daten bleiben erhalten,
solange du Orbit nicht löschst.

## Grenzen mit kostenloser Apple-ID

| Grenze | Folge für Orbit |
|---|---|
| höchstens 3 aktive Apps (inkl. SideStore, Erweiterungen zählen mit) | Orbit hat genau **eine** Erweiterung (Widgets). SideStore + Orbit + Widget = 3 |
| höchstens 10 neue App-IDs pro 7 Tage | Nicht ständig neu installieren, lieber „Refresh“ nutzen |
| kein iCloud/CloudKit | Datensicherung über Backups in der Dateien-App (ab Phase 1) |
| Apple Health eventuell nicht erlaubt | Test 2 im Systemcheck zeigt es. Ohne Health laufen alle Funktionen mit lokalen Daten weiter |

## Kein Developer-Account

Orbit bleibt bei der kostenlosen Apple-ID. Apple Health, iCloud-Sync und TestFlight gibt es
deshalb nicht. Health-Werte kommen später über Kurzbefehle (Phase 8), die Datensicherung zusätzlich
in einen Ordner deiner Wahl, z. B. iCloud Drive (Phase 9).
