# App-Icon

Das App-Icon von Woodshed Player ist Konzept 1 «Waveform Loop»: ein Ausschnitt einer Wellenform, das mittlere Drittel in Bernstein zwischen zwei Loop-Klammern, auf dem dunklen Hintergrund des Designs «Studio».

## Quelle und Rechte

- **Vorlage:** [`concepts/icon_1_waveform_loop.svg`](concepts/icon_1_waveform_loop.svg)
- **Herkunft:** selbst erstellt für dieses Projekt, entstanden in Issue #48 (Konzepte) und ausgewählt in #6. Keine fremden Grafiken, Schriften oder Vorlagen.
- **Rechte:** liegen beim Projekt Woodshed Player. Die Vorlage und das Skript sind Teil des Repositorys; wie im Abschnitt «Lizenz» der [README](../../../README.md) festgehalten, ist das App-Icon (wie der Name «Woodshed Player») von der [MIT-Lizenz](../../../LICENSE) des Quellcodes ausgenommen.

Die übrigen Konzepte in `concepts/` (#48) sind ebenfalls selbst erstellt. Sie werden nicht verwendet.

## Erzeugen

Alle Grössen entstehen aus der SVG-Vorlage mit dem Skript (aus `app/`):

```bash
tool/generate_icons.sh
```

Ziele:

| Plattform | Ort |
|---|---|
| macOS | `macos/Runner/Assets.xcassets/AppIcon.appiconset/` (16 bis 1024 px, transparente Ecken) |
| iOS | `ios/Runner/Assets.xcassets/AppIcon.appiconset/` (alle Grössen aus `Contents.json`, ohne Transparenz) |
| Web | `web/favicon.png`, `web/icons/` (inkl. maskable) |
| Android, Windows, Linux | `assets/icons/generated/` (bis die Plattformordner angelegt sind) |

`preview.html` zeigt die Konzepte in mehreren Grössen und Masken. Der Test `test/app_icon_test.dart` prüft, dass jede in `Contents.json` verlangte Grösse vorhanden ist.
