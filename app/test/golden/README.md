# Golden-Dateien

Musterdateien jeder Version von `library.json` (#10/AK5). Die aktuelle Version der App muss jede davon lesen
(`test/golden_files_test.dart`); eine Datei wird nie geändert, ein neues Format bekommt eine neue Datei. Alle Titel,
Namen und IDs sind erfunden.

| Datei | Version | erzeugt mit |
|---|---|---|
| `library_swift_legacy.json` | Format 1 der Swift-App, `[Track]` (vor den Ordnern) | `make_golden.swift` (Modell `WoodshedPlayer/Model/Track.swift`) |
| `library_swift.json` | Format 1 der Swift-App, `{folders, tracks}` | `make_golden.swift` |
| `library_v2_36.json` | Format 2 mit Stempeln (#36), ein Feld `loop` je Titel | `make_golden_v2.dart` mit dem Code von Commit 8f9fb22 (ohne Loop-IDs, `noUpload` und Ordner-Abgleich) |
| `library_v2.json` | Format 2 seit #37: Loops je ID (`loops.<id>`, `activeLoop`), `noUpload`, Ordner `sync` | `make_golden_v2.dart` |

Neu schreiben nur die aktuelle Datei, und nur wenn sich das Format gewollt ändert; dann zuerst die bisherige unter
neuem Namen behalten:

```sh
cd app && dart run test/golden/make_golden_v2.dart test/golden/library_v2.json
```
