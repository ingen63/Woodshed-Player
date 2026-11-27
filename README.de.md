<div align="center">

<img src="app/web/icons/Icon-192.png" width="112" alt="Icon von Woodshed Player">

# Woodshed Player

**Der Übe-Player für Musikerinnen und Musiker.**<br>
Ein Stück langsamer abspielen, ohne dass sich die Tonhöhe ändert, die schweren Takte im Loop üben, mit Metronom spielen und das Tempo steigern, wenn es sitzt.

[**Web-App öffnen**](https://ingen63.github.io/Woodshed-Player/app/) · [Für macOS laden](https://github.com/ingen63/Woodshed-Player/releases) · [Änderungen](CHANGELOG.md)

[![Test quality](https://github.com/ingen63/Woodshed-Player/actions/workflows/test-quality.yml/badge.svg)](https://github.com/ingen63/Woodshed-Player/actions/workflows/test-quality.yml)
[![Pages](https://github.com/ingen63/Woodshed-Player/actions/workflows/pages.yml/badge.svg)](https://github.com/ingen63/Woodshed-Player/actions/workflows/pages.yml)
[![Release](https://github.com/ingen63/Woodshed-Player/actions/workflows/release.yml/badge.svg)](https://github.com/ingen63/Woodshed-Player/actions/workflows/release.yml)

[English](README.md) · **Deutsch**

</div>

<br>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/studio-desktop-dark.png">
  <img src="docs/screenshots/studio-desktop-light.png" alt="Woodshed Player am Desktop: Wellenform mit Loop, Tempo und Steigerung">
</picture>

<table>
  <tr>
    <td width="62%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/studio-tablet-dark.png">
        <img src="docs/screenshots/studio-tablet-light.png" alt="Woodshed Player auf dem Tablet">
      </picture>
    </td>
    <td width="38%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/studio-phone-dark.png">
        <img src="docs/screenshots/studio-phone-light.png" alt="Woodshed Player auf dem Phone">
      </picture>
    </td>
  </tr>
</table>

<sub>Englische Oberfläche, erfundene Titel und eine erzeugte Wellenform. Die Screenshots folgen Deinem GitHub-Design (hell oder dunkel).</sub>

## Warum Woodshed Player?

*Woodshedding* nennen Musikerinnen und Musiker das Üben einer schweren Stelle, immer wieder, bis sie sitzt. Genau dafür ist Woodshed Player gemacht: eine Bibliothek mit der Musik, die Du lernst, und die Werkzeuge, um sie auseinanderzunehmen.

- 🐢 **Langsamer, gleiche Tonhöhe.** Tempo von 0,1× bis 2×, ohne dass sich die Tonart ändert, mit hochwertigem Time-Stretch in einem Audio-Kern in C++.
- 🔁 **Loops, die bleiben.** Die Marker **S** und **E** in der Wellenform ziehen, `mm:ss.d` eintippen oder während der Wiedergabe **S** / **E** drücken. Jeder Titel merkt sich seinen Loop und sein Tempo.
- 📈 **Steigerung.** Bei 60 % beginnen, alle 10 Durchgänge 5 % schneller, am Ende volles Tempo, ganz von selbst.
- 🥁 **Metronom.** 20–300 BPM, Tap-Tempo, 4/4, 3/4, 2/4 und 6/8, Unterteilungen bis zu Sechzehnteln und eine automatische Tempo-Steigerung nach Takten oder nach Zeit.
- 📚 **Bibliothek.** Ordner, Playlists, Mehrfachauswahl, Ziehen und Ablegen. Jede Datei wird nur einmal gespeichert, erkannt an ihrem Inhalt. Anfang und Ende eines Titels abschneiden (WAV, FLAC, MP3, AAC, M4A).
- 🎙️ **Aufnahme.** Systemton (Mac) oder Mikrofon (Mac und Web-App) verlustfrei als FLAC aufnehmen. Die Aufnahme landet direkt in der Bibliothek, bereit für den Loop. Mit dem Schalter **Scharf** wird beim Üben das nächste Spielen zu einer eigenen Aufnahme, abgelegt unter `Recordings › Datum`; bleibt er scharf, wird jede Spielphase aufgenommen.
- ☁️ **Deine Geräte, Deine Wahl.** Abgleich auf Wunsch über Dein eigenes Google Drive, nur mit den Dateien, die die App selbst anlegt. Ohne Konto verlässt nichts Dein Gerät.
- 🌗 **Zum Üben gemacht.** Die Bereiche Player, Üben und Metronom, Layouts für Desktop, Tablet und Phone, hell und dunkel, Tastenkürzel überall (**?** zeigt die Übersicht), eine eingebaute Hilfe, die auch offline geht, Deutsch und Englisch nach der Systemsprache, auch in der Menüleiste des Mac und in den Rückfragen des Systems.

Alle Funktionen im Detail: [`docs/FUNKTIONEN.md`](docs/FUNKTIONEN.md).

## Plattformen

| | Wie | |
| --- | --- | --- |
| **macOS** 14+ | Native App, Apple Silicon und Intel | Aufnahme des Systemtons, MP3-Export und Kommandozeile nur hier |
| **iPhone, iPad** | [Web-App](https://ingen63.github.io/Woodshed-Player/app/), auf den Home-Bildschirm installierbar | Läuft offline, Steuerung auf dem Sperrbildschirm, Aufnahme über das Mikrofon |
| **Android und alles andere** | [Web-App](https://ingen63.github.io/Woodshed-Player/app/) im Browser | Ohne Installation, ohne Konto, Aufnahme über das Mikrofon |
| **Windows, Linux** | Folgt später | Bis dahin: die Web-App |

## Installation

Die Pakete jeder Version liegen unter [Releases](https://github.com/ingen63/Woodshed-Player/releases), mit den Release Notes auf Englisch und Deutsch ([`CHANGELOG.en.md`](CHANGELOG.en.md), [`CHANGELOG.md`](CHANGELOG.md)). Jedes Paket enthält die Lizenz (`LICENSE`) und die Lizenztexte der Schriften und Kern-Bibliotheken (Ordner `Licenses` bzw. `licenses`).

| Paket | Plattform |
| --- | --- |
| `WoodshedPlayer-<Version>-macos.dmg` | macOS 14 oder neuer, Apple Silicon und Intel (Universal) |
| `WoodshedPlayer-<Version>-web.zip` | Web-App zum Selbst-Hosten, derselbe Stand wie unter <https://ingen63.github.io/Woodshed-Player/app/> |

- **macOS:** `.dmg` öffnen und *Woodshed Player* in den Ordner *Programme* ziehen. Die App ist nur ad hoc signiert und nicht notarisiert (es gibt kein Apple-Developer-Konto). Beim ersten Start darum im Finder **Rechtsklick › Öffnen** wählen und im Dialog nochmals *Öffnen*. Zeigt macOS nur «Nicht öffnen» oder «In den Papierkorb», unter *Systemeinstellungen › Datenschutz & Sicherheit* bei «Woodshed Player wurde blockiert» auf *Dennoch öffnen* klicken. Danach startet sie normal.
- **Web-App:** Nichts zu installieren, einfach <https://ingen63.github.io/Woodshed-Player/app/> öffnen. Zum Selbst-Hosten den Ordner aus dem `.zip` an die Wurzel eines Webservers mit HTTPS legen (oder lokal über `localhost` ausliefern). Die App läuft nur an der Wurzel (`/`), nicht in einem Unterordner.

## Kommandozeile (Mac)

Die App ist zugleich eine Kommandozeile: einen Titel der Bibliothek abspielen oder eine Aufnahme scharf machen, die mit dem ersten Ton beginnt und nach einer Pause von selbst endet. So landet ein Stück, das im Browser läuft, ohne Stille am Anfang und Ende in der Bibliothek.

```bash
cp tools/woodshed ~/bin/woodshed          # ein beliebiger Ordner im PATH
woodshed play --title "Blue Practice" --artist "Test Band"
woodshed record --title "Blue Practice" --artist "Test Band" --year 1937
woodshed --help
```

Der Befehl spricht nur mit der App auf demselben Mac, über eine Socket-Datei, nie über das Netzwerk. Details: [`docs/FUNKTIONEN.md`](docs/FUNKTIONEN.md) (Zeile «Kommandozeile»).

## Datenschutz

Woodshed Player arbeitet **lokal**.

- Kein Konto nötig, keine Werbung, keine Analyse, kein Tracking.
- Keine Netzwerkverbindung, ausser für den Abgleich, den Du selbst wählst (Google Drive nach der Anmeldung oder Deine eigenen gekoppelten Geräte), und das Laden der Web-App.
- Deine Musik und Deine Bibliothek bleiben im privaten Ordner der App, bei der Web-App im privaten Speicher des Browsers.
- Das Mikrofon nutzt die App nur, während Du damit aufnimmst oder **Scharf** an ist; Aufnahmen bleiben auf Deinem Gerät (in der Web-App im Speicher des Browsers) und verlassen es nur mit dem gewählten Abgleich.
- Eine automatische Prüfung bei jedem Push stellt sicher, dass nur der Code für den Abgleich Verbindungen öffnen darf.

Datenschutzerklärung: <https://ingen63.github.io/Woodshed-Player/datenschutz.html> · Nutzungsbedingungen: <https://ingen63.github.io/Woodshed-Player/nutzungsbedingungen.html> · Alle Details: [`docs/FUNKTIONEN.md`](docs/FUNKTIONEN.md#datenschutz-im-detail)

## Unter der Haube

- **App:** [Flutter](https://flutter.dev) für macOS, iOS und das Web, in [`app/`](app/).
- **Audio-Kern:** C++17 in [`core/`](core/) mit C-API, mit [miniaudio](https://miniaud.io), [Signalsmith Stretch](https://signalsmith-audio.co.uk/code/stretch/) und libFLAC. Nativ über `dart:ffi`, im Browser als WebAssembly in einem AudioWorklet.
- **Gründlich getestet:** Unit- und Oberflächentests, Sanitizer, Untergrenzen für die Abdeckung, Mutationstests und eine Prüfung, dass sich der WASM-Kern genau wie der native verhält. Siehe [`docs/TESTS.md`](docs/TESTS.md).
- **Ältere Version:** Die ursprüngliche SwiftUI-App liegt weiter in [`WoodshedPlayer/`](WoodshedPlayer/).

## Mitarbeit

Anforderungen kommen aus [GitHub Issues](https://github.com/ingen63/Woodshed-Player/issues), jedes mit Abnahmekriterien als Häkchen-Liste. Bauen, Testen, die Technik im Detail und den Release-Ablauf beschreibt [`docs/ENTWICKLUNG.md`](docs/ENTWICKLUNG.md), die Arbeitsregeln stehen in [`CLAUDE.md`](CLAUDE.md). Sicherheitslücken bitte wie in [`SECURITY.md`](SECURITY.md) beschrieben melden.

## Lizenz

Der Quellcode und das App-Icon ([Quelle](app/assets/icons/README.md)) stehen unter der [MIT-Lizenz](LICENSE). Der Name «Woodshed Player» ist davon nicht umfasst.

Die Schriften Inter und JetBrains Mono stehen unter der [SIL Open Font License 1.1](app/assets/fonts/README.md). Der Audio-Kern enthält miniaudio (Public Domain oder MIT-0), Signalsmith Stretch und Signalsmith Linear (MIT) sowie libFLAC (BSD-3-Clause). Der MP3-Export am Mac lädt **LAME** (LGPL) als eigene, austauschbare Bibliothek. Versionen, Quellen und Lizenztexte: [`docs/ENTWICKLUNG.md`](docs/ENTWICKLUNG.md#lizenzen-im-detail) und in der App unter *Über Woodshed Player › Lizenzen ansehen*.
