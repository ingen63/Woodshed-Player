# Konzept: Sync über einen geteilten Ordner, ohne Anmeldung am Desktop

Stand: 19.11.2026 · Status: **abgelöst durch `KONZEPT-SYNC.md`** (Mischform; alle Geräte schreiben über die Schnittstelle, kein Ordner-Sync). Bleibt als Begründung stehen. · Ergänzt `PLAN-WEB-UND-SYNC.md` (W5/W6, #37/#38)

## Idee

Am Desktop meldet sich die App bei keinem Cloud-Anbieter an. Sie schreibt ihren Stand in einen **gewöhnlichen Ordner**, den Du einmal wählst. Den Transport übernimmt der **Sync-Client des Systems** («Google Drive für Desktop», OneDrive), der ohnehin installiert ist.

Am Handy (Web-App) gibt es keinen solchen Ordner. Dort meldet sich die App einmal beim Anbieter an und liest und schreibt **denselben Ordner** über dessen Schnittstelle. Desktop und Handy sehen damit dieselben Dateien.

**Anbieter:** Google Drive und OneDrive. Zusammen decken sie grob 80 % der Cloud-Nutzerinnen und -Nutzer ab (Schätzung, nicht recherchiert). Dropbox und weitere Ordner (iCloud Drive, Syncthing, Nextcloud) funktionieren am Desktop ohne Mehraufwand mit, am Handy aber nicht.

| | Desktop (macOS, Windows, Linux) | Handy (Web-App) |
|---|---|---|
| Einrichtung | einmal den Ordner wählen | einmal anmelden, bei Google zusätzlich den Ordner wählen |
| Danach | still, keine Tokens | Google: still, gelegentlich ein Tippen. OneDrive: etwa täglich eine kurze Weiterleitung, meist ohne Eingabe |
| Netzwerkcode in der App | **keiner** | REST zum gewählten Anbieter |
| Zugriffsrecht | nur der gewählte Ordner (Sandbox-Lesezeichen) | Google `drive.file`, OneDrive `Files.ReadWrite.AppFolder` |

## Wo der Ordner liegt

| Anbieter | Ordner in der Cloud | Am Desktop (Beispiel macOS) | Am Handy |
|---|---|---|---|
| **Google Drive** | `Meine Ablage/WoodshedPlayer`, normaler Ordner | `~/Library/CloudStorage/GoogleDrive-<konto>/Meine Ablage/WoodshedPlayer` | Ordner einmal in der Google-Auswahl (Picker) wählen, Recht `drive.file` |
| **OneDrive** | App-Ordner `Apps/Woodshed Player` (`approot`) | `~/Library/CloudStorage/OneDrive-<konto>/Apps/Woodshed Player` | Recht `Files.ReadWrite.AppFolder`, kein Picker nötig |

Warum nicht überall der app-eigene Bereich: Googles `appDataFolder` ist versteckt und für «Google Drive für Desktop» unsichtbar. Den Desktop-Ordner gibt es dort nicht. Deshalb bei Google ein normaler Ordner mit dem engen Recht `drive.file`: Die App sieht nur, was Du ihr in der Auswahl zeigst oder was sie selbst anlegt, nicht Dein übriges Drive. `drive.file` gilt bei Google als **nicht sensibel**: Nötig ist nur die einfache Prüfung der App, keine Sicherheitsbewertung (Quelle: Google, «Choose Drive API scopes»).

Das weicht von der Entscheidung «nur app-eigener Ordner» im Plan ab, bleibt aber auf einen Ordner begrenzt.

## Ablauf aus Deiner Sicht

1. **Desktop:** Einstellungen → Abgleich → «Sync-Ordner wählen». Die App schlägt gefundene Orte vor (`~/Library/CloudStorage/GoogleDrive-*`, `OneDrive-*`, unter Windows `%USERPROFILE%\OneDrive` und das Google-Drive-Laufwerk) und legt dort `WoodshedPlayer` bzw. `Apps/Woodshed Player` an. Ein Klick genügt, ein anderer Ordner ist frei wählbar.
2. Liegt dort schon ein Stand eines anderen Geräts, führt die App beide zusammen.
3. **Handy:** Einstellungen → Abgleich → Google Drive oder OneDrive → anmelden. Bei Google wählst Du danach den Ordner `WoodshedPlayer` in der Google-Auswahl.
4. Die Statuszeile zeigt je Gerät, wann es zuletzt geschrieben hat («MacBook: vor 2 Min., iPhone: vor 3 Tagen»). So siehst Du, ob ein Sync-Client hängt.

## Aufbau im Ordner

```
WoodshedPlayer/
  format.json                         Format-Version und Bibliotheks-ID
  devices/<geraet-id>.json            Stand dieses Geräts (nur dieses Gerät schreibt die Datei)
  backup/<geraet-id>/state-<n>.json   die letzten 5 eigenen Stände (rotierend)
  audio/<hash>.<ext>                  Audiodateien, Name = SHA-256 des Inhalts
```

### Eine Datei je Gerät statt einer `state.json`

Ein Ordner kennt kein bedingtes Schreiben (ETag), auf das die Sync-Engine heute baut. Schreiben zwei Geräte dieselbe Datei, macht der Sync-Client daraus Konfliktkopien (`state (1).json`) oder überschreibt still.

Darum schreibt **jedes Gerät nur seine eigene Datei**. Gelesen werden alle Dateien unter `devices/`. Das Zusammenführen aus #36 (je Feld, kommutativ, assoziativ, idempotent) ergibt auf jedem Gerät denselben Stand, egal in welcher Reihenfolge die Dateien ankommen. Jedes Gerät schreibt den **zusammengeführten** Stand, nicht nur seine eigenen Änderungen. Eine Gerätedatei, die 180 Tage nicht geschrieben wurde (ausgemustertes Gerät), kann deshalb ohne Verlust weg.

Weil Desktop (Ordner) und Handy (Schnittstelle) dieselben Dateien lesen, gilt dieses Layout **für beide Wege**. Bedingtes Schreiben braucht die Engine dann nicht mehr.

Taucht trotzdem eine Konfliktkopie auf (z. B. dieselbe Gerät-ID auf zwei Rechnern nach dem Kopieren eines App-Ordners), liest die App sie mit, führt sie zusammen, räumt sie weg und erneuert die Gerät-ID.

### Schreiben und Lesen

- **Atomar:** Am Desktop zuerst `.<name>.tmp-<zufall>`, dann umbenennen. Dateien mit führendem Punkt oder `.tmp` werden nie gelesen. Über die Schnittstelle ist ein Upload ohnehin atomar.
- **Halbe Dateien:** Ein Sync-Client kann eine Datei zeigen, die noch nicht fertig übertragen ist. JSON, das sich nicht lesen lässt, und Audio mit falschem Hash gelten als «noch unterwegs»: kein Fehler, nächster Versuch später.
- **Nur-online-Dateien:** «Google Drive für Desktop» (Streamen) und OneDrive (Dateien bei Bedarf) legen Platzhalter ab. Lesen löst einen Download aus und kann dauern. Lesen läuft deshalb im Hintergrund (Isolate) mit Zeitlimit.
- **Audio ist unveränderlich** (Name = Hash). Kopieren ist idempotent, ein Abbruch schadet nicht.
- **Löschen von Audio** nur, wenn der Titel im zusammengeführten Stand einen Grabstein hat oder ausgeschlossen ist (wie in #37).

### Wann abgeglichen wird

Auslöser wie in #37 (Start, Vordergrund, lokale Änderung nach 5 s), dazu:
- Desktop: Beobachten des Ordners (`Directory.watch`, auf macOS FSEvents), zusammengefasst nach 2 s.
- Im Vordergrund alle 60 s `devices/` auflisten (billig, am Handy eine Anfrage).

## Einbau in die bestehende Sync-Engine

- **`PerDeviceLayout`** ersetzt in der Engine das Lesen und bedingte Schreiben von `state.json`. Zusammenführen, Audio-Planung, Warteschlange und Backoff aus #37 bleiben.
- **`FolderProvider implements CloudProvider`** (`app/lib/sync/folder_provider.dart`) über `dart:io`, nur Desktop. Version = Änderungszeit plus Grösse, `quota` = freier Platz auf dem Datenträger.
- **`GoogleDriveProvider`** und **`OneDriveProvider`** (aus #38, nur noch zwei statt drei, im Web und bei Bedarf auch am Desktop). Google arbeitet mit Datei-IDs statt Pfaden. Der Provider bildet `devices/…` und `audio/…` auf Unterordner des gewählten Ordners ab und merkt sich die IDs.
- `NoSync` bleibt Standard. Ohne Ordner bzw. Konto liest und schreibt die App nichts ausserhalb ihres eigenen Datenordners.

## Plattformen

| Plattform | Weg | Was es braucht |
|---|---|---|
| macOS | Ordner | Die App ist in der Sandbox und hat heute nur `files.user-selected.read-only`. Nötig: `files.user-selected.read-write` und `files.bookmarks.app-scope`. Der gewählte Ordner wird als **Security-Scoped Bookmark** in `device.json` gespeichert, sonst ist der Zugriff nach dem Neustart weg. Die Orte unter `~/Library/CloudStorage/` lassen sich vorschlagen, freigeben musst Du sie einmal im Auswahldialog. |
| Windows, Linux | Ordner | Pfad in `device.json`, keine Sandbox. Unter Linux gibt es keinen offiziellen Client von Google oder Microsoft; dort Anmeldung wie am Handy oder ein Fremd-Client (z. B. rclone). |
| iPhone/iPad, Android | Schnittstelle | Anmeldung per OAuth mit PKCE (Plan W6), Tokens in IndexedDB. |

## Anmeldung am Handy: was «ohne Interaktion» dort heisst

- **Google:** Ohne eigenen Server gibt Google einer Web-App nur kurzlebige Zugriffstokens (ca. 1 h). Die App erneuert sie still, solange Du bei Google angemeldet bist. Läuft das schief, genügt ein Tippen. Unverändert gegenüber dem Plan.
- **OneDrive:** Microsoft gibt Web-Apps (Typ «SPA») Refresh-Tokens, aber nur für **24 Stunden**, auch wenn sie benutzt werden (Quelle: Microsoft Learn, «Refresh tokens»). Danach braucht es eine Weiterleitung über die Anmeldeseite von Microsoft in voller Seite. Ist die Sitzung bei Microsoft noch aktiv, siehst Du nur ein kurzes Neuladen, ohne Eingabe. Die App macht das beim Start, nicht mitten im Üben. **Korrektur zum Plan:** Dort steht, OneDrive gebe dauerhafte Refresh-Tokens.

## Ungeklärt, vor der Umsetzung zu prüfen

Die Dokumentation der Anbieter beantwortet diese Fragen nicht. Sie entscheiden, ob das Konzept so trägt:

| # | Frage | Wenn nein |
|---|---|---|
| G1 | Sieht die Web-App mit `drive.file` nach der Auswahl des **Ordners** auch die Dateien darin, die «Google Drive für Desktop» hochgeladen hat (also eine andere App)? Und Dateien, die später dazukommen? | **Kritisch.** Dann sieht das Handy nichts vom Desktop. Ausweg: Der Desktop schreibt bei Google ebenfalls über die Schnittstelle (Anmeldung auch am Desktop, kein Ordner-Sync für Google). Das breite Recht `drive` kommt nicht in Frage (eingeschränkt, Sicherheitsbewertung). |
| G2 | Funktioniert die Google-Auswahl (Picker, läuft in einem iframe von `docs.google.com`) in der installierten Web-App auf iPhone und Android? | Ohne Picker sieht die App mit `drive.file` nur Ordner, die sie selbst angelegt hat. Die Dateien des Desktops sieht sie dann trotzdem nicht (wie G1). Ausweg wie bei G1: Google auch am Desktop über die Schnittstelle. |
| M1 | Synchronisiert der OneDrive-Client den Ordner `Apps/Woodshed Player` auf den Desktop? (Laut Microsoft verhält er sich «wie jeder andere Ordner», ausdrücklich steht es nicht da.) | Desktop schreibt bei OneDrive über die Schnittstelle. |
| M2 | Gibt es den App-Ordner auch bei Geschäftskonten (OneDrive for Business)? | Nur private Microsoft-Konten unterstützen, in der Oberfläche benennen. |

Diese vier Punkte prüft der Machbarkeitstest S0 mit Testkonten (keine echten Daten).

## Verworfene Ansätze

| Ansatz | Warum nicht |
|---|---|
| Ein gemeinsamer Ordner auf **unserem** Google Drive mit Freigabelink | Die Drive-API schreibt nicht anonym; nötig wäre ein Dienstkonto, dessen Schlüssel in der App steckt. Dann kann jede und jeder die Daten aller lesen und löschen, und fremde Daten lägen bei uns. |
| Googles `appDataFolder` | für den Desktop-Client unsichtbar, also kein Ordner-Sync möglich. |
| Recht `drive` (ganzes Drive) | eingeschränktes Recht mit jährlicher Sicherheitsbewertung, und die App sähe alle Dateien. |
| Dropbox am Handy | deckt kaum zusätzliche Nutzer ab; als Ordner am Desktop geht es trotzdem. Später über dieselbe Schnittstelle möglich. |
| iCloud Drive am Handy | Keine Web-Schnittstelle für iCloud Drive. Am Mac als Ordner möglich, das iPhone erreicht ihn aus der Web-App nicht. |
| Direkter Abgleich im WLAN, WebRTC | HTTPS-Seite darf `http://192.168.…` nicht ansprechen; WebRTC braucht einen Vermittlungsserver. |

## Datenschutz und Regeln

- **Desktop:** Die App öffnet keine Netzverbindung. Die Regel «Kein Netzwerk» bleibt unberührt.
- **Handy:** wie im Plan nur nach ausdrücklicher Anmeldung, nur zum gewählten Anbieter.
- `DATENSCHUTZ.md`, Abschnitt 5, ergänzen: «Wählst Du am Desktop einen Sync-Ordner, schreibt die App Bibliothek und Audiodateien dorthin. Ob und wohin der Ordner übertragen wird, bestimmt Dein Sync-Programm.» Den Satz zum «eigenen, abgeschotteten Ordner» für Google anpassen: ein von Dir gewählter Ordner, die App sieht nur ihn. Dropbox aus der Anbieterliste nehmen.
- Keine Verschlüsselung (wie im Plan). Die Gerät-ID steht in den Dateinamen unter `devices/`; sie ist zufällig und keine Hardware-Kennung.
- Keine neuen Abhängigkeiten am Desktop (`dart:io` genügt). Die Google-Auswahl wird als Skript von Google geladen; das ist eine neue Verbindung zu Google beim Wählen des Ordners und gehört in die Datenschutzerklärung.

## Folgen für Plan und Issues

| Wo | Änderung |
|---|---|
| `PLAN-WEB-UND-SYNC.md`, Entscheidungen | Anbieter: Google Drive und OneDrive (Dropbox später). Zugriffsrecht: Google `drive.file` mit gewähltem Ordner, OneDrive App-Ordner. Desktop: Ordner-Sync ohne Anmeldung. |
| `PLAN-WEB-UND-SYNC.md`, W6 | OneDrive-Tokens 24 h statt dauerhaft; Google Picker dazu. |
| #37 (geschlossen) | Neues Issue für `PerDeviceLayout`, nicht #37 wieder öffnen. |
| #38 | Abnahmekriterien kommentieren (nicht still ändern): Dropbox entfällt, Google mit `drive.file` und Picker, Layout je Gerät. |
| #40 | Bereich «Abgleich» bekommt «Sync-Ordner wählen» und Status je Gerät. |

## Vorschlag Phasen und Issues

| # | Inhalt | Aufwand |
|---|---|---|
| S0 | Machbarkeitstest G1, G2, M1, M2 mit Testkonten und einer kleinen Testseite | 1–2 Tage · **Go/No-Go** für den Ordner-Sync bei Google |
| S1 | `PerDeviceLayout` in der Engine, Tests mit `InMemoryProvider`: zwei und drei Geräte, Konfliktkopie, halbe Datei, falscher Hash, Reihenfolge vertauscht, ausgemustertes Gerät | 2–3 Tage |
| S2 | `FolderProvider`, macOS-Berechtigungen und Security-Scoped Bookmark, Windows/Linux-Pfad, Ordner beobachten, Vorschläge für Google-Drive- und OneDrive-Orte | 2–3 Tage |
| S3 | `OneDriveProvider` (App-Ordner, Upload-Sitzungen, 24-h-Erneuerung) | 2–3 Tage |
| S4 | `GoogleDriveProvider` (`drive.file`, Picker, Pfade auf Datei-IDs abbilden) | 3–4 Tage |
| S5 | Oberfläche: «Sync-Ordner wählen», Anmelden, Status je Gerät, Wechsel und Trennen, Texte in allen ARB-Dateien | 2 Tage |
| S6 | `README.md`, `DATENSCHUTZ.md`, `PLAN-WEB-UND-SYNC.md` nachführen | 0,5 Tage |

S3 und S4 ersetzen #38. **Gesamt:** ca. 13–18 Arbeitstage.

**Vorher bei Dir:** App-Registrierung bei Google Cloud (OAuth-Client für Web, Picker-API-Schlüssel mit Freigabe für `docs.google.com`) und bei Microsoft Entra (Plattform «SPA», Weiterleitung auf die GitHub-Pages-Adresse).

## Offene Fragen an Dich

1. **Linux:** Ohne offiziellen Client von Google oder Microsoft dort Anmeldung wie am Handy, oder Linux beim Abgleich vorerst weglassen?
2. **Audio im Ordner:** wie in der Cloud standardmässig mit, oder nur Metadaten?
3. **Falls G1 scheitert:** Google am Desktop ebenfalls mit Anmeldung, oder Google nur am Desktop als Ordner und am Handy nur OneDrive?
