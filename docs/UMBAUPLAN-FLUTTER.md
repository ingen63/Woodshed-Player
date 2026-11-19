# Umbauplan: Woodshed Player auf Flutter

Stand: 19.11.2026 (Web-App statt Android, #41) · Status: Entwurf

## Ziel

Eine Codebasis für **macOS, Windows, Linux und iPhone/iPad**, dazu die **Web-App** im Browser für Android und alle anderen Geräte (siehe «Android und Web-App» unten und `docs/PLAN-WEB-UND-SYNC.md`).

| Funktion | macOS | Windows | Linux | iPhone/iPad | Web-App (auch Android) |
|---|---|---|---|---|---|
| Bibliothek, Ordner, Sortierung | ✓ | ✓ | ✓ | ✓ | ✓ |
| Tempo ohne Tonhöhenänderung | ✓ | ✓ | ✓ | ✓ | ✓ |
| Loops mit Markern | ✓ | ✓ | ✓ | ✓ | ✓ |
| Metronom | ✓ | ✓ | ✓ | ✓ | ✓ |
| Aufnahme laufender Musik (ohne Mikrofon) | ✓ | ✓ | ✓ | **–** | **–** |
| Abgleich (Google Drive, OneDrive, direkte Verbindung) | ✓ | ✓ | ✓ | ✓ | ✓ |

Die Web-App liegt auf GitHub Pages unter <https://ingen63.github.io/Woodshed-Player/app/> (#41).

## Architektur

```
┌──────────────────────────────────────────────┐
│ Flutter-Oberfläche (Dart)                    │  Liste, Ordner, Player, Loop-Marker,
│                                              │  Tempo-Regler, Metronom, Einstellungen
├──────────────────────────────────────────────┤
│ Dart-Schicht: Bibliothek, Einstellungen,     │  library.json, Import, Sortierung
│ Player-Service                               │
├────────────────────── dart:ffi ──────────────┤
│ Audio-Kern (C++), eine C-API                 │  Dekodieren, Time-Stretch, Loop,
│  miniaudio · signalsmith-stretch             │  Seek, Metronom, Pegel
├──────────────────────────────────────────────┤
│ Aufnahme-Module, je Plattform nativ          │
│  macOS: Core Audio Process Tap (Swift)       │
│  Windows: WASAPI Loopback (über miniaudio)   │
│  Linux: PipeWire/PulseAudio-Monitor (miniaudio)│
└──────────────────────────────────────────────┘
```

**Warum ein eigener Audio-Kern statt eines fertigen Flutter-Plugins:** Plugins wie `just_audio` können Tempo ohne Tonhöhenänderung nicht auf allen Plattformen, und Loops sind dort nicht sample-genau lückenlos. Genau das ist der Kern der App.

### Bibliotheken (alle mit MIT kompatibel)

| Zweck | Bibliothek | Lizenz |
|---|---|---|
| Oberfläche | Flutter | BSD-3 |
| Wiedergabe, Dekodieren (MP3, WAV, FLAC), Loopback-Aufnahme | miniaudio | Public Domain / MIT-0 |
| Tempo ohne Tonhöhenänderung | signalsmith-stretch | MIT |
| AAC/M4A dekodieren (falls nötig) | Plattform-Decoder (AVFoundation, Media Foundation, MediaCodec), unter Linux FFmpeg | – / LGPL dynamisch |
| Dateien wählen, Drag & Drop | `file_picker`, `desktop_drop` | MIT/BSD |
| Pfade | `path_provider` | BSD |
| Audio-Session, Sperrbildschirm-Steuerung | `audio_session`, `audio_service` | MIT |
| Dart-Bindings erzeugen | `ffigen` | BSD |

**Nicht verwenden:** JUCE, Rubber Band (GPL/kommerziell), Qt.

## Phasen

Aufwand grob geschätzt in Arbeitstagen, mit KI-Unterstützung. Grösste Unsicherheit: Phase 1 und 7.

### Phase 0 – Vorbereitung (1 Tag)
- Flutter-SDK installieren, `flutter doctor` für macOS, iOS, Android grün.
- Windows- und Linux-Builds über **GitHub Actions** (kein eigener PC nötig) oder eine VM.
- Repo-Struktur festlegen:
  ```
  /app      Flutter-Projekt
  /core     C++-Audio-Kern mit C-API und Tests
  /legacy   bisherige SwiftUI-App (bis Flutter gleichwertig ist)
  ```

### Phase 1 – Prototyp Audio-Kern (3–5 Tage) · **Go/No-Go**
Kleinstes Programm, das beweist, dass der Ansatz trägt:
- MP3 laden und abspielen auf macOS und iOS.
- Tempo 0,1×–2× ohne Tonhöhenänderung. Klangqualität bei 0,5× und darunter mit der Swift-Version vergleichen.
- Loop A–B lückenlos.
- Latenz beim Ändern von Tempo und Position.

Wenn die Qualität nicht reicht: anderen Stretcher testen (z. B. SoundTouch, LGPL) oder auf Apple-Geräten AVAudioUnitTimePitch weiterverwenden.

### Phase 2 – Audio-Kern vollständig (5–7 Tage)
C-API, etwa:
```c
wp_player* wp_create(void);
int  wp_load(wp_player*, const char* path);
void wp_play(wp_player*);  void wp_pause(wp_player*);
void wp_seek(wp_player*, double seconds);
void wp_set_rate(wp_player*, double rate);       // 0.1–2.0, Tonhöhe bleibt
void wp_set_loop(wp_player*, double a, double b); // a<b, min. 1 s; b<=a = aus
void wp_set_volume(wp_player*, float v);
double wp_position(wp_player*);  double wp_duration(wp_player*);
```
- Thread-sichere Steuerung (Befehle über Lock-free-Queue in den Audio-Thread).
- Unit-Tests für Loop-Grenzen, Seek, Dateiende.
- Builds für alle fünf Plattformen (CMake; iOS/macOS als XCFramework).

### Phase 3 – Dart-Anbindung und Player-Service (2–3 Tage)
- `ffigen`-Bindings, `PlayerService` mit Zustand (Position, Dauer, spielt/pausiert, Fehler).
- Positionsabfrage ~30× pro Sekunde für den Fortschrittsbalken.

### Phase 4 – Bibliothek und Datenmodell (2–3 Tage)
Aus der Swift-App übernehmen (`Track.swift`, `Library.swift`):
- `Track`, `Folder`, `PlaybackSettings` (Tempo, Loop, an/aus) **pro Datei**.
- `library.json` im gleichen Format `{folders, tracks}`, damit ein Import der alten Bibliothek möglich ist.
- Import kopiert Dateien in den App-Ordner, liest Titel, Künstler, Album, Cover.
- Sortierung: alphabetisch, nach Hinzufügedatum, eigene Reihenfolge.

### Phase 5 – Oberfläche (6–9 Tage)
Nachbau der bestehenden Ansichten (`TrackListView`, `PlayerView`):
- Liste mit Ordnern, Drag & Drop zum Sortieren und in Ordner verschieben, Kontextmenüs.
- Player: Cover, Titel, Play/Pause, ±15 s, Fortschrittsbalken, Lautstärke.
- Tempo: Schalter, Regler 0,05er-Schritte, Schnellwahl 0,5/0,7/0,8/0,9/1,0/1,1.
- Loop: Schalter, `mm:ss`-Felder, „Aktuelle Position“, ziehbare Marker.
- Tastatur (Desktop): Leertaste, S, E, ←/→. Auf dem Desktop Dateien in die Liste ziehen.
- Layouts: Desktop/iPad zweispaltig, Phone (iPhone, Web-App auf dem Handy) einspaltig mit Navigation.

### Phase 6 – Plattform-Integration (3–4 Tage)
- iOS: Hintergrund-Audio, Audio-Session, Sperrbildschirm und Kopfhörertasten.
- Android: keine native App, stattdessen die Web-App (`docs/PLAN-WEB-UND-SYNC.md`, W7 #39: Media Session, Wake Lock, Offline-Start).
- Desktop: Menüs, Fenstergrösse merken, Mediatasten.
- Teilen/„Öffnen mit“ auf iOS als Importweg.

**Meilenstein: Gleichstand mit der Swift-App.** Danach `/legacy` einfrieren.

### Phase 7 – Aufnahme auf dem Desktop (5–8 Tage)
- **Windows:** WASAPI-Loopback des Standard-Ausgabegeräts (in miniaudio eingebaut).
- **Linux:** Monitor-Quelle von PipeWire/PulseAudio als Eingang (über miniaudio).
- **macOS:** Core Audio Process Tap (ab macOS 14.2) als kleines Swift-Plugin. Einmalige Berechtigung für Systemaudio-Aufnahme.
- Gemeinsam: Aufnahme starten/stoppen, Pegelanzeige, Datei als WAV (später M4A/MP3) direkt in die Bibliothek, Titel aus Datum/Uhrzeit.
- iPhone/iPad: Funktion ausgeblendet.

### Phase 8 – Neue Funktionen (je 2–5 Tage)
- **Metronom** im Audio-Kern (sample-genau, Takt, Betonung, Lautstärke, optional zum Track mitlaufend).
- **Playlisten** (getrennt von Ordnern, ein Titel kann in mehreren sein).
- **Abgleich** über Google Drive, OneDrive oder direkte Verbindung: eigener Plan (`docs/KONZEPT-SYNC.md`).

### Phase 9 – Veröffentlichung (3–5 Tage)
- macOS/iOS: TestFlight, App Store (Apple-Entwicklerkonto nötig).
- Windows: MSIX oder Installer; Linux: Flatpak/AppImage; Web-App: GitHub Pages bei jedem Tag (#41).
- CI: GitHub Actions baut alle Plattformen bei jedem Push.
- Datenschutzangaben je Store, `PrivacyInfo.xcprivacy` für Apple.

## Aufwand gesamt

| | Arbeitstage |
|---|---|
| Phasen 0–6 (Gleichstand mit heutiger App) | ca. 22–32 |
| Phase 7 (Aufnahme Desktop) | ca. 5–8 |
| Phase 9 (Veröffentlichung) | ca. 3–5 |
| **Summe ohne neue Funktionen** | **ca. 30–45** |

## Risiken

| Risiko | Gegenmassnahme |
|---|---|
| Time-Stretch-Qualität schlechter als Apples AVAudioUnitTimePitch | Prototyp in Phase 1 vergleicht direkt; Ausweichlösung pro Plattform |
| App Store lehnt Aufnahmefunktion ab (Richtlinie 5.2.3) | Aufnahme als „eigene Wiedergabe / Übungsmitschnitt“ beschreiben; notfalls macOS-Version mit Aufnahme ausserhalb des Stores verteilen |
| Windows/Linux ohne eigenes Testgerät | CI-Builds plus VM; Tester aus der Community |
| Oberfläche wirkt auf Apple-Geräten weniger nativ | Cupertino-Widgets, plattformabhängige Details (Menüs, Tastenkürzel) |
| Bestehende Daten der Swift-App | gleiches JSON-Format, einmaliger Import |

## Android und Web-App

Eine native Android-App gibt es nicht (#25 als «not planned» geschlossen). Android-Geräte nutzen die **Web-App** im Browser, die aus derselben Flutter-Codebasis mit dem Audio-Kern als WebAssembly entsteht und sich auf den Home-Bildschirm legen lässt (PWA, #39). Aufnahme gibt es dort nicht. Plan, Phasen W0 bis W9 und Auslieferung auf GitHub Pages: `docs/PLAN-WEB-UND-SYNC.md`.

## Nächster Schritt

Phase 0 und der Prototyp aus Phase 1. Er entscheidet, ob der Umbau wie geplant weitergeht.
