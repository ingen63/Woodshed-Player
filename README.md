# Woodshed Player

Native SwiftUI-App für **macOS 14+** und **iOS/iPadOS 17+** aus einer gemeinsamen Codebasis.

## Starten

1. **Xcode** aus dem Mac App Store installieren (Version 16 oder neuer) und einmal öffnen.
2. `WoodshedPlayer.xcodeproj` öffnen.
3. Target *WoodshedPlayer* → *Signing & Capabilities* → unter *Team* deine Apple-ID wählen.
   Falls die Bundle-ID `de.papa.WoodshedPlayer` schon vergeben ist, dort ändern.
4. Oben in der Leiste als Ziel **My Mac** oder einen iPhone-Simulator/dein iPhone wählen → **⌘R**.

## Funktionen

| Funktion | Bedienung |
| --- | --- |
| MP3 hinzufügen | **+** in der Symbolleiste (⌘O), auf dem Mac auch Dateien in die Liste ziehen |
| MP3 löschen | Rechtsklick → *Löschen*, auf dem Mac auch Entf-Taste, auf iOS wischen oder *Bearbeiten* |
| Ordner | Ordner-Symbol in der Symbolleiste (⇧⌘N) legt einen Ordner an. Titel mit der Maus auf einen Ordner (oder zwischen dessen Titel) ziehen oder per Rechtsklick → *In Ordner verschieben*. Rechtsklick auf einen Ordner: *MP3 hinzufügen*, *Umbenennen*, *Ordner löschen* (die Titel bleiben erhalten) |
| Sortierung | Pfeil-Symbol → *Alphabetisch*, *Hinzugefügt* (neueste zuerst), *Eigene Reihenfolge* |
| Eigene Reihenfolge | Titel innerhalb eines Ordners mit der Maus (bzw. dem Finger) verschieben, die Sortierung wechselt dann automatisch auf *Eigene Reihenfolge* |
| Abspielen | Play/Pause (**Leertaste**), ±15 s, Fortschrittsbalken zum Springen, Lautstärke. Stoppt man mit der Leertaste bei aktivem Loop, springt die Position zum Loop-Anfang zurück |
| Geschwindigkeit | Schalter *Geschwindigkeit*, Regler 0,1× – 2× in 0,05er-Schritten, Pfeiltasten **←** / **→**, Schnellwahl 0,5× / 0,7× / 0,8× / 0,9× / 1,0× / 1,1×. Die Tonhöhe bleibt gleich |
| Loop | Schalter *Loop*, Anfang/Ende als `mm:ss` (z. B. `01:23` – `02:11`), per *Aktuelle Position*, mit den Tasten **S** (Anfang) / **E** (Ende) oder durch Ziehen der orangen Marker im Fortschrittsbalken (die Zeitfelder zeigen dabei live die Position). Das Ende liegt immer mindestens 1 s nach dem Anfang |

Geschwindigkeit und Loop werden **pro Datei** gespeichert und beim nächsten Öffnen wiederhergestellt.

## Technik

- `Audio/AudioPlayer.swift`: `AVAudioEngine` → `AVAudioPlayerNode` → `AVAudioUnitTimePitch`.
  Die Geschwindigkeit ändert sich ohne Tonhöhenänderung. Loops werden als sich wiederholende Segmente geplant (lückenlos).
- `Model/Library.swift`: Importierte Dateien werden in den App-Ordner kopiert (*Application Support/WoodshedPlayer*).
  Metadaten und Einstellungen liegen in `library.json`.
- `Views/PlayerKeyboardShortcuts.swift`: Tastatursteuerung. Beim Tippen in Textfeldern ist sie aus.
- `Views/`: SwiftUI-Oberfläche, angelehnt an die macOS-Schnellansicht.
- `WoodshedPlayerTests/`: Tests (Swift Testing) für Zeitformat, Loop-Grenzen und `library.json`. Testaudio wird im Test erzeugt.
  Ausführen mit ⌘U in Xcode oder `xcodebuild -project WoodshedPlayer.xcodeproj -scheme WoodshedPlayer -destination 'platform=macOS' test`.
- Auf iOS läuft die Wiedergabe auch im Hintergrund weiter (Background Mode *Audio*).

## Datenschutz

Woodshed Player arbeitet **vollständig lokal**:

- Keine Netzwerkverbindungen, kein Konto, keine Werbung.
- Keine Analyse- oder Tracking-Dienste, keine Weitergabe von Daten an Dritte.
- Importierte MP3-Dateien werden in den privaten App-Ordner kopiert. Titel, Künstler, Album, Cover sowie Tempo- und Loop-Einstellungen werden nur dort (`library.json`) und in den lokalen App-Einstellungen gespeichert.
- Die App läuft in der macOS-App-Sandbox und liest nur Dateien, die du selbst auswählst.
- Löschst du die App (und ihren Datenordner), sind alle gespeicherten Daten weg.

## Lizenz

Der Quellcode steht unter der [MIT-Lizenz](LICENSE). Der Name „Woodshed Player“ und das App-Icon sind davon nicht umfasst.
