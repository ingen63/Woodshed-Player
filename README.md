<div align="center">

<img src="app/web/icons/Icon-192.png" width="112" alt="Woodshed Player icon">

# Woodshed Player

### Practise smarter. Play it until it sits.

**The practice player for musicians.**<br>
Slow any track down without changing its pitch, loop the hard bars, play along with a metronome, and let the tempo climb as you get better. On the Mac, on your iPhone or iPad, and in any browser. Free, open source, and private by design.

[**▶ Open the web app**](https://ingen63.github.io/Woodshed-Player/app/) · [**Download 1.0 for macOS**](https://github.com/ingen63/Woodshed-Player/releases) · [What's new](CHANGELOG.en.md)

[![Test quality](https://github.com/ingen63/Woodshed-Player/actions/workflows/test-quality.yml/badge.svg)](https://github.com/ingen63/Woodshed-Player/actions/workflows/test-quality.yml)
[![Pages](https://github.com/ingen63/Woodshed-Player/actions/workflows/pages.yml/badge.svg)](https://github.com/ingen63/Woodshed-Player/actions/workflows/pages.yml)
[![Release](https://github.com/ingen63/Woodshed-Player/actions/workflows/release.yml/badge.svg)](https://github.com/ingen63/Woodshed-Player/actions/workflows/release.yml)

**English** · [Deutsch](README.de.md)

</div>

<br>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/studio-desktop-dark.png">
  <img src="docs/screenshots/studio-desktop-light.png" alt="Woodshed Player on the desktop: waveform with loop, tempo and speed trainer">
</picture>

<table>
  <tr>
    <td width="62%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/studio-tablet-dark.png">
        <img src="docs/screenshots/studio-tablet-light.png" alt="Woodshed Player on a tablet">
      </picture>
    </td>
    <td width="38%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/studio-phone-dark.png">
        <img src="docs/screenshots/studio-phone-light.png" alt="Woodshed Player on a phone">
      </picture>
    </td>
  </tr>
</table>

<sub>English interface, made-up titles and a generated waveform. The screenshots follow your GitHub theme (light or dark).</sub>

## Why Woodshed Player?

*Woodshedding* is what musicians call going off on your own and practising a hard passage over and over until it sits. Woodshed Player is built for exactly that moment: the solo you are transcribing, the run that is still too fast, the groove you want to lock in.

- **Hear every note.** Slow the music down to a crawl and it still sounds like itself, in the right key.
- **Stay on the hard part.** Mark the bars once; the loop, the tempo and your progress are still there tomorrow.
- **Get faster without thinking about it.** The speed trainer raises the tempo for you, pass by pass, until you play it at full speed.
- **Hear yourself.** Arm the recorder, play, and every take lands in your library, ready to listen back or loop.
- **Your music stays yours.** No account, no ads, no tracking. Nothing leaves your device unless you switch on sync.

## Features

### 🎧 Player and practice

- 🐢 **Slower, same pitch.** Tempo from 0.1× to 2× without changing the key, powered by a high-quality time stretch in a C++ audio engine.
- 🔁 **Loops that stay put.** Drag the **S** and **E** markers on the waveform, type `mm:ss.d`, or press **S** / **E** while it plays. Every track remembers its loop and tempo.
- 📈 **Speed trainer.** Start at 60 %, gain 5 % every 10 passes, finish at full speed, all on its own.
- 🥁 **Metronome.** 20–300 BPM, tap tempo, 4/4, 3/4, 2/4 and 6/8, subdivisions down to sixteenths, and an automatic tempo ramp by bars, by time or by passes.

### 🎙️ Recording

- **Record what you play.** Microphone on the Mac and in the web app, system audio on the Mac, lossless as 24-bit FLAC. Each recording goes straight into the library, ready to loop.
- **Armed.** Switch it on in *Practice* or *Metronome* and just play: the first note starts a take with one second of lead-in, a pause ends it, and it is filed under `Recordings › date`. Leave it armed and every phase of playing becomes its own take.

### 📚 Library

- Folders with subfolders of any depth, playlists, multi-select, drag and drop, sorting.
- Each file is stored once, recognised by its content. Trim the start and end of a track (WAV, FLAC, MP3, AAC, M4A).
- **MP3 export on the Mac** with title, artist and year.

### ☁️ Sync, if you want it

- Optional sync through your own Google Drive, using only the files the app creates itself. Without an account, nothing leaves your device.

### 🌗 Made to practise with

- Three areas: Player, Practice and Metronome, with layouts for desktop, tablet and phone.
- Dark by default, light whenever you like; on the Mac even the title bar follows your choice.
- Keyboard shortcuts everywhere (press **?** for the overview) and built-in help that works offline.
- English and German, following the system language, down to the Mac menu bar.

All features in detail (in German): [`docs/FUNKTIONEN.md`](docs/FUNKTIONEN.md).

## New in 1.0

Version 1.0 is the first stable release of the new app: a Flutter interface on a C++ audio engine that runs natively on the Mac and as WebAssembly in the browser. Highlights since the first preview:

- **Recording in the web app,** with the microphone and the **Armed** switch, on iPhone, iPad, Android and the desktop.
- **Armed recording while practising,** every take filed by date.
- **Subfolders,** help pages for every area and a shortcut overview.
- **Dark by default,** with a Mac title bar that matches the app.
- **Audible on the iPhone in silent mode,** like a music app.
- **MP3 export and a command line** on the Mac.

The full list is in the [release notes](CHANGELOG.en.md).

## Platforms

| | How | |
| --- | --- | --- |
| **macOS** 14+ | Native app, Apple Silicon and Intel | System-audio recording, MP3 export and command line only here |
| **iPhone, iPad** | [Web app](https://ingen63.github.io/Woodshed-Player/app/), installable to the home screen | Works offline, lock-screen controls, microphone recording |
| **Android and everything else** | [Web app](https://ingen63.github.io/Woodshed-Player/app/) in the browser | No installation, no account, microphone recording |
| **Windows, Linux** | Coming later | Until then: the web app |

## Installation

The packages of every version are under [Releases](https://github.com/ingen63/Woodshed-Player/releases), with release notes in English and German ([`CHANGELOG.en.md`](CHANGELOG.en.md), [`CHANGELOG.md`](CHANGELOG.md)). Every package contains the license (`LICENSE`) and the license texts of the fonts and engine libraries (folder `Licenses` or `licenses`).

| Package | Platform |
| --- | --- |
| `WoodshedPlayer-<Version>-macos.dmg` | macOS 14 or later, Apple Silicon and Intel (Universal) |
| `WoodshedPlayer-<Version>-web.zip` | Web app to host yourself, the same version as <https://ingen63.github.io/Woodshed-Player/app/> |

- **macOS:** Open the `.dmg` and drag *Woodshed Player* into *Applications*. The app is only ad hoc signed and not notarized (there is no Apple Developer account). So the first time, choose **Right-click › Open** in the Finder and *Open* again in the dialog. If macOS only offers «Don't Open» or «Move to Trash», go to *System Settings › Privacy & Security* and click *Open Anyway* next to «Woodshed Player was blocked». After that it starts normally.
- **Web app:** Nothing to install, just open <https://ingen63.github.io/Woodshed-Player/app/>. To host it yourself, put the folder from the `.zip` at the root of a web server with HTTPS (or serve it on `localhost`). It only runs at the root (`/`), not in a subfolder.

## Command line (Mac)

The app doubles as a command line: play a track from the library, or arm a recording that starts with the first sound and stops by itself after a pause, so a piece played in the browser lands in the library without silence at either end.

```bash
cp tools/woodshed ~/bin/woodshed          # any folder in your PATH
woodshed play --title "Blue Practice" --artist "Test Band"
woodshed record --title "Blue Practice" --artist "Test Band" --year 1937
woodshed --help
```

The command only talks to the app on the same Mac through a socket file, never over the network. Details: [`docs/FUNKTIONEN.md`](docs/FUNKTIONEN.md) (row «Kommandozeile»).

## Privacy

Woodshed Player works **locally**.

- No account needed, no ads, no analytics, no tracking.
- No network connection, except for the sync you choose yourself (Google Drive after signing in, or your own paired devices) and loading the web app.
- Your music and your library stay in the app's private folder, or in the browser's private storage for the web app.
- The microphone is only used while you record with it or while **Armed** is on; recordings stay on your device (in the web app in the browser's storage) and leave it only through the sync you chose.
- An automatic check on every push makes sure only the sync code may open connections.

Privacy policy: <https://ingen63.github.io/Woodshed-Player/datenschutz.html> · Terms of use: <https://ingen63.github.io/Woodshed-Player/nutzungsbedingungen.html> · All details (in German): [`docs/FUNKTIONEN.md`](docs/FUNKTIONEN.md#datenschutz-im-detail)

## Under the hood

- **App:** [Flutter](https://flutter.dev) for macOS, iOS and the web, in [`app/`](app/).
- **Audio engine:** C++17 in [`core/`](core/) with a C API, with [miniaudio](https://miniaud.io), [Signalsmith Stretch](https://signalsmith-audio.co.uk/code/stretch/) and libFLAC. Natively through `dart:ffi`, in the browser as WebAssembly in an AudioWorklet.
- **Tested hard:** unit and UI tests, sanitizers, coverage limits, mutation testing, and a check that the WASM build behaves exactly like the native one. See [`docs/TESTS.md`](docs/TESTS.md).
- **Older version:** the original SwiftUI app lives on in [`WoodshedPlayer/`](WoodshedPlayer/).

## Contributing

Requirements come from [GitHub Issues](https://github.com/ingen63/Woodshed-Player/issues), each with acceptance criteria as a checklist. Building, testing, the technical details and the release process are described in [`docs/ENTWICKLUNG.md`](docs/ENTWICKLUNG.md), the working rules in [`CLAUDE.md`](CLAUDE.md) (both in German). Please report security issues as described in [`SECURITY.md`](SECURITY.md).

## License

The source code and the app icon ([source](app/assets/icons/README.md)) are under the [MIT License](LICENSE). The name “Woodshed Player” is not covered by it.

The fonts Inter and JetBrains Mono are under the [SIL Open Font License 1.1](app/assets/fonts/README.md). The audio engine contains miniaudio (Public Domain or MIT-0), Signalsmith Stretch and Signalsmith Linear (MIT) and libFLAC (BSD-3-Clause). The MP3 export on the Mac loads **LAME** (LGPL) as a separate, replaceable library. Versions, sources and license texts: [`docs/ENTWICKLUNG.md`](docs/ENTWICKLUNG.md#lizenzen-im-detail), and in the app under *About Woodshed Player › View licenses*.
