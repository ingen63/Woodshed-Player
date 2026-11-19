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
| 2 Audio-Referenzfälle | `core/tests/engine_tests.cpp`, `metronome_tests.cpp`, `player_tests.cpp`; im Web dieselben Fälle unter Node.js (`core/build-wasm`) | Offline-Rendering ohne Audiogerät: Loop-Naht, Seek, Tempo und Tonhöhe, Klickpositionen | teilweise, Ausbau #9 |
| 3 Invarianten und Zufallstests | – | Eigenschaften über viele zufällige Fälle mit festem, ausgegebenem Startwert | Lücke, #10 |
| 4 Robustheit und Fuzzing | `metadata_test.dart` («Unsinn»), `player_tests.cpp` (Ladefehler) | verfälschte Dateien, libFuzzer auf Decoder und C-API, Sanitizer | teilweise, #10 und #57 |
| 5 Golden-Dateien | `app/test/golden/` (`library.json` der Swift-App, alt und neu) | jede Version liest alle alten Stände; Klickpositionen des Metronoms | teilweise, #9 und #10 |
| 6 Oberfläche | Widget-Tests in `app/test/`, Rauchtest `app/integration_test/app_smoke_test.dart`, Prüfseiten im Browser `app/tool/web_*_check.dart` | Layout je Grösse, Bedienung, Texte, Tastenkürzel | teilweise, #13 |
| Werkzeuge | `app/tool/after_commit_hook_test.dart` | Hook nach dem Commit | vorhanden (#7) |

## Testmatrix und QA-Abgleich

Stand 19.11.2026, abgeglichen gegen `app/test/`, `app/integration_test/` und `core/tests/` (dazu die Web-Prüfungen in
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
| Sortieren und Verschieben verlieren und verdoppeln keinen Titel; Speichern und Laden ergibt denselben Stand (Zufallstests) | Lücke | #10 |
| Verfälschte `library.json` (Typwechsel, fehlende Felder, abgeschnitten) ohne Absturz | Lücke | #10 |
| Golden-Dateien jeder Version (auch Format 2), Migration idempotent | Lücke (nur Swift-Stände eingecheckt) | #10 |
| 10'000 Titel in 500 Ordnern: Laden, Sortieren, Speichern je ≤ 1 s | Lücke | #59 |

### Wiedergabe

| Regel / Fall | Abgleich | Issue |
|---|---|---|
| Laden WAV sampelgenau, FLAC, MP3; Dauer ohne Laden | vorhanden: `player_tests.cpp` (`loadsWavSampleExact`, `loadsFlac`, `loadsMp3`, `fileDurationWithoutLoading`) | – |
| Laden im Hintergrund, neueres Laden ersetzt laufendes, Fehler mit Code und englischem Text | vorhanden: `player_tests.cpp` (`loadRunsInBackground`, `newerLoadReplacesRunningLoad`, `loadErrorsHaveCodeAndText`, `errorMessagesAreEnglishAscii`), `player_service_test.dart` (#15/AK3), `core_error_texts_test.dart` (#46) | – |
| Play, Pause, Seek, ±15 s, Lautstärke, Dateiende | vorhanden: `engine_tests.cpp` (`seekSetsPositionAndFirstSample`, `endOfFileStopsAndRestarts`, `volumeScalesDirectOutput`), `player_service_test.dart` (#15/AK1) | – |
| Gerätewechsel pausiert, Position bleibt | vorhanden: `player_tests.cpp` (`devicePolicy`, `deviceChangePausesAndKeepsPosition`) | – |
| Render-Pfad ohne Speicheranforderung, Befehle aus vielen Threads | vorhanden: `engine_tests.cpp` (`renderDoesNotAllocate`, `commandsFromManyThreadsWhileRendering`, Queue-Fälle) | – |
| Wellenform (Minimum/Maximum je Abschnitt, Grenzen) | vorhanden: `waveform_tests.cpp`, `wp_waveform_ffi_test.dart`, `web_binding_test.dart` (#34/AK3) | – |
| Seek auf t beginnt bei Sample round(t × Abtastrate); Pause und Fortsetzen ohne verlorenes Sample | Lücke (Seek nur Position und erstes Sample) | #9 |
| Abgeschnittene oder falsche Audiodateien, Fuzzing von Decoder und C-API | Lücke | #10 |
| AddressSanitizer, UBSan, ThreadSanitizer | Lücke | #57 |
| Lange Datei (60 min): Laden, Wellenform, Rendern, Spitzenspeicher | Lücke | #59 |

### Tempo

| Regel / Fall | Abgleich | Issue |
|---|---|---|
| Tempo 0,1× – 2×, Schritte 0,05, Pfeiltasten | vorhanden: `engine_tests.cpp` (`rateIsClamped`), `player_service_test.dart` («Tempo in 0,05er-Schritten») | – |
| Tonhöhe bleibt, Länge = Eingabe / Rate (0,25 / 0,5 / 1,5 / 2,0) | vorhanden: `engine_tests.cpp` (`stretchKeepsPitchAndChangesLength`, `stretchIsDeterministic`, `rateChangeKeepsPositionAndSignal`, `positionFollowsRate`) | – |
| Dieselbe Prüfung für 0,1 und 1,0 mit 1 % Toleranz | Lücke | #9 |
| Klang gegen AVAudioUnitTimePitch | nur von Hand: `tools/hoervergleich.sh` | – |
| Rechenzeit je Puffer ≤ 50 % des Echtzeitbudgets | Lücke | #59 |

### Loop

| Regel / Fall | Abgleich | Issue |
|---|---|---|
| Loop-Naht sampelgenau, auch mit Tempo | vorhanden: `engine_tests.cpp` (`loopSeamDirectIsSampleExact`, `stretchLoopHasNoGap`) | – |
| Ende ≥ Anfang + 1 s, Loop am Dateiende, zu kurzer Loop, Seek aus dem Loop springt zum Anfang | vorhanden: `engine_tests.cpp` (`loopAtFileEndIsClamped`, `shortLoopIsIgnored`, `seekOutsideLoopJumpsToLoopStart`), `player_tests.cpp` (`loopBoundsWithLoadedFile`), `player_service_test.dart` | – |
| Durchgänge zählen nur beim Sprung vom Ende, nicht bei Seek | vorhanden: `engine_tests.cpp` (`loopPasses*`), `player_service_test.dart` (#29/AK2) | – |
| Steigerung nach Durchgängen (Stufen, Ziel, Zurücksetzen, Speichern) | vorhanden: `loop_ramp_test.dart` (#29), `player_service_test.dart` (#29), `library_test.dart` (#29/AK7) | – |
| Marker ziehen, Zeitfelder, S/E, Ganzer Titel | vorhanden: `home_page_test.dart` (#17/AK4), `player_view_test.dart` (#19/AK7, #19/AK9), `studio_design_test.dart` (#30/AK6) | – |
| Naht mit Rampe über 100 Durchläufe | Lücke | #9 |
| Grenzen nach jeder zufälligen Änderung gültig | Lücke | #10 |

### Zeitformat

| Regel / Fall | Abgleich | Issue |
|---|---|---|
| `mm:ss` formatieren und parsen, ungültige Eingaben | vorhanden: `widget_test.dart` (`formatTime`, `parseTime`) | – |
| `parse(format(x)) == x` für zufällige Zeiten | Lücke | #10 |

### Metronom

| Regel / Fall | Abgleich | Issue |
|---|---|---|
| Klicks sampelgenau ohne Drift, Betonung je Taktart, Unterteilungen, Lautstärke ohne Knacken | vorhanden: `metronome_tests.cpp` (`beatsAreSampleExactWithoutDrift`, `accentsPerMeter`, `subdivisionsAndQuieterSubClicks`, `volumeChangeWithoutCrackle`) | – |
| Steigerung nach Takten und nach Zeit (#23), Wechsel der Betriebsart | vorhanden: `metronome_tests.cpp` (`ramp*`, `timedRamp*`, `switchingModes`), `metronome_test.dart` (#23) | – |
| Einstellungen, Tap-Tempo, Kürzel, nie gleichzeitig mit dem Titel | vorhanden: `metronome_test.dart` (#3/AK20) | – |
| 120 BPM bei 44,1 kHz: 22 050 Samples Abstand über 5 min; Positionen als Golden-Datei | Lücke | #9 |

### Aufnahme (nur Mac)

| Regel / Fall | Abgleich | Issue |
|---|---|---|
| Start, Stopp, Fehler des Kerns statt Aufnahme, Titel nach Gebietsschema, nie auf iPhone/iPad und im Browser | vorhanden: `recording_test.dart` (#4) | – |
| Fehlermeldungen und Berechtigungsdialog mehrsprachig | vorhanden: `recording_messages_test.dart` (#44), `permission_texts_test.dart` (#49) | – |
| Systemton-Aufnahme im Kern (`recorder_mac.mm`, Core Audio Process Tap) | Lücke: braucht echten Systemton, kein automatischer Test | #51 |

### Web/WASM

| Regel / Fall | Abgleich | Issue |
|---|---|---|
| Kern als WebAssembly: dieselben `ctest`-Fälle unter Node.js | vorhanden: `core/build-wasm` (`make test-wasm`), `core/web/web.cmake` | – |
| `wp_core_web.wasm` fürs AudioWorklet: Dekodieren, Seek, Loop, Dateiende, Tempo, PCM für AAC/M4A | vorhanden: `core/web/wp_core_web_test.mjs` (#33) | – |
| Dart-Anbindung per bedingtem Import, Wellenform im Browser | vorhanden: `web_binding_test.dart` (#34) | – |
| Auslieferung auf GitHub Pages, Service Worker für COOP/COEP | vorhanden: `web_hosting_test.dart` (#41) | – |
| Im echten Browser: Position, Pegel, Tempo, Loop, Metronom, Laden ohne Aussetzer, OPFS | nur von Hand: `app/tool/web_core_check.sh`, `app/tool/web_store_check.sh` (#34, #35, #42) | #13 |
| Vertrag nativ ↔ Web: gleiche Samples (Toleranz 1e-6), jede Funktion der C-API in einem Referenzfall | Lücke | #9 |
| `flutter build web` und `flutter test --platform chrome` bei jedem Push | Lücke | #13 |
| Content-Security-Policy mit erlaubten Hosts | Lücke | #58 |
| Web-Audio auf iPhone und Android | nur von Hand (Machbarkeitstest) | #32 |

### Abgleich/Sync

| Regel / Fall | Abgleich | Issue |
|---|---|---|
| Zusammenführen unabhängig von der Reihenfolge und idempotent, Loops einzeln, Grabsteine | vorhanden: `sync_test.dart` (#37/AK1, #37/AK4), `data_model_test.dart` (#36/AK2) | – |
| Ohne Konto keine Verbindung | vorhanden: `sync_test.dart` (#37/AK2), `sync_app_test.dart` (#37/AK2) | – |
| Warteschlange offline, Wiederholung, Sicherungen unter `backup/`, Auslöser | vorhanden: `sync_test.dart` (#37/AK3, #37/AK6, Auslöser), `sync_app_test.dart` | – |
| «Nicht hochladen» und «Synchronisieren» im Kontextmenü | vorhanden: `sync_test.dart` (#37/AK5), `sync_app_test.dart` (#37/AK5) | – |
| Zufallsfolgen auf 2–4 Geräten: gleicher Stand, zweiter Abgleich ändert nichts, kein Verlust | Lücke | #10 |
| Verfälschte Sync-Dateien aus der Cloud ohne Absturz und ohne Datenverlust | Lücke | #10 |
| Zusammenführen von 10'000 Titeln ≤ 2 s | Lücke | #59 |
| Nur die Anbietermodule öffnen Verbindungen | Lücke | #58 |
| Anbieter Google Drive, OneDrive, direkte Verbindung | Lücke (noch nicht umgesetzt) | #54, #55, #56 |

### Oberfläche und Sprache

| Regel / Fall | Abgleich | Issue |
|---|---|---|
| Layout Desktop/Tablet/Phone, Bibliothek, Player, Tempo, Loop, Tastatur und Dateien | vorhanden: `home_page_test.dart` (#17), `studio_design_test.dart` (#30), `player_view_test.dart` (#19) | – |
| Darstellung Hell/Dunkel/System, Info-Dialog, App-Icon, Schriftlizenzen | vorhanden: `appearance_test.dart` (#31), `about_test.dart` (#50), `app_icon_test.dart` (#6), `font_licenses_test.dart` | – |
| Jeder Schlüssel in jeder ARB-Datei, kein fester Text im Code, Zahlen nach Gebietsschema, Entwicklermeldungen englisch | vorhanden: `l10n_test.dart` (#43), `english_dev_texts_test.dart` (#45) | – |
| Rauchtest mit echtem Kern je Grösse | vorhanden, nur von Hand (`flutter test integration_test -d macos`): `app_smoke_test.dart` (#17/AK7, #30/AK13) | #13 |
| Tastenkürzel und Import im `integration_test`, Pseudo-Sprache ohne Überlauf | Lücke | #13 |

### Plattformen

| Regel / Fall | Abgleich | Issue |
|---|---|---|
| macOS- und iOS-Build bei jeder Änderung an Kern oder Plugin | vorhanden: Hook nach dem Commit (`.claude/hooks/after-commit.sh`), geprüft in `app/tool/after_commit_hook_test.dart` | – |
| Swift-Altprojekt: Tests und iOS-Build | vorhanden: `WoodshedPlayerTests/` über den Hook (`xcodebuild`) | – |
| Workflow `test-quality.yml` auf Linux, macOS/iOS nächtlich, Rauchtest der gebauten App | Lücke | #13 |
| Windows und Linux: Build, Tests, Windows-Pfade | Lücke | #60 |

### Hygiene und Werkzeuge

| Regel / Fall | Abgleich | Issue |
|---|---|---|
| Formatierung `dart format` und `clang-format`, `make format-check` | vorhanden: `Makefile`, `core/.clang-format` (#7) | – |
| Warnungen sind Fehler: strenge Dart-Analyse, `-Wall -Wextra -Werror`, `clang-tidy` | vorhanden: `app/analysis_options.yaml`, `core/CMakeLists.txt`, `core/.clang-tidy` (#7) | – |
| Hook nach dem Commit mit eigenen Tests | vorhanden: `app/tool/after_commit_hook_test.dart` (#7/AK7) | – |
| Abdeckung je Teil, `coverage-diff`, `pre-push` | Lücke | #8 |
| Mutationstests | Lücke | #11 |
| Übersichtsseite Testqualität | Lücke | #12 |

## Ausführen

```sh
make test           # Kern (ctest), App (flutter test) und die Tests des Hooks
make test-wasm      # Kern unter Node.js (Emscripten)
make format         # dart format (app/) und clang-format (core/, ohne third_party)
make format-check   # schlägt fehl, wenn eine Datei nicht formatiert ist
make lint           # flutter analyze (streng), C++ mit -Werror, clang-tidy
cd app && flutter test integration_test -d macos   # Rauchtest mit echtem Kern
```

Noch nicht eingerichtet; die Ziele melden «noch nicht eingerichtet» mit Issue und brechen ab: `make coverage` und
`coverage-diff` (#8), `make mutants` (#11), `make fuzz` (#10), `make report` (#12), `make sanitize` (#57),
`make network-free` (#58).

Entwicklerwerkzeuge (nicht Teil der App): Flutter, CMake, Emscripten für `test-wasm`, Homebrew `llvm` für
`clang-format` und `clang-tidy` (`brew install llvm`; das Makefile findet sie unter `$(brew --prefix llvm)/bin`).

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

## Hook nach dem Commit

`.claude/hooks/after-commit.sh` läuft nach jedem `git commit` aus Claude Code. Er prüft das Format der Nachricht
(`Titel (#22)`), baut und testet die betroffenen Teile selbst (Kern: CMake und `ctest`; App: `flutter analyze` und
`flutter test`; Kern oder Plugin: `flutter build macos --debug` und `flutter build ios --simulator --debug`; Swift:
`xcodebuild`; der Hook selbst: seine Tests) und meldet nur Fehler oder geänderte Logik ohne Tests, dann mit Auftrag an
den `test-agent`. Die volle Ausgabe liegt unter `$TMPDIR/woodshed-hook/`.

Die Tests des Hooks (`app/tool/after_commit_hook_test.dart`, `make test-hook`) legen je Fall ein kleines Git-Repository
an und ersetzen `cmake`, `ctest`, `flutter` und `xcodebuild` durch Skripte, die ihre Argumente aufschreiben und auf
Wunsch fehlschlagen. Geprüft werden Dart-Änderung, C++-Änderung, Logik ohne Test, Fehlschlag, Swift-Änderung, reine
Dokumente, Format der Nachricht, andere Befehle, `test(auto)`-Commits und die Änderung am Hook selbst.

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
   behoben und noch keinem Issue zugeordnet.
