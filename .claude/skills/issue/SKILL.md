---
name: issue
description: Legt ein GitHub-Issue für Woodshed Player an (kurzer Titel ohne Präfix, Art über Labels, Abnahmekriterien als Häkchen-Liste). Verwenden bei «Issue anlegen», «neue Anforderung», «Fehler erfassen».
---

# Issue anlegen (GitHub-Konvention)

Issues werden über ihre GitHub-Nummer angesprochen (`#22`). Der Titel hat kein Präfix; die Art steht im Label.

## Neues Issue

1. **Art bestimmen** und als Label setzen: Funktion/Änderung `enhancement`, Fehler `bug`, Allgemeines/Repo/Werkzeuge `general`.
   Zusätzliche Labels nach Bereich: `audio`, `ui`, `repo`, bei Doku `documentation`; bei Fehlern der Fundort `found:test|acceptance|usage`.
   Meilenstein «Nächste Version» oder «Später», wenn klar.
2. **Titel:** kurz (höchstens etwa 60 Zeichen), Deutsch, ohne Punkt. Bei Funktionen das Ziel («Ziehbare Loop-Marker»),
   bei Fehlern das Symptom («Absturz beim Öffnen einer leeren MP3»).
3. **Text nach Vorlage** aus `.github/ISSUE_TEMPLATE/funktion.md` bzw. `fehler.md` entwerfen:
   Anforderung (ohne Lösung vorzuschreiben) und **Abnahmekriterien als Häkchen-Liste**, jedes eindeutig und prüfbar.
   Keine privaten Daten (echte Titel, Künstler, Namen, E-Mail).
4. **Entwurf zeigen** (Titel, Labels, Text) und mit `AskUserQuestion` bestätigen lassen
   (Optionen «Anlegen» und «Abbrechen»). Ohne Bestätigung nichts anlegen.
5. Text in eine Datei im Scratchpad schreiben, dann:
   `gh issue create --title "<Titel>" --body-file <Datei> --label <labels> [--milestone "<Meilenstein>"]`
6. Ergebnis melden: Nummer, Titel, Link.

Mehrere Issues: alle Entwürfe zusammen zeigen, einmal bestätigen lassen, dann einzeln anlegen.

## Regeln

- Labels müssen auf GitHub existieren; fehlt eins, melden und nicht selbst anlegen.
- Abnahmekriterien bestehender Issues nicht ändern, nur kommentieren (siehe `CLAUDE.md`).
