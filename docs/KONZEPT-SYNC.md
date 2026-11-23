# Konzept: Sync als Mischform (Google Drive, OneDrive, direkte Verbindung)

Stand: 19.11.2026 · Status: **Entwurf, Fragen geklärt am 19.11.2026**, nächster Schritt Machbarkeitstest M0 · Fasst zusammen und ersetzt: `KONZEPT-ORDNER-SYNC.md` (abgelöst), Anbieter-Teil von `PLAN-WEB-UND-SYNC.md` (W6, #38). Die Technik der direkten Verbindung steht weiter in `KONZEPT-SYNC-OHNE-REGISTRIERUNG.md`.

## Idee

| Du hast … | Abgleich über | Zeitversetzt? |
|---|---|---|
| ein Google-Konto | **Google Drive**, über die Schnittstelle | ja, Geräte müssen nicht gleichzeitig laufen |
| ein Microsoft-Konto | **OneDrive**, über die Schnittstelle | ja |
| keines von beiden (oder willst keines nutzen) | **direkte Verbindung** zwischen gekoppelten Geräten | nein, zwei Geräte müssen gleichzeitig offen sein |
| nichts gewählt | nichts, alles bleibt lokal (`NoSync`) | – |

Eine Bibliothek hat **genau einen** Speicherort: Google Drive, OneDrive oder keinen (entschieden). Beide Clouds gleichzeitig gibt es nicht. Die direkte Verbindung funktioniert zusätzlich immer zwischen gekoppelten Geräten, auch wenn eine Cloud gewählt ist. So kann z. B. ein Gerät ohne Konto über einen gekoppelten Rechner mitmachen, der mit der Cloud abgleicht (siehe «Brücke»).

**Bewusst aufgegeben gegenüber dem Konzept ohne Registrierung:** Für Google und Microsoft registrierst Du die App einmal, kostenlos. Dafür gibt es den zeitversetzten Abgleich.

## Anforderungen und wie sie erfüllt werden

| Anforderung | Cloud (Google, OneDrive) | Direkt |
|---|---|---|
| Desktop und Handy | ja, alle über die Schnittstelle | ja |
| Registrierung der App | **ja**, einmal bei Google Cloud und Microsoft Entra, kostenlos | nein |
| Einmal anmelden | Desktop ja. Handy: Google erneuert still, gelegentlich ein Tippen; OneDrive etwa alle 24 h eine kurze Weiterleitung, meist ohne Eingabe | ja (QR-Code) |
| Keine Kosten | ja (Gratis-Kontingent des Nutzers: Google 15 GB, OneDrive 5 GB) | ja |
| Stabil | hoch, Cloud speichert zwischen | nur wenn beide offen sind; nicht in jedem Netz |

## Warum am Desktop die Schnittstelle und nicht der Ordner

Im Ordner-Konzept schrieb der Desktop in den lokalen Google-Drive-Ordner. Die Dateien stammten dann von «Google Drive für Desktop», und ob die App auf dem Handy sie mit dem engen Recht `drive.file` überhaupt sieht, war ungeklärt (dort G1). **Schreiben alle Geräte über die Schnittstelle, ist das kein Thema:** Alle Dateien legt dieselbe App an, `drive.file` deckt sie ab, und eine Ordnerauswahl (Picker) braucht es nicht. Für OneDrive gilt dasselbe mit dem App-Ordner.

Der Desktop braucht dafür eine Anmeldung, aber nur einmal: Desktop-Apps bekommen bei Google und Microsoft langlebige Refresh-Tokens (Systembrowser mit lokalem Empfänger, PKCE).

## Anbieter

| | Google Drive | OneDrive |
|---|---|---|
| Recht | `drive.file` (nicht sensibel) | `Files.ReadWrite.AppFolder` |
| Prüfung durch Google (geklärt 19.11.2026) | **Keine Prüfung nötig, keine eigene Domain, keine Kosten.** Bei nur nicht sensiblen Rechten ist die Prüfung nicht Pflicht; die Warnung «Google hat diese App nicht überprüft» und die Grenze von 100 Nutzern gelten nur für sensible oder eingeschränkte Rechte. Die kostenpflichtige Sicherheitsprüfung (CASA) gilt nur für eingeschränkte Rechte (z. B. `drive`). Status «In Produktion», nicht «Test» (Test: nur eingetragene Testnutzer, kurzlebige Refresh-Tokens). Pflicht bleibt eine öffentliche Startseite, die die App beschreibt; dafür genügt GitHub Pages. **Optional** ist die Markenprüfung, damit Name und Logo auf dem Zustimmungsbildschirm erscheinen: Dann müssen Startseite und Datenschutzerklärung auf einer eigenen, in der Search Console verifizierten Domain liegen; `github.io` lässt sich nicht verifizieren (geteilte Domain). Vorbehalt: Google kann die Einstufung eines Rechts ändern. | eigene Prüfung bei Microsoft, siehe #55 |
| Ort | Ordner `WoodshedPlayer` in Meine Ablage, von der App angelegt. Weitere Geräte finden ihn über die Suche nach Name (sie sehen ohnehin nur Dateien dieser App) | App-Ordner `Apps/Woodshed Player` (`approot`) |
| Was die App sieht | nur ihre eigenen Dateien | nur ihren App-Ordner |
| Desktop-Anmeldung | macOS: Anmeldefenster des Systems (Client vom Typ «iOS»), sonst Systembrowser; Refresh-Token, Schlüsselbund bzw. Credential Store | ebenso |
| Handy-Anmeldung | Weiterleitung, ohne eigenen Server nur Zugriffstokens (ca. 1 h), still erneuert | Weiterleitung, Refresh-Token gilt nur 24 h (Typ «SPA»), dann Weiterleitung in voller Seite |
| Grosse Dateien | fortsetzbarer Upload | Upload-Sitzungen |

Pfade (`devices/…`, `audio/…`) bildet der Google-Provider auf Datei-IDs ab und merkt sich diese.

**Umgesetzt in #54 (M3):** `app/lib/sync/providers/google_drive_provider.dart` legt echte Unterordner an (`devices`, `audio`, `backup/<id>`) und merkt sich deren IDs; der Ordner `WoodshedPlayer` entsteht erst beim ersten Schreiben (Lesen legt nichts an). Legen zwei Geräte ihn gleichzeitig an, gilt der älteste, der eigene leere wird gelöscht. Zwei Dateien gleichen Namens in einem Ordner zeigt der Provider nach Erstellzeit als `<name> (1).<ext>`, was die Engine als Konfliktkopie erkennt. Dateien über 5 MB gehen in Blöcken von 8 MB über eine fortsetzbare Sitzung hoch, die nach einem Abbruch beim nächsten Versuch nachfragt, wie viel angekommen ist. Anmeldung: macOS mit PKCE im Anmeldefenster des Systems (`ASWebAuthenticationSession`, Kanal `woodshed/webauth`) und dem Google-Client vom Typ «iOS», Rückleitung über die umgekehrte Client-ID als URL-Schema; der Weg über Systembrowser und Empfänger auf `127.0.0.1` bleibt für Windows und Linux, denn Safari mit «Nur HTTPS» lehnt die Rückleitung an `http://127.0.0.1` ab. Refresh-Token im Schlüsselbund (eigener Kanal `woodshed/keychain`); Web per Weiterleitung mit `response_type=token`, Token in IndexedDB, Erneuerung per Weiterleitung mit `prompt=none`, nie während der Wiedergabe. HTTP ohne neues Paket (`dart:io` bzw. `fetch`). Die App lädt das Google-Modul per `deferred`-Import erst, wenn Google Drive auf dem Gerät gewählt ist. In der nativen iPhone/iPad-App ist Google Drive ausgeblendet; dort läuft der Abgleich über die Web-App.

## Daten: ein Layout für alle Wege

```
WoodshedPlayer/
  format.json                         Format-Version und Bibliotheks-ID
  devices/<geraet-id>.json            Stand dieses Geräts (nur dieses Gerät schreibt die Datei)
  backup/<geraet-id>/state-<n>.json   die letzten 5 eigenen Stände
  audio/<hash>.<ext>                  Audiodateien, Name = SHA-256 des Inhalts
```

- **Eine Datei je Gerät** statt einer gemeinsamen `state.json`: Kein Gerät überschreibt ein anderes, bedingtes Schreiben (ETag) ist nicht nötig. Das Zusammenführen aus #36 ist reihenfolgeunabhängig; jedes Gerät liest alle `devices/*.json` und schreibt seinen zusammengeführten Stand.
- **Umgesetzt in #53 (M1):** `CloudSync` in `app/lib/sync/sync_engine.dart`. Ablauf je Abgleich: (0) `format.json` aller Quellen lesen; eine Bibliotheks-ID, die irgendwo steht, übernimmt das Gerät, bevor es für eine leere Quelle eine neue anlegt (zufällig, 32 Hex-Zeichen, in `device.json` als `libraryId`). (1) Alle `devices/*.json` aller Quellen lesen und gemeinsam zusammenführen. (2) Die eigene Datei schreiben, wenn sie fehlt, sich unterscheidet oder älter als 30 Tage ist; vorher kommt der bisherige Inhalt nach `backup/<geraet-id>/state-<n>.json` (Platz = Generation mod 5 + 1). Danach Konfliktkopien und Dateien von Geräten, die 180 Tage nicht geschrieben haben, löschen, sofern sie seit dem Lesen unverändert sind. (3) Audio: zuerst aus allen Quellen laden, dann hochladen und löschen.
- **Gerätedatei:** der geteilte Stand (`formatVersion`, Titel, Ordner, Einstellungen, Bereinigungshorizont) plus `deviceId`, `generation` und `written` (Millisekunden, Uhr des Geräts).
- **Kein bedingtes Schreiben:** Die Engine nutzt weder ETag noch `rev`. Der Test-Speicher `InMemoryProvider(conditional: false)` lehnt bedingtes Schreiben ab.
- **Konfliktkopien** erkennt die Engine an der Gerät-ID (16 Hex-Zeichen) mit beliebigem Zusatz vor `.json`, der nicht mit einer Hex-Ziffer beginnt: Google Drive für Desktop `<id> (1).json`, OneDrive-Schnittstelle mit `conflictBehavior=rename` `<id> 1.json`, OneDrive-Client `<id>-<Gerätename>.json`, iCloud `<id> 2.json`, `<id> (<Name>'s conflicted copy <Datum>).json`, Syncthing `<id>.sync-conflict-<Datum>-<Zeit>-<Kennung>.json`. Legt die Google-Drive-Schnittstelle zwei Dateien mit gleichem Namen an, muss der Provider (#54) die zweite unter einem solchen Namen zeigen.
- **Unlesbare Gerätedatei** (beschädigt, unbekannte Felder): wird übersprungen, ohne Meldung, und beim nächsten Abgleich erneut gelesen; sie wird nie gelöscht. Eine Gerätedatei mit neuerem Format stoppt den Abgleich wie `format.json` mit neuerer Version (Meldung «App aktualisieren», `SyncStatus.tooNew`). Fremde Bibliotheks-ID: diese Quelle wird weder gelesen noch geschrieben (`SyncStatus.foreignLibrary`), andere Quellen laufen weiter.
- **Bekannte Grenze:** Legen zwei Geräte `format.json` im selben Augenblick an, gewinnt die zuletzt gespeicherte; das Gerät liest sie nach dem Schreiben zurück und übernimmt sie. Fällt das Zurücklesen genau zwischen die beiden Schreibvorgänge, sieht ein Gerät danach eine fremde Bibliotheks-ID. Die Oberfläche (M5) muss dann «dieser Bibliothek beitreten» anbieten.
- **Dasselbe Layout** für Google, OneDrive und die direkte Verbindung. Bei der direkten Verbindung beantwortet die Gegenstelle `list`/`get`/`put` aus ihrer lokalen Kopie.
- Audio unveränderlich, nach Hash benannt, nach dem Laden geprüft; «nicht hochladen» je Titel und «synchronisieren» je Ordner wie in #37.

## Brücke: mehrere Quellen gleichzeitig

Ein Gerät kann mehrere Quellen haben: die Cloud und gekoppelte Geräte. Die Engine gleicht nacheinander mit jeder Quelle ab. Weil das Zusammenführen kommutativ und idempotent ist, ergibt das immer denselben Stand.

Beispiel: Rechner mit Google-Konto, Linux-Laptop ohne Konto, gekoppelt. Der Laptop gleicht direkt mit dem Rechner ab, der Rechner trägt alles in Google Drive weiter. Das iPhone mit Google-Konto sieht die Änderungen des Laptops zeitversetzt.

Die Brücke ist kein eigener Mechanismus, sondern ergibt sich aus mehreren `CloudProvider` je Gerät: `CloudSync(provider, library, more: [...])`, zur Laufzeit `addSource`/`removeSource` (z. B. wenn ein gekoppeltes Gerät sich verbindet). Ist eine Quelle nicht erreichbar, gleichen die übrigen trotzdem ab, und ein neuer Versuch wird geplant; offline ist der Abgleich erst, wenn keine Quelle erreichbar ist. Für die direkte Verbindung (#56) beantwortet B die Anfragen von C aus einem eigenen Speicher, den B selbst als Quelle führt; im Test aus #53 ist das ein `InMemoryProvider`.

## Ablauf aus Deiner Sicht

1. **Erstes Gerät:** Einstellungen → Abgleich → «Google Drive», «OneDrive» oder «Geräte direkt koppeln».
2. **Weitere Geräte mit Cloud:** dasselbe Konto wählen und anmelden. Kein Koppeln nötig.
3. **Weitere Geräte ohne Konto:** «Koppeln» → QR-Code eines bereits eingebundenen Geräts einlesen.
4. Die Statuszeile zeigt den Speicherort, je Gerät den letzten Abgleich und ob gekoppelte Geräte gerade verbunden sind.
5. **Wechsel des Speicherorts** (z. B. von OneDrive zu Google): Die App schreibt den vollständigen Stand samt Audio an den neuen Ort und meldet sich beim alten ab. Die Dateien dort löschst Du in Deinem Konto.

## Architektur

```
Sync-Engine (#37) mit einer Datei je Gerät und mehreren Quellen (#53)
  ├── GoogleDriveProvider   (drive.file, Desktop und Web)
  ├── OneDriveProvider      (approot, Desktop und Web)
  └── PeerProvider          (WebRTC, je gekoppeltes Gerät)
        └── Rendezvous      (öffentliche Relays, nur Verbindungsaufbau)
```

- Ohne Wahl bleibt `NoSync`: keine Anbieter-Module, keine Relays, keine Verbindung.
- Die Anbieter-Module sind dünn (REST über `http`), austauschbar und bekommen aufgezeichnete Antworten als Tests.
- Kopplung, Schlüssel, Relays, Datenkanal, Grenzen: siehe `KONZEPT-SYNC-OHNE-REGISTRIERUNG.md` (Entscheidungen dort gelten weiter: gleichzeitig offen akzeptiert, öffentliche Relays akzeptiert, `flutter_webrtc`, kein Ordner-Sync).

## Datenschutz und Regeln

- **Netzwerk-Regel**, Vorschlag: *«Netzwerkzugriff nur für den Abgleich und nur nach ausdrücklicher Wahl: zum gewählten Cloud-Anbieter (Google Drive oder OneDrive) nach Anmeldung, oder zu gekoppelten Geräten, mit Verbindungsaufbau über öffentliche Relays und STUN-Server. Dazu das Laden der Web-App selbst. Kein Tracking.»*
- `DATENSCHUTZ.md`: Dropbox streichen; Google mit `drive.file` («nur Dateien, die die App selbst anlegt»); Abschnitt zur direkten Verbindung (Relays sehen IP-Adresse und Zeitpunkt, keine Inhalte).
- Keine eigene Verschlüsselung in der Cloud (wie im Plan). Die direkte Verbindung ist Ende-zu-Ende verschlüsselt.
- **Neue Abhängigkeiten (Rückfrage nötig):** `http`, `web`, `flutter_secure_storage`, `crypto` (bereits im Plan), dazu `flutter_webrtc` (MIT), eine Kryptografie-Bibliothek (z. B. `cryptography`, Apache-2.0) und ein QR-Paket.

## Ungeklärt, vor der Umsetzung zu prüfen

| # | Frage | Wenn nein |
|---|---|---|
| P1 | Klappt die Anmeldung (Weiterleitung) in der **installierten** Web-App auf dem iPhone, und landet das Token in deren Speicher (nicht in Safari)? | Anmeldung in einem Popup-Fenster versuchen; sonst am iPhone nur direkte Verbindung |
| P2 | Wie oft verlangt Google auf dem iPhone ein Tippen (Safari schränkt die stille Erneuerung ein)? | anzeigen und beim Start erneuern, nicht mitten im Üben |
| P3 | Die 24-h-Weiterleitung bei OneDrive auf dem iPhone: ohne Eingabe, solange die Microsoft-Sitzung lebt? | täglich ein Tippen; in der Oberfläche benennen |
| P4 | App-Ordner bei OneDrive for Business (Geschäftskonten)? | nur private Microsoft-Konten |
| K0 | Machbarkeit der direkten Verbindung (sieben Prüfpunkte, siehe Konzept ohne Registrierung) | direkte Verbindung nur im selben WLAN oder streichen; Cloud bleibt |

## Phasen und Issues

| # | Inhalt | Aufwand |
|---|---|---|
| M0 | Machbarkeitstest: P1–P4 mit Testkonten und K0 (#52) | 3–4 Tage · **Go/No-Go** je Weg |
| M1 | Eine Datei je Gerät und mehrere Quellen je Gerät in der Engine (#53, umgesetzt); Tests mit `InMemoryProvider` (zwei, drei Geräte, Brücke, Reihenfolge vertauscht, Abbrüche) | 3–4 Tage |
| M2 | `OneDriveProvider` (#55): App-Ordner, Upload-Sitzungen, Anmeldung Desktop und Web | 3–4 Tage |
| M3 | `GoogleDriveProvider` (#54, umgesetzt): `drive.file`, Ordner anlegen und finden, Pfade auf IDs, Anmeldung Desktop und Web | 3–4 Tage |
| M4 | Direkte Verbindung (#56): Kopplung, Relays, `PeerProvider` (K2/K3 im Konzept ohne Registrierung) | 7–10 Tage |
| M5 | Oberfläche, parallel in #54, #55, #56 (ersetzt #40): Speicherort wählen und wechseln, Koppeln, Status je Gerät, Texte in allen ARB-Dateien (ersetzt Teile von #40) | 3 Tage |
| M6 | #41: `README.md`, `DATENSCHUTZ.md`, `CLAUDE.md`, `PLAN-WEB-UND-SYNC.md` nachführen | 0,5 Tage |

**Reihenfolge (entschieden):** M0, M1, dann **M3 Google**, M2 OneDrive, M4 direkte Verbindung, M5 wächst mit jedem Weg mit, M6 zum Schluss. Nach M3 ist der erste Abgleich nutzbar. **Gesamt:** ca. 23–30 Arbeitstage.

**Vorher bei Dir:** Google-Cloud-Projekt (OAuth-Client «Web» und «Desktop», Zustimmungsbildschirm mit `drive.file`, Status «In Produktion», ohne Prüfung), Microsoft-Entra-Registrierung (Plattformen «SPA» und «Mobile/Desktop», `Files.ReadWrite.AppFolder`). Beides kostenlos. Die Weiterleitung zeigt auf die GitHub-Pages-Adresse.

**Issues (19.11.2026):** #52 M0, #53 M1, #54 M3 Google, #55 M2 OneDrive, #56 M4 direkt, #41 M6. #38 und #40 als «not planned» geschlossen (abgelöst), #39, #41 und #50 kommentiert. Geklärt am 19.11.2026: Google verlangt für `drive.file` keine Prüfung und keine eigene Domain (Tabelle «Anbieter»); eine eigene Domain (#50) braucht es nur für Name und Logo auf dem Zustimmungsbildschirm.

## Entscheidungen (19.11.2026)

| Frage | Entscheidung |
|---|---|
| Reihenfolge | **Google Drive zuerst**, dann OneDrive, zuletzt die direkte Verbindung |
| Cloud-Anbieter je Bibliothek | **genau einer**; Wechsel möglich, beide gleichzeitig nicht |
| Audio bei direkter Verbindung | **alles mitnehmen** wie bei der Cloud (ausser «nicht hochladen» und Ordner ohne «synchronisieren»), damit das Handy die Titel hat, bevor Du unterwegs übst |
