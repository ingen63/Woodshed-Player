# Arbeitsanleitung für Claude Code

Woodshed Player ist ein Übe-Player für Musiker: Bibliothek mit Ordnern, Tempo ohne Tonhöhenänderung, Loops, später Metronom, Aufnahme und Cloud-Sync. Heute eine SwiftUI-App für macOS 14+ und iOS/iPadOS 17+ (`WoodshedPlayer/`), geplant ist der Umbau auf Flutter mit C++-Audio-Kern (`docs/UMBAUPLAN-FLUTTER.md`). Überblick und Bedienung in `README.md`. Open Source unter MIT (`LICENSE`).

## Sprache

Deutsch mit «ss» statt «ß» (Schweizer Rechtschreibung), Anrede **«Du»**. Oberfläche, Hilfe, Commits und Issues sind deutsch.

## Anforderungen kommen aus GitHub Issues

Jede Änderung hat ein Issue. Der Text enthält die Anforderung und die **Abnahmekriterien als Häkchen-Liste**. Die Abnahmekriterien sind die Prüfliste: Jedes Kriterium bekommt, wo möglich, einen Test.

Gibt es zur Aufgabe kein Issue, zuerst fragen oder eines vorschlagen. Nichts umsetzen, was keine Anforderung hat.

### Issue-ID = GitHub-Nummer

Die ID im Titel hat **dieselbe Nummer wie das Issue auf GitHub**: Issue #22 heisst `FEA-22 …` oder `ISS-22 …`, nie eine eigene Zählung.

| Präfix | Art | Label |
|---|---|---|
| `FEA` | Funktion, Änderung | `feature` |
| `ISS` | Fehler | `bug` |
| `GEN` | Allgemeines, Repo, Werkzeuge, Doku | `allgemein` |

Weil die Nummer erst beim Anlegen feststeht, werden Issues mit dem Skill **`issue`** angelegt (`tools/issue-id.sh new`): Er legt das Issue an und setzt danach das Präfix mit der richtigen Nummer. Issues, die im Browser angelegt wurden, korrigiert `tools/issue-id.sh sync` (Trockenlauf, mit `--apply` umbenennen).

## Ablauf pro Issue

1. **Issue lesen** (`gh issue view <Nr>`). Ist etwas unklar oder widersprüchlich, nachfragen. Nicht still annehmen.
2. **Direkt auf `main` arbeiten.** Eine Person, deshalb keine Feature-Branches und keine Pull Requests. Ein Branch ist die Ausnahme für grosse oder riskante Arbeiten (z. B. der Flutter-Umbau) und braucht Deine Zustimmung.
3. **Umsetzen**, klein und gezielt. Keine Änderungen ausserhalb des Issues. Gefundene Nebenbaustellen als neues Issue vorschlagen, nicht mitmachen.
4. **Testen** (siehe unten). Jedes Abnahmekriterium prüfen und im Bericht nennen, was geprüft ist und was nicht.
5. **Commit** mit ID und Issue-Nummer, Imperativ oder Substantiv, ohne Punkt:
   `FEA-22 Ziehbare Loop-Marker (#22)`. ID-Nummer und `(#…)` sind immer gleich.
   Eine Anforderung pro Commit (oder wenige Commits). Kein `Fixes #22` in der Commit-Nachricht, denn das schliesst das Issue beim Push von selbst.
   Nach dem Commit, der die Anforderung vollständig umsetzt, bekommt das Issue das Label `umgesetzt` und den Kommentar
   «Umgesetzt in <Commit>. Abnahme ausstehend.» (`gh issue edit <Nr> --add-label umgesetzt`, `gh issue comment`).
   Teilschritte bekommen das Label nicht. Wird das Issue wieder geöffnet, kommt das Label weg, bis die Nacharbeit committet ist.
6. **Abnahme** machst Du. Claude hakt die Kriterien im Issue **nicht** selbst ab und schliesst es nicht.
   **Ausnahme «Prüfe FEA-xx»:** Dann prüft Claude die Kriterien (vorhandene Tests laufen lassen, sonst von Hand), kommentiert
   das Ergebnis je Kriterium, hakt erfüllte Kriterien ab und schliesst das Issue, wenn alle erfüllt sind (sonst offen lassen und den Fehler nennen).
7. **Push und Version** (Tag) nur auf ausdrückliches Wort.

Commit und Push nur, wenn es ausdrücklich verlangt wird. Nie `--force`, nie die Git-Historie umschreiben. Der Hook nach dem Commit (`test-agent`) und später die GitHub-Workflows sind die Kontrolle anstelle eines Pull Requests.

## Bauen und Testen

- Build-Prüfung, beide Plattformen:
  ```
  xcodebuild -project WoodshedPlayer.xcodeproj -scheme WoodshedPlayer -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
  xcodebuild -project WoodshedPlayer.xcodeproj -scheme WoodshedPlayer -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
  ```
- Tests: Swift Testing / XCTest im Testziel `WoodshedPlayerTests` (noch anzulegen, eigenes Issue), Aufruf mit `xcodebuild … test`.
  Nach dem Flutter-Umbau: `flutter test` in `app/`, `ctest` im C++-Kern `core/`.
- Nach einem Commit mit Code-Änderungen startet der Hook den Agenten `test-agent` im Schnellmodus.
- Tests, die ein Abnahmekriterium belegen, nennen Issue und Kriterium (`FEA-22/AK2` im Namen oder Kommentar, `AK2` = zweites Häkchen).
- Audio-Logik (Tempo, Loop-Grenzen, Seek, Zeitformat `mm:ss`) und Bibliothek (`library.json`, Sortierung, Ordner) brauchen Unit-Tests. Oberfläche nur, wo sinnvoll.

## Regeln

- **Keine Netzwerkzugriffe** in der App, ausser für ausdrücklich beschlossene Funktionen (z. B. Cloud-Sync mit eigenem Issue). Keine Analyse- oder Tracking-Dienste.
- **Keine privaten Daten** in Code, Tests, Issues, Commits oder Screenshots: keine echten Namen, E-Mail-Adressen, Titel- oder Künstlernamen aus der eigenen Bibliothek. Commits laufen mit der GitHub-noreply-Adresse.
- **Keine fremden Audiodateien** im Repo. Testaudio wird erzeugt (Sinustöne, Klicks) oder ist nachweislich gemeinfrei (CC0), mit Quelle.
- **Lizenzen:** Nur Abhängigkeiten, die mit MIT verträglich sind (MIT, BSD, Apache-2.0, Public Domain/MIT-0). Keine GPL/AGPL (z. B. JUCE, Rubber Band) ohne Rückfrage. Neue Abhängigkeiten nur nach Rückfrage.
- Audio und Oberfläche getrennt halten: Audio in `WoodshedPlayer/Audio/` (später `core/`), Daten in `Model/`, Darstellung in `Views/`.
- `README.md` (Funktionstabelle, Datenschutz) im selben Zug nachführen, wenn sich Verhalten oder Begriffe ändern.
- Plattformen beachten: Jede Änderung muss auf macOS und iOS bauen. Aufnahme gibt es auf iPhone/iPad nicht.

## Issues anlegen und pflegen

- Vorlagen in `.github/ISSUE_TEMPLATE/` (Fehler, Funktion). Labels: `bug`, `feature`, `allgemein`, `audio`, `ui`, `repo`, `false-positive`, `umgesetzt`; bei Fehlern zusätzlich der Fundort `gefunden:test`, `gefunden:abnahme` oder `gefunden:nutzung`. Meilensteine: «Nächste Version», «Später».
- Eine Anforderung pro Issue. Die Abnahmekriterien nach dem Start nicht stillschweigend ändern: Änderungen als Kommentar mit Begründung.
- Fehlalarme mit `false-positive` als «not planned» schliessen, mit Begründung.
