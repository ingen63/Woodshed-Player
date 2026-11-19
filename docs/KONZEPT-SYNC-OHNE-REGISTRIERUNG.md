# Konzept: Sync ohne Registrierung, mit einmaliger Kopplung

Stand: 19.11.2026 · Status: **Teil von `KONZEPT-SYNC.md`** (Mischform): beschreibt dort den Weg «direkte Verbindung» ohne Konto. Fragen geklärt am 19.11.2026 · Alternative zum Handy-Teil von `KONZEPT-ORDNER-SYNC.md` (S3/S4) und zu #38

## Anforderungen

| # | Anforderung | Folge |
|---|---|---|
| A1 | Desktop (macOS, Windows, Linux) und Handy (iOS, Android als Web-App) gleichen sich ab | der Weg muss aus dem Browser heraus funktionieren |
| A2 | **Keine Registrierung der App** bei einem Anbieter | kein OAuth, also keine Schnittstelle von Google Drive, OneDrive, Dropbox, iCloud |
| A3 | **Einmal authentisieren**, danach nie wieder | keine Tokens, die ablaufen |
| A4 | Stabil | wenig bewegliche Teile, Abbrüche dürfen nichts beschädigen |
| A5 | **Keine Kosten** für uns und für Dich | kein eigener Server, kein bezahlter Dienst, kein Entwicklerkonto |

## Welche Wege es gibt

| Weg | A2 keine Registrierung | A3 einmal | A5 kostenlos | Handy (Web-App) | Urteil |
|---|---|---|---|---|---|
| Schnittstellen von Google Drive, OneDrive, Dropbox | nein | Google/OneDrive nein | ja | ja | scheidet aus (A2) |
| iCloud (CloudKit) | nein, Entwicklerkonto | ja | nein | ja | scheidet aus |
| Ordner mit Sync-Client | ja | ja | ja | **nein**, kein Ordnerzugriff im Browser | nur zwischen Desktops |
| WebDAV mit App-Passwort (Nextcloud u. a.) | ja | ja | meist ja | **nein**, die Server erlauben keine Zugriffe von fremden Webseiten (CORS) | nur Desktop |
| Eigener Speicher mit Schlüssel (S3-artig) | ja | ja | Gratisstufe | ja, nach Einrichtung durch Dich | für Laien nicht zumutbar |
| Eigener Server von uns | ja | ja | **nein** | ja | scheidet aus (A5) |
| **Direkt von Gerät zu Gerät** | ja | ja | ja | ja | **einziger Weg, der alle fünf erfüllt** |

Sobald A2 und A5 zusammen gelten, bleibt kein Speicher in der Cloud übrig, den das Handy erreicht. Die Daten müssen direkt zwischen Deinen Geräten fliessen.

## Die Lösung in zwei Bausteinen

```
 Desktop A  ◄───────── direkt (WebRTC) ─────────►  Desktop B
     ▲                                                 ▲
     │      direkte, verschlüsselte Verbindung         │
     ▼                                                 ▼
  iPhone (Web-App)                             Android (Web-App)
```

**Ein Mechanismus für alle Geräte:** Handy und Desktop, aber auch zwei Desktops, verbinden sich direkt und verschlüsselt. Einmal koppeln, danach findet sich das Paar selbst, sobald beide Apps offen sind. Einen Ordner-Sync zwischen Desktops gibt es nicht (entschieden, siehe unten); er lässt sich später nachrüsten.

**Der Preis:** Es gibt keinen Zwischenspeicher. Abgeglichen wird nur, wenn **zwei Geräte gleichzeitig laufen**. Typisch: Am Rechner Titel und Loops vorbereiten, Handy daneben öffnen, nach Sekunden bis Minuten ist alles drüben. Danach übst Du unterwegs ohne Netz; die Änderungen wandern beim nächsten Treffen zurück.

## Ablauf aus Deiner Sicht

1. Desktop: Einstellungen → Abgleich → «Gerät koppeln». Die App zeigt einen QR-Code und denselben Inhalt als Wortfolge.
2. Handy: Einstellungen → Abgleich → «Koppeln» → Code mit der Kamera in der App einlesen oder Wortfolge eintippen.
3. Fertig. Ab jetzt gleicht die App ab, sobald beide offen sind. Die Statuszeile zeigt je Gerät «verbunden» oder «zuletzt abgeglichen vor 3 Tagen».
4. «Entkoppeln» löscht den Schlüssel auf dem Gerät. Ein verlorenes Gerät sperrst Du aus, indem Du auf einem anderen «Neuen Schlüssel erzeugen» wählst und die übrigen neu koppelst.

Der Code wird in der App eingelesen, nicht mit der Kamera-App: Auf dem iPhone hat die installierte Web-App einen eigenen Speicher, ein Link aus der Kamera-App landete in Safari.

## Technik

### Kopplung und Schlüssel

- Der Code enthält einen zufälligen **Bibliotheks-Schlüssel** (256 Bit). Alle gekoppelten Geräte teilen ihn. Daraus abgeleitet (HKDF): ein Schlüssel für die Verschlüsselung und eine Treffpunkt-Kennung.
- Ablage: Desktop im Schlüsselbund bzw. Credential Store, Handy in IndexedDB (mit `navigator.storage.persist()`). Der Schlüssel läuft nicht ab (A3).
- Der Schlüssel verlässt die Geräte nie ausser im QR-Code.

### Sich finden (Treffpunkt)

Zwei Geräte hinter Routern brauchen einen Ort, um ihre Verbindungsdaten auszutauschen (wenige hundert Bytes je Verbindung). Dafür nutzt die App **öffentliche, kostenlose Relays**, die keine Anmeldung verlangen:

- Vorschlag: öffentliche Nostr-Relays (WebSocket, flüchtige Nachrichten, mehrere gleichzeitig). Die Liste liegt in einer Konfigurationsdatei und lässt sich ohne Codeänderung tauschen.
- Die Nachrichten sind mit dem Bibliotheks-Schlüssel verschlüsselt und authentisiert. Ein Relay sieht eine zufällige Kennung, Chiffretext und die IP-Adressen. Es kann die Verbindung weder mitlesen noch sich dazwischenschalten.
- Hinter einer Schnittstelle `Rendezvous`, damit sich der Mechanismus austauschen lässt (z. B. öffentliche MQTT-Broker als zweite Umsetzung).
- Öffentliche STUN-Server (z. B. von Google) sagen den Geräten ihre Adresse von aussen. Auch sie verlangen keine Anmeldung.

Über die Relays laufen **keine Bibliotheksdaten**, nur der Verbindungsaufbau.

### Verbindung und Übertragung

- **WebRTC-Datenkanal**, direkt von Gerät zu Gerät, Ende-zu-Ende verschlüsselt (DTLS). Der Fingerabdruck der Verbindung ist an den Bibliotheks-Schlüssel gebunden.
- Im selben WLAN bleiben die Daten im Haus. Zwischen verschiedenen Netzen geht es über das Internet direkt, sofern die Router das zulassen (siehe Grenzen).
- Das Handy behandelt den Desktop wie einen Speicher: **`PeerProvider implements CloudProvider`**. `list`, `get`, `put`, `delete` gehen als Anfragen über den Datenkanal an den Desktop, der sie aus seiner Bibliothek (bzw. seinem Sync-Ordner) beantwortet. Die Sync-Engine aus #37 bleibt, wie sie ist.
- **Layout je Gerät** (`devices/<geraet-id>.json`, `audio/<hash>.<ext>`) wie im Ordner-Konzept. Kein bedingtes Schreiben nötig, das Zusammenführen aus #36 ist reihenfolgeunabhängig.
- **Audio in Stücken** (16–64 KB) mit Flusskontrolle, fortsetzbar ab der letzten Position. Dateien heissen nach ihrem Hash und werden nach dem Empfang geprüft: Ein Abbruch (Bildschirm aus, WLAN weg) beschädigt nichts, beim nächsten Treffen geht es weiter.
- Während einer Übertragung hält das Handy den Bildschirm wach (Wake Lock), weil iOS eine Web-App im Hintergrund anhält.

### Grenzen, ehrlich

| Lage | Erwartung |
|---|---|
| Beide im selben WLAN, Internet vorhanden | soll zuverlässig gehen; in Gäste-WLANs mit Geräte-Trennung nicht |
| Handy im Mobilnetz, Desktop zu Hause | geht mit den meisten Heimroutern; bei manchen Mobilfunk- und Firmennetzen **nicht**, weil dafür ein Vermittlungsserver (TURN) nötig wäre, der Geld kostet (A5). Dann wartet der Abgleich auf das gemeinsame WLAN |
| Kein Internet, aber gemeinsames WLAN | geht **nicht**, der Treffpunkt ist nicht erreichbar (Ausbaustufe unten) |
| Desktop aus oder im Ruhezustand | kein Abgleich; das Handy arbeitet mit dem, was es hat |
| Öffentliche Relays fallen weg | Liste tauschen (Konfiguration); mehrere parallel mindern das Risiko, eine Garantie gibt niemand |

A4 «stabil» heisst hier: Daten gehen nie kaputt, und im heimischen WLAN klappt der Abgleich verlässlich. Eine Verfügbarkeit wie bei einem Cloud-Speicher gibt es ohne Server und ohne Kosten nicht.

### Ausbaustufe: ganz ohne Dritte im WLAN

Später möglich, getrennt zu prüfen: Der Desktop nimmt Verbindungen im WLAN direkt an, das Handy kennt nach der Kopplung dessen Zertifikats-Fingerabdruck und baut die Verbindung ohne Treffpunkt auf (Verfahren «WebRTC Direct» oder WebTransport mit Zertifikats-Hash). Dann bräuchte es im Haus weder Relays noch Internet. Aufwand und Browser-Unterstützung (vor allem Safari) sind ungeklärt.

## Datenschutz und Regeln

- **Regel «Kein Netzwerk» braucht eine neue Ausnahme**, Vorschlag: *«Gerätekopplung nur nach ausdrücklichem Koppeln: Verbindungsaufbau über öffentliche Relays und STUN-Server (nur verschlüsselte Verbindungsdaten), Bibliotheksdaten ausschliesslich direkt zwischen den gekoppelten Geräten.»* Ohne Kopplung bleibt es bei: keine Verbindung.
- Die Betreiber der Relays und STUN-Server sehen die **IP-Adressen** der Geräte und den Zeitpunkt, sonst nichts. Das gehört in `DATENSCHUTZ.md`, mit der Liste der Relays.
- Kein Konto, keine Daten bei uns oder bei einem Speicheranbieter. Die Abschnitte zu Google, Dropbox und OneDrive in `DATENSCHUTZ.md` entfallen.
- **Neue Abhängigkeiten (nur nach Rückfrage):**
  - WebRTC am Desktop: `flutter_webrtc` (MIT, bringt libwebrtc mit, BSD-3). Macht die App um einige zehn MB grösser. Im Browser ist WebRTC eingebaut. (`libdatachannel` verworfen: MPL-2.0.)
  - Verschlüsselung und Signaturen in Dart (z. B. `cryptography`, Apache-2.0); QR-Code erzeugen und lesen (MIT/Apache-2.0-Pakete).

## Risiken

| Risiko | Wirkung | Gegenmassnahme |
|---|---|---|
| Verbindung im selben WLAN kommt nicht zustande (Browser verbergen lokale Adressen hinter mDNS-Namen) | Kernfall scheitert | **K0 prüft das zuerst** auf echten Geräten; sonst Ausbaustufe vorziehen |
| iOS hält die Web-App an, sobald der Bildschirm sperrt | Übertragung grosser Bibliotheken bricht ab | Wake Lock, fortsetzbare Stücke, Fortschrittsanzeige |
| iOS räumt den Speicher der Web-App | Schlüssel und Titel weg | `persist()`, neu koppeln (einmal Code einlesen), Titel kommen vom Desktop zurück |
| Öffentliche Relays verschwinden oder drosseln | kein Verbindungsaufbau | mehrere parallel, Liste austauschbar, zweite `Rendezvous`-Umsetzung |
| Kein TURN | manche Netz-Kombinationen gehen nicht | klar anzeigen («im selben WLAN erneut versuchen»), kein stiller Fehler |
| Schlüssel im QR-Code wird abfotografiert | Fremde könnten sich koppeln | Code nur während des Koppelns anzeigen, Liste gekoppelter Geräte, «Neuen Schlüssel erzeugen» |
| Erstabgleich grosser Bibliotheken dauert | Geduldsprobe | Metadaten zuerst, Audio danach und bei Bedarf (wie #37), Schätzung anzeigen |

## Vorschlag Phasen und Issues

| # | Inhalt | Aufwand |
|---|---|---|
| K0 | **Machbarkeitstest, Go/No-Go:** Testseite und kleines Desktop-Testprogramm. Prüfpunkte: (1) installierte Web-App auf iPhone ↔ Mac im selben WLAN, (2) Android ebenso, (3) Handy im Mobilnetz ↔ Desktop zu Hause, (4) Verbindungsaufbau über drei öffentliche Relays, eine Woche lang täglich, (5) 100 MB übertragen, Abbruch und Fortsetzen, (6) Verhalten bei Bildschirmsperre, (7) Schlüssel nach 7 Tagen noch da | 2–3 Tage |
| K1 | Layout je Gerät in der Sync-Engine (wie S1 im Ordner-Konzept), Tests mit `InMemoryProvider` | 2–3 Tage |
| K2 | Kopplung: Schlüssel, QR-Code und Wortfolge, Verschlüsselung, `Rendezvous` mit Umsetzung für Tests (im Speicher) und für Relays | 3–4 Tage |
| K3 | Transport: WebRTC am Desktop und im Web, `PeerProvider`, Gegenstelle am Desktop, Stücke mit Fortsetzen; Tests mit zwei Engines in einem Prozess | 4–6 Tage |
| K4 | Oberfläche: Koppeln, Geräteliste, Entkoppeln, Status, Texte in allen ARB-Dateien | 2–3 Tage |
| K5 | `README.md`, `DATENSCHUTZ.md`, `CLAUDE.md` (Netzwerk-Regel), `PLAN-WEB-UND-SYNC.md` nachführen | 0,5 Tage |

**Gesamt:** ca. 14–20 Arbeitstage. Entfällt: App-Registrierung bei Google und Microsoft, #38 (als «not planned» schliessen, mit Verweis hierher).

## Entscheidungen (19.11.2026)

| Frage | Entscheidung |
|---|---|
| Abgleich nur, wenn zwei Geräte gleichzeitig offen sind | **akzeptiert.** Ein Zwischenspeicher (Dropbox mit Registrierung, Relays als Briefkasten, eigener Dienst) wurde erwogen und verworfen, weil er A2, A4 oder A5 verletzt. |
| Öffentliche Relays und STUN-Server sehen beim Verbindungsaufbau die IP-Adresse | **einverstanden.** Die Regel «Kein Netzwerk» bekommt die Ausnahme oben (K5). |
| WebRTC-Bibliothek am Desktop | **`flutter_webrtc`** (MIT). |
| Ordner-Sync zwischen Desktops | **weglassen.** Desktops koppeln sich direkt; später nachrüstbar. |

**Nachtrag 19.11.2026:** Entschieden ist die Mischform (`KONZEPT-SYNC.md`): Google Drive und OneDrive über die Schnittstelle, die direkte Verbindung für Geräte ohne Konto. #38 bleibt deshalb und wird umgeschrieben, nicht geschlossen. Phasen und Aufwand gelten nur noch über M4 und M0 in `KONZEPT-SYNC.md`.
