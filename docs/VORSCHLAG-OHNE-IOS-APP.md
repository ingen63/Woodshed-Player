# Vorschlag: iPhone und iPad nur noch als Web-App

Stand: 22.11.2026 · Status: Vorschlag, nicht entschieden

## Kurz

Die native Flutter-App für iPhone und iPad (`app/ios/`, `app/packages/wp_core/ios/`) fällt weg. iPhone und iPad
nutzen wie Android die Web-App (PWA) von GitHub Pages. Native Apps gibt es nur noch für den Desktop (macOS, später
Windows und Linux).

**Voraussetzung:** Der Machbarkeitstest #32 (Web-Audio auf einem echten iPhone, Plan W0) besteht. Solange er offen
ist, bleibt die iOS-App.

## Ausgangslage

Die Doku widerspricht sich heute:

| Dokument | Aussage |
|---|---|
| `docs/PLAN-WEB-UND-SYNC.md` (freigegeben 19.11.2026) | iPhone/iPad als **Web-App**, «Native iOS/Android: gestrichen» |
| `docs/UMBAUPLAN-FLUTTER.md`, `README.md`, `CLAUDE.md` | iPhone/iPad als **native App** und Web-App |
| Code und CI | iOS-App wird gebaut und getestet (#99), der Hook baut sie nach jedem Commit an Kern oder Plugin |

Dieser Vorschlag beseitigt den Widerspruch in Richtung des freigegebenen Plans.

## Was wegfällt

| Bereich | Heute | Danach |
|---|---|---|
| Code | `app/ios/` (Runner, `AppDelegate.swift` mit Dokumentenauswahl, Wake Lock beim Metronom, Links, Build-Infos), `app/packages/wp_core/ios/`, Zweig `Platform.isIOS` in `wp_core.dart`, iOS-Fälle in `ui/style.dart` (Touch-Ziel 44 pt, ⌘-Badges) | gelöscht; die iOS-Fälle in `style.dart` bleiben, soweit sie die Web-App auf dem iPhone betreffen (Flutter Web meldet dort ebenfalls `TargetPlatform.iOS`) |
| Tests | `make test-ios`, `tools/ios_sim_test.sh`, Rauchtest `app_smoke_test.dart` auf dem Simulator (#99), Prüfung «keine Aufnahme auf iPhone/iPad» (#4/AK6) nativ | gestrichen; die Aufnahme-Prüfung für die Web-App bleibt |
| CI (`test-quality.yml`, Job `macos`) | iOS-Build ≈ 4 min, iOS-Simulator ≈ 6 min von ≈ 24 min je Lauf | ≈ 14 min je Lauf, rund **220 macOS-Minuten weniger im Monat** (≈ 530 → ≈ 310) |
| Hook nach dem Commit | `flutter build ios --simulator --debug` bei jeder Änderung an Kern oder Plugin | entfällt; der Hook wird spürbar schneller |
| Veröffentlichung (Phase 9) | TestFlight, App Store für iOS, `PrivacyInfo.xcprivacy`, App-Store-Prüfung | für iOS entfällt alles; nötig bleibt nur der Mac (oder Vertrieb ausserhalb des App Store) |
| Phase 6 | iOS: Hintergrund-Audio, Audio-Session, Sperrbildschirm, Kopfhörertasten, «Öffnen mit» | ersetzt durch die Web-Lösung aus W7 (#39: Media Session, Wake Lock) |
| Regel in `CLAUDE.md` | «Jede Änderung muss auf macOS, iOS und Web bauen» | «auf macOS und Web» |

Das Swift-Altprojekt (`WoodshedPlayer/`) ist nicht betroffen. Es bleibt eingefroren, wie es ist.

## Was es bringt

1. **Eine mobile Plattform statt zwei.** iPhone, iPad und Android teilen sich denselben Code und dieselben Tests.
   Mobile Fehler zeigen sich einmal, nicht je Plattform.
2. **Schnellere Arbeit an Kern und Plugin.** Der iOS-Build im Hook und in `make`-Läufen fällt weg, ebenso die
   Abstimmung von FFI, Podspec und miniaudio-Backend auf iOS (siehe Gefundene Fehler 38, Null-Gerät auf dem Simulator).
3. **Weniger CI-Zeit.** Rund 40 % des macOS-Jobs fallen weg.
4. **Kein Apple-Konto für das Handy.** Kein TestFlight, keine App-Store-Prüfung, keine Datenschutzangaben im Store
   für iOS. Updates kommen mit jedem Tag über GitHub Pages sofort bei allen an.
5. **Einheitlicher Abgleich.** Der Sync-Plan geht für das Handy ohnehin von der Web-App aus (Anmeldung per OAuth im
   Browser, Tokens in IndexedDB, direkte Verbindung aus dem Browser). Eine native iOS-App bräuchte dafür eigene Wege.
6. **Klare Doku.** Plan, Umbauplan, README und CLAUDE.md sagen dasselbe.

## Was es kostet

| Nachteil | Gewicht | Gegenmittel |
|---|---|---|
| **Audio im Hintergrund und bei gesperrtem Bildschirm:** iOS pausiert Web Audio in der PWA unzuverlässig; die native App spielt mit `UIBackgroundModes: audio` sicher weiter | hoch, Kern eines Übe-Players | #32 entscheidet; Umweg über `<audio>` und Media Session; Wake Lock beim Üben (#109) |
| **Speicher:** iOS kann den Speicher der Web-App räumen; die native App behält ihre Titel | mittel | `persist()`, Titel aus dem Abgleich nachladen, Hinweis bei Verlust |
| **Import:** kein «Öffnen mit» aus anderen Apps, nur die Dateiauswahl des Browsers | mittel | Dateiauswahl, Abgleich vom Desktop |
| **Leistung:** WASM im AudioWorklet statt nativem Kern; der Browser dekodiert AAC/M4A | gering bis mittel | auf dem Gerät messen (#32) |
| Sperrbildschirm und Kopfhörertasten nur so gut, wie Safari die Media Session umsetzt | mittel | in #32 und #39 von Hand prüfen |
| Geleistete Arbeit (#99, iOS-Teile von #18) wird verworfen | gering | bleibt in der Git-Historie |

## Vorgehen

1. **#32 abschliessen** (Machbarkeitstest auf einem echten iPhone und iPad). Wichtig sind Wiedergabe bei gesperrtem
   Bildschirm, Rückkehr aus dem Hintergrund, Stummschalter und Speicherdauer. Fällt der Test durch, bleibt die
   iOS-App, und dieser Vorschlag ist erledigt.
2. **Entscheidung** festhalten: in `docs/PLAN-WEB-UND-SYNC.md` bestätigen, in `docs/UMBAUPLAN-FLUTTER.md`
   (Ziel, Tabelle, Phase 6 und 9) nachführen.
3. **Issue «iOS-App entfernen»** mit Abnahmekriterien, etwa:
   - [ ] `app/ios/` und `app/packages/wp_core/ios/` sind entfernt; `flutter build macos` und `flutter build web` bauen.
   - [ ] `make test-ios`, `tools/ios_sim_test.sh` und die iOS-Schritte in `test-quality.yml` sind entfernt; `actionlint` ist grün.
   - [ ] Der Hook baut kein iOS mehr; `make test-hook` ist grün.
   - [ ] Die Web-App auf dem iPhone verhält sich unverändert (Touch-Ziele, Hinweis «Zum Home-Bildschirm», keine Aufnahme).
   - [ ] `README.md`, `CLAUDE.md`, `docs/TESTS.md` (Testmatrix, Minuten) und `docs/NUTZUNGSBEDINGUNGEN.md` nennen iPhone/iPad nur als Web-App.
4. **Umsetzung** in einem Commit auf `main`. Ein Zurück ist über die Git-Historie jederzeit möglich.

## Offene Fragen an Dich

- Soll die iOS-App bis zum Ergebnis von #32 weiter gebaut und getestet werden, oder setzen wir die iOS-Schritte in
  der CI schon jetzt aus?
- Soll das iPad gleich behandelt werden wie das iPhone? Technisch gelten dieselben Grenzen von Safari.
- Brauchst Du je einen Vertrieb über den App Store für den Mac? Davon hängt ab, ob das Apple-Konto ganz wegfallen kann.
