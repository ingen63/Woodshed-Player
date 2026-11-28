# Arbeitsanleitung für Claude Code

Woodshed Player ist ein Übe-Player für Musiker (Bibliothek, Tempo ohne Tonhöhenänderung, Loops, Metronom, später Aufnahme und Cloud-Sync). Umbau von SwiftUI (`WoodshedPlayer/`, macOS 14+/iOS 17+) auf Flutter (`app/`) mit C++-Audio-Kern (`core/`), Plan in `docs/UMBAUPLAN-FLUTTER.md`. Überblick in `README.md` (Englisch) und `README.de.md` (Deutsch), Funktionen im Detail in `docs/FUNKTIONEN.md`, Bauen und Release in `docs/ENTWICKLUNG.md`. Lizenz MIT.

## Technik

- **App:** Flutter/Dart (`app/`) für macOS, iOS, Windows, Linux und Web. Dart-Pakete stehen in `app/pubspec.yaml`.
- **Audio-Kern:** C++17 mit CMake (`core/`) und C-API `core/include/wp_core.h`.
  - Nativ (macOS, iOS, Windows, Linux) bindet das FFI-Plugin `app/packages/wp_core/` den Kern über `dart:ffi` an (Windows und Linux: `src/CMakeLists.txt` des Plugins).
  - Im Web wird der Kern mit Emscripten zu WebAssembly gebaut (`core/web/`, `core/build-wasm/`) und läuft in einem AudioWorklet. AAC/M4A dekodiert dort der Browser.
- **Bibliotheken im Kern** (header-only, in `core/third_party/`, Versionen dort im README): miniaudio für Dekodieren und Audiogerät, signalsmith-stretch mit signalsmith-linear für Tempo ohne Tonhöhenänderung.
- **Schriften:** Inter und JetBrains Mono (SIL OFL 1.1, `app/assets/fonts/`).
- **Werkzeuge:** clang-format, clang-tidy, `dart format`, `flutter analyze`. Node.js für die WASM-Tests, Python für die Website (`site/`). CI mit GitHub Actions (`.github/workflows/`): `test-quality.yml` für Tests und Qualität, `pages.yml` für Web-App und Website auf GitHub Pages.
- **Altprojekt:** Swift/SwiftUI mit AVFoundation (`WoodshedPlayer/`), gebaut mit Xcode.

## Sprache

- **Mit Dir, in Commits, Issues und Dokumenten** (`docs/`, `README.de.md`): Deutsch mit «ss» statt «ß», Anrede **«Du»**.
- **`README.md` ist englisch**, `README.de.md` die gleichwertige deutsche Fassung mit denselben Abschnitten; Änderungen kommen im selben Commit in beide.
- **Code ist englisch:** Bezeichner, Kommentare, Testnamen, Log- und Fehlermeldungen im Code. Neuer und geänderter Code wird englisch geschrieben. Bestehende deutsche Kommentare übersetzt Du nur in Zeilen, die Du ohnehin änderst; eine Übersetzung in grossem Stil braucht ein eigenes Issue. Test-Kennungen bleiben `#22/AK2`. Das Swift-Altprojekt bleibt, wie es ist.
- **Die Oberfläche ist mehrsprachig.** Englisch ist Standard- und Rückfallsprache, Deutsch die zweite Sprache. Weitere Sprachen kommen nur über eine zusätzliche Übersetzungsdatei dazu, ohne Codeänderung.
  - Texte für die Oberfläche (Beschriftungen, Menüs, Dialoge, Hilfe, Fehlermeldungen an die Nutzerin oder den Nutzer) schreibst Du nie fest in den Code. Sie stehen in ARB-Dateien unter `app/lib/l10n/` (`app_en.arb` als Vorlage, `app_de.arb`) und werden mit Flutter `gen-l10n` erzeugt (`AppLocalizations.of(context)`).
  - Jeder neue Text kommt im selben Commit in **alle** ARB-Dateien. Platzhalter und Mehrzahl schreibst Du im ICU-Format, keine zusammengesetzten Sätze. Zahlen, Zeiten und Grössen formatierst Du nach Gebietsschema (z. B. `1,2 GB` bzw. `1.2 GB`); `mm:ss` bleibt sprachneutral.
  - Die App folgt der Systemsprache. Fehlt sie, gilt Englisch.
  - Tests zur Oberfläche prüfen auf Schlüssel oder setzen die Sprache fest, nie auf zufällig eingestellte Systemsprachen.

## Anforderungen kommen aus GitHub Issues

Jede Änderung hat ein Issue mit **Abnahmekriterien als Häkchen-Liste**; jedes Kriterium bekommt, wo möglich, einen Test. Gibt es kein Issue, zuerst fragen oder eines vorschlagen. Issues werden über die Nummer angesprochen (`#22`). Anlegen, Titel, Labels und Meilensteine: Skill **`issue`**. Abnahmekriterien nach dem Start nicht stillschweigend ändern, sondern kommentieren. Fehlalarme (`false-positive`) und Abgelehntes (`wontfix`) als «not planned» mit Begründung schliessen.

## Ablauf pro Issue

1. **Lesen** (`gh issue view <Nr>`). Unklares nachfragen, nicht still annehmen.
2. **Direkt auf `main`**, keine Feature-Branches, keine Pull Requests. Ein Branch nur für grosse oder riskante Arbeiten und nur mit Deiner Zustimmung.
3. **Umsetzen**, klein und gezielt, nur was im Issue steht. Nebenbaustellen als neues Issue vorschlagen.
4. **Testen**, jedes Abnahmekriterium prüfen und im Bericht nennen, was geprüft ist und was nicht.
   Bei Änderungen an `core/src`, `core/web` oder der Dart-Logik (`app/lib`) läuft vor der Abnahme `make mutants-diff` (Basis `origin/main`, auf die geänderten Dateien beschränkt, siehe «Testumfang»). Jeder nicht erkannte Mutant wird durch einen Test erkannt oder mit Begründung in `tools/mutants-exclude.txt` ausgeschlossen; sonst wird das Issue nicht geschlossen.
   Danach nicht mehr alles neu mutieren: Nach neuen Tests läuft `make mutants-diff` mit `--rerun` (nur die bisher nicht erkannten und neuen Mutanten), nach einem neuen Ausschluss mit `--exclusions-only` (kein Mutant läuft, nur die Ausschlüsse werden neu angewandt).
5. **Commit** im Imperativ oder als Substantiv, ohne Punkt, mit Issue am Ende: `Ziehbare Loop-Marker (#22)`. Kein `Fixes #22`.
   Nach dem Commit, der die Anforderung vollständig umsetzt: `gh issue edit <Nr> --add-label implemented` und Kommentar «Umgesetzt in <Commit>. Abnahme ausstehend.». Teilschritte bekommen das Label nicht. Wird das Issue wieder geöffnet, kommt das Label weg, bis die Nacharbeit committet ist.
6. **Abnahme** machst Du. Claude hakt nichts ab und schliesst nichts.
   **Ausnahme «Prüfe #22»:** Kriterien prüfen (Tests, sonst von Hand), Ergebnis je Kriterium kommentieren, Erfülltes abhaken, schliessen, wenn alles erfüllt ist (sonst offen lassen und den Fehler nennen).
7. **Commit, Push und Version** (Tag) nur auf ausdrückliches Wort. Nie `--force`, nie die Historie umschreiben.

## Bauen und Testen

Ausgaben immer kurz halten (`-quiet`, `--reporter failures-only`, `| tail -30`). Nichts aus `core/third_party/` lesen (u. a. `miniaudio.h`, 4 MB). Teststrategie, Schichten und Testmatrix: `docs/TESTS.md`.

```
make test                  # ctest (Kern), flutter test (App), Tests des Hooks
make format-check          # dart format und clang-format, ohne Änderungen
make lint                  # flutter analyze (streng), C++ mit -Wall -Wextra -Werror, clang-tidy
cmake -S core -B core/build -DCMAKE_BUILD_TYPE=Release && cmake --build core/build 2>&1 | tail -20 && ctest --test-dir core/build --output-on-failure
cd app && flutter analyze --no-pub && flutter test --reporter failures-only
cd app && flutter build macos --debug && flutter build ios --simulator --debug
cd app && flutter build web --release --no-wasm-dry-run                          # Web-App
make mutants-diff          # Mutationstests der seit origin/main geänderten Zeilen (Kern mit Mull, Dart-Logik), vor jeder Abnahme
make test-wasm             # Kern als WASM (Emscripten) unter Node.js, verglichen mit dem nativen Kern
make test-web              # Web-Tests in Chrome: OPFS und WASM-Kern (braucht Emscripten)
xcodebuild -project WoodshedPlayer.xcodeproj -scheme WoodshedPlayer -destination 'platform=macOS' -quiet test        # Swift-Altprojekt
xcodebuild -project WoodshedPlayer.xcodeproj -scheme WoodshedPlayer -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO -quiet build
tools/hoervergleich.sh <datei.mp3>   # 0,5x/0,25x: neuer Kern gegen AVAudioUnitTimePitch
```

- **Testumfang:** Die Läufe sind lang. Darum läuft nur, was die Änderung betrifft, und jeder volle Lauf einmal je Stand.
  - Während der Arbeit nur die betroffenen Tests (`ctest --test-dir core/build -R <name>`, `cd app && flutter test <datei>`).
  - Vor dem Umsetzungs-Commit einmal `make format-check`, `make lint` und `make test`, dazu je nach geänderten Pfaden:

    | Geändert | Zusätzlich |
    |---|---|
    | `core/` | `make sanitize`, `make test-wasm`; bei Dekodieren, C-API oder Web-API auch `make fuzz` (60 s je Ziel) |
    | `core/src`, `core/web`, `app/lib` ausser `app/lib/ui` | `make mutants-diff MUTANTS_ARGS="--file '<regex der geänderten Dateien>'"` (Zwischenspeicher bleibt an, kein `--fresh`); Wiederholung mit `--rerun` bzw. `--exclusions-only` im selben `MUTANTS_ARGS` |
    | `app/lib/ui`, `app/integration_test` | `make test-ui`, bei Bezug zu iPhone/iPad auch `make test-ios` |
    | `app/web`, `*_web.dart`, `core/web` | `make test-web` |
    | nur `docs/`, `README.md`, `README.de.md`, `.github/` | nur `make format-check` und `make lint` (actionlint) |

  - **«Prüfe #Nr»** übernimmt die Ergebnisse des Laufs vor dem Commit, wenn seither nichts geändert ist (derselbe Commit, sauberer Arbeitsbaum), und nennt sie im Kommentar. Neu laufen nur Tests zu Nachbesserungen und Kriterien, die der Lauf nicht abdeckt.
  - Kriterien, die nur auf GitHub prüfbar sind, bleiben offen bis zum nächsten Push mit Lauf; kein Push nur dafür.
- **Hook nach dem Commit** baut und testet die betroffenen Teile selbst. Nur bei Fehlern oder geänderter Logik ohne Tests meldet er sich; dann Fehler beheben bzw. den `test-agent` (Schnellmodus) starten. Testdetails stehen im Agenten.
- Flutter-App und Kern werden mit `flutter test` und `ctest` geprüft; `xcodebuild` nur noch für das Swift-Altprojekt.
- Neuer Code ist formatiert (`make format`) und ohne Warnungen (`make lint`); Ausnahmen nur mit Begründung (`core/.clang-tidy`, `NOLINT(<Prüfung>)`).
- Tests zu Abnahmekriterien nennen Issue und Kriterium (`#22/AK2`). Audio-Logik (Tempo, Loop-Grenzen, Seek, `mm:ss`) und Bibliothek (`library.json`, Sortierung, Ordner) brauchen Unit-Tests, Oberfläche nur, wo sinnvoll. Tests berühren nie die echte Bibliothek.

## Regeln

- **Kein Netzwerk** in der App ausser für beschlossene Funktionen mit eigenem Issue. Ausnahme (`docs/KONZEPT-SYNC.md`): Netzwerkzugriff nur für den Abgleich und nur nach ausdrücklicher Wahl: zu Google Drive nach Anmeldung, oder zu gekoppelten Geräten, mit Verbindungsaufbau über öffentliche Relays und STUN-Server. Dazu das Laden der Web-App selbst (GitHub Pages). Ohne Konto und ohne Kopplung keine Verbindung. Kein Tracking.
- **Keine privaten Daten** in Code, Tests, Issues, Commits, Screenshots (keine echten Namen, E-Mails, Titel oder Künstler). Commits mit der GitHub-noreply-Adresse.
- **Keine fremden Audiodateien.** Testaudio erzeugen (Sinus, Klicks) oder CC0 mit Quelle.
- **Lizenzen:** nur MIT-verträglich (MIT, BSD, Apache-2.0, Public Domain/MIT-0), keine GPL/AGPL. Ausnahme: LGPL für den MP3-Encoder des Exports (#141), nur dynamisch gebunden und austauschbar, mit Lizenztext und Quellenangabe im Repo. Ausnahme unter Linux (#60): GTK (Flutter-Linux) und libsecret (Token-Speicher, #161) als Systembibliotheken, nur dynamisch, nie im Paket, mit Hinweis in den Lizenzangaben (`app/linux/SYSTEM-LIBRARIES.txt`). Schriften zusätzlich unter SIL OFL 1.1 (unverändert einbinden, Lizenztext und Copyright-Hinweis ins Repo). Neue Abhängigkeiten nur nach Rückfrage.
- Audio und Oberfläche trennen: Audio in `core/` (Swift: `Audio/`), Daten in `Model/`, Darstellung in `Views/`.
- `docs/FUNKTIONEN.md` (Funktionstabelle, Datenschutz im Detail) im selben Zug nachführen, wenn sich Verhalten oder Begriffe ändern; `README.md` und `README.de.md` dazu, wenn es den Überblick betrifft (Funktionen, Plattformen, Installation, Datenschutz kurz).
- Jede Änderung muss auf macOS, iOS und Web bauen; Änderungen am Kern auch als WASM. Windows und Linux (x64, #60) bauen nur in GitHub Actions (Jobs `windows` und `linux` in `test-quality.yml`, nächtlich oder von Hand mit `desktop=true`). Aufnahme gibt es in der nativen App auf iPhone/iPad nicht; die Web-App nimmt überall das Mikrofon auf (#157), die App unter Windows und Linux ebenfalls (#162, mit «Scharf»). Systemton, MP3-Export und `record` der Kommandozeile bleiben Mac-only (Windows und Linux: `play`, #60).
