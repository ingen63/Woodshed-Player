---
name: issue
description: Legt ein GitHub-Issue für Woodshed Player an, dessen ID zur GitHub-Nummer passt (Issue #22 → «FEA-22 …»), oder gleicht bestehende Issue-Titel ab. Verwenden bei «Issue anlegen», «neue Anforderung», «Fehler erfassen», «Issue-IDs prüfen».
---

# Issue anlegen (ID = GitHub-Nummer)

Die ID im Titel hat dieselbe Nummer wie das Issue auf GitHub. Da die Nummer erst beim Anlegen feststeht, läuft das
Anlegen immer über `tools/issue-id.sh`.

## Neues Issue

1. **Art bestimmen:** `FEA` (Funktion/Änderung, Label `enhancement`), `ISS` (Fehler, Label `bug`), `GEN` (Allgemeines, Repo, Werkzeuge, Label `general`).
   Zusätzliche Labels nach Bereich: `audio`, `ui`, `repo`, bei Doku `documentation`; bei Fehlern der Fundort `found:test|acceptance|usage`.
2. **Text nach Vorlage** aus `.github/ISSUE_TEMPLATE/funktion.md` bzw. `fehler.md` entwerfen:
   Anforderung (ohne Lösung vorzuschreiben) und **Abnahmekriterien als Häkchen-Liste**, jedes eindeutig und prüfbar.
   Keine privaten Daten (echte Titel, Künstler, Namen, E-Mail).
3. **Entwurf zeigen** (Titel ohne ID, Labels, Text) und mit `AskUserQuestion` bestätigen lassen
   (Optionen «Anlegen» und «Abbrechen»). Ohne Bestätigung nichts anlegen.
4. Text in eine Datei im Scratchpad schreiben, dann:
   `tools/issue-id.sh new <FEA|ISS|GEN> "<Titel ohne ID>" <Datei> [weitere,Labels]`
5. Ergebnis melden: Nummer, vollständiger Titel, Link.

Mehrere Issues: alle Entwürfe zusammen zeigen, einmal bestätigen lassen, dann einzeln anlegen.

## Bestehende Titel abgleichen

1. Trockenlauf: `tools/issue-id.sh sync` (Issues aus dem Browser haben oft noch keine oder eine falsche ID).
2. Liste zeigen und bestätigen lassen (Optionen «Umbenennen» und «Abbrechen»).
3. Nur nach Bestätigung: `tools/issue-id.sh sync --apply`.

## Regeln

- Labels müssen auf GitHub existieren; fehlt eins, melden und nicht selbst anlegen.
- Abnahmekriterien bestehender Issues nicht ändern, nur kommentieren (siehe `CLAUDE.md`).
