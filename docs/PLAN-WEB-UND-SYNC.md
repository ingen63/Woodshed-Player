# Plan: Web-App für iOS/Android und optionaler Cloud-Sync

Stand: 19.11.2026 · Status: freigegeben, Issues #32 bis #41 · Ergänzt `UMBAUPLAN-FLUTTER.md`

## Ziel

| Plattform | Form | Aufnahme |
|---|---|---|
| macOS, Windows, Linux | native Flutter-App, wie bisher | ja |
| iPhone/iPad, Android | **Web-App (PWA) im Browser**, aus Safari bzw. Chrome auf den Home-Bildschirm installiert | nie |

1. Bibliothek und Konfiguration sind auf allen Plattformen dieselben Daten.
2. Änderungen gleichen sich **optional** ab: über Google Drive oder OneDrive, oder direkt zwischen gekoppelten Geräten ohne Konto (Mischform, `docs/KONZEPT-SYNC.md`).
3. **Ohne Konto und ohne Kopplung bleibt alles lokal.** Die App öffnet dann keine Netzverbindung und synchronisiert nichts.

## Entscheidungen (aus der Klärung vom 19.11.2026)

| Thema | Entscheidung |
|---|---|
| Cloud-Anbieter | Google Drive (#54) und OneDrive (#55), dazu die direkte Verbindung ohne Konto (#56); Dropbox gestrichen (`docs/KONZEPT-SYNC.md`). Weitere später über dieselbe Schnittstelle (z. B. WebDAV) |
| Umfang | Metadaten **und** Audiodateien |
| Zugriffsrechte | Google `drive.file` (nur Dateien, die die App selbst anlegt), OneDrive «App folder»; die App sieht sonst nichts |
| Konflikte | pro Titel und Feld zusammenführen, neuester Zeitstempel gewinnt, kein Dialog |
| Verschlüsselung | keine eigene; Anmeldung per OAuth mit PKCE im Systembrowser bzw. im Browser |
| Hosting der Web-App | GitHub Pages unter `/app/`, gebaut aus dem letzten Tag (#41) |
| Native iOS/Android | gestrichen (Phase 6 des Umbauplans, Issue #25) |
| Handy-Speicher | einstellbare Obergrenze (Standard 2 GB), älteste Titel zuerst entfernen, «Offline halten» pro Titel |
| Hochladen pro Titel | Schalter «nicht hochladen» je Titel schon in W5 |
| Desktop-Ordner | nur auf Wunsch: beim Anmelden wählst Du, welche Ordner synchronisiert werden; neue Titel in gewählten Ordnern laden automatisch hoch |
| Sicherung | die Cloud behält die letzten 5 Stände von `state.json` |
| Adresse | <https://ingen63.github.io/Woodshed-Player/app/>, keine eigene Domain |

## Architektur

```
┌────────────────────────────────────────────────────────────┐
│ Flutter-Oberfläche (Dart), eine Codebasis                  │
├────────────────────────────────────────────────────────────┤
│ Bibliothek, Einstellungen (Dart, plattformneutral)         │
│  Änderungsstempel, Grabsteine, Gerät-ID                    │
├────────────────────────────────────────────────────────────┤
│ Sync-Engine (reines Dart)                                  │  nur aktiv mit Konto,
│  Zusammenführen · Warteschlange · Wiederholen              │  sonst NoSync
├─────────────────────────────┬──────────────────────────────┤
│ GoogleDrive                 │ OneDrive   (CloudProvider)   │  REST über `http`
├─────────────────────────────┴──────────────────────────────┤
│ Speicher-Schicht (FileStore)                               │
│  Desktop: Dateisystem · Web: OPFS (Origin Private FS)      │
├───────────────────────────┬────────────────────────────────┤
│ Audio-Kern (C++), C-API   │ Audio-Kern als WASM            │
│  dart:ffi, Desktop        │  AudioWorklet, Web             │
│  + Aufnahme (nur Desktop) │  dart:js_interop               │
└───────────────────────────┴────────────────────────────────┘
```

Grundsätze:
- **Ein Kern, zwei Ziele.** Derselbe C++-Code (`core/`) wird für Desktop nativ und für das Web mit Emscripten gebaut. `audio_core.dart` bekommt eine Schnittstelle mit zwei Implementierungen (FFI bzw. JS-Interop, per bedingtem Import).
- **Sync ist reines Dart** und läuft unverändert auf Desktop und im Browser. Nur die Anmeldung (OAuth) und die Token-Ablage unterscheiden sich je Plattform.
- **Anbieter hinter einer kleinen Schnittstelle** `CloudProvider` (`list`, `get`, `put` mit Versionskennung, `delete`, `quota`). Der Sync-Code kennt keinen Anbieter.
- **Ohne Konto:** `SyncService` ist ein `NoSync`, es werden keine Anbieter-Module geladen und keine Anfragen gesendet.

## Cloud-Layout (im app-eigenen Ordner)

```
state.json              Bibliothek und geteilte Konfiguration (Stempel, Grabsteine)
backup/state-<n>.json   die letzten 5 früheren Stände (rotierend, n = 1..5)
audio/<hash>.<ext>      Audiodateien, benannt nach Inhalts-Hash (SHA-256)
```

- **Titel-ID = Inhalts-Hash** der Audiodatei. So erkennt jedes Gerät denselben Titel ohne Pfade, und doppelte Dateien werden nur einmal hochgeladen.
- `state.json` wird bedingt geschrieben (ETag / `rev`), bei Fehlschlag neu laden, zusammenführen, wiederholen. Es gibt keinen Server und keine Sperren.
- Audio ist unveränderlich (Name = Hash). Hochladen ist daher idempotent und wiederaufnehmbar.

## Daten und Zusammenführen

**Geteilt (wandert in die Cloud):** Titel (ID, Titel, Artist, Ordnerzuordnung, Sortierung), Loops und Marker, Tempo je Titel, Ordnerbaum, Metronom- und Tempo-Steigerungs-Voreinstellungen, Darstellung (Hell/Dunkel/System), Sortierung der Bibliotheksliste.

**Gerätelokal (bleibt lokal):** Gerät-ID, Cloud-Konto und Tokens, Cache-Obergrenze, Fensterlage, Ausgabegerät, Dateipfade auf dem Desktop.

Regeln:
- Jedes Feld trägt einen **hybriden Zeitstempel** (Zeit plus Zähler plus Gerät-ID). Je Feld gewinnt der höhere Stempel. Das ist unabhängig von Uhrabweichungen eindeutig.
- **Grabsteine:** Gelöschte Titel und Ordner bleiben mit Stempel in `state.json`. Eine jüngere Änderung am Titel «belebt» ihn wieder. Grabsteine werden nach 90 Tagen entfernt; danach hält der **Bereinigungs-Horizont** die Löschung fest (#98, siehe Umsetzung W4).
- **Mengen** (Loops je Titel) werden elementweise zusammengeführt (Loop-ID als Schlüssel), nicht als Ganzes.
- **Migration:** Das heutige `library.json` (Swift-kompatibel) wird beim ersten Start mit neuer Version in das Format mit Stempeln überführt, ohne Datenverlust, mit Sicherungskopie. Danach kann das Swift-Altprojekt die Bibliothek nicht mehr öffnen (#36).
- Format hat eine **Versionsnummer**. Ein älteres Gerät schreibt eine neuere Datei nicht zurück, sondern meldet «App aktualisieren».

## Phasen

Aufwand in Arbeitstagen, grob, mit KI-Unterstützung. Grösste Unsicherheit: W0 und W6.

### W0 – Machbarkeitstest auf dem iPhone (2–3 Tage) · **Go/No-Go**
- Kern nach WASM bauen (Emscripten, `-sAUDIO_WORKLET`, geteilter Speicher), kleine Testseite auf GitHub Pages mit **COOP/COEP** (bei Pages über Service-Worker-Verfahren, da keine eigenen Header möglich).
- Auf einem echten iPhone und einem Android-Handy prüfen:
  1. Spielt Audio weiter, wenn der Bildschirm sich sperrt oder die App im Hintergrund ist?
  2. Spielt es bei aktivem Stummschalter?
  3. Tempo 0,5x/0,25x, Loop lückenlos, Metronom-Latenz im Rahmen?
  4. Bleiben 500 MB OPFS-Daten nach einer Woche erhalten?
  5. Läuft die Seite mit `SharedArrayBuffer` auf iOS Safari?
- Ergebnis wird in diesem Plan dokumentiert. **Fällt 1 oder 2 durch und lässt sich nicht umgehen** (z. B. Ausgabe über ein `<audio>`-Element mit Media Session), entscheiden wir neu, bevor weitergebaut wird. Die Hörqualität prüft `tools/hoervergleich.sh` gegen die nativen Builds.

#### Prototyp W0

- **Kern:** `core/web/w0_bridge.cpp` stellt Engine und Metronom als WebAssembly bereit (`core/web/build_w0.sh`, Emscripten, `STANDALONE_WASM`, SIMD, 112 KB). Abweichend vom Plan läuft der Kern **ohne** `-sAUDIO_WORKLET` direkt im `AudioWorkletProcessor`: keine JS-Hülle, keine Threads nötig. Der Status geht über einen `SharedArrayBuffer` an die Seite, damit Punkt 5 echt geprüft wird.
- **Testseite:** `web/w0/` (Worklet, OPFS-Worker, Service Worker für COOP/COEP und Offline, Manifest). Testsignal wird erzeugt (Töne über 110-Hz-Grundton, Loop 4–8 s im Signal nahtlos); eigene Dateien lassen sich lokal laden. Die Seite misst selbst: Klickabweichung, Rechenlast, ob Audio im Hintergrund weiterlief (Zeit des AudioContext gegen Wanduhr), OPFS-Inhalt Byte für Byte.
- **Veröffentlichung:** `.github/workflows/pages.yml` (bis #50 `w0-pages.yml`) prüft den Kern mit Node.js und stellt `web/` auf GitHub Pages (Adresse `…/w0/`). Das Repo ist privat: Pages braucht dafür ein kostenpflichtiges GitHub-Konto, sonst Repo öffentlich machen oder Ausweichen laut Risiken.
- **Lokal:** `python3 -m http.server 8732 --directory web/w0`, dann `http://localhost:8732` (localhost gilt als sicher, Service Worker und Isolation funktionieren).

#### Ergebnis W0

Stand: 19.11.2026. «offen» = Prüfung auf echtem Gerät steht aus. Punkte 1–3 auf den Geräten von Dir bestätigt.

| # | Prüfpunkt | Desktop-Chrome / Node.js | iPhone (Safari, installiert) | Android (Chrome, installiert) | Go/No-Go |
|---|---|---|---|---|---|
| 1 | Weiter bei Sperrbildschirm und Hintergrund | – | ok, direkt und `<audio>` | ok, direkt und `<audio>` | **Go** |
| 2 | Weiter bei Stummschalter | – | ok, direkt und `<audio>` | entfällt | **Go** |
| 3 | 0,5x/0,25x ohne Knackser, Loop lückenlos, Metronom < 20 ms | Node.js: keine Sprünge bei 0,5x/0,25x, Loop 1x/0,5x lückenlos, Klickabweichung 0,000 ms, ~88x schneller als Echtzeit; Chrome: Last 4–7 % | ok (gehört) | ok (gehört) | **Go** |
| 4 | 500 MB OPFS nach 7 Tagen | Chrome: Schreiben und Prüfen von 20 MB ok | offen (bis frühestens 7 Tage nach Schreiben) | offen | offen |
| 5 | `SharedArrayBuffer` auf der Pages-Testseite | Chrome lokal: isoliert über Service Worker, SAB im Worklet ja | offen | offen | offen |

Zur Metronom-Abweichung: Der Klick wird sample-genau im selben Puffer wie der Titel gemischt, die Abweichung zum Raster ist daher unter einem Sample. Die Ausgabelatenz des Geräts (auf der Seite angezeigt) verschiebt Klick und Titel gleich.

### W1 – Audio-Kern für das Web (4–6 Tage)
- CMake-Ziel für Emscripten, C-API exportieren, Decodieren (MP3, WAV, FLAC) über miniaudio im Worklet.
- AAC/M4A: im Browser mit `decodeAudioData` vorab in PCM wandeln, dann an den Kern geben (Plattform-Decoder, wie im Umbauplan vorgesehen).
- Gleiche `ctest`-Fälle laufen auch gegen das WASM-Ziel (Node.js), damit Tempo, Loop-Grenzen und Seek identisch bleiben.

#### Umsetzung W1 (#33)

- **Bau:** `emcmake cmake -S core -B core/build-wasm -DCMAKE_BUILD_TYPE=Release && cmake --build core/build-wasm && ctest --test-dir core/build-wasm` (Emscripten über Homebrew oder emsdk). Der Zweig steht in `core/web/web.cmake`.
- **Zwei Varianten:** Die `ctest`-Programme (`engine_tests`, `metronome_tests`, `waveform_tests`, `player_tests`) laufen mit Threads unter Node.js, unverändert und mit denselben Prüfungen wie nativ. `wp_core_web.wasm` (ca. 360 KB) läuft ohne Threads und ohne JS-Hülle im AudioWorklet, wie in W0.
- **C-API:** Steuerung, Wellenform und Metronom wie `wp_core.h`; dazu `core/web/wp_core_web.h` (`wp_web_create`, `wp_web_load_encoded`, `wp_web_load_pcm`, `wp_web_render`). Laden geht über Bytes statt Pfade.
- **Dekodieren:** MP3, WAV, FLAC im Kern (miniaudio aus dem Speicher). AAC/M4A meldet der Kern als nicht unterstützt; der Hauptthread dekodiert mit `decodeAudioData` und gibt das PCM weiter (`loadFile` in `wp_core_web.mjs`).
- **Erledigt mit #42:** Dekodieren blockierte das Worklet für die Dauer des Ladens. Jetzt dekodiert ein Worker mit einer zweiten Instanz des Kerns, siehe Umsetzung W2.
- **Prüfung:** `node core/web/wp_core_web_test.mjs` (Teil von `ctest`) und `core/web/browser_test.html` (MP3, FLAC, M4A im Worklet eines `OfflineAudioContext`, misst Tonhöhe und Pegel).

### W2 – Dart-Anbindung Web (3–4 Tage)
- `audio_core.dart`: Schnittstelle mit `AudioCoreFfi` und `AudioCoreWeb` (`dart:js_interop`, Paket `web`).
- Wellenform, Pegel, Position als Nachrichten vom Worklet; Steuerung in Gegenrichtung.
- Flutter-Web-Build (WASM-Rendering) startet, Oberfläche ist mit der Desktop-Version identisch einspaltig/zweispaltig nach Breite.

#### Umsetzung W2 (#34)

- **Schnittstelle:** `AudioCore` mit `WpAudioCore` (FFI, `audio_core_ffi.dart`) und `WebAudioCore` (`audio_core_web.dart`, `dart:js_interop`, Paket `web`). `main.dart` wählt per bedingtem Import `platform_native.dart` oder `platform_web.dart`. Die reinen Typen (`WpCode`, `WpWaveform`) liegen in `wp_types.dart` ohne `dart:ffi`.
- **Nachrichten:** Befehle gehen mit fortlaufender id ans Worklet. Das Worklet meldet alle 10 ms Position, Loop-Durchgänge, Metronom, Spitzenpegel und die id des letzten Befehls (ältere Zustände nach einem Seek werden verworfen). Die Wellenform holt die Anbindung einmal nach dem Laden (200 Abschnitte pro Sekunde) und beantwortet jede Abfrage daraus.
- **Dateien:** Bis W3 vorläufige Dateiauswahl (`<input type=file>`), Bibliothek nur für die Sitzung (`Library.session`, mit #35 ersetzt).
- **Bau:** `app/tool/build_web_core.sh` legt Kern, Hülle und Worklet nach `app/web/wp_core/`, dann `flutter build web`. CanvasKit kommt von der eigenen Seite (`web/flutter_bootstrap.js`).
- **Prüfung:** `app/tool/web_core_check.sh` baut eine Prüfseite mit den Diensten der Web-App, die eine erzeugte Sinusdatei und `sine440.m4a` lädt und Position, Pegel, Wellenform, Tempo (0,5× und 1,5×), Loop-Sprung, Seek und Metronom misst.
- **Laden ohne Aussetzer (#42):** Der Worker `wp_loader.js` dekodiert mit einer eigenen Instanz von `wp_core_web.wasm` (`wp_web_track_decode`, für AAC/M4A `wp_web_track_convert` nach `decodeAudioData` im Hauptthread) und berechnet die Wellenform. Ins Worklet geht nur das fertige PCM (Stereo, Rate des AudioContext); es übernimmt es in Stücken von 32 768 Frames nach jedem Block (`wp_web_pcm_begin/append/commit`), der bisherige Titel spielt bis zur Übernahme weiter. Gemessen in Chrome mit einer WAV von 3 Minuten: Laden ca. 0,8 s, Worklet höchstens 1 ms am Stück beschäftigt, Klickabstände 0,488–0,500 s; vorher (Kern dekodiert im Worklet) 29 ms am Stück.
- **Dauer in der Bibliothek (#42):** Im Browser kennt die Bibliothek die Dauer beim Import nicht; nach dem ersten Laden übernimmt sie die Dauer aus dem Kern und speichert sie sofort.
- **Hinweise:** Ohne Titel nennen Player und leere Bibliothek im Browser die Dateiauswahl des Browsers (`openFileHintBrowser`, `emptyLibraryHintBrowser`).
- **Prüfung #42:** `app/tool/web_core_check.sh` misst zusätzlich Metronom und Wiedergabe gegen die Wanduhr während des Ladens, MP3/WAV/FLAC/M4A, eine kaputte Datei und die Dauer, auch nach dem Neuladen der Seite (die Seite lädt sich dazu einmal selbst neu). Eine Kontrollmessung lädt auf dem alten Weg und zeigt, dass die Messung ein blockiertes Worklet erkennt.

### W3 – Speicher-Schicht und Bibliothek ohne Pfade (3–4 Tage)
- `FileStore`-Schnittstelle (`file_platform.dart` wird dazu ausgebaut): Desktop = Dateisystem, Web = OPFS. Import im Web über Dateiauswahl.
- Titel verweisen über ID (Hash) auf Dateien, nicht über Pfade. Auf dem Desktop bleibt der Pfad als gerätelokale Zusatzinfo.
- `navigator.storage.persist()` anfordern, Speicherverbrauch und Obergrenze anzeigen.

#### Umsetzung W3 (#35)

- **Speicher-Schicht:** `FileStore` (`file_platform.dart`) mit Namen relativ zur Bibliothek (`library.json`, `Tracks/<id>.<ext>`). `IoFileStore` (`file_store_io.dart`) im App-Ordner wie bisher, `OpfsFileStore` (`file_store_web.dart`) im Ordner `WoodshedPlayer` des OPFS; Schreiben über `createWritable()` ist atomar, Schreib- und Löschvorgänge laufen nacheinander. `Library` kennt nur noch den Store, kein `dart:io` mehr.
- **Titel-ID:** Jeder Titel trägt `contentHash` (SHA-256, Paket `crypto`). Die UUID bleibt interne `id` und Dateiname, damit `library.json` für die Swift-App lesbar bleibt (sie überliest das Zusatzfeld). Alte Bibliotheken bekommen den Hash nach dem Öffnen im Hintergrund (Dateisystem: eigenes Isolate, Datei in Stücken gelesen). Ein Import mit bekanntem Hash legt keine zweite Datei an (`ImportResult.duplicates`). Die volle Umstellung der ID folgt mit W4 (#36), siehe dort; der Hash im Hintergrund entfällt damit.
- **Pfade:** Auf Desktop und Handy liefert der Store den gerätelokalen Pfad (Audio-Kern, Cover); im Browser gibt es keinen, der Kern liest die Bytes aus dem OPFS.
- **Dateiauswahl im Web:** übergibt die Bytes einmal an die Bibliothek, die sie im OPFS ablegt; der Titel bleibt nach Neuladen. Die Dauer kennt erst der Kern beim Laden; die Bibliothek übernimmt sie dann (#42).
- **Speicher:** Sobald die Bibliothek Titel hat, fragt sie einmal `navigator.storage.persist()` an (nur im Browser). Im Fuss der Bibliothek steht der Verbrauch, im Browser mit freiem Platz aus `estimate()` und ob der Speicher dauerhaft ist.
- **Prüfung:** `app/tool/web_store_check.sh` baut eine Prüfseite (Import einer erzeugten Sinusdatei, OPFS, Hash, Doppel, Abspielen, Neuladen, Speicherzeile).

### W4 – Datenmodell für den Abgleich (3–4 Tage)
- Stempel, Grabsteine, Gerät-ID, Versionsnummer, Migration von `library.json`.
- Trennung geteilt/gerätelokal bei den Einstellungen.
- Reine Dart-Logik, deshalb gut testbar (siehe Tests).

#### Umsetzung W4 (#36)

- **Format 2:** `library.json` = `{formatVersion: 2, settings, folders, tracks}`, Ordner und Titel als Abbildung ID → Eintrag `{values, stamps, deleted?}`. Die Titel-ID ist der SHA-256 der Audiodatei, Dateien heissen `Tracks/<hash>.<ext>` und `Tracks/<hash>.artwork`. Ordner behalten ihre UUID.
- **Stempel** (`app/lib/library/stamps.dart`): `Hlc` (Millisekunden, Zähler, Gerät-ID, Text `millis-zähler-gerät`), `HlcClock` steigt auch bei zurückgestellter Uhr. Jedes geteilte Feld hat einen Stempel; Loop-Anfang, -Ende und -Schalter bilden ein Feld, damit sich Grenzen zweier Geräte nicht mischen. Ein entfernter Wert (z. B. Artist) ist ein gestempeltes `null`. `Library` vergleicht beim Speichern mit dem letzten Stand und stempelt nur Geändertes.
- **Zusammenführen:** `StampedRecord.merge` und `SharedState.merge` sind rein (ohne Ein-/Ausgabe), kommutativ, assoziativ und idempotent (Zufallstest). #37 baut darauf auf; `Library.state` liefert den Stand.
- **Grabsteine:** Löschen setzt `deleted`, die Werte bleiben. Lebendig ist ein Eintrag, wenn ein Feldstempel jünger ist als `deleted`; ein erneuter Import belebt ihn. Nach 90 Tagen fällt der Grabstein beim Laden und beim Abgleich weg. Ein Titel in einem anderswo gelöschten Ordner erscheint ohne Ordner.
- **Bereinigungs-Horizont (#98):** Damit ein Gerät, das länger als 90 Tage nicht abgeglichen hat, gelöschte Titel und Ordner nicht wiederbelebt, merkt sich der Stand beim Bereinigen den Stempel der jüngsten entfernten Löschung (`purged` in `library.json` und `state.json`). Kennt beim Zusammenführen nur eine Seite einen Eintrag, gilt er gegenüber dem Horizont der anderen Seite als gelöscht, ein Grabstein mit dem Horizont als Löschstempel: Wurde er zuletzt vor dem Horizont geändert, ist er danach gelöscht und fällt beim nächsten Bereinigen weg; jüngere Einträge bleiben lebendig. Das Ergebnis hat den höheren Horizont. Weil das wie ein gewöhnlicher Grabstein zusammengeführt wird, bleibt das Zusammenführen kommutativ, assoziativ und idempotent. Es braucht keine Uhr; die Zeit kommt nur beim Bereinigen dazu (`now` des Geräts minus 90 Tage).
  - **Folge (Entscheid in #98):** Ein Eintrag, der auf einem Gerät vor dem Horizont entstand oder zuletzt geändert wurde und nie abgeglichen wurde, geht beim Abgleich verloren, samt Audiodatei auf diesem Gerät. Hat noch kein Gerät einen Grabstein bereinigt, gibt es keinen Horizont und nichts geht verloren; der Horizont liegt nie später als 90 Tage vor dem Bereinigen. Ein erneuter Import derselben Audiodatei (neuer Stempel) belebt den Titel wieder.
  - Ein bereinigter toter Eintrag kann Feldwerte gehalten haben, die ein lange offline gewesenes Gerät noch kennt. Belebt eine jüngere Änderung den Eintrag, bringt dieses Gerät die Werte beim nächsten Abgleich zurück; der gemeinsame Endstand stellt sich dann eine Abgleichrunde später ein.
- **Migration** (`migration.dart`, gleiche Logik für Dateisystem und OPFS): Sicherung `library.v1.json`, dann die Zuordnung alte UUID → Hash in `library.v1-ids.json` (aus `contentHash` von #35, sonst berechnet), dann Umbenennen, zuletzt `library.json` im Format 2. Bricht sie ab, setzt der nächste Start dort fort. `preferences.json` und `metronome.json` werden übernommen und bleiben liegen. **Die Swift-Kompatibilität entfällt:** Das Swift-Altprojekt kann die Bibliothek danach nicht mehr öffnen.
- **Version:** Eine Datei mit höherer `formatVersion` wird nicht geschrieben (auch nicht über Import oder Löschen), die Oberfläche meldet «App aktualisieren» (`libraryTooNew`).
- **Trennung:** Geteilt (in `library.json`): Titeldaten, Ordner, Loops, Tempo, Steigerung, Metronom-Voreinstellungen, Darstellung, Sortierung. Gerätelokal: `device.json` mit der Gerät-ID; Cloud-Konto, Tokens, Cache-Obergrenze, Fensterlage und Ausgabegerät kommen dort hinzu, Dateipfade leitet der Store ab.
- **Gelöst in #37:** Ein Titel ohne lokale Datei, der auf einem anderen Gerät importiert wurde, bleibt sichtbar.

### W5 – Sync-Engine (4–5 Tage)
- `CloudProvider`-Schnittstelle, `InMemoryProvider` für Tests, `NoSync` ohne Konto.
- Zusammenführen, bedingtes Schreiben, Wiederholung mit Backoff, Offline-Warteschlange, Fortschritt je Datei.
- Auslöser: Start, Rückkehr in den Vordergrund, Änderung (verzögert zusammengefasst), Knopf «Jetzt abgleichen».
- Audio: bei Bedarf laden (Handy), im Hintergrund hochladen (Desktop). Schutz vor Endlosschleifen bei Teilfehlern.
- **Pro Titel «nicht hochladen»:** gemeinsames Feld mit Stempel; der Titel bleibt in der Bibliothek der anderen Geräte sichtbar, mit «Datei nur auf einem Gerät».
- **Pro Ordner «synchronisieren»:** Feld am Ordner (geteilt); Titel in nicht gewählten Ordnern werden nicht hochgeladen, ihre Metadaten wandern trotzdem mit.
- **Sicherung:** Vor jedem Schreiben von `state.json` wird der bisherige Stand nach `backup/state-<n>.json` (rotierend, 5 Stück) kopiert. Wiederherstellen über Einstellungen → Cloud.

#### Umsetzung W5 (#37)

- **Schnittstelle** (`app/lib/sync/cloud_provider.dart`): `CloudProvider` mit `list(prefix)`, `get`, `put` (mit `ifVersion` bzw. `ifAbsent`, sonst `VersionConflict`), `delete`, `quota`. Fehlerarten: `CloudOffline` (ganzer Abgleich wartet), `CloudError` (eine Aufgabe wird wiederholt). `InMemoryProvider` für Tests kann offline gehen, Uploads abbrechen und zwischen Lesen und Schreiben ein anderes Gerät schreiben lassen.
- **Ohne Konto** erzeugt die App `NoSync` (`sync_service.dart`, ohne Import der Engine oder eines Anbieters); ein Test prüft den Importgraphen und dass kein `HttpClient` entsteht. Mit Konto (#38/#40) kommt `CloudSync` (`sync_engine.dart`), dann per bedingtem bzw. verzögertem Import.
- **Ablauf eines Abgleichs:** `state.json` lesen, mit `Library.mergeRemote` zusammenführen (rein, je Feld), nur bei Unterschied schreiben: zuerst den bisherigen Inhalt nach `backup/state-<n>.json` (Platz = Generation mod 5 + 1, die Generation steht in `state.json`), dann bedingt auf die gelesene Version; bei Konflikt neu lesen, zusammenführen, höchstens 5-mal. Danach `audio/` auflisten und planen: fehlende Dateien hochladen, Dateien gelöschter oder ausgeschlossener Titel löschen (nur Hashes, die `state.json` kennt), am Desktop fehlende herunterladen, sonst beim Abspielen (`fetchAudio`). Heruntergeladenes wird gegen den Hash geprüft.
- **Warteschlange:** Aufgaben `state`, `up:`, `down:`, `rm:` je Hash mit Versuchszähler und Backoff (2 s verdoppelnd, höchstens 5 min); nach 5 Fehlversuchen ruht eine Aufgabe bis «Jetzt abgleichen» (#40) oder zum nächsten Start. Ohne Verbindung wartet der ganze Abgleich, höchstens 8 automatische Wiederholungen, danach nur noch Auslöser. Die Warteschlange wird bei jedem Abgleich aus Bibliothek und Cloud neu abgeleitet, darum braucht sie keine eigene Datei: Offline-Änderungen stehen in `library.json` und gehen beim nächsten Abgleich mit.
- **Loops:** Jeder Loop ist ein eigenes Feld `loops.<id>` (`{start, end}`, `null` = gelöscht), dazu `activeLoop` und `loopEnabled`. Zwei Geräte, die je einen Loop setzen, behalten beide; der zuletzt gesetzte wird angezeigt. Der eine Loop aus Format 2 vor #37 bekommt die feste ID `0`.
- **Schalter:** `noUpload` am Titel und `sync` am Ordner (Standard an) sind geteilte Felder mit Stempel, bedienbar im Kontextmenü. Ein Titel, dessen Datei hier fehlt und der auf einem anderen Gerät importiert wurde, bleibt sichtbar; liegt die Datei auch nicht in der Cloud, steht «Datei nur auf einem Gerät». Fehlt die Datei eines hier importierten Titels, fällt er wie bisher weg.
- **Auslöser:** Start (`AppController.start`), Rückkehr in den Vordergrund (`AppLifecycleListener`), Änderung (`Library.onLocalChange`, 5 s verzögert und zusammengefasst). Der Knopf «Jetzt abgleichen» (`syncNow`) und die Wiederherstellung aus `backup/` kommen mit #40.

### W6 – Anbieter und Anmeldung (6–9 Tage)
Abgelöst durch `docs/KONZEPT-SYNC.md` (Mischform): Google Drive #54, OneDrive #55, direkte Verbindung #56; Dropbox entfällt.
- Je Anbieter ein Modul über die REST-API mit dem Paket `http`, ohne grosse SDKs:
  - **Google Drive:** Bereich `drive.file` (nur Dateien, die die App selbst anlegt), eigener Ordner.
  - **OneDrive:** Microsoft Graph, Bereich `Files.ReadWrite.AppFolder`, Sitzungen für grosse Dateien.
  - **Direkte Verbindung:** gekoppelte Geräte ohne Konto, Verbindungsaufbau über öffentliche Relays und STUN-Server, Ende-zu-Ende verschlüsselt.
- OAuth mit PKCE: Desktop im Systembrowser mit lokalem Loopback-Empfänger, Web per Weiterleitung auf die Pages-Adresse.
- **App-Registrierung** bei Google und Microsoft (öffentliche Client-IDs, kein Geheimnis im Code). Das legst Du an, die IDs kommen in die Konfiguration.
- Token-Ablage: Desktop im Schlüsselbund bzw. Credential Store, Web in IndexedDB. Ziel sind Refresh-Tokens, wo der Anbieter sie für Web-Apps ausgibt (OneDrive). Bei Google gibt es ohne eigenen Server nur kurzlebige Zugriffstokens, deshalb stille Neuanmeldung, im Zweifel ein Tippen.
- Kontingent anzeigen, Warnung bei fast vollem Speicher.
- **Ablage und Netzwerkprüfung (#58):** Alle Anbietermodule und jeder andere Netzwerkcode liegen in `app/lib/sync/providers/`, nur dort erlaubt `make network-free` Netzwerkpakete und Verbindungen. Die Web-App erlaubt Verbindungen per Content Security Policy (`app/web/index.html`) nur zur eigenen Seite und zu den API- und Anmelde-Hosts von Google und Microsoft; weitere Hosts (z. B. Download-Adressen von OneDrive, Relays der direkten Verbindung) kommen mit dem jeweiligen Issue in die Liste und den Test. Einzelheiten in `docs/TESTS.md`.

### W7 – PWA und Handy-Bedienung (4–6 Tage)
- Manifest, Icons, Service Worker (Offline-Start der App-Hülle), Hinweis «Zum Home-Bildschirm» für iOS.
- Audio-Freischaltung per Berührung, Media Session (Sperrbildschirm, Kopfhörertasten), Wake Lock beim Üben.
- Cache-Verwaltung: Obergrenze, Entfernen der ältesten Titel, «Offline halten», Anzeige «nur in der Cloud».
- Aufnahme-Knopf bleibt unsichtbar; Datei-Import über Auswahl.

### W8 – Einstellungen, Oberfläche, Desktop (3–4 Tage)
Abgelöst durch M5 in `docs/KONZEPT-SYNC.md`: die Oberfläche wächst in #54, #55 und #56 mit (#40 geschlossen).
- Bereich «Abgleich» in den Einstellungen: Weg wählen (Google Drive, OneDrive, direkte Verbindung), anmelden bzw. koppeln, abmelden bzw. entkoppeln, Status je Gerät, letzter Abgleich, Fehler.
- Abmelden bzw. Entkoppeln entfernt Tokens und Schlüssel, lässt alle lokalen Daten stehen und beendet jeden Netzverkehr.
- Desktop: Audio aus der Cloud wird in den Datenordner der App geladen; vorhandene lokale Ordner werden nur hochgeladen, nicht verschoben.
- Beim ersten Anmelden fragt die App, welche Ordner synchronisiert werden (Auswahlliste mit Grösse); später je Ordner umschaltbar. Zeigt vorab die Datenmenge und das freie Kontingent.

### W9 – Auslieferung, CI, Dokumente (2–3 Tage)
- GitHub Actions: Web-Build, Tests, Veröffentlichung auf GitHub Pages bei Tag; Windows und Linux laufen wie im Umbauplan.

#### Umsetzung W9 (#41)
- **Adresse:** <https://ingen63.github.io/Woodshed-Player/app/>; die Startseite (#50) hat den Knopf «App öffnen». Datenschutz, Nutzungsbedingungen und `/w0/` bleiben an der Wurzel.
- **Workflow** `.github/workflows/pages.yml`: läuft bei jedem Push auf `main` und veröffentlicht die ganze Seite; ein Tag `v*` startet ihn auf `main` neu, weil die Umgebung `github-pages` nur `main` veröffentlichen lässt. Die App darin kommt aus dem letzten Tag (`git describe --tags --abbrev=0`): Checkout dieses Stands, WASM-Kern mit Emscripten bauen (`app/tool/build_web_core.sh`), unter Node.js prüfen (`wp_core_web_test.mjs`), `flutter test`, dann `flutter build web --base-href /Woodshed-Player/app/` mit Tag und Datum für den Info-Dialog. Ohne Tag fehlen App und Knopf. Neue App-Stände erscheinen also nur mit einem neuen Tag, Text-Korrekturen sofort.
- **COOP/COEP:** `app/web/sw.js` setzt die Header auf alle Antworten der eigenen Seite (Verfahren wie W0); `index.html` registriert ihn vor dem Start von Flutter und lädt beim ersten Besuch einmal neu. Danach ist die Seite «cross-origin isolated» und hat `SharedArrayBuffer`. W7 (#39) erweitert denselben Service Worker um den Offline-Start.
- `README.md`: Funktionstabelle, Plattformen, Datenschutz (neuer Abschnitt Cloud und Hosting).
- `UMBAUPLAN-FLUTTER.md` nachführen: Zieltabelle, Phase 6 und Abschnitt «Android» ersetzen durch Verweis hierher.
- `CLAUDE.md`: Regel «Kein Netzwerk» um die Ausnahme erweitern (siehe unten).

**Gesamt:** ca. 35–50 Arbeitstage. Nach W0 lässt sich der Rest sicherer schätzen.

## Datenschutz und Regeln

- Ausnahme für «Kein Netzwerk» (in `CLAUDE.md` seit #41, Fassung aus `docs/KONZEPT-SYNC.md`): *«Netzwerkzugriff nur für den Abgleich und nur nach ausdrücklicher Wahl: zum gewählten Cloud-Anbieter (Google Drive oder OneDrive) nach Anmeldung, oder zu gekoppelten Geräten, mit Verbindungsaufbau über öffentliche Relays und STUN-Server. Dazu das Laden der Web-App selbst. Kein Tracking.»*
- Beim Laden der Web-App sieht GitHub die IP-Adresse (wie bei jeder Webseite). Die App selbst sendet nichts ausser an den gewählten Anbieter bzw. an gekoppelte Geräte (über Relays und STUN-Server).
- **Neue Abhängigkeiten (nur nach Rückfrage, alle MIT-verträglich):** `http` (BSD-3), `web` (BSD-3), `flutter_secure_storage` (BSD-3), `crypto` (BSD-3, SHA-256), ggf. `url_launcher` (BSD-3). Emscripten (MIT/UIQ) ist nur Werkzeug.
- Testdaten ohne echte Namen, Titel oder Konten. Cloud-Tests laufen gegen den `InMemoryProvider` und aufgezeichnete Antworten, nie gegen echte Konten.

## Tests (je Issue mit `#Nr/AKn`)

| Bereich | Art | Beispiele |
|---|---|---|
| Zusammenführen | Unit, auch zufällig (Fuzzing, Reihenfolge der Eingaben vertauscht) | gleiche Eingaben → gleiches Ergebnis, Idempotenz, Grabstein gegen jüngere Änderung, Loops elementweise |
| Migration | Unit | altes `library.json` → neues Format, nichts geht verloren, Rückwärts-Version wird abgelehnt |
| Sync-Engine | Unit mit `InMemoryProvider` | Offline-Warteschlange, ETag-Konflikt, Abbruch mitten im Upload, kein Netz ohne Konto |
| Anbieter | Unit mit aufgezeichneten Antworten | Seitenweises Auflisten, Fehlercodes, Token abgelaufen |
| Kern (WASM) | `ctest` über Node.js | Tempo, Loop-Grenzen, Seek wie nativ |
| Web | Flutter-Tests plus Test auf echten Geräten | Handy-Layout, Cache-Obergrenze; Sperrbildschirm und Stummschalter von Hand |

## Risiken

| Risiko | Wirkung | Gegenmassnahme |
|---|---|---|
| iOS beendet oder pausiert Web Audio bei Sperrbildschirm oder Hintergrund | Übe-Player unbrauchbar auf dem iPhone | W0 zuerst; Umweg über `<audio>` und Media Session; sonst neu entscheiden (z. B. natives iOS) |
| Stummschalter macht Web Audio stumm | Wirkt wie Fehler | Umweg über `<audio>`-Element, in W0 prüfen |
| COOP/COEP auf GitHub Pages | Kein `SharedArrayBuffer`, Kern läuft nicht | Service-Worker-Verfahren, sonst Wechsel zu Cloudflare Pages/Netlify (gleiche Dateien) |
| iOS räumt PWA-Speicher | Titel lokal weg | `persist()`, Titel aus der Cloud nachladen, Hinweis bei Löschung |
| Google ohne Server: nur kurzlebige Tokens | Gelegentliche Neuanmeldung | Stille Erneuerung, klare Anzeige; OneDrive oder direkte Verbindung als Alternativen |
| Grosse Audiodateien im Browser | Speicher- und Zeitlimits beim Dekodieren | Streaming-Dekodierung im Kern, Dateien in Blöcken hochladen |
| Cloud-Kontingent knapp (z. B. 15 GB bei Google) | Upload schlägt fehl | Anzeige, Warnung, später Schalter «nicht hochladen» pro Titel |
| Kernänderungen brechen Web oder Desktop | Doppelte Fehler | `ctest` gegen beide Ziele in CI |
| Anbieterregeln ändern sich (OAuth, API) | Wartungsaufwand | Dünne Provider-Module, je Anbieter austauschbar |

## Folgen für bestehende Issues (zur Freigabe)

| Issue | Vorschlag |
|---|---|
| #25 Android-Plattform mit Hintergrundwiedergabe | schliessen als «not planned», ersetzt durch die Web-App |
| #18 Plattform-Integration | iOS/Android-Teile streichen, Desktop-Teile behalten |
| #16 Bibliothek und Datenmodell | bleibt, W4 baut darauf auf |

## Issues (Reihenfolge)

1. #32 Machbarkeitstest Web-Audio auf iPhone und Android (W0)
2. #33 Audio-Kern als WASM (W1)
3. #34 Dart-Anbindung für das Web (W2)
4. #35 Speicher-Schicht mit OPFS, Titel-ID statt Pfad (W3)
5. #36 Datenmodell mit Änderungsstempeln und Migration (W4)
6. #37 Sync-Engine mit Zusammenführen (W5)
7. #38 Cloud-Anbieter Google Drive, OneDrive (W6; aufgeteilt in #54, #55, #56)
8. #39 PWA und Handy-Bedienung (W7)
9. #40 Cloud-Einstellungen in der Oberfläche (W8)
10. #41 Auslieferung auf GitHub Pages, README und Regeln (W9)

Jedes Issue bekommt Abnahmekriterien als Häkchen-Liste (Skill `issue`). Die Abnahmekriterien von W0 sind die fünf Prüfpunkte oben.

## Offene Punkte

Entschieden am 19.11.2026: Schalter pro Titel in W5, Desktop-Ordner nur auf Wunsch, 5 Sicherungsstände, GitHub-Pages-Adresse (siehe Entscheidungen).

1. **Anbieter-Registrierungen** (Google Cloud, Microsoft Entra) legst Du an, bevor W6 beginnt. Die OAuth-Weiterleitung zeigt auf die GitHub-Pages-Adresse; sie muss deshalb vorher feststehen (Kontoname und Repo-Name).
2. **Veröffentlichung:** GitHub Pages braucht ein öffentliches Repo (oder bezahlten Plan). Das Repo ist MIT-lizenziert; vor der Veröffentlichung prüfen, dass keine privaten Daten drin sind.
