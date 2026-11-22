# Eingebundene Bibliotheken

Unverändert übernommen, Lizenztexte im jeweiligen Ordner. miniaudio und Signalsmith sind header-only. Von libFLAC liegen nur die Teile für natives FLAC hier (Quellen von `src/libFLAC` und ihre Header, `include/FLAC`, die nötigen Header aus `include/share` und `win_utf8_io.c` für Windows), ohne Ogg, ohne SIMD-Varianten, ohne Werkzeuge und Tests. Gebaut wird es mit der eigenen `core/src/flac_config/config.h`.

| Ordner | Projekt | Version | Lizenz |
|---|---|---|---|
| `miniaudio/` | https://github.com/mackron/miniaudio | 0.11.26 (877ea4a) | Public Domain (Unlicense) oder MIT-0 |
| `signalsmith-stretch/` | https://github.com/Signalsmith-Audio/signalsmith-stretch | Tag 1.4.0 (a670068) | MIT |
| `signalsmith-linear/` | https://github.com/Signalsmith-Audio/linear (von signalsmith-stretch benötigt) | Tag 0.6.6 | MIT |
| `flac/` | https://github.com/xiph/flac (libFLAC, #113) | Tag 1.5.0 (1507800) | BSD-3-Clause (`COPYING.Xiph`) |

Aktualisieren: neue Version holen, Dateien ersetzen, Version hier nachführen, `ctest` im Kern laufen lassen.
