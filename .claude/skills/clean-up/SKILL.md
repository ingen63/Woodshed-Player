---
name: clean-up
description: Räumt Woodshed Player auf - nicht mehr benötigte GitHub-Workflow-Runs sowie Systemmüll und Build-Ordner (Xcode DerivedData des Projekts, später Flutter/C++-Builds). Zeigt vor jedem Löschen eine Zusammenfassung, die bestätigt werden muss. Verwenden bei «aufräumen», «clean-up», «Workflow-Runs löschen», «Speicher freigeben».
---

# Aufräumen (clean-up)

Zwei Teile, jeder mit Trockenlauf, Zusammenfassung und Bestätigung. Ohne ausdrückliche Bestätigung wird **nichts**
gelöscht. Beide Teile laufen über `.claude/skills/clean-up/clean_up.py` im Projektordner.

Hast Du nur einen Teil verlangt («nur die Runs», «nur lokal»), nur diesen ausführen.

## 1. Workflow-Runs auf GitHub

1. Trockenlauf: `python3 .claude/skills/clean-up/clean_up.py runs`
2. Zusammenfassung zeigen: Anzahl insgesamt, was bleibt (mit Grund), was gelöscht wird, Anzahl je Workflow.
3. Mit `AskUserQuestion` bestätigen lassen («N Workflow-Runs löschen?», Optionen «Löschen» und «Abbrechen»). In der Frage
   sagen, dass das Löschen endgültig ist und Protokolle und Artefakte mit verschwinden.
4. Nur nach «Löschen»: `python3 .claude/skills/clean-up/clean_up.py runs --apply` und das Ergebnis melden.

Es bleiben immer: laufende oder wartende Runs, je Workflow der neueste abgeschlossene Run, Runs zu einem veröffentlichten Release.

## 2. Lokal

1. Trockenlauf: `python3 .claude/skills/clean-up/clean_up.py local`
2. Zusammenfassung zeigen: Systemmüll (`.DS_Store`, `__pycache__`) und Build-Ordner mit Grösse:
   Xcode-DerivedData dieses Projekts (`~/Library/Developer/Xcode/DerivedData/WoodshedPlayer-*`), `build/`,
   später `app/build/`, `app/.dart_tool/`, `core/build/`. Dazu der Hinweis, dass der nächste Build länger dauert.
3. Meldet das Skript, dass gerade gebaut wird (`xcodebuild`, `flutter`, `dart`, `cmake`), nicht löschen, sondern melden und später erneut fragen.
4. Mit `AskUserQuestion` bestätigen lassen (Optionen «Löschen» und «Abbrechen»).
5. Nur nach «Löschen»: `python3 .claude/skills/clean-up/clean_up.py local --apply` und das Ergebnis melden.

Nicht angefasst werden: eingecheckte Dateien, `.git`, `docs/`, die App-Daten (importierte Titel unter Application Support).

## Regeln

- Jede Bestätigung gilt nur für die gezeigte Liste. Ändert sich etwas, neu fragen.
- Nichts committen. Der Skill ändert keine eingecheckten Dateien.
- Schlägt ein Löschen fehl, die Fehler melden und nicht wiederholen.
