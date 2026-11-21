# Teststrategie

Gilt für die Flutter-App (`app/`) und den C++-Audio-Kern (`core/`). Das Swift-Altprojekt (`WoodshedPlayer/`,
`WoodshedPlayerTests/`) bleibt, wie es ist, und wird hier nur als Plattform erwähnt. Vorbild ist das Testkonzept von
VivaPlan.

## Grundsatz

- **Die Regeln sind die Referenz, nicht das alte Programm.** Massgebend sind die Funktionstabelle in `README.md` und die
  Abnahmekriterien der Issues (z. B. «Tempo 0,1× – 2× in 0,05er-Schritten», «Ende mindestens 1 s nach dem Anfang»,
  «Klicks bei 120 BPM genau 22 050 Samples auseinander»).
- **Jede Regel hat mindestens einen Fall mit hergeleitetem Erwartungswert.** Der Erwartungswert wird von Hand aus der
  Regel gerechnet und steht mit der Rechnung im Kommentar, nicht aus einem Lauf des Programms abgeschrieben. Beispiel:
  2 s Testaudio bei Tempo 0,5 ergeben 2 / 0,5 = 4 s Ausgabe; ein 440-Hz-Sinus bleibt 440 Hz.
- **Ein Test prüft konkrete Werte.** Ein Test, der Code nur ausführt, zählt nicht.
- **Tests nennen ihr Kriterium** als `#22/AK2` im Namen, im Kommentar oder im Titel einer `group(...)`.
- **Testaudio wird erzeugt** (Sinus, Rampe, Stille, Klicks) oder ist CC0 mit Quelle. Die drei kleinen Dateien in
  `core/tests/audio/` erzeugt `core/tools/make_test_audio.sh`. Tests berühren nie die echte Bibliothek, sondern
  arbeiten in temporären Ordnern.
- **Oberflächentests** prüfen auf ARB-Schlüssel oder setzen die Sprache fest, nie auf die Systemsprache.

## Schichten

| Schicht | Wo | Was geprüft wird | Stand |
|---|---|---|---|
| 1 Einheiten | `app/test/*_test.dart`, `core/tests/*_tests.cpp` | Zeitformat, Bibliothek, Stempel und Zusammenführen, Metadaten, Player-Service, Metronom-Logik, Engine, Befehls-Queue, Wellenform | vorhanden |
| 2 Audio-Referenzfälle | `core/tests/reference_tests.cpp` über die C-API, dazu `engine_tests.cpp`, `metronome_tests.cpp`, `player_tests.cpp`; im Web dieselben Fälle unter Node.js (`core/build-wasm`), Vergleich der Samples nativ ↔ Web | Offline-Rendering ohne Audiogerät: Loop-Naht, Seek und Pause, Tempo und Tonhöhe, Klickpositionen, jede Funktion von `wp_core.h` | vorhanden (#9) |
| 3 Invarianten und Zufallstests | `app/test/property/` (`property.dart`, Regressionsfälle in `regressions.json`) | Eigenschaften über viele zufällige Fälle mit festem, ausgegebenem Startwert: Bibliothek, Loop-Grenzen, Zeitformat, Abgleich auf 2–4 Geräten | vorhanden (#10) |
| 4 Robustheit und Fuzzing | `metadata_test.dart` («Unsinn»), `player_tests.cpp` (Ladefehler, abgeschnittene Dateien), `library_files_property_test.dart`, `sync_property_test.dart`, `core/tests/fuzz/` (`make fuzz`); alle Kerntests unter ASan/UBSan und TSan (`make sanitize`, `make sanitize-thread`) | verfälschte Dateien, libFuzzer auf Decoder und C-API, Sanitizer | vorhanden (#57, #10) |
| 5 Golden-Dateien | `app/test/golden/` (`library.json` jeder Version: Swift alt und neu, Format 2 von #36 und #37), `golden_files_test.dart`, `core/tests/golden/metronome_positions.txt` | jede Version liest alle alten Stände; Klickpositionen des Metronoms (#9) | vorhanden (#9, #10) |
| 6 Oberfläche | Widget-Tests in `app/test/`, Oberflächentests mit echtem Kern in `app/integration_test/` (Rauchtest, Tastenkürzel, Pseudo-Sprache), Web-Tests im Chrome `app/test/web/`, Rauchtest der gebauten App `tools/smoke_app.sh`, Prüfseiten im Browser `app/tool/web_*_check.dart` | Layout je Grösse, Bedienung, Texte, Tastenkürzel, OPFS und WASM-Anbindung im Browser | vorhanden (#13) |
| Werkzeuge | `app/tool/after_commit_hook_test.dart`, `coverage_test.dart`, `pre_push_hook_test.dart`, `mutants_test.dart` | Hook nach dem Commit, Abdeckung je Teil, `coverage-diff`, `pre-push`, Mutationswerkzeug | vorhanden (#7, #8, #11) |

## Testmatrix und QA-Abgleich

Stand 20.11.2026, abgeglichen gegen `app/test/`, `app/integration_test/` und `core/tests/` (dazu die Web-Prüfungen in
`core/web/` und `app/tool/`). «vorhanden» nennt die Datei und, wo hilfreich, den Fall; jede Lücke ist einem Issue
zugeordnet.

### Bibliothek

| Regel / Fall | Abgleich | Issue |
|---|---|---|
| `library.json` lesen und schreiben, Einstellungen pro Titel | vorhanden: `library_test.dart` (#16/AK2) | – |
| Altes Format der Swift-App (`[Track]` und `{folders, tracks}`), Schlüssel aus `preferences.json` | vorhanden: `library_test.dart` (#21/AK4), `app/test/golden/library_swift*.json` | – |
| Format 2 mit Stempeln, Grabsteine 90 Tage, Migration mit Sicherung, neuere Datei bleibt unverändert | vorhanden: `data_model_test.dart` (#36/AK2–AK5) | – |
| Import mit Kopie, Metadaten (ID3v1/v2.2/v2.3, FLAC, Cover), Titel aus Dateiname | vorhanden: `library_test.dart` (#16/AK4), `metadata_test.dart` | – |
| Titel-ID SHA-256, dieselbe Datei nur einmal, Speicher-Schicht Dateisystem und OPFS | vorhanden: `file_store_test.dart` (#35/AK1–AK5) | – |
| Sortierung (alphabetisch natürlich, hinzugefügt, eigene), Ordner, Verschieben | vorhanden: `library_test.dart` (#16/AK5, `naturalCompare`) | – |
| Titel und Artist bearbeiten, leerer Titel nicht möglich | vorhanden: `track_edit_test.dart` (#24) | – |
| Sortieren und Verschieben verlieren und verdoppeln keinen Titel; Speichern und Laden ergibt denselben Stand (Zufallstests) | vorhanden: `property/library_property_test.dart` (#10/AK1) | – |
| Verfälschte `library.json` (Typwechsel, fehlende Felder, falsche Verweise, Extremwerte, abgeschnitten) ohne Absturz, mit Meldung | vorhanden: `property/library_files_property_test.dart` (#10/AK3) | – |
| Golden-Dateien jeder Version (auch Format 2), Migration idempotent | vorhanden: `golden_files_test.dart` (#10/AK5), `property/library_files_property_test.dart` (#10/AK8) | – |
| 10'000 Titel in 500 Ordnern: Laden, Sortieren, Speichern je ≤ 1 s | vorhanden, nächtlich: `app/bench/library_bench_test.dart` (#59/AK3), `make bench` | – |

### Wiedergabe

| Regel / Fall | Abgleich | Issue |
|---|---|---|
| Laden WAV sampelgenau, FLAC, MP3; Dauer ohne Laden | vorhanden: `player_tests.cpp` (`loadsWavSampleExact`, `loadsFlac`, `loadsMp3`, `fileDurationWithoutLoading`) | – |
| Laden im Hintergrund, neueres Laden ersetzt laufendes, Fehler mit Code und englischem Text | vorhanden: `player_tests.cpp` (`loadRunsInBackground`, `newerLoadReplacesRunningLoad`, `loadErrorsHaveCodeAndText`, `errorMessagesAreEnglishAscii`), `player_service_test.dart` (#15/AK3), `core_error_texts_test.dart` (#46) | – |
| Play, Pause, Seek, ±15 s, Lautstärke, Dateiende | vorhanden: `engine_tests.cpp` (`seekSetsPositionAndFirstSample`, `endOfFileStopsAndRestarts`, `volumeScalesDirectOutput`), `player_service_test.dart` (#15/AK1) | – |
| Gerätewechsel pausiert, Position bleibt | vorhanden: `player_tests.cpp` (`devicePolicy`, `deviceChangePausesAndKeepsPosition`) | – |
| Render-Pfad ohne Speicheranforderung und ohne Sperre, Befehle aus vielen Threads | vorhanden: `engine_tests.cpp` (`renderDoesNotAllocate`, `commandsFromManyThreadsWhileRendering`, Queue-Fälle), `realtime_tests.cpp` (#57/AK4, `Player::render` mit Tempo, Loop, Metronom), `player_tests.cpp` (`controlFromSecondThreadWhileRendering`, #57/AK2) | – |
| Wellenform (Minimum/Maximum je Abschnitt, Grenzen) | vorhanden: `waveform_tests.cpp`, `wp_waveform_ffi_test.dart`, `web_binding_test.dart` (#34/AK3) | – |
| Seek auf t beginnt bei Sample round(t × Abtastrate); Pause und Fortsetzen ohne verlorenes Sample | vorhanden: `reference_tests.cpp` (#9/AK3, Rampe, t knapp unter und über einem halben Sample, im Stand und beim Spielen) | – |
| Abgeschnittene oder falsche Audiodateien, Fuzzing von Decoder und C-API | vorhanden: `player_tests.cpp` (`truncatedAndWrongAudioFiles`, #10/AK3), `core/tests/fuzz/` mit Wiederholung von Korpus und Regressionsfällen in jedem Build (`fuzz_*_replay`), `make fuzz` (#10/AK4), dieselben Eingaben gegen den WASM-Kern (`make test-wasm`, `make fuzz-wasm`, #67; Funde mit `make fuzz-wasm-findings`, #88) | – |
| AddressSanitizer, UBSan, ThreadSanitizer | vorhanden: `make sanitize`, `make sanitize-thread`, Selbsttest `tests/sanitizer/selftest.cpp`, Workflow `test-quality.yml` (#57) | – |
| Lange Datei (60 min): Laden, Wellenform, Rendern, Spitzenspeicher | vorhanden, nächtlich: `core/tests/bench_tests.cpp` (`bench_long_file`, #59/AK2, Grenze #75/AK2), `make bench` | – |
| Lange Titel (über 5 min): Länge aus dem Dateikopf einmal reservieren, Rückfall bei `bad_alloc`, falsche Längenangabe | vorhanden: `player_tests.cpp` (`longTitleReservesHeaderLength`, #75/AK1; `longTitleWithWrongHeaderLength`, #75/AK3), nächtlich `bench_tests.cpp` (`bench_reserve_fallback`, #75/AK1) | – |

### Tempo

| Regel / Fall | Abgleich | Issue |
|---|---|---|
| Tempo 0,1× – 2×, Schritte 0,05, Pfeiltasten | vorhanden: `engine_tests.cpp` (`rateIsClamped`), `player_service_test.dart` («Tempo in 0,05er-Schritten») | – |
| Tonhöhe bleibt, Länge = Eingabe / Rate (0,25 / 0,5 / 1,5 / 2,0) | vorhanden: `engine_tests.cpp` (`stretchKeepsPitchAndChangesLength`, `stretchIsDeterministic`, `rateChangeKeepsPositionAndSignal`, `positionFollowsRate`) | – |
| Dieselbe Prüfung für 0,1 / 0,5 / 1,0 / 2,0 mit 1 % Toleranz; Stille bleibt Stille | vorhanden: `reference_tests.cpp` (#9/AK4, #9/AK1) | – |
| Klang gegen AVAudioUnitTimePitch | vorhanden, von Hand (Hörvergleich, nicht automatisierbar): `tools/hoervergleich.sh` | – |
| Rechenzeit je Puffer ≤ 50 % des Echtzeitbudgets | vorhanden, nächtlich: `core/tests/bench_tests.cpp` (`bench_stretch`, #59/AK1), `make bench` | – |

### Loop

| Regel / Fall | Abgleich | Issue |
|---|---|---|
| Loop-Naht sampelgenau, auch mit Tempo | vorhanden: `engine_tests.cpp` (`loopSeamDirectIsSampleExact`, `stretchLoopHasNoGap`) | – |
| Ende ≥ Anfang + 1 s, Loop am Dateiende, zu kurzer Loop, Seek aus dem Loop springt zum Anfang | vorhanden: `engine_tests.cpp` (`loopAtFileEndIsClamped`, `shortLoopIsIgnored`, `seekOutsideLoopJumpsToLoopStart`), `player_tests.cpp` (`loopBoundsWithLoadedFile`), `player_service_test.dart` | – |
| Durchgänge zählen nur beim Sprung vom Ende, nicht bei Seek | vorhanden: `engine_tests.cpp` (`loopPasses*`), `player_service_test.dart` (#29/AK2) | – |
| Steigerung nach Durchgängen (Stufen, Ziel, Zurücksetzen, Speichern) | vorhanden: `loop_ramp_test.dart` (#29), `player_service_test.dart` (#29), `library_test.dart` (#29/AK7) | – |
| Marker ziehen, Zeitfelder, S/E, Ganzer Titel | vorhanden: `home_page_test.dart` (#17/AK4), `player_view_test.dart` (#19/AK7, #19/AK9), `studio_design_test.dart` (#30/AK6) | – |
| Naht mit Rampe über 100 Durchläufe, Durchgänge zählen genau | vorhanden: `reference_tests.cpp` (#9/AK2, Blöcke 1–4096 Frames) | – |
| Grenzen nach jeder zufälligen Änderung gültig, auch nach dem Laden gespeicherter Grenzen | vorhanden: `property/player_property_test.dart` (#10/AK1) | – |

### Zeitformat

| Regel / Fall | Abgleich | Issue |
|---|---|---|
| `mm:ss` formatieren und parsen, ungültige Eingaben | vorhanden: `widget_test.dart` (`formatTime`, `parseTime`) | – |
| `parse(format(x)) == x` für zufällige Zeiten | vorhanden: `property/player_property_test.dart` (#10/AK1) | – |

### Metronom

| Regel / Fall | Abgleich | Issue |
|---|---|---|
| Klicks sampelgenau ohne Drift, Betonung je Taktart, Unterteilungen, Lautstärke ohne Knacken | vorhanden: `metronome_tests.cpp` (`beatsAreSampleExactWithoutDrift`, `accentsPerMeter`, `subdivisionsAndQuieterSubClicks`, `volumeChangeWithoutCrackle`) | – |
| Steigerung nach Takten und nach Zeit (#23), Wechsel der Betriebsart | vorhanden: `metronome_tests.cpp` (`ramp*`, `timedRamp*`, `switchingModes`), `metronome_test.dart` (#23) | – |
| Einstellungen, Tap-Tempo, Kürzel, nie gleichzeitig mit dem Titel | vorhanden: `metronome_test.dart` (#3/AK20) | – |
| 120 BPM bei 44,1 kHz: 22 050 Samples Abstand über 5 min; Betonung, Nebenakzent (6/8), Unterteilungen an den berechneten Stellen; Positionen eines festen Ablaufs als Golden-Datei | vorhanden: `reference_tests.cpp` (#3/AK7–AK10, #9/AK5, Klicks aus der Ausgabe erkannt), `core/tests/golden/metronome_positions.txt` | – |
| Wechsel der Unterteilung an der Schlaggrenze überspringt keinen Schlag | vorhanden: `metronome_tests.cpp` (`subdivisionChangeKeepsBeat`, #3/AK10, gefunden mit #9) | – |
| Taktart und Unterteilung wechseln gleichzeitig mitten im Schlag (#70): Liegt der laufende Schlag ausserhalb der neuen Taktart, klingt er aus (seine restlichen Klicks in der neuen Unterteilung, als Unterteilung dieses Schlags), der nächste Schlag ist die betonte Eins eines neuen Takts. Liegt er innerhalb, zählt der Takt weiter (#3/AK10). Die Taktart setzt den Zähler nur an einer Schlaggrenze zurück | vorhanden: `reference_tests.cpp` (#70/AK2, #70/AK3, nativ und WASM), `metronome_tests.cpp` (`meterAndSubdivisionChangeMidBeat`, Takt und Schlag) | #70 |

### Aufnahme (nur Mac)

| Regel / Fall | Abgleich | Issue |
|---|---|---|
| Start, Stopp, Fehler des Kerns statt Aufnahme, Titel nach Gebietsschema, nie auf iPhone/iPad und im Browser | vorhanden: `recording_test.dart` (#4) | – |
| Fehlermeldungen und Berechtigungsdialog mehrsprachig | vorhanden: `recording_messages_test.dart` (#44), `permission_texts_test.dart` (#49) | – |
| Ringpuffer, Schreib-Thread, WAV-Kopf (Stereo, float32, Abtastrate des Geräts), Pegel und Stille, Übernahme der Tap-Daten (interleaved, je Kanal ein Puffer, Mono, Geräteeingänge vor dem Tap) | vorhanden: `recorder_tests.cpp` (#68, `recorder_core.cpp` ohne Audiogerät) | – |
| Systemton-Aufnahme im Kern (`recorder_mac.mm`: Core Audio Process Tap, Aggregate-Device, IOProc) | Lücke: braucht echten Systemton, kein automatischer Test | #51 |

### Web/WASM

| Regel / Fall | Abgleich | Issue |
|---|---|---|
| Kern als WebAssembly: dieselben `ctest`-Fälle unter Node.js | vorhanden: `core/build-wasm` (`make test-wasm`), `core/web/web.cmake` | – |
| `wp_core_web.wasm` fürs AudioWorklet: Dekodieren, Seek, Loop, Dateiende, Tempo, PCM für AAC/M4A | vorhanden: `core/web/wp_core_web_test.mjs` (#33) | – |
| Dart-Anbindung per bedingtem Import, Wellenform im Browser | vorhanden: `web_binding_test.dart` (#34) | – |
| Auslieferung auf GitHub Pages, Service Worker für COOP/COEP | vorhanden: `web_hosting_test.dart` (#41) | – |
| Im echten Browser: Position, Pegel, Tempo, Loop, Metronom, Laden ohne Aussetzer, OPFS | automatisch: `app/test/web/web_core_test.dart`, `web_storage_test.dart` (#13/AK4, Laden, Play/Pause, Tempo, Loop, Metronom, OPFS); Pegel und Aussetzer weiter von Hand: `app/tool/web_core_check.sh`, `app/tool/web_store_check.sh` (#34, #35, #42) | – |
| Vertrag nativ ↔ Web: gleiche Samples (Toleranz 1e-6, gestreckte Tempo-Fälle 5e-2, #94), jede Funktion der C-API in einem Referenzfall | vorhanden: `reference_tests` (nativ `--dump`, WASM `--compare`), `reference_api_coverage` (#9/AK7), `core_build_flags_test.dart` (ohne FMA) | – |
| `flutter build web` und `flutter test --platform chrome` bei jedem Push mit Web-Änderung | vorhanden: Job `web` in `test-quality.yml`, `make test-web` (#13/AK4); die Web-App wird dort nur einmal gebaut, im Release-Modus in `make test-web-start` (#83) | – |
| Content-Security-Policy mit erlaubten Hosts | vorhanden: `app/web/index.html`, `app/tool/network_free_test.dart` (#58/AK4), im Browser von Hand geprüft | – |
| Gebaute Web-App startet ohne gescheiterte Anfrage, ohne fremde Hosts und ohne Konsolenfehler (fremde Hosts im Test nicht erreichbar, also wie offline) | vorhanden: `make test-web-start` (auch am Ende von `make test-web`), `app/tool/web_start_check.dart`, Tests `web_start_check_test.dart` (#72) | – |
| Web-Audio auf iPhone und Android | vorhanden unter Node.js: `core/web/w0_test.mjs`; Lücke: auf echten Geräten nur von Hand | #32 |

### Abgleich/Sync

| Regel / Fall | Abgleich | Issue |
|---|---|---|
| Zusammenführen unabhängig von der Reihenfolge und idempotent, Loops einzeln, Grabsteine | vorhanden: `sync_test.dart` (#37/AK1, #37/AK4), `data_model_test.dart` (#36/AK2) | – |
| Ohne Konto keine Verbindung | vorhanden: `sync_test.dart` (#37/AK2), `sync_app_test.dart` (#37/AK2) | – |
| Warteschlange offline, Wiederholung, Sicherungen unter `backup/`, Auslöser | vorhanden: `sync_test.dart` (#37/AK3, #37/AK6, Auslöser), `sync_app_test.dart` | – |
| «Nicht hochladen» und «Synchronisieren» im Kontextmenü | vorhanden: `sync_test.dart` (#37/AK5), `sync_app_test.dart` (#37/AK5) | – |
| Zufallsfolgen auf 2–4 Geräten: gleicher Stand, zweiter Abgleich ändert nichts, kein Verlust | vorhanden: `property/sync_property_test.dart` (#10/AK6) | – |
| Verfälschte Sync-Dateien aus der Cloud ohne Absturz und ohne Datenverlust, mit Meldung | vorhanden: `property/sync_property_test.dart` (#10/AK7) | – |
| Beschädigte `state.json` wiederherstellen: Sicherung aus `backup/` oder Stand des Geräts, ohne lokalen Verlust | vorhanden: `cloud_repair_test.dart` (#65/AK1–AK3), `property/sync_property_test.dart` (#65/AK4) | – |
| Zusammenführen von 10'000 Titeln ≤ 2 s | vorhanden, nächtlich: `app/bench/library_bench_test.dart` (#59/AK3), `make bench` | – |
| Nur die Anbietermodule (`app/lib/sync/providers/`) öffnen Verbindungen, keine Analyse- oder Werbepakete, kein Netzwerk im Kern | vorhanden: `make network-free`, `app/tool/network_free_test.dart` (#58) | – |
| Anbieter Google Drive, OneDrive, direkte Verbindung | Lücke (noch nicht umgesetzt) | #54, #55, #56 |

### Oberfläche und Sprache

| Regel / Fall | Abgleich | Issue |
|---|---|---|
| Layout Desktop/Tablet/Phone, Bibliothek, Player, Tempo, Loop, Tastatur und Dateien | vorhanden: `home_page_test.dart` (#17), `studio_design_test.dart` (#30), `player_view_test.dart` (#19) | – |
| Darstellung Hell/Dunkel/System, Info-Dialog, App-Icon, Schriftlizenzen | vorhanden: `appearance_test.dart` (#31), `about_test.dart` (#50), `app_icon_test.dart` (#6), `font_licenses_test.dart` | – |
| Jeder Schlüssel in jeder ARB-Datei, kein fester Text im Code, Zahlen nach Gebietsschema, Entwicklermeldungen englisch | vorhanden: `l10n_test.dart` (#43), `english_dev_texts_test.dart` (#45) | – |
| Rauchtest mit echtem Kern je Grösse: Start, Import, Play/Pause, Loop, Tempo | vorhanden: `app_smoke_test.dart` (#13/AK1, #17/AK7, #30/AK13), nächtlich im Job `macos`, lokal `make test-ui` | – |
| Tastenkürzel im `integration_test` (Leertaste, S, E, ←/→, M, T, ↑/↓) | vorhanden: `shortcuts_test.dart` (#13/AK1) | – |
| Pseudo-Sprache: nichts abgeschnitten, nichts läuft über | vorhanden: `pseudo_locale_test.dart`, `pseudo_l10n_test.dart` (#13/AK7) | – |
| Regeln der Oberflächentests: auf Zustände warten, feste Sprache | vorhanden: `ui_test_rules_test.dart` (#13/AK2, AK7) | – |
| Widget-Tests warten auf Zustände, ein danebengehendes Tippen scheitert | vorhanden: `pumpUntil`/`waitUntil` in `fakes.dart`, `test/flutter_test_config.dart` (#62) | – |

### Plattformen

| Regel / Fall | Abgleich | Issue |
|---|---|---|
| macOS- und iOS-Build bei jeder Änderung an Kern oder Plugin | vorhanden: Hook nach dem Commit (`.claude/hooks/after-commit.sh`), geprüft in `app/tool/after_commit_hook_test.dart` | – |
| Swift-Altprojekt: Tests und iOS-Build | vorhanden: `WoodshedPlayerTests/` über den Hook (`xcodebuild`) | – |
| Workflow `test-quality.yml`: Sanitizer-Läufe des Kerns auf Linux | vorhanden: `test-quality.yml` (Jobs `sanitize`, `sanitize-thread`), `test_quality_workflow_test.dart` (#57) | – |
| Workflow `test-quality.yml`: Fuzzing und Zufallstests nächtlich | vorhanden: Jobs `fuzz` (mit `make fuzz-wasm`, #67, nach einem Fund `make fuzz-wasm-findings`, #88) und `property`, `test_quality_workflow_test.dart` (#10); beobachtbar erst nach dem Push | – |
| Workflow `test-quality.yml`: Format, Lint, Tests, Abdeckung auf Linux je Push; macOS/iOS-Build, Oberflächentests und Rauchtest der gebauten App nächtlich | vorhanden: Jobs `checks`, `web`, `macos`, `test_quality_workflow_test.dart`, `smoke_test.dart` (#13); beobachtbar erst nach dem Push | – |
| Rauchtest der gebauten App auf Windows und Linux | Lücke | #60 |
| Windows und Linux: Build, Tests, Windows-Pfade | Lücke | #60 |

### Hygiene und Werkzeuge

| Regel / Fall | Abgleich | Issue |
|---|---|---|
| Formatierung `dart format` und `clang-format`, `make format-check` | vorhanden: `Makefile`, `core/.clang-format` (#7) | – |
| Warnungen sind Fehler: strenge Dart-Analyse, `-Wall -Wextra -Werror`, `clang-tidy` | vorhanden: `app/analysis_options.yaml`, `core/CMakeLists.txt`, `core/.clang-tidy` (#7) | – |
| GitHub-Workflows ohne Fund von `actionlint` (mit ShellCheck), in `make lint` und im Job `checks` | vorhanden: `make lint-workflows`, `test_quality_workflow_test.dart` mit Gegenprobe (#64) | – |
| Hook nach dem Commit mit eigenen Tests | vorhanden: `app/tool/after_commit_hook_test.dart` (#7/AK7) | – |
| Abdeckung je Teil mit Untergrenze, `coverage-diff`, `pre-push` mit eigenen Tests | vorhanden: `tools/coverage-min`, `tools/git-hooks/pre-push`, `app/tool/coverage_test.dart`, `app/tool/pre_push_hook_test.dart` (#8) | – |
| C-API (`player.cpp`) über die geteilte Bibliothek: Nullzeiger, Laden, Seek, Tempo, Loop, Wellenform, Metronom, Aufnahme im Ruhezustand | vorhanden: `core/tests/capi_tests.cpp` (#8) | – |
| Gerätehülle (`player.cpp`) von innen auf dem Null-Gerät: Meldungen von miniaudio, Neustart des Geräts, Metronom über die C-API | vorhanden: `core/tests/device_tests.cpp` (#61) | – |
| Mutationstests: Kern mit Mull, Dart-Logik mit eigenem Werkzeug, `make mutants`, `make mutants-diff`, Job `mutants-diff` | vorhanden: `app/tool/mutants*.dart`, `core/tests/mutants/`, `tools/mutants-exclude.txt` (#11); kein offener Mutant mehr (#61, Abschnitt «Mutationstests (#11)») | – |
| Übersichtsseite Testqualität: vier Schichten mit Status, Zuordnung `#nn/AKn`, Verlauf, «keine Daten» | vorhanden: `make report`, `app/tool/report/` mit `report_test.dart`, Artefakt `test-quality-report` im Job `checks` (#12) | – |
| Netzwerkfreiheit bei jedem Push: Prüfung mit eigenen Tests | vorhanden: `make network-free`, Job `network-free` in `test-quality.yml`, `test_quality_workflow_test.dart` (#58/AK6) | – |

## Ausführen

```sh
make test           # Kern (ctest), App (flutter test) und die Tests der Werkzeuge
make test-wasm      # Kern unter Node.js (Emscripten), Referenzfälle gegen die Samples des nativen Laufs
make test-core-debug  # Kerntests im Debug-Build (core/build-debug), gleiche Toleranzen wie Release
make sanitize       # Kerntests mit AddressSanitizer und UBSan (core/build-asan)
make sanitize-thread  # Kerntests mit ThreadSanitizer (core/build-tsan)
make fuzz           # libFuzzer mit ASan/UBSan auf Decoder und C-API, FUZZ_SECONDS je Ziel (Vorgabe 60)
make fuzz-wasm      # Regressionen, Startkorpus und gewachsener Korpus von make fuzz gegen den WASM-Kern (#67)
make fuzz-wasm-findings # die Funde von make fuzz (core/build-fuzz/artifacts/) einzeln gegen den WASM-Kern (#88)
make property       # Zufallstests der App mit PROPERTY_CASES Fällen und Startwert PROPERTY_SEED
make coverage       # alle Tests mit Abdeckung, Prüfung je Teil gegen tools/coverage-min
make coverage-diff  # Abdeckung der seit BASE geänderten Zeilen (Vorgabe origin/main), ein Hinweis
make network-free   # kein Netzwerkcode ausserhalb der Anbietermodule, Sperrliste, Kern, CSP (#58)
make format         # dart format (app/) und clang-format (core/, ohne third_party)
make format-check   # schlägt fehl, wenn eine Datei nicht formatiert ist
make lint           # flutter analyze (streng), C++ mit -Werror, clang-tidy
make test-ui        # Oberflächentests mit echtem Kern auf macOS; ohne Audiogerät WP_AUDIO_BACKEND=null
make test-web       # Web-Tests in Chrome: OPFS und WASM-Kern (braucht Emscripten), danach test-web-start
make test-web-start # gebaute Web-App startet in Chrome ohne gescheiterte Anfrage und Konsolenfehler (#72)
make smoke-app      # macOS-App bauen (Release) und ihren Rauchtest ausführen
make pseudo-l10n    # Pseudo-Sprache der Oberflächentests nach einer Änderung an den ARB-Dateien
make bench          # Leistungs- und Lasttests von Kern und Bibliothek (nächtlich, nicht in make test, #59)
make mutants        # Mutationstests: Kern mit Mull, Dart-Logik mit eigenem Werkzeug (#11), local/mutants/full/
make mutants-diff   # Mutationstests der seit BASE geänderten Zeilen (Vorgabe origin/main), local/mutants/diff/
make report         # Übersichtsseite Testqualität aus den vorhandenen Ergebnissen (#12), local/test-quality/report/
```

Entwicklerwerkzeuge (nicht Teil der App): Flutter, CMake, Emscripten 7.0.0 für `test-wasm` (Homebrew `emscripten`, in beiden Workflows dieselbe Version), Homebrew `llvm` für
`clang-format`, `clang-tidy` und libFuzzer (`brew install llvm`; das Makefile findet sie unter
`$(brew --prefix llvm)/bin`; Apple-Clang hat kein libFuzzer). `actionlint` 1.7.12 (MIT) für die GitHub-Workflows
(`brew install actionlint`, #64); ist ShellCheck installiert, prüft actionlint damit auch die `run:`-Skripte.
`llvm-cov` und `llvm-profdata` für `make coverage` müssen zum Compiler passen; auf macOS nimmt das Makefile die aus
Xcode (`xcrun`), sonst die aus dem `PATH` bzw. Homebrew.

## Formatierung und Warnungen (#7)

- **Dart:** `dart format` mit Standardbreite 80 für alle Dart-Dateien unter `app/`, ausser den von `gen-l10n` erzeugten
  `app/lib/l10n/app_localizations*.dart`.
- **C/C++/Objective-C++:** `clang-format`, Stil LLVM mit 100 Spalten (`core/.clang-format`), für `core/src`,
  `core/include`, `core/tests`, `core/tools` und `core/web`. `core/third_party/` wird nie formatiert.
- **Dart-Analyse:** `flutter_lints` plus `strict-casts`, `strict-inference` und `strict-raw-types` in
  `app/analysis_options.yaml` und `app/packages/wp_core/analysis_options.yaml`. `flutter analyze` schlägt bei jedem
  Fund fehl, auch bei Hinweisen.
- **C++-Warnungen:** `-Wall -Wextra -Werror` für die eigenen Ziele (`wp_strict_warnings` in `core/CMakeLists.txt`,
  im Web-Zweig `core/web/web.cmake`). Bibliotheken aus `third_party` werden ohne diese Schalter übersetzt, ihre
  Header als `SYSTEM` eingebunden. Abschalten nur zur Fehlersuche: `-DWP_STRICT_WARNINGS=OFF`.
- **clang-tidy:** schlanke Auswahl in `core/.clang-tidy` (`bugprone-*`, `clang-analyzer-*`, `performance-*` und
  einzelne weitere), jeder Fund ist ein Fehler. Abgeschaltete Prüfungen stehen dort mit Begründung; einzelne
  Ausnahmen im Code nur als `NOLINT(<Prüfung>)` mit Begründung.
- **GitHub-Workflows** (#64): `make lint` ruft `make lint-workflows`, also `actionlint` über alle Dateien in
  `.github/workflows/` (Aufbau, Ausdrücke `${{ }}`, Bedingungen, Aktionen und mit ShellCheck die `run:`-Skripte).
  Jeder Fund lässt `make lint` scheitern. Der Job `checks` in `test-quality.yml` führt dieselbe Prüfung aus.
  Version: lokal Homebrew `actionlint` (Stand 1.7.12), im Workflow fest `ACTIONLINT_VERSION` 1.7.12 mit Prüfsumme
  `ACTIONLINT_SHA256` des Linux-Archivs; beim Aktualisieren beide Werte und diese Zeile nachführen. Gegenprobe:
  `test_quality_workflow_test.dart` lässt actionlint auf einen absichtlich fehlerhaften Workflow los und erwartet
  einen Fund (übersprungen, wenn actionlint fehlt).

## Abdeckung (#8)

Abdeckung zeigt, was ausgeführt wird, nicht was geprüft wird. Die Untergrenze ist deshalb eine Untergrenze, kein Ziel;
ein Test zählt nur, wenn er konkrete Werte prüft (siehe Grundsatz).

**Teile.** Gemessen wird die Zeilenabdeckung getrennt je Teil; die Regeln stehen in `app/tool/coverage.dart`
(`classify`):

| Teil | Dateien | Messung | Untergrenze |
|---|---|---|---|
| C++-Kern | `core/src/`, `core/include/` | `llvm-cov` über alle `ctest`-Programme und die geteilte Bibliothek `libwp_core` (Build `core/build-cov`, Release mit `-DWP_COVERAGE=ON`) | ja |
| Dart-Logik | `app/lib/` ohne die drei folgenden Gruppen | `flutter test --coverage` | ja |
| Dart-Oberfläche | `app/lib/ui/`, `app/lib/main.dart` und jede Datei, die ein Widget oder einen `State` deklariert (z. B. `metronome_panel.dart`) | `flutter test --coverage` | nein, nur ausgewiesen |
| Dart nur fürs Web | `*_web.dart` und Dateien mit `package:web` oder `dart:js_interop` | nicht messbar, nur aufgelistet | nein |
| Erzeugt | `app/lib/l10n/app_localizations*.dart` (`gen-l10n`) | nicht gezählt, aufgelistet | nein |

Die Untergrenze (80 %) steht nur in `tools/coverage-min`. `app/tool/coverage_check.dart` liest sie dort; der
pre-push-Hook und der Job `checks` des Workflows `test-quality.yml` (#13) rufen dieses Werkzeug auf. Jeder Teil mit Untergrenze
muss sie für sich erreichen. Eine Datei der Dart-Logik, die kein Test lädt, lässt die Prüfung ebenfalls scheitern
(`flutter test --coverage` kennt nur geladene Dateien); ausgenommen sind Dateien ohne ausführbaren Code (nur
Konstanten, z. B. `app_info.dart`).

**Ablauf.** `make coverage-run` führt alle Tests mit Abdeckung aus (`app/coverage/lcov.info`,
`core/build-cov/lcov.info`, dazu die Tests der Werkzeuge), `make coverage` prüft danach je Teil. `make coverage-diff`
(Basis `BASE=<Commit>`, Vorgabe `origin/main`) zeigt, welcher Anteil der seit der Basis geänderten ausführbaren Zeilen
(Commits und Arbeitsbaum) von Tests ausgeführt wird, mit den nicht abgedeckten Zeilen; ein Hinweis, keine Sperre.

**Vor dem Push.** `tools/git-hooks/pre-push` führt `make coverage-run` aus und danach die Prüfung je Teil. Schlägt ein
Test fehl oder liegt ein Teil unter der Untergrenze, bricht der Push ab, mit dem Grund (letzte Zeilen der Testausgabe
bzw. Teil und Anteil). Einrichten einmal je Klon:

```sh
git config core.hooksPath tools/git-hooks
```

Nur im Notfall umgehen: `git push --no-verify`. Die Tests von Hook und Werkzeugen (`app/tool/coverage_test.dart`,
`app/tool/pre_push_hook_test.dart`, in `make test`) arbeiten mit gestellten Abdeckungsdateien, Diffs und Schwellen,
erreicht und verfehlt, in kleinen Git-Repositorys mit einem gestellten `make`; ein Fall pusht echt in ein leeres
Repository mit `core.hooksPath`.

**Stand** 20.11.2026 nach #68 (`make coverage`): C++-Kern **87,4 %** (1266 von 1449 Zeilen), Dart-Logik **91,2 %**
(1891 von 2074), Dart-Oberfläche 95,0 % (2100 von 2210). Im Kern: `recorder_core.cpp` 100 % (neu, aus
`recorder_mac.mm` herausgelöst: Ringpuffer, Schreib-Thread, WAV-Datei, Pegel, Übernahme der Tap-Daten;
`recorder_tests.cpp`), `recorder_mac.mm` 25,1 % (43 von 171, nur noch Core Audio), `engine.cpp` 99,6 %,
`metronome.cpp` 99,6 %, `waveform.cpp` 100 %, `player_core.cpp` 90,9 %, C-API `player.cpp` 90,5 %, Offline-Kern
`wp_core_web.cpp` 86,7 %.

**Stand** 19.11.2026 (`make coverage`): C++-Kern **80,8 %** (1065 von 1318 Zeilen), Dart-Logik **90,3 %** (1754 von
1943), Dart-Oberfläche 95,1 % (2093 von 2200, ohne Untergrenze). Im Kern: `engine.cpp` 99,2 %, `metronome.cpp`
96,3 %, `waveform.cpp` 100 %, `player_core.cpp` 90,2 %, C-API `player.cpp` 90,1 % (vor #8 ohne Test: 0 %),
Aufnahme `recorder_mac.mm` 20,9 %. Für #8 neu: `core/tests/capi_tests.cpp` und Fälle für nicht lesbare Dateien,
WAV ohne Frames, Wellenform ohne Audio und Play ohne Titel.

**Ausnahmen und Grenzen der Messung** (nichts davon wird aus einem Teil mit Untergrenze herausgerechnet, ausser wo
genannt):

- **Code nur fürs Web** (`file_platform_web.dart`, `file_store_web.dart`, `platform_web.dart`,
  `audio_core_web.dart`): Diese Dateien importieren `package:web` bzw. `dart:js_interop` und lassen sich in der
  Dart-VM von `flutter test` nicht laden; `flutter test --platform chrome` liefert keine Abdeckung. Sie werden bei jeder
  Prüfung aufgelistet. Geprüft werden sie im Browser mit `flutter test --platform chrome` (`app/test/web/`, `make test-web`, Job `web`,
  #13), von Hand mit `app/tool/web_*_check.sh`, und über `web_binding_test.dart`.
- **Erzeugte Übersetzungen** (`app_localizations*.dart`): von `gen-l10n` aus den ARB-Dateien erzeugt, nicht von
  Hand geschrieben. Ihre Vollständigkeit prüft `l10n_test.dart`.
- **Aufnahme `recorder_mac.mm`** zählt zum Kern, obwohl sie grösstenteils nur mit echtem Systemton und der
  Berechtigung des Nutzers läuft (Core Audio Process Tap, #51); getestet sind Ruhezustand und Argumentprüfung. Seit
  #68 enthält sie nur noch die Ansteuerung von Core Audio; der Rest steht in `recorder_core.cpp` mit eigenen Tests.
  Sie drückt den Kern um rund 9 Prozentpunkte (ohne sie 95,7 %; vor #68 13 Prozentpunkte).
- **Fehlerpfade ohne Auslöser** im Kern (Speichermangel, Audiogerät lässt sich nicht anlegen, Gerätemeldungen von
  miniaudio in `player.cpp`) bleiben nicht abgedeckt; sie zählen mit.
- **Native Anbindung** (`platform_native.dart`, `audio_core_ffi.dart`, Teile von `file_platform.dart`) zählt zur
  Dart-Logik, wird aber nur im Rauchtest mit echtem Kern ausgeführt (`app_smoke_test.dart`, von Hand), also mit 0 %
  bzw. 36 % gezählt.
- **`recorder_stub.cpp`** (Aufnahme auf anderen Plattformen, im Browser und im Offline-Kern) wird seit #9 auch auf
  dem Mac gebaut und von `reference_tests.cpp` gemessen. `miniaudio_impl.c` bindet
  nur `third_party/miniaudio` ein und hat keine eigenen Zeilen.
- **`wp_core.h`:** `llvm-cov` rechnet Zeilen von Makros (`WP_ERR_*`, `WP_REC_ERR_*`) dem Header zu, wo sie im Code
  verwendet werden; sie zählen mit.
- **Zähler über 64 Bit:** Beim Zusammenführen der Profile mehrerer Testprogramme meldet `llvm-cov` für einzelne
  Inline-Funktionen aus Headern («mismatched data») übergelaufene Zähler; sie gelten als ausgeführt.

## Sanitizer und Echtzeitsicherheit (#57)

**Läufe.** Der Schalter `WP_SANITIZE` in `core/CMakeLists.txt` (Liste für `-fsanitize`) instrumentiert alle Ziele
eines Builds, auch die Bibliotheken aus `core/third_party/`, und setzt für jeden `ctest`-Fall die Optionen der
Sanitizer (`halt_on_error=1`, `-fno-sanitize-recover=all`). Jeder Fund beendet das Testprogramm mit einem Fehlercode
und lässt den Lauf scheitern. Die Builds liegen in eigenen Ordnern, `core/build` bleibt unberührt:

| Ziel | Build | Sanitizer | Workflow `test-quality.yml` (Linux) |
|---|---|---|---|
| `make sanitize` | `core/build-asan`, Debug | AddressSanitizer, UndefinedBehaviorSanitizer; unter Linux mit LeakSanitizer | Job `sanitize`: bei jedem Push auf `main` mit Änderung in `core/` (oder an `Makefile`, Workflow), von Hand startbar |
| `make sanitize-thread` | `core/build-tsan`, Debug | ThreadSanitizer | Job `sanitize-thread`: nächtlich, nur wenn `main` seit dem letzten erfolgreichen Nachtlauf einen neuen Commit hat; von Hand startbar |
| `make test-core-debug` | `core/build-debug`, Debug | – | – (#13) |
| `make test-core` | `core/build`, Release | – | – (#13) |

Lokal laufen sie auf macOS mit Apple-Clang, im Workflow unter Linux mit Clang. Der Selbsttest
`core/tests/sanitizer/selftest.cpp` enthält je Sanitizer einen absichtlichen Fehler (Pufferüberlauf,
Ganzzahlüberlauf, Wettlauf); `expect_finding.cmake` verlangt Meldung und Fehlercode. Er beweist, dass ein Fund die
Tests wirklich scheitern lässt. Der Wettlauf hat einen festen Ablauf (#63): Die beiden Threads schreiben nacheinander,
abgestimmt über `relaxed`-Atomics, die für TSan keine Ordnung herstellen. So meldet TSan ihn auch unter Last in jedem
Lauf (geprüft mit 20 Läufen parallel zu `make coverage`).

**Wettläufe (AK2).** Unter ThreadSanitizer steuern `engine_tests.cpp` (`commandsFromManyThreadsWhileRendering`: drei
Threads mit Seek, Tempo, Lautstärke, Loop, Pause, Play) und `player_tests.cpp` (`controlFromSecondThreadWhileRendering`:
ein Render-Thread wie das Audiogerät, gesteuert werden Play, Pause, Seek, Tempo, Loop, Metronom und Laden im
Hintergrund) die Wiedergabe, während gerendert wird.

**Debug und Release (AK3).** Alle Kerntests laufen in Debug (`make test-core-debug`, auch die Sanitizer-Builds) und in
Release (`make test-core`) mit denselben Fällen und denselben Toleranzen; es gibt keine Toleranz je Build. Nur die
Zeitgrenzen (Wellenform in 200 ms, 1001 Seeks in 50 ms) prüfen ausschliesslich optimierte Builds ohne Sanitizer
(`core/tests/test_timing.hpp`). Die Referenzfälle und die Golden-Datei aus #9 (`reference_tests`, `reference_api_coverage`) sind
`ctest`-Fälle und laufen damit ohne weitere Einrichtung in allen vier Builds mit denselben Toleranzen.

**Echtzeitsicherheit (AK4).** `core/tests/realtime_tests.cpp` rendert über `Player::render` (das ruft der Callback des
Audiogeräts) mit Tempo 0,75, 1,5, 0,5 und 1,25, Loop, Metronom mit Taktart, Unterteilung und Steigerung, Seek,
Lautstärke und Titelwechsel und zählt im Render-Thread jede Speicheranforderung und -freigabe (alle ersetzbaren
`operator new`/`delete`) und, unter Linux mit glibc ohne Sanitizer, zusätzlich `malloc`, `calloc`, `realloc`, `free`,
`posix_memalign`, `aligned_alloc` und `pthread_mutex_lock`. Erwartet wird 0. Ein Gegentest im selben Programm zeigt,
dass der Zähler Anforderungen und Sperren sieht. Die geteilten Atomics müssen sperrfrei sein (`static_assert`).
Grenze: Auf macOS lassen sich `malloc` und Sperren aus dem Testprogramm nicht abfangen; dort zählen nur `operator new`
und `delete`, den Rest prüft der Linux-Lauf.

**Fuzzing (AK5).** Die Fuzz-Ziele aus #10 bauen mit `make fuzz` in `core/build-fuzz` mit
`-DWP_SANITIZE=address,undefined -DWP_FUZZ=ON`: aller Code des Builds mit `-fsanitize=fuzzer-no-link` (Abdeckung für
libFuzzer), die Fuzz-Programme zusätzlich mit `-fsanitize=fuzzer`; jeder Fund von ASan oder UBSan beendet den Lauf
(Abschnitt «Zufallstests, Robustheit, Fuzzing und Golden-Dateien»).

**Unterdrückungen (AK6).** In `core/tests/sanitizer/` liegen `ubsan.supp`, `tsan.supp` und `lsan.supp`. Jeder Eintrag
braucht darüber einen Kommentar mit Meldung, Grund und Issue und steht in der folgenden Liste. Funde in
`core/third_party/` werden gemeldet und unterdrückt, nicht dort behoben.

| Sanitizer | Eintrag | Grund | Issue |
|---|---|---|---|
| – | keine | Stand 19.11.2026: ASan, UBSan und TSan melden in allen Kerntests nichts (macOS) | – |

**Grenzen.** LeakSanitizer gibt es mit ASan auf macOS nicht; Lecks prüft nur der Linux-Lauf. `capi_tests` öffnet ein
echtes Audiogerät; ohne Gerät (Linux-Runner) überspringt er die Ladefälle, der Callback des Geräts läuft dann nicht
unter den Sanitizern.

## Audio-Referenzfälle (#9)

`core/tests/reference_tests.cpp` rendert offline, ohne Audiogerät, über die C-API von `wp_core.h`. Gerendert wird
mit dem Offline-Kern `wp_core_offline` (`core/tests/reference.cmake`): `core/web/wp_core_web.cpp`, dieselbe Quelle
wie der Kern im Browser, dazu das Laden per Pfad (`WP_WEB_FILES`, nur wo es Dateisystem und Threads gibt) und
`recorder_stub.cpp`. Der Kern der App (`player.cpp`) ist dieselbe dünne Hülle um `wp::Player` plus Audiogerät; ihn
prüft `capi_tests.cpp`. Jeder Fall leitet den Erwartungswert im Kommentar her und nennt `#9/AKn`, Metronom-Fälle
zusätzlich `#3/AKn`.

| Fall | Testaudio | Erwartung |
|---|---|---|
| #9/AK1 | Sinus, Rampe, Stille, im Test erzeugt | Rampe bildet Frame-Index ab ((n + 1) · 2⁻²⁴, rechts negativ); Stille bleibt bei Tempo 0,5 exakt 0 |
| #9/AK2 Loop-Naht | Rampe 3 s, Loop 0,5–1,6 s | Ausgabe k = 22 050 + (k mod 48 510), 100 Durchläufe, Zähler +100; Blöcke 1–4096 Frames |
| #9/AK3 Seek, Pause | Rampe | erstes Sample round(t · 44 100), im Stand und beim Spielen; Pause verliert und wiederholt nichts |
| #9/AK4 Tempo | Sinus 440 Hz, 1 s | Länge 44 100 / r ± 1 % für r = 0,1 / 0,5 / 1,0 / 2,0, Grundfrequenz 440 Hz ± 1 % |
| #9/AK5, #3 Metronom | ohne Titel und mit stillem Titel | 600 Klicks in 5 min genau k · 22 050; 6/8 A B B S B B; Unterteilungen bei round(k · 22 050 / s), leiser; fester Ablauf als Golden-Datei |
| #70 Takt und Unterteilung mitten im Schlag | ohne Titel | 4/4 Achtel → 3/4 Triolen im 4. Schlag: Triolen bei 73 500 und 80 850, Betonung bei 88 200; → 6/8 Viertel im 3. Schlag: Nebenakzent bei 154 350; → 4/4 Achtel im 6. Schlag: Achtel bei 341 775, Betonung bei 352 800 und 441 000 |
| #9/AK7 übrige C-API | WAV (Float, 22,05 kHz), im Test geschrieben | Laden, Dauer, Wellenform, Fehlercodes, Aufnahme nicht verfügbar |

**Klickerkennung.** Ein Klick beginnt mit sin(0) = 0; zwischen den Klicks ist die Ausgabe exakt 0. Die Position ist
das erste Sample ungleich 0 nach mindestens 64 stillen Samples minus 1, die Art folgt aus der Frequenz (Nulldurchgänge
in 1500 Samples: 1600 / 1250 / 1000 / 700 Hz).

**Golden-Datei.** `core/tests/golden/metronome_positions.txt` hält Position und Art jedes Klicks eines festen
Ablaufs (4/4, Wechsel auf 6/8 mit Triolen, 3/4 mit Achteln bei 90 BPM, Steigerung nach Takten, Steigerung nach Zeit,
Stopp). Die ersten 14 Klicks leitet der Fall zusätzlich von Hand her. Nach einer gewollten Änderung neu schreiben und
den Diff prüfen:

```sh
GOLDEN_UPDATE=1 core/build/reference_tests
```

**Vertrag nativ ↔ Web (AK7).** Derselbe Quelltext läuft nativ (`ctest` in `core/build`, `build-debug`, `build-asan`,
`build-tsan`) und als WebAssembly unter Node.js (`core/build-wasm`). Der native Lauf schreibt jede aufgezeichnete
Ausgabe nach `reference_native.bin` im eigenen Build-Ordner (`--dump`); der WASM-Lauf vergleicht mit
`core/build/reference_native.bin` (`--compare`, Toleranz 1e-6, die gestreckten Tempo-Fälle 5e-2, siehe unten, CMake-Variable `WP_REFERENCE_DUMP`) und verlangt, dass
jede native Ausgabe auch dort entsteht. `make test-wasm` rendert den nativen Stand vorher (`make reference-native`,
danach `make test-wasm-compare`). Im Workflow läuft derselbe Ablauf bei jedem Push mit Änderung am Kern im Job
`contract` (#77), auf Linux mit Emscripten 7.0.0 (`EMSDK_VERSION`, dieselbe Version wie lokal mit Homebrew
`emscripten`). Stand 19.11.2026: alle
12 Ausgaben bitgleich (grösste Abweichung 0). Unter Linux weichen die gestreckten Tempo-Fälle (`tempo_0.1`,
`tempo_0.5`, `tempo_2.0`) ab, weil glibc `sincosf` anders rundet als Apple und musl (#94, «Gefundene Fehler» 27):
bis 2,12e-02. Für sie gilt deshalb 5e-2 (`kStretchTolerance`); ein falscher Stretch weicht um rund 1 ab. Unter
macOS bleiben auch sie bitgleich; `make test-wasm` zeigt die grösste Abweichung je Fall. `reference_api_coverage` (`core/tests/reference_api_coverage.cmake`)
liest alle `WP_API`-Funktionen aus `wp_core.h` und schlägt fehl, wenn eine davon in `reference_tests.cpp` nicht
aufgerufen wird. Derselbe Test verlangt, dass die Referenzfälle keine Audiodatei aus `core/tests/audio/` lesen
(#9/AK1); dort liegen nur die Dateien für die Decoder-Tests von `player_tests.cpp` und `capi_tests.cpp`, erzeugt von
`core/tools/make_test_audio.sh`.

**Ohne FMA.** Kern, Tests, Werkzeuge und Web bauen mit `-ffp-contract=off` (`core/CMakeLists.txt`), das Flutter-Plugin
ebenso (`app/packages/wp_core/*/wp_core.podspec`, geprüft in `app/test/core_build_flags_test.dart`). Apple-Clang fasst
auf arm64 sonst `a · b + c` zu einer FMA-Anweisung zusammen, WebAssembly kennt keine; der Time-Stretch verstärkte den
Rundungsunterschied bis 2e-2 (siehe «Gefundene Fehler»).

**Grenze.** Die Aufnahme ist im Offline-Kern der Stub (nicht verfügbar); die echte Aufnahme (`recorder_mac.mm`)
braucht Systemton (#51). Der optionale Vergleich mit AVAudioUnitTimePitch bleibt der Hörvergleich von Hand
(`tools/hoervergleich.sh`).

## Zufallstests, Robustheit, Fuzzing und Golden-Dateien (#10)

**Zufallstests (AK1, AK2, AK6).** `app/test/property/property.dart` führt eine Eigenschaft über viele Fälle aus,
ohne zusätzliches Paket (`dart:math` `Random`). Die Fallzahl kommt aus `WP_PROPERTY_CASES` (Vorgabe 100, bei jedem
`flutter test`), der Startwert aus `WP_PROPERTY_SEED` (Vorgabe 20261119); jeder Test gibt beides aus, Fall *i*
läuft mit `caseSeed(Startwert, i)`. Scheitert ein Fall, nennt die Meldung dessen Startwert. Er wird mit Datum und
Grund in `app/test/property/regressions.json` unter dem Namen der Eigenschaft eingetragen und läuft danach bei jedem
Lauf **zuerst**, vor den Zufallsfällen. Nächtlich läuft `make property PROPERTY_CASES=3000` mit neuem Startwert
(Job `property`). Langsame Eigenschaften (Abgleich) nehmen einen Bruchteil der Fallzahl.

| Eigenschaft | Datei | Invariante |
|---|---|---|
| Sortieren und Verschieben | `library_property_test.dart` | nach jedem von 5–35 zufälligen Schritten (Import, Ordner anlegen, umbenennen, löschen, verschieben, ziehen, Sortierung, Titel, Einstellungen, Löschen) jeder Titel genau einmal, in einem bestehenden Ordner oder ohne |
| Speichern und Laden | `library_property_test.dart` | geladener Stand = gespeicherter Stand; erneutes Speichern schreibt dieselbe Datei |
| Loop-Grenzen | `player_property_test.dart` | nach Laden (gespeicherte Grenzen, auch ausserhalb der Datei) und jeder Änderung: 0 ≤ Anfang, Ende ≤ Dauer; ab 1 s Dauer Ende ≥ Anfang + 1 s; der Kern hat genau den aktiven Loop |
| Zeitformat | `player_property_test.dart` | `parseTime(formatTime(x)) == x` (ganze Sekunden bis 100 h), dasselbe mit Zehnteln und im Zeitfeld; beliebiges x ergibt ⌊x⌋ |
| Abgleich | `sync_property_test.dart` | 2–4 Geräte, 10–40 Schritte (Import aus gemeinsamem Vorrat, Löschen, Titel, Ordner, Verschieben, Loops, Abgleich, teils offline): Zusammenführen in jeder Reihenfolge gleich; nach zwei Runden Abgleich alle Geräte gleich; ein weiterer Abgleich schreibt nichts; jeder nie gelöschte Titel ist auf allen Geräten, mit Audiodatei dort und in der Cloud; der gespeicherte Stand lädt wieder gleich |

**Robustheit (AK3, AK7, AK8).** `app/test/property/corrupt.dart` verfälscht eine Datei zufällig: Typwechsel,
fehlendes Feld, falscher Verweis (Ordner, Loop, ID, Dateiname), Extremwerte (`1e400`, 30-stellige Zahlen, 2⁵³ + 1,
riesige Texte), fremde Versionsnummer, fehlende oder unsinnige Stempel, abgeschnittene Datei.

- `library_files_property_test.dart`: Jede Golden-Datei, verfälscht, wird geladen. Erlaubt sind drei Ausgänge: Die
  Bibliothek öffnet ohne Meldung und ist stimmig (jeder Titel einmal, in einem bestehenden Ordner, Speichern und
  erneutes Laden ohne Meldung und ohne Änderung); oder «beschädigt» mit Sicherung der Datei unter
  `library.json.defekt-<Zeit>`; oder «neuere Version» (nur lesen, Datei bleibt). Jede Meldung hat einen Text in jeder
  Sprache. Stand 19.11.2026 bei 3 × 1500 Fällen: rund 49 % geöffnet, 48 % beschädigt, 3 % neuere Version.
- AK8: Für jede Golden-Datei und jede verfälschte, die noch öffnet, ändert ein zweites Laden und Speichern nach der
  Migration nichts (gleicher Inhalt von `library.json`) und meldet nichts; `migrateLegacyLibrary` zweimal auf
  dieselbe Datei gibt dasselbe Ergebnis.
- `sync_property_test.dart`: Gerät A legt `state.json` in die Cloud, Gerät B hat eigene, nie abgeglichene Titel. Die
  verfälschte `state.json` darf nie abstürzen; B behält jeden eigenen Titel unverändert, und was B gespeichert hat,
  lädt ohne Meldung gleich wieder. Unbrauchbare Dateien prüft die Sync-Engine vor dem Zusammenführen
  (`CloudSync._readState`): Version genau 2, keine Zahl ausserhalb des Bereichs eines double, Stempel lesbar und im
  Bereich, jeder Datensatz darstellbar. Sonst bleibt die Bibliothek unberührt, die Datei in der Cloud ebenso, der
  Abgleich wartet (Status `damaged`, ohne automatische Wiederholung) auf die Wahl der Reparatur (#65), und die Meldung «Bibliothek in der Cloud beschädigt» bzw. «neuere
  Version» erscheint einmal je Version der Datei. Stand 19.11.2026 bei 2 × 1000 Fällen: rund 69 % abgewiesen, 28 %
  noch gültig und übernommen, 3 % neuere Version.
- `sync_property_test.dart` (#65/AK4): A gleicht mehrmals ab (Sicherungen unter `backup/`), B hat eigene Titel. Die
  `state.json` wird so verfälscht, dass sie unbrauchbar ist (geprüft auf einem Wegwerf-Gerät), manche oder alle
  Sicherungen ebenso; manchmal bricht vor der Reparatur die Verbindung ab. B wählt zufällig einen Weg (ohne gültige
  Sicherung danach «Dieses Gerät verwenden»). Danach behält B jeden eigenen Titel unverändert samt Audiodatei, lädt
  ohne Meldung wieder, und A und B kommen auf denselben Stand, ohne dass ein Titel verloren geht. Stand 20.11.2026
  bei 3 × 90 Fällen: rund 52 % ersetzt, 43 % aus der Sicherung, 5 % ohne gültige Sicherung.
- Kern (AK3): `player_tests.cpp` (`truncatedAndWrongAudioFiles`) schneidet WAV, FLAC und MP3 an 10 Stellen ab
  (leer, Teil des Kopfs, nur Kopf, Teile der Daten) und lädt falsche Inhalte hinter bekannten Endungen: Ergebnis ist
  immer der lesbare Teil oder `WP_ERR_UNSUPPORTED_FORMAT` (in der App «Format nicht unterstützt», `loadUnsupported`),
  danach spielt der bisherige Titel weiter.

**Fuzzing (AK4, AK9).** Zwei Ziele in `core/tests/fuzz/`:

| Ziel | Eingabe | Invarianten |
|---|---|---|
| `fuzz_decoder` | rohe Bytes als Datei: `wp::decodeMemory` (Kern im Browser, Worker) mit einer vom ersten Byte gewählten Rate, `wp::fileDuration` über eine temporäre Datei | Ergebnis OK oder ein dokumentierter Fehlercode; bei OK mindestens ein Frame, genau Frames × 2 endliche Samples, Wellenform endlich; die Dauer positiv oder ein Fehlercode |
| `fuzz_capi` | ein kleines Programm aus Befehlen über die C-API von `wp_core.h` (`wp_core_offline`, derselbe `wp::Player` wie in der App, ohne Audiogerät): Laden aus Bytes, PCM und Datei, Play, Pause, Seek, Tempo, Loop, Lautstärke, Rendern, Metronom, Wellenform; Argumente auch NaN, unendlich, negativ, riesig | nach jedem Befehl Position und Dauer endlich, 0 ≤ Position ≤ Dauer, Loop-Zähler fällt nie, Metronom 20–300 BPM, jedes gerenderte Sample endlich, Fehlercodes dokumentiert |

Der Startkorpus (`core/tests/fuzz/corpus/<ziel>/`, 19 Dateien, 78 kB) ist erzeugt: `core/tools/make_fuzz_corpus.py`
schreibt kleine WAV-Dateien (8/16/24 Bit, Float, Mono/Stereo), beschädigte WAV-Köpfe, die ersten 1500 Bytes des
eigenen Testaudios und Befehlsprogramme; keine fremden Audiodateien. Gefundene Eingaben liegen in
`core/tests/fuzz/regressions/<ziel>/`. Beide Ordner laufen in **jedem** Build als `ctest`-Fall `fuzz_<ziel>_replay`
(Regressionsfälle zuerst), ohne libFuzzer, also auch in Release, Debug, ASan/UBSan und TSan.

`make fuzz` baut `core/build-fuzz` (RelWithDebInfo, ASan und UBSan, `allocator_may_return_null=1`, unter Linux
LeakSanitizer) mit Homebrew-Clang und lässt jedes Ziel `FUZZ_SECONDS` lang laufen (Vorgabe 60, nächtlich 1200), mit
Zeitgrenze 10 s je Eingabe und 2 GB Speicher. Neue Korpusdateien bleiben in `core/build-fuzz/corpus/` (nicht
eingecheckt; im Workflow über den Cache von Nacht zu Nacht). Ein Fund (Absturz, Sanitizer, verletzte Invariante,
Zeitüberschreitung, Speicher) beendet den Lauf mit Fehler und legt die Eingabe unter
`core/build-fuzz/artifacts/<ziel>/` ab; der Job `fuzz` lädt sie als Artefakt hoch. Nach der Behebung kommt die
Eingabe nach `core/tests/fuzz/regressions/<ziel>/`. Stand 19.11.2026, je 60 s auf dem Mac: `fuzz_decoder` rund
35 000–90 000 Eingaben, `fuzz_capi` rund 700–1100, ohne Fund.

**Dieselben Eingaben gegen den WASM-Kern (#67).** Der Emscripten-Zweig (`core/web/web.cmake`) bindet `fuzz.cmake`
ebenfalls ein: `fuzz_decoder_replay` und `fuzz_capi_replay` laufen als WebAssembly unter Node.js (`NODERAWFS`) im
`ctest` von `core/build-wasm`, also in `make test-wasm` und im Job `contract` bei jedem Push, der `core/` ändert.
`make fuzz-wasm` spielt zusätzlich den von `make fuzz` gewachsenen Korpus (`core/build-fuzz/corpus/<ziel>/`, falls
vorhanden) nach; der Job `fuzz` ruft es nächtlich nach `make fuzz` auf, mit Emscripten in der festen Version
(`EMSDK_VERSION`). Die Ordner werden ganz gelesen: Eine neu eingecheckte Regression oder neue Korpusdatei läuft ohne
weitere Änderung auch unter WebAssembly. Ein Fund (verletzte Invariante mit `abort()`, WASM-Trap) beendet Node.js mit
Exit-Code ungleich 0; die letzte Zeile `replay …` im Protokoll (`core/build-wasm/fuzz_<ziel>_replay.log`, im Workflow
als Artefakt) nennt die Eingabe. Ohne Sanitizer: unter WebAssembly zählen nur Abstürze und Invarianten. Stand
20.11.2026 auf dem Mac: 15 und 7 Eingaben im `ctest`, mit dem lokal gewachsenen Korpus 2080 (`decoder`) und 616
(`capi`) Eingaben in rund 7 s, ohne Fund.

**Ein nativer Fund auch gegen den WASM-Kern (#88).** Hat `make fuzz` im Job `fuzz` einen Fund, laufen Zwischenspeicher
und Installation von Emscripten trotzdem (`if: !cancelled()`), `make fuzz-wasm` entfällt, und `make fuzz-wasm-findings`
spielt jede Eingabe aus `core/build-fuzz/artifacts/<ziel>/` einzeln unter Node.js ab. Je Eingabe steht eine Zeile
`fuzz_<ziel>: <datei>: finding under WASM: no` bzw. `yes (exit N)` oder `yes (timeout after 60 s)` im Protokoll und
in `core/build-wasm/fuzz_findings_wasm.txt`; diese Datei und die Protokolle `fuzz_<ziel>_finding_<datei>.log` kommen
ins Artefakt `fuzz-findings`. Das WASM-Ergebnis ändert den Ausgang nicht: Der fehlgeschlagene Schritt `make fuzz`
hält den Job rot, solange der native Fund besteht. Lokal ohne `timeout` (macOS) gilt kein Zeitlimit.

**Durchsatz von `fuzz_capi` (#66).** Ein Profil zeigte, dass nicht das Rendern die meiste Zeit braucht, sondern das
Laden: rund 78 % in `wp_web_load_pcm` (Umrechnen langer PCM-Titel auf die Geräterate, Peaks), 10 % im Anlegen des
Players, 7 % im Rendern. `fuzz_capi` macht deshalb pro Eingabe nur, was die Befehlsfolge braucht:

- Ein erzeugter PCM-Titel ist 0–2 s lang, gleich verteilt (vorher bis 200 000 Frames, bei 8000 Hz 25 s). Der
  Startkorpus nutzt 1,5 s und bleibt unverändert gültig.
- Höchstens 4 Ladebefehle pro Eingabe; weitere lesen ihre Argumente und laden nichts, so bleibt jede Eingabe ein
  gültiges Programm.
- «Lang rendern» (bis 64 Blöcke) hört auf, sobald weiteres Rendern nichts mehr ändert: nach einem Block, wenn weder
  Titel noch Metronom laufen, nach einem Loop-Durchgang und am Ende des Titels. Der Schlussblock entfällt, wenn das
  Programm mit Rendern endet.

Messung auf demselben Mac (Apple M1 Pro, `make fuzz`-Build mit ASan und UBSan), je 60 s nur vom eingecheckten Korpus
aus, mit leerem Arbeitskorpus und festem Seed (1, 2, 11, 12, 13):

| Stand | Eingaben pro Minute | Median |
|---|---|---|
| vorher (ef479d1) | 811, 1337, 1420, 1759, 2223 | 1420 |
| nachher (#66) | 2158, 2668, 3178, 3198, 3354 | 3178 |

Die Abdeckung blieb gleich oder stieg (cov 2367–2400 vorher, 2406–2462 nachher). Alle 29 Funktionen der C-API, die
`fuzz_capi` aufruft, erreicht schon der Startkorpus allein; geprüft mit
`core/build-fuzz/fuzz_capi -runs=0 -print_coverage=1 core/tests/fuzz/regressions/capi core/tests/fuzz/corpus/capi`
(jede Funktion als `COVERED_FUNC`).

**Golden-Dateien (AK5).** `app/test/golden/` hält `library.json` jeder Version mit erfundenen Titeln
(`README.md` dort): Swift `[Track]`, Swift `{folders, tracks}`, Format 2 von #36 (ein Feld `loop`, erzeugt mit dem
Code von Commit 8f9fb22) und Format 2 seit #37 (`make_golden_v2.dart`). `golden_files_test.dart` lädt jede mit der
aktuellen Version (Werte von Hand aus den Dateien), verlangt, dass jede Datei im Ordner in der Liste steht, und dass
die aktuelle Version `library_v2.json` inhaltlich unverändert wieder schreibt; ändert sich das Format, braucht es eine
neue Golden-Datei.

**Grenzen.** Der nächtliche Fuzz- und Zufallslauf lässt sich erst nach dem Push beobachten; lokal belegt sind
`make fuzz` (60 s je Ziel), `make fuzz-wasm` und `make property` mit bis zu 2000 Fällen. libFuzzer selbst läuft
nicht unter WebAssembly; dort werden nur die nativ gefundenen Eingaben nachgespielt (#67). Eine beschädigte `state.json` bleibt in der Cloud liegen, bis die Nutzerin oder der Nutzer
eine Reparatur wählt (#65).

## Netzwerkfreiheit (#58)

Das Versprechen «kein Netzwerk ausser beschlossenen Funktionen» (`CLAUDE.md`, README Datenschutz) prüft
`make network-free`, auch nachdem die Cloud-Anbieter (#38) Netzwerkcode mitbringen. Das Ziel führt die Prüfung
`app/tool/network_free.dart` aus, dann ihre Tests `app/tool/network_free_test.dart` und `app/test/sync_app_test.dart`
(#37/AK2: ohne Konto entsteht kein `HttpClient`). Der Workflow `test-quality.yml` startet es im Job `network-free` bei
jedem Push auf `main`, ohne Pfadfilter.

**Erlaubter Ordner: `app/lib/sync/providers/`.** Nur dort darf Code Netzwerkpakete importieren (`package:http`,
`dio`, `web_socket_channel` u. a.) oder Verbindungen öffnen (`HttpClient`, `HttpServer`, `WebSocket`, Sockets,
`fetch`, `XMLHttpRequest`, `EventSource`, `sendBeacon`, `RTCPeerConnection`). Die Anbietermodule für Google Drive
(#54), OneDrive (#55) und die direkte Verbindung (#56) legt #38 dort ab, auch den Loopback-Empfänger der Anmeldung
am Desktop. Geprüft werden Dart, JavaScript und HTML in `app/lib/`, `app/packages/`, `app/web/` und die Dateien, die
`build_web_core.sh` aus `core/web/` in die App kopiert; Kommentare zählen nicht, Build-Ordner und die erzeugte Kopie
`app/web/wp_core/` werden übersprungen. Jeder Treffer nennt Datei und Zeile.

Das Laden eigener Dateien der Seite per `fetch` (gleicher Ursprung) ist erlaubt, wenn die Zeile oder eine der zwei
darüber `network-free: own origin, <Grund>` trägt. Heute sind das zwei Stellen: der WASM-Kern in
`audio_core_web.dart` und `sw.js`, der nur Anfragen an die eigene Seite weiterreicht. Für andere Netzwerkaufrufe
gilt die Markierung nicht.

**Sperrliste.** `app/pubspec.lock` darf keines der Pakete aus `blockedPackages` enthalten (Analyse, Absturzberichte,
Werbung, Fernkonfiguration, z. B. `firebase_analytics`, `sentry_flutter`, `amplitude_flutter`, `mixpanel_flutter`,
`google_mobile_ads`). Verglichen werden exakte Paketnamen; ein Paket mit ähnlichem Namen fällt nicht auf, ein neues
Paket dieser Art kommt mit seinem Namen auf die Liste.

**Kern.** `core/src/` und `core/include/` enthalten keine Netzwerkaufrufe und -header (`socket`, `connect`,
`getaddrinfo`, `curl_*`, `sys/socket.h`, `NSURLSession`, Network.framework u. a.). `core/third_party/` wird nie gelesen.

**Content Security Policy der Web-App** (`app/web/index.html`, `<meta http-equiv>`, GitHub Pages erlaubt keine
eigenen Header). `connect-src` enthält genau `'self'` und die API- und Anmelde-Hosts der Anbieter: Google
(`https://www.googleapis.com`, `https://oauth2.googleapis.com`, `https://accounts.google.com`) und Microsoft (`https://graph.microsoft.com`,
`https://login.microsoftonline.com`). Dropbox entfällt laut `docs/KONZEPT-SYNC.md`; seine Hosts sind seit #71 nicht
mehr erlaubt. Ein neuer Host braucht einen Kommentar im Issue und gehört in
`allowedConnectSrc` und den Test. Die übrigen Direktiven:

| Direktive | Wert | Grund |
|---|---|---|
| `default-src` | `'self'` | alles Übrige nur von der eigenen Seite |
| `script-src` | `'self' 'wasm-unsafe-eval' 'sha256-…'` | eigene Skripte (Flutter, AudioWorklet, Worker); WebAssembly von CanvasKit und Audio-Kern; das Inline-Skript in `index.html` über seinen Hash. Ändert es sich, nennt die Prüfung den neuen Hash |
| `style-src` | `'self' 'unsafe-inline'` | Flutter schreibt `<style>`-Elemente in die Seite |
| `img-src`, `media-src` | `'self' data: blob:` bzw. `'self' blob:` | Bilder und Audio aus dem Speicher der Seite |
| `font-src` | `'self' data:` | Schriften liegen bei der App |
| `worker-src`, `manifest-src` | `'self'` | Service Worker, Decoder-Worker, Manifest |
| `object-src`, `form-action` | `'none'` | keine Plugins, keine Formulare |
| `base-uri` | `'self'` | `<base href>` nur auf die eigene Seite |

Von Hand geprüft am 20.11.2026: `flutter build web`, lokal ausgeliefert, Chrome: App startet isoliert
(`crossOriginIsolated`, Service Worker), Metronom läuft (WASM, AudioWorklet, Decoder-Worker), keine CSP-Meldung in
der Konsole; ein `fetch` an einen fremden Host wird mit `connect-src` blockiert.

**Grenzen.** Die Suche ist textbasiert: Netzwerkzugriff über Umwege (z. B. ein Plugin mit nativem Netzwerkcode, ein
dynamisch zusammengesetzter Name) findet sie nicht; dafür prüfen die Sperrliste und `sync_app_test.dart` zur Laufzeit.
Die direkte Verbindung (#56) braucht im Browser ihre Relay-Hosts in `connect-src`; sie kommen mit #56 dazu. Der Job im
Workflow lässt sich erst nach dem Push beobachten.

## Oberflächentests, Web-Tests und GitHub-Workflow (#13)

**Oberflächentests** (`app/integration_test/`, Flutter `integration_test`, echte App mit echtem Kern, `make test-ui`):

| Datei | Prüft |
|---|---|
| `app_smoke_test.dart` | Start, Import einer erzeugten Audiodatei (wie Ziehen ins Fenster, Kanal `woodshed/files`), Play/Pause, Loop mit den Knöpfen «hier», Tempo (Schalter und 0,75×); danach Play/Pause je Grösse (#13/AK1, #17/AK7, #30/AK13) |
| `shortcuts_test.dart` | Leertaste, S, E, ←/→, M, T, ↑/↓ (mit Shift ±10) gegen den Zustand von Player und Metronom (#13/AK1) |
| `pseudo_locale_test.dart` | Pseudo-Sprache in allen drei Grössen: kein Überlauf, kein abgeschnittener Text (#13/AK7) |

Regeln (#13/AK2, aus VivaPlan), geprüft in `app/test/ui_test_rules_test.dart`:

- **Auf Zustände warten, nie auf Zeit.** Jedes Warten geht über `pumpUntil` (`ui_helpers.dart`): Bild für Bild, bis
  der Zustand erreicht ist (z. B. «spielt und Position > 0,2 s»). Keine `pump(Duration)`, kein `Future.delayed`,
  kein `sleep`.
- **Kein eigenes Zeitlimit** ausser `hangGuard` (60 s) gegen Hänger; ein bestandener Test kommt nie in dessen Nähe,
  auch nicht auf einem ausgelasteten Rechner. Wo die Zeit selbst die Regel ist (Tap-Tempo), setzt der Test die Uhr
  (`createAppController(tapTempo: …)`).
- **Die Sprache ist fest:** Englisch über `startApp`, im Pseudo-Test die Pseudo-Sprache. Testaudio wird erzeugt
  (`sineWav` in `app/lib/app/smoke.dart`), jeder Test arbeitet in einem eigenen temporären Ordner.
- **Ohne Audiogerät** (GitHubs macOS-Runner) läuft der Kern mit `WP_AUDIO_BACKEND=null` auf dem stummen Null-Gerät von
  miniaudio, im Echtzeittakt (`core/src/player.cpp`). Dieselben C-API-Fälle laufen in `ctest` auch so
  (`capi_null_backend_tests`), dort wird nichts übersprungen. Lokal nehmen die Tests das echte Gerät.

**Pseudo-Sprache** (#13/AK7): `app/integration_test/pseudo.dart` setzt jeden Text zwischen `⟦ ⟧`, ersetzt Buchstaben
durch Akzentbuchstaben und verlängert um 40 %. Die Test-Lokalisierung `pseudo_localizations.dart` erzeugt
`app/tool/pseudo_l10n.dart` aus den englischen Texten (`make pseudo-l10n`); `pseudo_l10n_test.dart` schlägt fehl,
wenn sie veraltet ist, und prüft die Erkennung abgeschnittener Texte. Für Nutzer gibt es keine ARB-Datei dieser
Sprache; `WoodshedApp(localizationsDelegate: …)` nimmt sie nur im Test. Abgeschnitten heisst: mehr Zeilen als erlaubt
(auch Auslassungspunkte), eine nicht umbrechende Zeile breiter als ihr Platz oder ein Wort breiter als sein Platz.

**Web-Tests** (#13/AK4, `app/test/web/`, `@TestOn('browser')`, `make test-web`): OPFS (Schreiben, Lesen, Umbenennen,
Löschen, SHA-256, Speicherzeile), Übergabe gewählter Dateien und die Web-App mit WASM-Kern im AudioWorklet und
Lade-Worker (Laden, Dauer, Wellenform, Play/Pause, Tempo, Loop, Metronom). IndexedDB nutzt die App nicht. Der WASM-Kern
liegt für den Test neben der Testseite (`app/test/web/wp_core/`, nicht eingecheckt); Chrome startet über
`tools/chrome_autoplay.sh` mit erlaubter Wiedergabe, weil der AudioContext sonst einen Klick bräuchte. Der Lauf in der
Dart-VM (`flutter test`) überspringt diese Dateien.

**Rauchtest der gebauten App** (#13/AK5, `make smoke-app`, `tools/smoke_app.sh`): Mit `WP_SMOKE=1` öffnet die
Release-App ihr Fenster, erzeugt eine Sinusdatei in einem temporären Ordner, importiert und spielt sie (lokal, ohne
Netzwerk), bis die Position 0,5 s überschreitet, pausiert und endet mit Code 0 und «smoke: ok» (sonst Code 1 mit dem
gescheiterten Schritt). Keine Bedienung nötig, nie die echte Bibliothek. Ablauf in `app/lib/app/smoke.dart`, geprüft
in `smoke_test.dart`. Windows und Linux folgen mit #60.

**Workflow** `.github/workflows/test-quality.yml`:

| Job | Läuft | Inhalt |
|---|---|---|
| `checks` | Linux, jeder Push mit Code-Änderung (`core/`, `app/`, `tools/`, `Makefile`, Workflows), von Hand | `make format-check`, `make lint` (mit actionlint, #64), `make coverage-run`, Prüfung gegen `tools/coverage-min`, `coverage-diff`, Zusammenfassung |
| `web` | Linux, jeder Push mit Web-Änderung (`app/web/`, `*_web.dart`, Kern, Web-Build), von Hand | WASM-Kern, `make test-web` in Chrome, am Ende `make test-web-start`: einziger `flutter build web` des Jobs (Release, #83) und Start ohne gescheiterte Anfrage (#72) |
| `sanitize` | Linux, Push mit Änderung am Kern, von Hand | ASan/UBSan (#57) |
| `contract` | Linux, Push mit Änderung am Kern, von Hand | Vertrag nativ ↔ WASM (#77, #9/AK7): zuerst `make reference-native` (native Referenzfälle schreiben ihre Samples), danach `make test-wasm-compare` (WASM-Kern unter Node.js vergleicht, Toleranz 1e-6, gestreckte Tempo-Fälle 5e-2, jede Funktion der C-API) |
| `network-free` | Linux, jeder Push, von Hand | Netzwerkfreiheit (#58) |
| `macos` | macOS, nächtlich nach neuem Commit, von Hand mit `nightly=true` | macOS- und iOS-Build, Oberflächentests, Rauchtest der gebauten App |
| `sanitize-thread`, `fuzz`, `property` | Linux, nächtlich nach neuem Commit, von Hand mit `nightly=true` | TSan (#57), Fuzzing und Zufallstests (#10) |

- **Nächtlich** (02:17 UTC) entscheidet `nightly-gate`: Läufe nur, wenn `main` seit dem letzten erfolgreichen
  nächtlichen Lauf einen neuen Commit hat. **Von Hand** (`workflow_dispatch`) laufen die Push-Jobs; mit `nightly=true`
  zusätzlich alle nächtlichen Jobs zusammen, ohne Sperre.
- **Concurrency** (#13/AK8): nächtliche Läufe (Zeitplan oder `nightly=true`) teilen die Gruppe `test-quality-nightly`
  und werden nie abgebrochen; ein Push bricht nur einen älteren Push-Lauf derselben Branch ab.
- **Zusammenfassung** (#13/AK9): Der Job `checks` schreibt die Abdeckung je Teil, `coverage-diff` (Basis: Commit vor
  dem Push) und den Stand der Übersichtsseite in die Zusammenfassung des Laufs; die lcov-Dateien sind ein Artefakt.
  Danach erzeugt er die Übersichtsseite (#12, `make report` mit der Basis des Pushs, Issues über `gh` mit dem
  Token des Laufs und der Berechtigung `issues: read`), schreibt ihre Kurzfassung in die Zusammenfassung und lädt
  Seite und JUnit-Dateien als Artefakt `test-quality-report` hoch. Mutationsläufe sind eigene Jobs; im Job `checks`
  zeigt die Seite für sie «keine Daten».
- **Werkzeuge:** Flutter in derselben Version wie `pages.yml` (`FLUTTER_VERSION`, `dart format` hängt davon ab),
  `clang-format` und `clang-tidy` in Hauptversion 23 wie Homebrew `llvm` (über `pipx`), der Kern mit clang-18 und
  passendem `llvm-cov-18`, `actionlint` in fester Version mit Prüfsumme (#64), in den Jobs `contract`, `fuzz` und `web` sowie in `pages.yml`
Emscripten 7.0.0 über `emsdk` (`EMSDK_VERSION`, je Workflow an einer Stelle, nie `latest`, wie Homebrew `emscripten`
lokal; nach einem Update alle drei nachführen, #77, #79). Die emsdk-Installation liegt im Zwischenspeicher von
`actions/cache` (Schlüssel `emsdk-<Runner-OS>-<EMSDK_VERSION>`); bei einem Treffer entfällt die Installation, eine neue
Version gibt einen neuen Schlüssel und wird beim nächsten Lauf neu installiert (#89). Mutationstests der geänderten Zeilen laufen nächtlich im Job `mutants-diff` (#11).
- **Lokal geprüft** werden die Workflows mit `actionlint` und ShellCheck (`make lint`, #64) und über
  `test_quality_workflow_test.dart`. Ob alle Jobs auf den Runnern laufen, zeigen erst die Läufe nach dem Push.

**Verbrauch an Minuten** (#13/AK10, Schätzung vom 20.11.2026, nach den ersten Läufen nachführen). Annahmen: ungefähr
20 Nächte im Monat mit neuem Commit, 60 Pushes mit Code-Änderung, davon 20 mit Web-Änderung, 2 Läufe von Hand mit
`nightly=true`. Lokal gemessen: Oberflächentests 0:45 min, Release-Build 0:50 min (warm); auf dem Runner ohne Cache
deutlich länger angesetzt.

| Job | Minuten je Lauf | Läufe im Monat | Minuten im Monat |
|---|---|---|---|
| `macos` (Flutter einrichten 2, macOS-Build 4, iOS-Build 4, Oberflächentests 4, Release-Build und Rauchtest 4) | ≈ 18 | 22 | ≈ 400 **macOS** |
| `checks` | ≈ 15 | 60 | ≈ 900 Linux |
| `web` | ≈ 10 | 20 | ≈ 200 Linux |
| `sanitize`, `network-free` | ≈ 8 und 3 | 30 und 80 | ≈ 480 Linux |
| `contract` (emsdk 3, aus dem Zwischenspeicher unter 1, #89; nativ 2, WASM 5) | ≈ 10 | 30 | ≈ 300 Linux |
| `sanitize-thread`, `fuzz` (2 × 20 min, dazu emsdk 3, aus dem Zwischenspeicher unter 1, und WASM 2, #67, #89), `property` | ≈ 10, 50, 10 | 22 | ≈ 1540 Linux |

Das sind rund **400 macOS-Minuten** und rund **3400 Linux-Minuten** im Monat. Bei einem privaten Repository zählt
GitHub macOS-Minuten zehnfach: 400 × 10 = 4000 von 2000 Gratis-Minuten (GitHub Free), also über dem Kontingent; dann
müssten die macOS-Läufe seltener werden (z. B. nur wöchentlich). Das Repository ist öffentlich (GitHub Pages), dort
sind Standard-Runner kostenlos; die Grenze entfällt, die Schätzung bleibt als Richtwert.

## Leistungs- und Lasttests (#59)

Gegenstück zu `bench.rs`, Stresstest und Messtabelle in VivaPlan: Rechenzeit und Speicher von Audio-Kern und
Bibliothek haben Grenzen, damit eine Verschlechterung auffällt, bevor sie hörbar wird. Die Tests laufen **nächtlich**
(Job `bench` in `test-quality.yml`, nur nach einem neuen Commit, von Hand mit `nightly=true`) und mit `make bench`,
nicht bei jedem Push und nicht in `make test`:

- Kern: `core/tests/bench_tests.cpp` wird immer gebaut (Formatierung, `-Werror`, clang-tidy), als ctest-Fall aber nur
  mit `-DWP_BENCH=ON` angemeldet (Label `bench`, `ctest -L bench`, Release-Build in `core/build-bench`).
- Dart: `app/bench/library_bench_test.dart` (Tag `bench`, `app/dart_test.yaml`) liegt ausserhalb von `test/`;
  `flutter test` ohne Pfad erreicht es nicht.
- `make bench` schreibt die Messwerte (Zeilen `BENCH …`) nach `core/build-bench/bench.txt`; der Workflow stellt sie
  mit Rechner und Datum in die Zusammenfassung des Laufs. Eine überschrittene Grenze lässt den Lauf scheitern.

| Fall | Was | Grenze |
|---|---|---|
| `bench_stretch` (#59/AK1) | Time-Stretch je Puffer (512 Frames, 44,1 kHz, Stereo) für 0,1 / 0,25 / 0,5 / 1,0 / 2,0, je 2000 Puffer nach 200 zum Einschwingen; Testsignal mit Teiltönen und Rauschen | Mittelwert und 99. Perzentil je ≤ 50 % des Echtzeitbudgets (11,6 ms) |
| `bench_long_file` (#59/AK2) | 60 min Stereo (16-Bit-WAV, 605 MiB, im Test erzeugt und danach gelöscht): Laden mit Wellenform, zwei Wellenform-Abfragen, vollständiges Offline-Rendern bis zum Ende | Spitzenspeicher Heap ≤ 1,2 × Samples (1211 MiB → 1453 MiB, #75/AK2) |
| `bench_reserve_fallback` (#75/AK1) | 6 min Stereo (WAV, im Test erzeugt); der zählende Allokator lässt die erste Anforderung ab 110 MiB einmal scheitern, also die Reservierung der Länge aus dem Dateikopf (121 MiB): Laden gelingt trotzdem mit allen Frames | – |
| `bench_memory_limit` (#59/AK4) | Selbsttest der Speichergrenze: 128 MiB über der Grenze werfen `bad_alloc`, Laden meldet «kein Speicher», unter Linux scheitert auch `malloc` | – |
| `library_bench_test.dart` (#59/AK3) | 10'000 erfundene Titel in 500 Ordnern (je mit Einstellungen und Loop) in einem temporären Ordner mit leeren Titeldateien: Laden, Sortieren (alle drei Reihenfolgen, Ordner, ein Ordner), Speichern nach einer Änderung, Zusammenführen mit dem Stand eines zweiten Geräts (ein Fünftel bearbeitet, 500 gelöscht, 1000 neu, 50 Ordner umbenannt; `SharedState.merge` und `Library.mergeRemote` mit Schreiben) | Laden, Sortieren, Speichern je ≤ 1 s; Zusammenführen ≤ 2 s |

**Speichergrenze je Testprozess** (#59/AK4):

- Kern, alle Plattformen: `bench_tests` ersetzt `operator new`/`delete`, zählt die belegten Bytes (Grösse vom
  Allokator, `malloc_size` bzw. `malloc_usable_size`) und wirft über der Grenze des Falls `std::bad_alloc`; der Kern
  meldet das als `kErrOutOfMemory`, der Test scheitert. Dekodierte Titel, Wellenform und Stretch-Puffer sind
  `std::vector`, liegen also darunter. Grenzen: Stretch 256 MiB, lange Datei 1,2 × Samples = 1453 MiB (#75/AK2).
- Kern, Linux (Workflow): zusätzlich `setrlimit(RLIMIT_AS)` auf Grenze + 1 GiB (Code, Thread-Stacks, malloc-Arenen);
  das erfasst auch `malloc` in miniaudio. macOS setzt `RLIMIT_AS`, `RLIMIT_DATA` und `RLIMIT_RSS` für mmap-Speicher
  nicht durch, dort gilt der zählende Allokator.
- Kern, nach jedem Fall: Heap-Spitze ≤ Grenze, Spitze des Arbeitsspeichers (`getrusage`, `ru_maxrss`) ≤ Grenze +
  512 MiB. Der Zuschlag deckt Code, Stacks und vom Allokator behaltenen Speicher; auf macOS schwankte `ru_maxrss` beim
  gleichen Fall zwischen 1910 und 2771 MiB (Speicherkompression), die Heap-Spitze gar nicht.
- Dart: Eine harte Grenze wie im Kern gibt es für die Test-VM nicht: `ulimit -v` greift auf macOS nicht, und die VM
  reserviert Adressraum weit über ihrem tatsächlichen Bedarf, eine Adressraumgrenze träfe also nicht den Speicher.
  Der Test prüft deshalb nach jedem Schritt `ProcessInfo.maxRss` (macOS und Linux gleich) gegen 1 GiB und bricht beim
  ersten Überschreiten ab.

**Messwerte** (Release-Build bzw. Test-VM im JIT-Modus; die App läuft AOT und ist schneller):

| Messung | 20.11.2026, MacBook Pro M1 Pro, 16 GB, macOS 26.7 | Grenze |
|---|---|---|
| Stretch 0,1× je Puffer: Mittel / p99 / max | 0,10 / 0,28 / 0,38 ms (0,9 / 2,4 / 3,2 %) | 50 % |
| Stretch 0,25× | 0,10 / 0,28 / 0,37 ms (0,9 / 2,4 / 3,2 %) | 50 % |
| Stretch 0,5× | 0,10 / 0,30 / 0,64 ms (0,9 / 2,5 / 5,5 %) | 50 % |
| Stretch 1,0× (ohne Stretch) | 0,002 / 0,003 / 0,009 ms | 50 % |
| Stretch 2,0× | 0,11 / 0,28 / 0,29 ms (0,9 / 2,4 / 2,5 %) | 50 % |
| Stretch: Heap-Spitze / RSS | 82 / 89 MiB (mit 42 MiB Testsignal) | 256 MiB |
| 60 min: Datei schreiben / Laden mit Wellenform / Rendern | 5,5 s / 2,3 s / 2,3 s (1550× Echtzeit) | – |
| 60 min: Wellenform, 2 Abfragen | 6,3 ms | – |
| 60 min: Heap-Spitze / RSS | 1314 / 1351 MiB (1,08 × Samples; vor #75: 2425 / 1910–2771 MiB) | 1453 / 1965 MiB |
| Bibliothek laden (10'000 Titel, 500 Ordner) | 446 ms | 1 s |
| Sortieren alphabetisch / hinzugefügt / eigene / Ordner / in einem Ordner | 46 / 3 / 1 / 1 / 2 ms | je 1 s |
| Speichern | 266 ms | 1 s |
| Zusammenführen `SharedState.merge` / `Library.mergeRemote` | 171 / 643 ms | 2 s |
| Dart-Testprozess, `maxRss` | 424 MiB | 1 GiB |
| Ganzes `make bench` | 20 s | – |

Die Werte auf dem GitHub-Runner (Linux) stehen nach jedem nächtlichen Lauf in dessen Zusammenfassung; nach dem ersten
Lauf werden sie hier nachgetragen und die Grenzen im Issue bestätigt oder angepasst.

Gefunden beim Messen (siehe «Gefundene Fehler» 19 und 20): Alphabetisches Sortieren brauchte 601 ms (jetzt 46 ms);
ein 60-Minuten-Titel braucht beim Laden doppelt so viel Speicher wie seine Samples.

## Mutationstests (#11)

Mutationstests zeigen, ob die Tests Fehler wirklich erkennen: Ein Werkzeug ändert den Code an einer Stelle (aus `<`
wird `<=`, aus `+` wird `-`, ein Aufruf fällt weg), lässt die Tests laufen und erwartet, dass einer scheitert. Abdeckung
zeigt nur, was ausgeführt wird. Vorbild ist VivaPlan (cargo-mutants, #38/#40/#43/#116 dort).

**Ausführen.** `make mutants` mutiert alles, `make mutants-diff` nur die seit `BASE` (Vorgabe `origin/main`) geänderten
Zeilen (Commits seit der Basis und Arbeitsbaum, wie `coverage-diff`). Beides ruft `app/tool/mutants_run.dart` auf
(`MUTANTS_JOBS`, Vorgabe 4; `MUTANTS_ARGS`, z. B. `--part core`, `--part dart`, `--file engine` oder `--fresh`). Die
Ergebnisse liegen in `local/mutants/full/` bzw. `local/mutants/diff/` (nicht eingecheckt): `summary.txt` (Zahlen je
Teil, jeder nicht erkannte Mutant mit Datei, Zeile und Spalte), `missed.txt` (nur die nicht erkannten) und
`results.json` (alle Mutanten, für die Übersichtsseite #12). Das Werkzeug endet mit Code 3, wenn ein Mutant nicht
erkannt und nicht begründet ausgeschlossen ist, mit 2 bei einem Werkzeugfehler, sonst mit 0 (`make` meldet jeden Code
ausser 0 als Fehler). Zeitüberschreitungen zählen wie in
VivaPlan als erkannt (Endlosschleife).

**Werkzeuge und Lizenzen (AK6).**

| Teil | Werkzeug | Lizenz | Begründung |
|---|---|---|---|
| C++-Kern (`core/src`, `core/web`) | [Mull](https://github.com/mull-project/mull) 0.39.1: Compiler-Plugin `mull-ir-frontend-<LLVM>` und `mull-runner` | Apache-2.0 | nur als Werkzeug genutzt, nichts davon geht in die App; Apache-2.0 ist MIT-verträglich. Mutiert auf LLVM-IR-Ebene und schaltet die Mutanten zur Laufzeit um: ein Bau für alle Mutanten statt einem je Mutant. |
| Dart-Logik (`app/lib`) | eigenes Werkzeug `app/tool/mutants.dart` | MIT (Projekt) | keine neue Abhängigkeit (ein Paket ist nicht freigegeben, Vorschlag im Issue); einfache Mutationen reichen für die Logik |

Installation von Mull (Entwicklerrechner, nicht Teil der App): das offizielle Paket der GitHub-Releases passend zur
LLVM-Version von Homebrew (`clang --version` von `$(brew --prefix llvm)/bin`, Stand LLVM 23):
`Mull-23-0.39.1-LLVM-23.1.4-macOS-aarch64-26.7.2.zip` (Plugin), `Mull-0.39.1-macOS-aarch64-26.7.2.zip` (`mull-runner`,
`mull-reporter`), nach `~/.local/opt/mull` entpackt (`bin/`, `lib/`). Ein anderer Ort über `MULL_DIR` oder
`MULL_RUNNER` und `MULL_PLUGIN`, ein anderer Compiler über `MULL_CC`/`MULL_CXX` (gleiche LLVM-Hauptversion wie das
Plugin). Im Workflow: die Debian-Pakete für Ubuntu 24.04 und LLVM 18 (`clang-18`).

**C++-Kern mit Mull.**

- Eigener Bau `core/build-mutants` (Debug mit `-O1`, Asserts an; ASan und UBSan wie `make sanitize`). Nur die eigenen Ziele laden das Plugin (`wp_mutate` in `core/CMakeLists.txt`), mutiert werden laut
  `core/tests/mutants/mull.yml` nur `core/src/` und `core/web/`; `core/third_party/`, die Tests, `recorder_mac.mm`
  (Systemton-Aufnahme, braucht echten Ton und die Erlaubnis, #51), `miniaudio_impl.c` und `w0_bridge.cpp` nicht.
  Operatoren: Arithmetik, Vergleiche und Grenzen, Logik, Negation, `++`/`--`, `+=`/`-=`, Wegfall eines
  `void`-Aufrufs.
- Mulls Prüfung, ob ein Mutant im Quelltext existiert (Junk-Erkennung), liest die mit `-grecord-command-line`
  gespeicherte Befehlszeile und trennt sie an Leerzeichen; der Projektpfad hat eines. Das Werkzeug baut deshalb über
  einen Link ohne Leerzeichen im temporären Ordner.
- **Testauswahl (AK3):** Jedes Testprogramm des Kerns läuft einzeln unter `mull-runner` (`engine_tests`,
  `metronome_tests`, `waveform_tests`, `player_tests`, `recorder_tests`, `capi_tests --null-backend`, `device_tests`,
  `realtime_tests`, `reference_tests`, `fuzz_decoder_replay`, `fuzz_capi_replay`; nicht die Leistungstests aus #59) und führt jeden
  Mutanten aus, der in ihm steckt. Ein Mutant ist erkannt, wenn ein Programm ihn erkennt. Mulls Abdeckungsfilter
  (nur ausgeführte Zeilen mutieren) ist bewusst aus: Er übersprang Funktionen, die die Tests ausführen
  (`Engine::apply` in `engine_tests`, die ganze geteilte Bibliothek in `capi_tests`). Mulls Zwischenspeicher
  (`local/mutants/core-cache.db`) behält erkannte Mutanten auch nach einer Änderung des Testprogramms; nur die
  übrigen laufen erneut. `--fresh` beginnt neu.
- **Schneller Schalter:** Mull fragt bei jedem Aufruf einer mutierten Funktion `getenv(<Mutant>)`, ob der Mutant
  aktiv ist. In den Render-Schleifen (je Sample) brauchten die Metronom-Tests so 65 s statt 0,7 s, die Engine-Tests
  endeten nicht in 200 s. `core/tests/mutants/mutant_switch.cpp` ersetzt im Mutationsbau `getenv` und beantwortet die
  Mutanten-Namen (Präfix `cxx_`) aus der beim Start gelesenen Umgebung; welcher Mutant läuft, ändert sich nicht.
- Ein Mutant, der ausserhalb eines Puffers schreibt, wird von ASan erkannt wie im Workflow-Job `sanitize`. Lecks zählen
  nicht (`detect_leaks=0`, LeakSanitizer läuft auf macOS nicht; so ergeben beide Systeme dieselben Mutanten).

**Dart-Logik mit eigenem Werkzeug.**

- **Umfang:** Dateien in `app/lib/` ohne Oberfläche (kein Import von `flutter/material`, `widgets`, `cupertino`,
  `material_ui`) und ohne Web-Code (`dart:js_interop`, `package:web`, `*_web.dart`), ohne `main.dart`, `smoke.dart`
  (Start der App, Rauchtest) und die erzeugten `l10n`-Dateien. Die Oberfläche prüfen Widget- und Oberflächentests, den
  Web-Code die Web-Tests im Chrome (`make test-web`).
- **Mutationen** nur im Code, nie in Kommentaren oder Zeichenketten: Vergleiche (`<`↔`<=`, `>`↔`>=`, `==`↔`!=`),
  `&&`↔`||`, `+`↔`-`, `*`↔`/`, `~/`→`*`, `%`→`~/`, `+=`↔`-=`, `++`↔`--`, Wegfall eines vorangestellten `!`,
  `true`↔`false`, Wegfall eines Aufrufs, der allein auf einer Zeile steht. Binäre Operatoren erkennt das Werkzeug an
  den Leerzeichen, die `dart format` immer setzt (`List<int>` und `=>` bleiben unberührt).
- **Testauswahl (AK3):** je Datei die Testdateien mit dem kürzesten Importweg: die, die sie direkt importieren; nur
  wenn es keine gibt, die über eine Datei dazwischen, und so weiter. Die Widget-Tests erreichen über die Oberfläche
  fast jede Datei und machten jeden Mutanten minutenlang; die Logik prüfen ihre eigenen Tests. Ein Mutant läuft in
  einer von `MUTANTS_JOBS` Kopien von `app/` (`local/mutants/<Lauf>/dart/ws<n>`, ohne Build-Ordner; die Ordner neben
  `app/` als Links) mit `flutter test --no-pub --concurrency 2 <Testdateien>`.
- Ein Mutant, der nicht übersetzt, zählt als «nicht übersetzbar», nicht als erkannt.

**Grenzen: Zeit, Speicher, Parallelität (AK3, AK4).**

| | C++-Kern | Dart-Logik |
|---|---|---|
| Zeitlimit je Mutant | max(10 × Dauer des unveränderten Programms, 20 s) (`--minimum-timeout`); Aufwärm- und Basislauf 300 s | max(3 × Dauer des unveränderten Testlaufs der Datei, 60 s) |
| Speicher je Testprozess | 1024 MiB (`WP_TEST_MEMORY_LIMIT_MB`, `--memory-mib`): Wächter-Thread in jedem Testprogramm (`core/tests/mutants/memory_guard.cpp`) prüft alle 2 ms den physischen Speicher (macOS `phys_footprint`, Linux `/proc/self/statm`) und beendet das Programm mit Code 86 (zählt als erkannt). Eine Adressraumgrenze (`RLIMIT_AS`) gibt es im Mutationsbau nicht: ASan reserviert Terabytes Adressraum für seinen Schattenspeicher | 4096 MiB für `flutter test` mit allen Kindprozessen (Compiler, Test-VM), von aussen alle 250 ms über `ps` gemessen; darüber wird der ganze Prozessbaum beendet (zählt als erkannt, Vermerk «memory limit») |
| Parallele Prozesse | `MUTANTS_JOBS` Mutanten gleichzeitig (Vorgabe 4, `--workers`) | `MUTANTS_JOBS` Kopien, je `flutter test --concurrency 2` |
| Grösster Speicherbedarf | 4 × 1 GiB | 4 × 4 GiB, gemessen je Lauf rund 1–1,7 GiB |

macOS setzt `RLIMIT_AS` nicht durch (#59), deshalb messen beide Teile selbst. Ein Selbsttest beweist die Grenzen:
`core/tests/mutants/selftest.cpp` hat zwei Schleifen, deren Mutant `i += 1` → `i -= 1` endlos läuft, einmal mit
wachsendem Vektor, einmal ohne Speicher; `make mutants` verlangt «erkannt» (Speicherwächter) und «Zeitüberschreitung»
(5 s), sonst bricht es ab. Für Dart prüfen `app/tool/mutants_test.dart` (`#11/AK4`) Endlosschleife und wachsenden
Speicher in einem Kindprozess.

**Einzeln beurteilen, kein Score-Ziel (AK2).** Jeder nicht erkannte Mutant wird mit einem Test getötet oder mit
Begründung in `tools/mutants-exclude.txt` ausgeschlossen. Erlaubt sind vier Arten: **gleichwertig** (das Ergebnis bleibt
bei jeder Eingabe gleich), **Grenzfall** (der Mutant ändert nur das Verhalten bei exakter Gleichheit gerechneter
Werte oder innerhalb einer Toleranz), im Kern dazu **Speicherfreigabe** (nur ein Leck, ohne beobachtbare Wirkung;
Lecks zählen im Mutationslauf nicht) und **Mull-Grenze** (Mull schaltet den Mutanten nicht wirksam; von Hand
gemessen: ohne den Aufruf scheitert ein Test, der Eintrag nennt ihn) (#61/AK3). Ein Eintrag ohne Begründung bricht
den Lauf ab. Die Einträge sind an Datei,
Mutator und Quelltextzeile gebunden, nicht an die Zeilennummer; ändert sich die Zeile, erscheint der Mutant wieder und
wird neu beurteilt. Ein voller Lauf meldet Einträge ohne Treffer. Einen Mutation Score als Zielwert gibt es nicht.

**Vor dem Push und nächtlich (AK5).** Der `test-agent` lässt im Vollmodus `make mutants-diff` laufen und meldet jeden
nicht erkannten Mutanten mit Datei und Zeile (`.claude/agents/test-agent.md`). Im Workflow läuft der Job `mutants-diff`
nächtlich (nach einem neuen Commit, von Hand mit `nightly=true`) gegen den letzten erfolgreichen Nachtlauf, höchstens
3 Tage zurück, sonst gegen den Stand vor 24 Stunden; die Zusammenfassung steht im Lauf, die Ergebnisse im Artefakt
`mutants-diff`. Nicht erkannte Mutanten lassen den Job scheitern, Zeitüberschreitungen nicht.

**Messung und Stand.** Gemessen am 20.11.2026 auf einem MacBook Pro M1 Pro (10 Kerne, 16 GB), macOS 26.7, Stand 871b6dc
mit den Änderungen von #11, `make mutants` mit 4 parallelen Mutanten:

| Teil | Mutanten | erkannt | Zeitüberschreitung | nicht übersetzbar | ausgeschlossen | nicht erkannt (offen) | Laufzeit |
|---|---|---|---|---|---|---|---|
| C++-Kern (Mull) | 585 | 481 | 11 | 0 | 64 | 29 | 26 min ohne Zwischenspeicher, 35 s mit |
| Dart-Logik | 1022 | 651 | 26 | 74 | 12 | 259 | 72 min |

Vor #11 erkannte der Kern im ersten Lauf (ohne ASan) rund 170 Mutanten nicht, die Dart-Logik 312. Dazugekommen sind
Tests in `core/tests/engine_tests.cpp`, `metronome_tests.cpp`, `waveform_tests.cpp`, `player_tests.cpp`,
`reference_tests.cpp` (Fall «#11 browser entry points at their limits») sowie `app/test/player_service_test.dart`
(Gruppe «#11 PlayerService …») und `app/test/mutation_cases_test.dart`, alle mit `#11` im Namen oder Kommentar; dazu
zwei `assert` an den Puffergrenzen von `core/src/engine.cpp`. Was dabei auffiel, steht unter «Gefundene Fehler» (21,
22).

**Grenze von Mull:** Einige Mutanten «Aufruf entfernen» schaltet Mull nicht wirksam: Mit gesetzter Umgebungsvariable
des Mutanten verhält sich das Programm unverändert, obwohl ein Test sicher scheitern müsste (z. B. `Player` ohne
`engine_.configure` liefe mit 44,1 statt 48 kHz, `loadAsync` ohne `cancelLoad` endete mit `std::terminate`). Betroffen
sind vor allem Konstruktoren, Destruktoren und Funktionen mit `lock_guard` oder `try`. Gemessene Fälle sind
ausgeschlossen (in #11 als «gleichwertig», seit #61 als «Mull-Grenze», mit dem Test, der den von Hand entfernten
Aufruf erkennt). Mulls Abdeckungsfilter ist aus demselben Grund aus (siehe oben).

**Aufnahme (#68):** `recorder_core.cpp` (aus `recorder_mac.mm` herausgelöst) wird mutiert und von `recorder_tests`
geprüft: 65 Mutanten, 51 erkannt, 8 Zeitüberschreitungen, 6 begründet ausgeschlossen (drei gleichwertige, drei in
Destruktoren nach der Grenze oben, von Hand gemessen), keiner offen.

**Stand nach #61 (AK2 erfüllt):** Der volle Lauf meldet keinen offenen Mutanten mehr. Gemessen am 20.11.2026, Stand
8c26733 mit dem Test zu `Library.dispose` aus dem Abschluss-Commit von #61, `make mutants` mit 6 parallelen
Mutanten:

| Teil | Mutanten | erkannt | Zeitüberschreitung | nicht übersetzbar | ausgeschlossen | nicht erkannt (offen) | Laufzeit |
|---|---|---|---|---|---|---|---|
| C++-Kern (Mull) | 666 | 584 | 19 | 0 | 63 | 0 | 37 s mit Zwischenspeicher (20 min nach neuem Bau) |
| Dart-Logik | 1065 | 703 | 254 | 57 | 51 | 0 | 98 min |

Zeitüberschreitungen zählen als erkannt; ihre Zahl hängt von der Last ab (6 parallele Mutanten, daneben andere
Läufe). Darum meldet der Lauf 16 Ausschlüsse ohne Treffer: Ihre Mutanten endeten diesmal mit Zeitüberschreitung oder
wurden in den Fuzz- und Referenzläufen erkannt. Die Einträge bleiben stehen, solange ihre Begründung stimmt.

Ausgangslage war der Lauf aus #11 mit 288 offenen Mutanten (29 Kern, 259 Dart); vor #61 waren es nach #62–#76 noch
172 (39 Kern, 133 Dart, die Zeilen hatten sich teils verschoben). Jeder davon ist jetzt von einem Test erkannt oder in
`tools/mutants-exclude.txt` begründet ausgeschlossen. Neue Tests, je Regel ein Test mit `#nn/AKn` (dem Kriterium, das
er belegt) oder `#61`:

| Bereich | Tests | Was sie prüfen |
|---|---|---|
| `metadata.dart` | `app/test/metadata_test.dart` (Gruppen «#16/AK4 … (#61)») | ID3v2-Kodierungen (UTF-16 mit und ohne BOM, ungerade Länge, Terminator), Struktur (Versionen, Frame-Grenzen, erweiterter Kopf, Unsynchronisation, Kompression), Bilder, FLAC (Blockgrenzen, Kommentarzahl, Bild mit Beschreibung), WAV (LIST/INFO, Füllbytes, id3-Chunk), beschädigter Block am Ende (#91) |
| `stamps.dart` | `app/test/stamps_test.dart` | Stempel (UTC, Vergleich, `parse` und Grenzen), Uhr (`observe`), JSON-Vergleich, Frist der Grabsteine genau 90 Tage |
| `track.dart` | `app/test/track_rules_test.dart` | Loop-ID beim Verschieben und Anlegen, `LoopRange`, alte Einträge, Vorgaben fehlender geteilter Felder |
| `library.dart` | `app/test/library_rules_test.dart` | Benachrichtigung bei jedem Laden, fehlende Dateien, Stempel nach Laden und Abgleich, Abwesenheit von Dateien, Audio aus der Cloud, Speichern (Entprellen mit der Testuhr von `testWidgets`, `flush`, `dispose`), Import, Ordner, Verschieben, Titel und Dauer |
| `sync_engine.dart` | `app/test/sync_rules_test.dart` | Zeitgeber (Testuhr), Wiederholungen ohne Verbindung, Abgleich während eines Abgleichs, Status, Audiodateien, Konflikte, Inhalt von `state.json`, Reparatur, `dispose` |
| übrige Dart-Dateien | `app/test/app_controller_rules_test.dart`, `migration_rules_test.dart`, `support_rules_test.dart`, `mutation_cases_test.dart` | Meldungen und `dispose` des AppController, Titel nur auf einem anderen Gerät, Migration, natürliche Sortierung, Geräte-ID, Dateispeicher, Plattformkanal, Wellenform im Browser, Cloud im Speicher, Metronom nach `restore` |
| Kern | `core/tests/device_tests.cpp` (neu), `core/tests/player_tests.cpp` | Gerätehülle von innen: `player.cpp` wird in das Testprogramm übersetzt, Meldungen von miniaudio und Neustart des Null-Geräts; Reservierung beim Laden aus Datei und Speicher (grösste einzelne Reservierung, stilles FLAC mit falscher oder unplausibler Länge), Fortschritt nach dem Laden, kein Speicher für den Lade-Thread (nativ und im WASM-Build, der wie der Browser-Kern mit `-fwasm-exceptions` übersetzt ist, #93), Stille und Metronom-Rate bei nicht unterstützter Rate |

Ausgeschlossen mit Begründung (Auswahl): im Kern gibt `collectGarbage` bzw. `ma_data_converter_uninit` nur Speicher
frei (Speicherfreigabe), `data.reserve`, `setSampleRate` im Konstruktor und `loader_.join` schaltet Mull nicht wirksam
(Mull-Grenze, von Hand gemessen), die Decoder von miniaudio enden immer mit `MA_AT_END` (gemessen mit ganzen,
abgeschnittenen und verfälschten FLAC-, MP3- und WAV-Dateien); in Dart Anfangswerte, die nie gelesen werden,
Grenzen genau am Datenende, gleiche Werte in Vergleichen und ein nicht erreichbarer Zweig in
`PlayerService.updateSettings`. Am Produktivcode ist für #61 nichts geändert: Kein Mutant zeigte einen Fehler, der eine
Änderung verlangte. Zwei Beobachtungen ohne Änderung stehen im Bericht zu #61 als Vorschlag (ein beschädigter letzter
Block in FLAC oder ein abgeschnittener id3-Chunk in WAV verwirft alle Metadaten der Datei).

## Übersichtsseite Testqualität (#12)

`make report` erzeugt `local/test-quality/report/index.html` aus den vorhandenen Ergebnissen. Die Seite ist statisch
(kein Skript, keine Schrift oder Grafik von aussen), funktioniert ohne Netzwerk und wird nicht eingecheckt (`/local/`
in `.gitignore`). Das Werkzeug ist in Dart ohne Paket geschrieben (`app/tool/report/report.dart`, Aufruf
`report_run.dart`), die Texte der Seite stehen in `app/tool/report/texts_de.json`. Es braucht wenige Sekunden.

| Eingabe | Herkunft |
|---|---|
| JUnit des Kerns | `make test-core` und `make coverage-core`: `ctest --output-junit local/test-quality/junit/core.xml` |
| Ergebnisse der App und der Werkzeuge | `make test-app`, `make test-tools`, `make coverage-app`: `flutter test --file-reporter json:local/test-quality/flutter/app.json` bzw. `tools.json`; `make report` wandelt sie in `junit/app.xml` und `junit/tools.xml` um |
| Abdeckung je Teil | `app/coverage/lcov.info`, `core/build-cov/lcov.info` (`make coverage-run`), Untergrenze `tools/coverage-min`, Teile wie `coverage_check` (#8); dazu die Abdeckung der geänderten Zeilen gegenüber `--base` (Vorgabe `DIFF_BASE`, sonst `origin/main`) |
| Mutationen | `local/mutants/full/results.json` (`make mutants`) für den Status, `local/mutants/diff/results.json` (`make mutants-diff`) als Zusatz (#11) |
| Issues und Kommentare | `gh issue list --state all --json …`, nur beim Erzeugen der Seite (nicht die App) |

Es gibt **keine Gesamtnote**. Jede Schicht hat ihren eigenen Status nach einer Regel, die auf der Seite steht:

| Schicht | erfüllt | Hinweis | nicht erfüllt | keine Daten |
|---|---|---|---|---|
| 1 Hygiene | kein fehlgeschlagener, kein flaky Test | flaky Tests | ein Test schlägt fehl (auch eine Testdatei, die nicht lädt) | keine JUnit-Datei |
| 2 Angemessenheit | C++-Kern und Dart-Logik ≥ Untergrenze, kein nicht erkannter Mutant | Untergrenze erreicht, aber nicht erkannte Mutanten, kein voller Mutationslauf oder ein Teil ohne Daten | ein Teil unter der Untergrenze oder eine Logikdatei, die kein Test lädt | keine Abdeckung |
| 3 Anforderungsbezug | jedes Kriterium mit Test, geprüft oder abgehakt | Kriterien ohne Test, ohne Prüfung und ohne Haken | – | `gh` nicht erreichbar |
| 4 Ergebnis | jeder Fehler mit `found:*` nennt den Test, der ihn hätte fangen müssen, und den Regressionstest | eine Antwort fehlt | – | `gh` nicht erreichbar oder noch kein Fehler mit `found:*` |

Fehlende oder unlesbare Daten erscheinen als «keine Daten», nie als Fehler; die übrige Seite bleibt vollständig.
Flaky heisst: ein Test schlug fehl und bestand bei der Wiederholung im selben Lauf (JUnit `flakyFailure` oder
`rerunFailure`; bei `flutter test` ein Test mit `retry:`, der erst einen Fehler meldet und dann besteht, oder derselbe
Test zweimal mit Fehlschlag und danach Erfolg). `make test` und `ctest` wiederholen von sich aus nichts: Flaky Tests
erscheinen nur, wenn ein Test eine Wiederholung erlaubt; sonst zählen sie als fehlgeschlagen. Die Dart-Oberfläche hat keine Untergrenze und
wird nur gezeigt.

**Zuordnung der Tests (Schicht 3):** Ein Test belegt ein Kriterium mit `#nn/AKn` im Testnamen oder in einem Kommentar
(Dart, C++ unter `core/tests/`), führende Nullen zählen nicht (`#08/AK4` = `#8/AK4`). Steht ein Dart-Test in einer
`group(...)`, deren Titel genau eine Issue-Nummer nennt, genügt `AKn` im eigenen Namen; ohne `AKn` erbt er das
Kriterium der Gruppe (`group('#22/AK2 …')`). Nennt der Titel mehrere Nummern, zählt `AKn` im Testnamen nicht.
`AKn` ist das n-te Kriterium der Häkchen-Liste des Issues. Gelesen werden `app/test/`, `app/integration_test/`,
`app/bench/`, `app/tool/*_test.dart`, `app/packages/*/test/` und `core/tests/`.

**Arten je Kriterium**, in dieser Rangfolge: *mit Test* (gekennzeichneter Test), *geprüft* (Prüfung nach `CLAUDE.md`),
*nur manuell* (abgehakt ohne Test und ohne Prüfung, etwa bei einer Abnahme durch den Anwender), *ohne*. Als Prüfung
zählt ein Kommentar, dessen erste Zeile mit «Prüfung …», «Erneute Prüfung …», «Nacharbeit AKn …» oder «AKn erfüllt in
<Commit>» beginnt und nicht «durch den Anwender» enthält. Darin macht eine Zeile «AKn erfüllt», «AKn ok», «AKn ist
belegt» oder «**AKn Titel** ✅» (auch «AK1, AK3 ok») das Kriterium geprüft, ebenso «Alle n Kriterien sind erfüllt»;
«nicht», «offen», «teilweise», «überholt» oder ❌ nehmen es zurück. Je Kriterium zählt die letzte Aussage. Als «nicht
geplant» geschlossene Issues zählen nicht.

**Verlauf:** Die Kennzahlen (Tests, fehlgeschlagene und flaky Tests, Abdeckung je Teil, nicht erkannte Mutanten,
Anteile der Kriterien mit Test und geprüft, durchgerutschte Fehler) liegen je Version (`version` in
`app/pubspec.yaml`) in `local/test-quality/history/<Version>.json`. Die Seite vergleicht mit der zuletzt erzeugten
anderen Version und zeigt die Richtung (▲ besser, ▼ schlechter). Ein neuer Lauf derselben Version überschreibt ihren
Stand.

**Aufrufe:** `make report REPORT_ARGS="--out build/report --no-gh --summary"` (anderer Zielordner, ohne GitHub, mit
Kurzfassung in Markdown auf der Standardausgabe). Die Tests des Werkzeugs (`app/tool/report/report_test.dart`, Namen
`#12/AKn`, in `make test-tools`) prüfen die Regeln, die Zuordnung, die Prüfkommentare (erfundene Issues in
`app/tool/report/testdata/issues.json`), den Verlauf und einen Lauf in einem gestellten Repository mit und ohne Daten.

## Wackelnde Tests (#62)

**Ursache der vermeintlich wackelnden Widget-Tests.** «#17/AK1 Liste Sortierung umstellen» und «#4/AK3: a refused
start …» sind nie gescheitert. Beide gaben bei jedem Lauf etwas aus: der erste die Warnung von `tap()` «would not hit
test on the specified widget», der zweite die Fehlermeldung aus `debugPrint`. Der Reporter `failures-only` schreibt
dann die Zeile `+402 -1: …/recording_test.dart: #4/AK3 …` mit dem Zähler der bisherigen Fehlschläge, aber ohne
`[E]`. Gescheitert waren in jenen Läufen andere Tests, die gerade in Arbeit waren (#45, #46, `file_store_test.dart`
bei #10). Nachgestellt mit sechs vollen Läufen unter Last (12 CPU-Brenner auf 10 Kernen): alle grün, beide Namen
jedes Mal in der Ausgabe.

Die Warnung kommt daher, dass `CheckedPopupMenuItem` seinen Inhalt in ein `IgnorePointer` legt. Das Tippen auf den
Text «Alphabetisch» trifft darum den Menüeintrag, nicht den Text.

**Behoben:**

- Die Einträge des Sortiermenüs haben Schlüssel (`sort-<name>`, wie `appearance-<name>`); der Test tippt auf den
  Eintrag selbst.
- `test/flutter_test_config.dart` setzt `WidgetController.hitTestWarningShouldBeFatal`: Ein Tippen, das sein Widget
  nicht trifft, lässt den Test scheitern, statt eine Warnung auszugeben. Das gilt für alle Tests unter `app/test/`.
- `recording_test.dart` fängt die Meldung des abgelehnten Starts ab und prüft sie, statt sie auszugeben.
- Widget-Tests warten auf Zustände wie die Oberflächentests (#13/AK2): `pumpUntil(tester, done, what)` in
  `app/test/fakes.dart` pumpt Bild für Bild auf der Testuhr, bis der Zustand erreicht ist (Grenze: 500 Bilder).
  `waitUntil(tester, done, what)` wartet in Echtzeit auf Arbeit ausserhalb der Testuhr (Dateisystem) und scheitert
  nur nach 60 s als Hänger. Vorher wartete `recording_test.dart` (#4/AK4) höchstens 1 s in Echtzeit auf die
  Aufnahme in der Bibliothek; das hätte unter Last wirklich scheitern können. Tests ohne `WidgetTester` warten mit
  `eventually(done, what)` aus derselben Datei. Dass kein Test unter `app/test/` mehr in einer Schleife mit fester
  Höchstzahl wartet (`Future.delayed` oder `sleep` in `for`/`while` ohne `hangGuard`), prüft «#78/AK2 …» in
  `ui_test_rules_test.dart`. Einzelne Pausen ausserhalb einer Schleife erfasst die Prüfung nicht.

**Kein globales `retry` in `dart_test.yaml`.** Entschieden am 20.11.2026: Ein wackelnder Test ist ein Fehler, dessen
Ursache behoben wird. Eine Wiederholung würde ihn verstecken und auch echte Fehler mit zeitlicher Ursache (Rennen,
Echtzeit-Grenzen) durchlassen. Die Übersichtsseite (#12) erkennt wackelnde Tests deshalb nur, wo ein einzelner Test
`retry:` ausdrücklich setzt; heute tut das keiner.

**Ausgabe lesen:** Im Reporter `failures-only` ist nur eine Zeile mit `[E]` ein Fehlschlag. Eine Zeile ohne `[E]`
heisst nur, dass der Test etwas ausgegeben hat. Absichtlich geben nur die Zufallstests (#10) ihren Startwert aus.

**Nachweis (AK2):** 20 volle Läufe von `flutter test` hintereinander am 20.11.2026, davon 8 unter Last (12 CPU-Brenner
auf 10 Kernen), alle grün; MacBook Pro M1 Pro, macOS 26.7.

## Hook nach dem Commit

`.claude/hooks/after-commit.sh` läuft nach jedem `git commit` aus Claude Code. Er prüft das Format der Nachricht
(`Titel (#22)`), baut und testet die betroffenen Teile selbst (Kern: CMake und `ctest`; App: `flutter analyze` und
`flutter test`; Kern oder Plugin: `flutter build macos --debug` und `flutter build ios --simulator --debug`; Swift:
`xcodebuild`; der Hook selbst, `app/tool/` oder `tools/git-hooks/`: die Werkzeugtests mit `make test-tools`, #69) und meldet nur Fehler oder geänderte Logik ohne Tests, dann mit Auftrag an
den `test-agent`. Die volle Ausgabe liegt unter `$TMPDIR/woodshed-hook/`.

Die Tests des Hooks (`app/tool/after_commit_hook_test.dart`, `make test-hook`) legen je Fall ein kleines Git-Repository
an und ersetzen `cmake`, `ctest`, `flutter`, `make` und `xcodebuild` durch Skripte, die ihre Argumente aufschreiben und auf
Wunsch fehlschlagen. Geprüft werden Dart-Änderung, C++-Änderung, Logik ohne Test, Fehlschlag, Swift-Änderung, reine
Dokumente, Format der Nachricht, andere Befehle, `test(auto)`-Commits sowie Änderungen am Hook selbst, unter `app/tool/` und unter `tools/git-hooks/` (#69).

## Gefundene Fehler

Mit dieser Strategie gefunden (Datum, was, wo, Test):

1. 19.11.2026, #7: `core_error_texts_test.dart` las die Fehlertexte der Dart-Anbindung mit einem regulären Ausdruck,
   der nach dem Umbruch durch `dart format` nichts mehr fand. Der Test erlaubt jetzt einen Zeilenumbruch nach
   `WpException(`.
2. 19.11.2026, #7, clang-tidy: tote Zuweisung in `player_tests.cpp`, `atof` ohne Fehlerprüfung in
   `core/tools/wp_render.cpp` (jetzt `strtod`), Zuweisungen in `if`-Bedingungen in `recorder_mac.mm`, unnötige
   Kopie des Pfads in `Player::runLoad`. Kein Fehlverhalten der App.
3. 19.11.2026, #7: Im vollen, parallelen Lauf von `flutter test` schlugen `home_page_test.dart` («#17/AK1 Liste
   Sortierung umstellen», Tippen ging daneben) und `recording_test.dart` (#4/AK3) in zwei von sechs Läufen
   gemeinsam fehl; einzeln immer grün. Vermutlich abhängig von der Rechnerlast (parallele Testprozesse), noch nicht
   behoben und noch keinem Issue zugeordnet. Geklärt in #62: kein Fehlschlag, nur Ausgabe, die im Reporter
   `failures-only` wie ein Fehler aussah (Abschnitt «Wackelnde Tests (#62)»). Regressionstest: «#17/AK1 Liste
   Sortierung umstellen» mit `hitTestWarningShouldBeFatal` (`test/flutter_test_config.dart`) und «#4/AK3: a refused
   start …», der die Meldung abfängt und prüft.
4. 19.11.2026, #9: Das Metronom übersprang einen Schlag, wenn die Unterteilung genau an einer Schlaggrenze oder
   im Rest eines Schlags nach dessen letztem Klick wechselte (`Metronome::applyCommands`): Der Zähler war schon auf
   den nächsten Schlag weitergerückt und wurde beim Neuplanen ein zweites Mal weitergezählt. Folge: Die Betonung des
   nächsten Takts kam als gewöhnlicher Schlag, das 6/8-Muster war verschoben. Gefunden mit der Golden-Datei
   (`reference_tests.cpp`, #9/AK5), behoben, Test `subdivisionChangeKeepsBeat` (`metronome_tests.cpp`, #3/AK10).
5. 19.11.2026, #9/AK7: Nativer Kern und WASM-Kern lieferten beim Time-Stretch verschiedene Samples (bis 2,1e-2 bei
   Tempo 0,1, 3,9e-3 bei 2,0, 9,7e-5 bei 0,5; ohne Stretch bitgleich). Ursache: Apple-Clang fasst auf arm64
   Multiplikation und Addition zu FMA zusammen, WebAssembly nicht. Behoben mit `-ffp-contract=off` in CMake und im
   Flutter-Plugin; jetzt bitgleich.
6. 19.11.2026, #9: `sanitizer_selftest_thread` (#57) schlug in `make sanitize-thread` einmal fehl, als parallel
   `make coverage` lief; einzeln dreimal grün. Der absichtliche Wettlauf wird unter starker Last offenbar nicht immer
   erkannt. Noch nicht behoben und noch keinem Issue zugeordnet.
7. 19.11.2026, #10/AK4, `fuzz_decoder`: Float-WAV-Dateien mit NaN, unendlichen oder riesigen Samples wurden
   unverändert übernommen; sie wären ans Gerät gegangen und hätten den Time-Stretch für den Rest des Titels
   vergiftet. Behoben in `player_core.cpp` (`sanitizeSamples`: nicht endlich wird Stille, sonst auf ±8 begrenzt,
   beim Dekodieren und beim Wandeln von PCM). Regressionsfall `regressions/decoder/nan_float_wav`.
8. 19.11.2026, #10/AK4, `fuzz_decoder`: Ein beschädigter MP3-Kopf (Xing-Rahmenzahl) liess wenige Bytes 24 GB
   reservieren (`readAll` reservierte die Länge aus dem Kopf). Auf iPhone/iPad hätte das «kein Speicher» statt
   «Format nicht unterstützt» gemeldet. Behoben: im Voraus höchstens 5 min, längere Titel wachsen beim Dekodieren.
   Regressionsfall `regressions/decoder/huge_length_header`.
9. 19.11.2026, #10/AK4, `fuzz_capi`: NaN oder unendlich als Lautstärke oder Tempo über die C-API machten jedes
   folgende Sample NaN; Seek und Loop-Ende mit riesigen Zeiten verliessen über `llround` den Bereich von `long long`
   (auf x86 ein negativer Lesezeiger). Behoben in `engine.cpp` (NaN-Seek und -Tempo ignoriert, Zeiten bis 10⁶ s,
   Lautstärke 0–1, NaN = still) und `metronome.cpp` (NaN-Lautstärke = still). Regressionsfall
   `regressions/capi/nonfinite_arguments`, Tests `nonFiniteArgumentsAreSafe` (`engine_tests.cpp`) und
   `volumeChangeWithoutCrackle` (`metronome_tests.cpp`). In der App nicht erreichbar (die UI begrenzt die Werte).
10. 19.11.2026, #10/AK1, Zufallstest: `Library.moveTracks` mit negativer Zeile warf einen `RangeError`. Die App ruft
    es nie so auf; jetzt zählt eine negative Zeile als erste. Regressionsfälle in `regressions.json`.
11. 19.11.2026, #10/AK1, Zufallstest: Gespeicherte Loop-Grenzen, die nach dem Begrenzen auf die Dauer weniger als
    1 s auseinander lagen (z. B. Loop 10–11 s eines anderen Geräts, hier 10,5 s Dauer), blieben «an», ohne den Kern
    zu erreichen. Behoben in `PlayerService._normalized` (wie beim Setzen des Endes: Ende auf Anfang + 1 s oder
    Anfang auf Ende − 1 s). Regressionsfall und Tests «loop bounds of stored settings» (`player_property_test.dart`).
12. 19.11.2026, #10/AK5, Golden-Datei: Ein Titel aus dem ältesten Swift-Format `[Track]` mit `folderID` (Ordner gab es
    in der Datei nicht) war nach der Migration bis zum nächsten Start in keinem Ordner sichtbar. Behoben in
    `Library._migrate`; `file_store_test.dart` (#36/AK3) erwartet für diese Datei jetzt «ohne Ordner».
13. 19.11.2026, #10/AK8, Zufallstest: Eine Zahl ausserhalb des Bereichs eines double (`1e400`) in `library.json` las
    Dart als unendlich; jedes Speichern warf danach eine Ausnahme direkt in die Oberfläche statt «konnte nicht
    gespeichert werden» zu melden. Behoben: Eine solche Datei gilt als beschädigt (`isFiniteJson`), `_write` meldet
    Fehler über die Future. Regressionsfall und Test «a number beyond the range of a double».
14. 19.11.2026, #10/AK6, Zufallstest Abgleich: Das erste Speichern eines neuen Geräts stempelte seine
    Standardwerte (Sortierung «hinzugefügt», Darstellung «System») als jüngste Änderung; sein erster Abgleich setzte
    die auf allen anderen Geräten gewählte Sortierung und Darstellung zurück, und die Geräte waren nach zwei Runden
    nicht gleich. Behoben: nie gewählte Standardwerte werden nicht gestempelt (`Library._chosenSettings`).
    Regressionsfall und Test «a new device does not reset the settings chosen on the others».
15. 19.11.2026, #10/AK7, Zufallstest Abgleich: Eine `state.json` mit `1e400` wurde zusammengeführt; danach scheiterte
    jedes Speichern der Bibliothek, Änderungen gingen nicht mehr auf die Platte. Ebenso wurden Typwechsel
    übernommen. Behoben: `CloudSync._readState` prüft vor dem Zusammenführen, Stempel ausserhalb des Bereichs gelten
    als ungültig (`Hlc.parse`), Meldungen `cloudStateUnreadable` und `cloudStateTooNew`. Regressionsfall und Test
    «one message per damaged version».
16. 19.11.2026, #10: Im vollen Lauf von `flutter test` schlug `home_page_test.dart` («#17/AK1 Liste Sortierung
    umstellen») erneut einmal fehl, einzeln grün; wie Fall 3, noch nicht behoben. Geklärt in #62 wie Fall 3:
    Gescheitert war `file_store_test.dart`, der Test gab nur die Warnung von `tap()` aus. Regressionstest wie bei
    Fall 3.
17. 20.11.2026, #13/AK4, Web-Test in Chrome: In Debug-Builds der Web-App (`flutter run -d chrome`, DDC) scheiterte
    jedes Laden eines Titels mit «Format nicht unterstützt». `postMessage` konnte die konstante leere Argumentliste
    (`const []` mit `toJS`) nicht klonen (`DataCloneError`); im Release-Build (dart2js) trat es nicht auf. Behoben in
    `audio_core_web.dart` (`_plain`: neue, einfache JS-Liste je Nachricht). Test `web_core_test.dart`.
18. 20.11.2026, #13, Oberflächentest ohne Audiogerät: Nach einem Seek im Pausenzustand fragt `PlayerService` die
    Position nur einmal ab und hört dann auf. Antwortet das Gerät langsamer als ein Abfragetakt (33 ms, so beim
    Null-Gerät), bleibt die alte Position stehen, bis wieder gespielt wird; Knöpfe wie «Anfang hier» nehmen dann die
    alte Position. Mit echtem Gerät nicht beobachtet. Die Tests setzen den Loop deshalb aus dem Zustand nach Pause
    und während der Wiedergabe; Behebung als eigenes Issue vorgeschlagen. Behoben in #73: Nach einem Seek fragt
    `PlayerService` weiter ab, bis der Kern die neue Position meldet (höchstens 30 Takte, etwa 1 s), und zeigt bis
    dahin das Ziel statt der alten Position. Regressionstest: Gruppe «#73 position after a seek while paused» in
    `player_service_test.dart` (verzögerter Ersatzkern, Takte von Hand ausgelöst).
19. 20.11.2026, #59/AK3, Lasttest Bibliothek: Alphabetisches Sortieren von 10'000 Titeln brauchte 601 ms (Grenze 1 s,
    auf einem langsameren Rechner darüber). `naturalCompare` faltete und zerlegte beide Titel bei jedem der rund
    130'000 Vergleiche neu. Behoben: `NaturalKey` wird einmal je Titel berechnet (`sortedNaturally`, für Titel und
    Ordner), jetzt 46 ms bei gleicher Reihenfolge. Test «#59 sortedNaturally … sorts like naturalCompare»
    (`library_test.dart`).
20. 20.11.2026, #59/AK2, Lasttest lange Datei: Ein 60-Minuten-Titel (1211 MiB Samples) braucht beim Laden 2425 MiB
    Heap und behält danach 1615 MiB. `readAll` reserviert höchstens 5 min im Voraus (Fall 8), darüber wächst der Puffer
    geometrisch; der letzte Schritt hält 40 und 80 min Platz zugleich, 20 min davon bleiben ungenutzt belegt. Nicht
    im Rahmen von #59 behoben (Änderung des Ladens); die Grenze des Tests (3 GiB) hielt den damaligen Stand fest.
    Behoben mit #75: Sobald 5 min dekodiert sind, reserviert `readAll` einmal die Länge aus dem Dateikopf, wenn die
    Dateigrösse sie plausibel macht (mindestens 500 Byte je Sekunde); scheitert das mit `bad_alloc`, wächst der Puffer
    wie bisher. Spitze jetzt 1314 MiB (1,08 × Samples), Grenze 1,2 × Samples. Tests `longTitleReservesHeaderLength`,
    `longTitleWithWrongHeaderLength` (`player_tests.cpp`) und `bench_reserve_fallback`.
21. 20.11.2026, #11, Mutationstests (UBSan im Mutationsbau): `wp_web_create(1)` (und `wp::Player` mit 1 Hz) wird
    angenommen, der Time-Stretch teilt bei 1 Hz aber durch 0 (`signalsmith-linear/stft.h`, Blockgrösse 0). Die
    Prüfung lässt jede Samplerate ab 1 Hz zu; sinnvoll wäre eine Untergrenze (z. B. 8000 Hz). Behoben mit #76: Der
    Kern nimmt erst ab `WP_MIN_SAMPLE_RATE` (8000 Hz) an; darunter bleibt der Player stumm, und jedes Laden (auch
    Dekodieren und Wandeln in einen Track) meldet `WP_ERR_UNSUPPORTED_SAMPLE_RATE`, die App zeigt dazu
    `loadUnsupportedSampleRate`. Regressionstest: Referenzfall «#76/AK1 #76/AK2 sample rate lower limit»
    (`core/tests/reference_tests.cpp`, `sampleRateLowerLimit`, 8000 Hz, 7999 Hz, 1 Hz, 0 und −1), nativ (`make test`)
    und im WASM-Kern (`make test-wasm`). Mit #81 schützen sich auch Engine und Metronom selbst: Die Engine
    konfiguriert den Time-Stretch mit mindestens `wp::kMinSampleRate` (`core/src/sample_rate.hpp`, einzige Stelle
    der Untergrenze), das Metronom hebt die Rate darauf an. Tests `stretchRateHasALowerLimit` (`engine_tests.cpp`)
    und `sampleRateHasALowerLimit` (`metronome_tests.cpp`), je 8000 Hz, 7999 Hz, 1 Hz, 0 und −1.
22. 20.11.2026, #11, Mutationstests: Mehrere Regeln waren ausgeführt, aber nicht geprüft und sind jetzt getestet
    (Kanaltrennung und Lautstärke im gedehnten Pfad, Seek genau aufs Loop-Ende, Loop ab 0 s und knapp unter 1 s,
    mehrere Loop-Durchgänge in einem Block, Wellenform je Block, Klangform und Stopp des Metronoms, Neubeginn der
    Steigerung nach Zeit, Ladezustand und Fortschritt). Fehlverhalten der App kam dabei nicht zutage.
23. 20.11.2026, #64, actionlint (ShellCheck SC2086): `pages.yml`, Schritt «Build site», übergab die Schalter für die
    Web-App als ungequotete Variable `$APP_ARGS` (Worttrennung beabsichtigt, aber fehleranfällig bei Leerzeichen im
    Pfad). Jetzt `${APP_DIR:+--app "$APP_DIR"}`. Geprüft von `make lint`.
24. 20.11.2026, #64, actionlint (ShellCheck SC2129, Stil): `test-quality.yml`, Job `changes`, schrieb drei Zeilen
    einzeln nach `$GITHUB_OUTPUT`; jetzt in einem Block. Dabei den Pfadfilter `code` auf alle Workflows erweitert,
    damit eine Änderung an `pages.yml` den Job `checks` (mit actionlint) auslöst. Geprüft von `make lint`.
25. 20.11.2026, #70 (aus #9): Wechselten Taktart und Unterteilung gleichzeitig mitten in einem Schlag, der in der
    neuen Taktart nicht mehr vorkommt (z. B. im 4. Schlag von 4/4 auf 3/4), setzte `Metronome::scheduleTick` den
    Zähler schon beim nächsten Unterteilungsklick auf Schlag 1. Die restlichen Klicks des laufenden Schlags zählten
    als Schlag 1, die Betonung des neuen Takts fehlte, der Takt war um einen Schlag verschoben. Behoben: Die Taktart
    setzt den Zähler nur an einer Schlaggrenze zurück; der laufende Schlag klingt aus, der nächste ist die Eins.
    Hätte gefangen werden müssen von einem Referenzfall mit Taktwechsel mitten im Schlag; die Golden-Datei wechselt
    die Taktart nur in der Nähe von Schlaggrenzen. Regressionstest: Referenzfall «#70/AK2 #70/AK3 #3/AK10 meter and
    subdivision change mid-beat» (`reference_tests.cpp`, nativ und WASM) und `meterAndSubdivisionChangeMidBeat`
    (`metronome_tests.cpp`). Die Golden-Datei bleibt unverändert.
26. 20.11.2026, #72 (aus #58): Die Web-App forderte beim Start `fonts/fallback/roboto/…woff2` an und bekam einen
    404 mit Fehler in der Konsole. Flutters Web-Engine lädt Roboto als Standard-Ersatzschrift von
    `fontFallbackBaseUrl`, wenn die App keine Familie dieses Namens mitbringt; die Adresse zeigt seit #34 auf die
    eigene Seite, dort liegt die Datei nicht. Behoben ohne neue Datei: `pubspec.yaml` meldet die Familie «Roboto»
    als Alias auf `Inter-Regular.ttf`, die Anfrage entfällt. Hätte gefangen werden müssen von einem Starttest der
    gebauten Web-App, der Netzwerk und Konsole prüft; die Web-Tests liefen nur mit `flutter test --platform
    chrome`, das die Schriften nicht wie die gebaute App lädt. Regressionstest: `make test-web-start`
    (`app/tool/web_start_check.dart`) und «#72/AK2 pubspec declares Roboto as an alias …»
    (`web_start_check_test.dart`).
27. 20.11.2026, #94 (aus #77): Im ersten Lauf des Jobs `contract` wichen die Tempo-Fälle zwischen dem nativen Kern
    unter Linux x86_64 und dem WASM-Kern ab (`tempo_0.1` 9,83e-01, `tempo_0.5` 1,07e-02, `tempo_2.0` 2,17e-03). Die
    Länge stimmte (bei 2,0× beide 22 080 Frames; 22 050 ist der erwartete Wert der Prüfung ± 1 %). Ursache 1, belegt:
    `SignalsmithStretch<float>` würfelt mit `std::default_random_engine`, und den legt jede Standardbibliothek selbst
    fest: `minstd_rand` (Faktor 48271) in libc++ (macOS, iOS, Emscripten), `minstd_rand0` (16807) in libstdc++
    (Linux). Gleicher Startwert 42, andere Zahlenfolge. Nachgestellt auf macOS mit Clang und den Headern von libstdc++
    (Homebrew GCC 14): genau 9,83e-01 und 1,07e-02. Der Kern nennt den Generator jetzt selbst
    (`SignalsmithStretch<float, std::minstd_rand>`, `core/src/engine.cpp`); die Ausgabe unter macOS bleibt bitgleich,
    der libstdc++-Bau ist danach in allen Tempo-Fällen bitgleich zu libc++. x86_64 unter Rosetta war schon vorher
    bitgleich zu arm64, die Architektur spielt keine Rolle. Ursache 2, nur mittelbar belegt: Der Stretch reagiert auf
    1 ulp in `sincosf`. Setzt man die 168 von 320 532 Ergebnissen, die Apples libm nicht korrekt rundet, auf den korrekt
    gerundeten Wert, weicht `tempo_2.0` um 1,99e-03 ab. musl (Emscripten) liefert dieselben Werte wie Apple, glibc
    rechnet `sincosf` mit einem eigenen Verfahren. Der Lauf 44809822849 mit dem festen Generator bestätigt das: Es
    blieben 2,12e-02 (0,1×), 1,83e-05 (0,5×) und 2,17e-03 (2,0×), dieselbe Grösse wie im Versuch mit `sincosf`. Die
    gestreckten Tempo-Fälle vergleicht der Vertrag deshalb mit 5e-2 statt 1e-6 (`kStretchTolerance`). Test: Vertragsfälle «#9/AK4 #94/AK2 #94/AK3 tempo …» in
    `reference_tests.cpp`.
28. 21.11.2026, #92 (aus #61): `sync_test.dart`, «#37 triggers … several changes are sent together once», wartete
    fest 80 ms echter Zeit auf den Abgleich, der 20 ms nach der letzten Änderung startet, und danach fest 20 ms auf
    das Ergebnis von `resumed()`. Unter Last (paralleler Mutationslauf) kam der Abgleich zu spät: «Expected: <2>
    Actual: <1>», danach «A CloudSync was used after being disposed», weil der Abgleich nach dem Testende weiterlief.
    Der Test wartet jetzt mit `eventually` (in `sync_test.dart`, Hänger nach 60 s) auf Zustände: den Schreibvorgang
    von `state.json` und den Status `idle`, danach auf die fremde Sortierung. Er prüft weiterhin, dass fünf Änderungen
    genau einmal gesendet werden. Die übrigen Tests der Datei warten nicht auf feste Zeiten. Test: «#92/AK1 start and
    resume sync; several changes are sent together once» in `sync_test.dart`, 20 Läufe neben voller CPU-Last grün.
29. 21.11.2026, #78 (aus #62): Zwei Widget-Tests warteten in `Future.delayed`-Schleifen mit fester Höchstzahl
    (100 bzw. 200 und 20 Runden zu 5 ms, also höchstens rund 1 s Echtzeit) auf Arbeit ausserhalb der Testuhr:
    `home_page_test.dart`, «ins Fenster gezogene Dateien erscheinen in der Liste», und `recording_test.dart`,
    «#4/AK4: a recording plays with tempo and loop like any title». Unter Last hätten sie scheitern können, ohne dass
    etwas falsch ist; beobachtet wurde kein Fehlschlag. Sie warten jetzt mit `waitUntil` bzw. `eventually`
    (`app/test/fakes.dart`, Hänger nach 60 s) auf den Zustand. Die neue Prüfung fand zwei weitere solche Schleifen:
    `until` in `app_controller_test.dart` (200 × 5 ms) und das Warten auf das verzögerte Speichern in
    `library_rules_test.dart` (500 × 10 ms); beide warten jetzt ebenfalls mit `eventually`. Die Regelprüfung von
    #13/AK2 deckte `app/test/` nicht ab. Test: «#78/AK2 widget tests wait for states, not in fixed-count loops» in `ui_test_rules_test.dart`, mit
    den alten Schleifen als Regressionsfall.
30. 21.11.2026, #91 (aus #61): `readMetadata` (`app/lib/library/metadata.dart`) warf bei einem beschädigten Block
    am Dateiende, und die App verwarf darauf alle Felder der Datei: in WAV ein `id3 `-Chunk aus nur «ID3» oder mit
    abgeschnittenem Tag nach einem lesbaren `LIST/INFO`, in FLAC der 4 Byte lange Kopf eines leeren Kommentar- oder
    Bildblocks am Ende. Die Mutanten `_starts` (`<` → `<=`) und `_readFlac` (`p + 4 <= b.length` → `<`) lieferten
    dort mehr Felder als das Original und waren als Grenzfall ausgeschlossen; der Test von #16/AK4 prüfte abgeschnittene
    Tags nur auf «keine Ausnahme». Ein beschädigter `id3 `-Chunk wird jetzt übergangen, ein beschädigter FLAC-Block
    beendet das Lesen; die bis dahin gelesenen Felder bleiben. Die beiden Ausschlüsse sind neu begründet. Test:
    Gruppe «#91 damaged block at the end keeps the fields read so far» (`#91/AK1`, `#91/AK2`) in `metadata_test.dart`.
