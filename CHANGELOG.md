# Changelog

Release Notes von Woodshed Player, neueste Version zuerst. Diese Datei ist massgebend; [`CHANGELOG.en.md`](CHANGELOG.en.md) übersetzt jede Version. Jeder Eintrag beginnt mit `## Version X.Y.Z` und hat die Abschnitte «Neu, geändert, behoben» und «Tests und Entwicklung» (mindestens einen, in dieser Reihenfolge); jeder Punkt nennt seine Issues. `python3 tools/changelog.py check` prüft beide Dateien (#139).

## Version 0.8.2

### Neu, geändert, behoben

- **Fenster (#129, #130):** Die Breite der Bibliothek-Seitenleiste lässt sich mit der Maus ändern. Das Fenster hat eine Standard- und eine Mindestgrösse und öffnet in der zuletzt gewählten Grösse.
- **Metronom (#133):** Auf dem Desktop zweispaltig.

### Tests und Entwicklung

- Eigener Temp-Ordner je Lauf der C-API-Tests (#132); der Test der Tastenkürzel hält die App im Vordergrund (#134).

## Version 0.8.1

### Neu, geändert, behoben

- **Google-Anmeldung in der Web-App (#131):** Die Antwort von Google wird beim Start der Web-App übernommen.

### Tests und Entwicklung

- Übersprungene Tests gelten in CI als Fehler, mit Grund auch unter Windows (#125).
- Regeln für den test-agent gegen überflüssige Tests, sein Bericht nennt Regel und Bruch auch bei Ausnahmen (#126).
- Funde der Zufallstests als benannte Regressionstests (#127), Laufzeitgrenze für einzelne Dart-Tests (#128), Startprüfung der Web-App mit eingeklappter Bibliothek (#123).

## Version 0.8.0

Erste Version der neuen Flutter-App mit C++-Audio-Kern für macOS, iPhone/iPad und Browser.

### Neu, geändert, behoben

- **Bibliothek und Playlists (#114, #121, #122, #123, #124):** Playlists neben Ordnern; Dateien von aussen auf Playlists und Ordner ziehen; mehrere Titel auswählen, gemeinsam verschieben und mit der Entf-Taste löschen; Playlists nach Titel, Artist, Dauer oder Hinzugefügt sortieren; die Bibliothek ist im Player-Bereich standardmässig eingeklappt.
- **Bereiche (#115):** Player, Üben und Metronom.
- **Aufnahme und Kürzen (#113, #116, #118, #120):** Mikrofon- und Systemton-Aufnahme als FLAC; Anfang und Ende eines Titels abschneiden, auch bei M4A.
- **Abgleich über Google Drive (#53, #54, #65, #98, #104, #107):** Anmeldung am Mac über das Anmeldefenster des Systems, eine Datei je Gerät, Rückfrage vor dem Verlust offline geänderter Titel und Ordner, Wiederherstellen einer beschädigten `state.json` in der Cloud, Schutz gegen wiederbelebte gelöschte Einträge; der Start mit gespeicherter Anmeldung hängt nicht mehr.
- **Web-App (#39, #71, #72, #82, #109, #110):** Offline-Start, Media Session, Audio-Cache und Hinweis «Zum Home-Bildschirm», der nach dem Schliessen wegbleibt; der Bildschirm bleibt beim Üben an; keine fehlende Schriftdatei, Ersatzzeichen statt nachgeladener Schriften, keine Dropbox-Hosts mehr in der CSP.
- **Lizenzhinweise (#119):** Die Lizenztexte der Kern-Bibliotheken stehen in der App.
- **Wiedergabe und Dateien (#70, #73, #75, #76, #81, #91, #93, #96, #97, #105, #106):** Richtige Position nach Seek in der Pause und nach Seek mit Play; Metronom beim gleichzeitigen Wechsel von Takt und Unterteilung; lange Titel mit weniger Speicher laden; Grenzen der Abtastrate (höchstens 192 kHz); lesbare Metadaten trotz beschädigter Tags; Speichermangel im WASM-Kern ohne Abbruch; Dateipfad mit Punkt am Ende.
- **Aufgeräumt (#84, #111, #117):** Reparatur-Dialog der beschädigten `state.json` entfernt, Dropbox-Reste entfernt, Vorschlag iPhone und iPad nur noch als Web-App.

### Tests und Entwicklung

- Teststrategie, Formatierung und Code-Hygiene (#7), Testabdeckung je Teil (#8), Audio-Referenzfälle (#9), Zufallstests, Fuzzing und Golden-Dateien (#10), Übersichtsseite der Testqualität (#12), Oberflächentests und GitHub-Workflow (#13).
- Sanitizer und Echtzeitsicherheit im Kern (#57, #63, #101, #102, #103), Prüfung der Netzwerkfreiheit (#58), Leistungs- und Lasttests (#59).
- Mutationstests (#11) mit erkannten oder begründet ausgeschlossenen Mutanten (#61, #108).
- Vertrag nativ und WASM (#77, #80, #94, #100), Fuzzing der C-API und Web-API, auch gegen den WASM-Kern (#66, #67, #85, #86, #88).
- Stabilere Tests durch Warten auf Zustände statt fester Pausen (#62, #78, #92, #95), testbare Teile der Aufnahme (#68), Oberflächen-Rauchtest auf dem iOS-Simulator (#99).
- Workflow: actionlint (#64), Werkzeugtests im Hook (#69), feste Emscripten-Version im Zwischenspeicher (#79, #89), Web-App nur einmal gebaut (#83), Zeitgrenze für Web-Tests (#112), Tag-Push veröffentlicht über einen Lauf auf `main` (#41), Testseite M0 für die Google-Anmeldung (#52).
