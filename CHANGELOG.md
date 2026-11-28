# Changelog

Release Notes von Woodshed Player, neueste Version zuerst. Diese Datei ist massgebend; [`CHANGELOG.en.md`](CHANGELOG.en.md) übersetzt jede Version. Jeder Eintrag beginnt mit `## Version X.Y.Z` und hat die Abschnitte «Neu, geändert, behoben» und «Tests und Entwicklung» (mindestens einen, in dieser Reihenfolge); jeder Punkt nennt seine Issues. `python3 tools/changelog.py check` prüft beide Dateien (#139).

## Version 1.0.1

### Neu, geändert, behoben

- **Google-Anmeldung unter Windows und Linux (#164):** Die Pakete für Windows und Linux bringen das Secret des Desktop-Clients von Google mit, das Google bei der Anmeldung verlangt. Es kommt beim Bauen aus einem GitHub-Actions-Secret und steht nie im Repository.

### Tests und Entwicklung

- Der Release-Workflow erlaubt neben dem Token des Laufs genau dieses eine Secret, nur für Windows und Linux; ein Test prüft, dass kein Google-Secret im Repository steht (#164, #139).
- Weitere Tests für die Aufnahme unter Windows und Linux aus dem nächtlichen Mutationslauf (#138).

## Version 1.0.0

Die erste stabile Version von Woodshed Player: eine neue App in Flutter mit einem Audio-Kern in C++ für macOS, Windows, Linux, iPhone/iPad und den Browser. Diese Release Notes fassen alles seit der ersten Vorschau 0.8.0 zusammen; die einzelnen Schritte stehen weiter unten.

### Neu, geändert, behoben

- **Üben:** Tempo ohne Änderung der Tonhöhe, Loops mit ziehbaren Markern, Steigerung und Metronom mit Tempo-Steigerung, in den drei Bereichen Player, Üben und Metronom (#115, #133).
- **Bibliothek:** Ordner mit beliebig tiefen Unterordnern, Playlists, Mehrfachauswahl, Dateien von aussen hineinziehen, Sortierung, Anfang und Ende abschneiden; robust gegen gleichnamige Einträge, ungültige Loops und beschädigte Tags (#114, #121, #122, #123, #124, #135, #136, #137, #143, #146).
- **Aufnahme:** Mikrofon und Systemton am Mac als FLAC mit 24 Bit, Mikrofon auch unter Windows, Linux und in der Web-App; der Schalter «Scharf» macht jedes Spielen zu einer eigenen Aufnahme unter `Recordings › Datum` und geht auf Wunsch danach aus (#113, #116, #118, #120, #147, #156, #157, #162).
- **Mac:** MP3-Export mit Jahr, Kommandozeile `woodshed` zum Abspielen und für scharfe Aufnahmen, Menüleiste in der Systemsprache, Fenster mit verstellbarer Seitenleiste und gemerkter Grösse, Titelleiste passend zur Darstellung (#129, #130, #140, #141, #144, #152).
- **Windows und Linux:** Native Apps für x64 als `.zip` bzw. `.tar.gz`, mit Dateiauswahl und Hineinziehen von Dateien, Wiedergabe über WASAPI bzw. PulseAudio/ALSA, Aufnahme über das Mikrofon mit «Scharf», Abgleich über Google Drive und Kommandozeile `play` mit eigener Hilfe; die Google-Anmeldung in diesen Paketen ist noch nicht mit einem echten Konto geprüft (#60, #161, #162, #163, #164, #166).
- **Web-App:** Startet offline, Steuerung auf dem Sperrbildschirm, Audio-Cache, Hinweis zum Installieren, Bildschirm bleibt beim Üben an, auf dem iPhone auch im Stumm-Modus hörbar (#39, #71, #72, #82, #109, #110, #158).
- **Abgleich über Google Drive:** Anmeldung am Mac, unter Windows und Linux und in der Web-App, eine Datei pro Gerät, Rückfrage vor verlorenen Änderungen, Schutz vor wieder auftauchenden gelöschten Einträgen; OneDrive, Dropbox und die alte Reparatur entfernt (#53, #54, #55, #65, #84, #90, #98, #104, #107, #111, #131).
- **Bedienung:** Hilfe-Seite für alle Bereiche und Übersicht der Tastenkürzel, dunkle Darstellung als Standard, Lizenztexte in der App (#119, #148, #149).
- **Wiedergabe und Dateien:** richtige Position nach dem Springen, Metronom bei gleichzeitigem Wechsel von Takt und Unterteilung, lange Titel mit weniger Speicher, Grenzen der Abtastrate, kein Abbruch bei vollem Speicher im WASM-Kern (#70, #73, #75, #76, #81, #91, #93, #96, #97, #105, #106).

### Tests und Entwicklung

- Teststrategie mit Abdeckung pro Teil, Referenzfällen, Zufallstests, Fuzzing, Golden Files, Oberflächentests und Rauchtests auf dem iOS-Simulator (#7, #8, #9, #10, #12, #13, #99).
- Sanitizer, Echtzeit-Sicherheit, Netzwerkfreiheit, Last- und Mutationstests; gleiches Verhalten von nativem und WASM-Kern (#11, #57, #58, #59, #63, #77, #101, #138, #142).
- Stabilere Tests ohne feste Pausen und mit Zeitgrenzen (#62, #78, #92, #95, #112, #128, #150, #155, #159, #165).
- Nächtliche Builds, Tests und Rauchtests unter Windows und Linux, Windows-Pfade mit Laufwerk, UNC und Umlauten (#60).
- Release-Workflow mit Paketen für macOS, Windows, Linux und die Web-App und zweisprachigen Release Notes; englische README mit deutscher Fassung (#41, #139, #145, #160).

## Version 1.0.0-beta.3

### Neu, geändert, behoben

- **Aufnahme in der Web-App (#157):** Die Web-App nimmt mit dem Mikrofon auf, in allen Browsern mit Speicherzugriff im Hintergrund (OPFS), als FLAC mit 24 Bit wie die native App; den Schalter «Scharf» gibt es jetzt auch in der Web-App.
- **Scharf geht nach einer Aufnahme aus (#156):** Nach einer Aufnahme ist «Scharf» wieder aus; für die nächste schaltest Du es wieder ein.
- **Web-App auf dem iPhone im Stumm-Modus hörbar (#158):** Player und Metronom klingen auch, wenn der Stumm-Schalter an ist.

### Tests und Entwicklung

- Zeitgrenze und Diagnose für den iOS-Rauchtest in CI (#155).
- Stabiler Web-Test für «Scharf» (#157).

## Version 1.0.0-beta.2

### Neu, geändert, behoben

- **Unterordner (#146):** Ordner der Bibliothek können beliebig tiefe Unterordner haben («Neuer Unterordner» im Kontextmenü); Ordner lassen sich per Ziehen verschieben, ohne Zyklen, auch über den Abgleich. Beim Löschen eines Ordners kommen seine Titel unter «Ohne Ordner».
- **Scharfe Aufnahme beim Üben (nur Mac, #147):** Schalter «Scharf» in *Üben* und *Metronom*: Jedes Spielen wird als eigene Aufnahme mitgeschnitten (1 s Vor- und Nachlauf) und unter `Recordings › <Datum>` abgelegt; Schwelle und Pause im Popover am Schalter.
- **Hilfe in der App (#148):** Hilfe-Seite für alle Bereiche, offline und in allen Sprachen der App, dazu eine Übersicht der Tastenkürzel (Taste «?»); am Mac im Menü «Hilfe», sonst im Menü «⋯» der Bibliothek.
- **Dunkle Darstellung als Standard (#149):** Ohne gewählte Darstellung startet die App dunkel, auch der Startbildschirm; eine gewählte Darstellung bleibt erhalten.
- **Reparatur der Cloud-Bibliothek (#90):** nicht mehr nötig, seit jedes Gerät nur seine eigene Datei schreibt (#53, #111).

### Tests und Entwicklung

- Mutationstests melden Fehler der Umgebung im Basislauf getrennt und wiederholen ihn allein (#142); LAME im nächtlichen Mutationsjob, Zeitgrenze für den iOS-Rauchtest (#153).
- Swift-Tests ohne Start der Dart-App, ohne Schlüsselbund und Mikrofon (#151).
- Minutenschätzung der Workflows mit gemessenen Laufzeiten (#74).
- Die Abdeckungsprüfung zählt Dateien mit `typedef` als reine Deklarationen (#154).

## Version 1.0.0-beta.1

### Neu, geändert, behoben

- **Kommandozeile (nur Mac, #140):** `woodshed play` lädt und spielt einen Titel der Bibliothek, `woodshed record` macht eine Aufnahme scharf: Sie beginnt mit dem ersten Ton und endet nach einer Pause; die App spricht mit dem Befehl nur über eine lokale Socket-Datei. Die scharfe Aufnahme gibt es auch in der App.
- **MP3-Export (#141):** Ausgewählte Titel als MP3 exportieren, mit Jahr als Metadatum (`--year` für die scharfe Aufnahme).
- **Bibliothek (#135, #136, #137):** Titel besser lesbar, «Neuer Ordner», Darstellung und Info im Menü «⋯»; ungültige Loops werden beim Speichern und Kürzen verworfen; eine gelöschte lokale Playlist stört den Abgleich nicht mehr.
- **OneDrive entfernt (#55):** aus Doku und Web-App.
- **Menüleiste und Sprache (#144):** Die Menüleiste des Mac folgt der Systemsprache; iOS und macOS melden Englisch und Deutsch als Sprachen der App; die Web-App setzt die Sprache der Seite.
- **Gleichnamige Einträge (#143):** Die Bibliothek bricht bei gleichnamigen Titeln, Ordnern oder Playlists nicht mehr ab.

### Tests und Entwicklung

- Release-Workflow mit macOS-Paket, Web-App und zweisprachigen Release Notes (#139).
- Testseite und Testprogramm K0 für die direkte Verbindung zwischen Geräten (#52).
- Nächtliche Mutationstests mit Zwischenspeicher je Quellstand (#138); abgebrochene Verbindung der Kommandozeile unter Linux ohne unbehandelten Fehler (#140).
- Englische Projekt-README mit deutscher Fassung (#145).

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
