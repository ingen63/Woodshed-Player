# K0: Testprogramm für die direkte Verbindung (#52)

Machbarkeitstest K0 aus `docs/KONZEPT-SYNC-OHNE-REGISTRIERUNG.md`: Können zwei Geräte direkt Daten austauschen? Gegenstück zur Testseite `web/k0/` (GitHub Pages unter `k0/`). Kein Teil der App: eigenes Flutter-Projekt für macOS mit `flutter_webrtc` und `cryptography`, deutsche Beschriftung wie die Testseite, keine Übersetzung.

## Bauen und starten

```
cd tools/k0 && flutter build macos --debug
open build/macos/Build/Products/Debug/woodshed_k0.app
```

Ein zweites Exemplar auf demselben Mac (eigene Geräte-ID, eigener Schlüssel):

```
open -n --env K0_PROFILE=-2 build/macos/Build/Products/Debug/woodshed_k0.app
```

Ohne Klicken (Rauchtest): `K0_KEY=<Kopplungscode>` koppelt, `K0_CONNECT=relay,lan` verbindet beim Start, `K0_SEND=1` sendet 100 MB, sobald der Datenkanal offen ist.

## Wege

| Weg | Treffpunkt | STUN | Internet nötig |
|---|---|---|---|
| Über Relays | öffentliche Nostr-Relays (`relays` in `lib/session.dart`, `web/k0/config.js`) | wählbar | ja |
| Bonjour | mDNS im WLAN, danach TCP für die Verbindungsdaten | nein | nein (nur nativ) |
| Direktcode | Codes von Hand austauschen (Zwischenablage) | nein | nein |

In allen Fällen gehen die Testdaten über einen WebRTC-Datenkanal direkt zwischen den Geräten (DTLS). Die Verbindungsdaten sind mit dem Kopplungsschlüssel verschlüsselt (AES-256-GCM). Die Relays sehen eine zufällige Kennung, Chiffretext und die IP-Adresse.

## Ablage

Schlüssel, Stand und Protokoll liegen im Container der App: `~/Library/Containers/ch.woodshed.woodshedK0/Data/Library/Application Support/woodshed-k0/` (`state.json`, `log.txt`). Das Protokoll nennt keine Adressen, nur ihre Art (privat, öffentlich, mDNS).

## Tests

`make test-k0`: Die Testseite (`web/k0/k0.mjs`, Node.js) und das Testprogramm (`lib/protocol.dart`) erzeugen dieselben Bytes wie `test/vectors.json` (Schlüsselableitung, Umschlag, Nostr-Ereignis, Testdaten) und bestehen die offiziellen BIP-340-Testvektoren.
