# Datenschutzerklärung – Woodshed Player

Stand: 19.11.2026

## 1. Wer ist verantwortlich

{{CONTROLLER_NAME}}\
{{CONTROLLER_ADDRESS}}\
E-Mail: {{CONTACT_EMAIL}}

Woodshed Player ist ein Übe-Player für Musikerinnen und Musiker. Diese Erklärung beschreibt, welche Daten die App verarbeitet und wo sie liegen.

## 2. Grundsatz: alles bleibt auf Deinem Gerät

Woodshed Player arbeitet **vollständig lokal**. Solange Du keinen Abgleich wählst (Abschnitte 5 und 6), gibt es keine Verbindung ins Internet, keine Anmeldung und keine Übertragung von Daten.

- Keine Werbung, keine Analyse- oder Tracking-Dienste, keine Absturzberichte, die an uns gesendet werden.
- Wir erhalten keine Daten von Dir. Wir betreiben keinen Server für die App.
- Es gibt keine Weitergabe an Dritte, ausser Du verbindest ein Cloud-Konto (Abschnitt 5) oder koppelst Geräte direkt (Abschnitt 6).

## 3. Welche Daten lokal gespeichert werden

Die App speichert auf Deinem Gerät:

- **Bibliothek:** Titel, Künstler, Album, Cover, Tempo, Loops, Ordner, Sortierung und Darstellung in der Datei `library.json`.
- **Audiodateien:** Die MP3-, WAV-, FLAC- oder anderen Dateien, die Du importierst, werden in den privaten Speicher der App kopiert.
- **Gerätekennung:** Eine zufällig erzeugte Gerät-ID in `device.json`. Sie ist keine Hardware-Kennung. Sie steht in den Änderungsstempeln und verlässt das Gerät nur mit dem Abgleich.
- **Aufnahmen (nur Mac):** Mitschnitte des Systemtons oder des Mikrofons, die Du selbst startest. Sie bleiben im App-Ordner.

Dateipfade speichert die App nicht. Die App liest nur Dateien, die Du selbst auswählst.

**Löschen:** Wenn Du die App löschst oder ihren Datenordner entfernst, sind alle diese Daten weg.

## 4. Berechtigungen

- **Mikrofon (nur Mac):** Nur für Mikrofon-Aufnahmen, die Du startest, und nur während der Aufnahme. macOS fragt dafür beim ersten Mal nach der Erlaubnis. Ohne sie startet keine Mikrofon-Aufnahme; alles andere funktioniert weiter.
- **Bildschirm- und Systemaudioaufnahme (nur Mac):** Nur für Aufnahmen, die Du startest. macOS fragt dafür beim ersten Mal nach der Erlaubnis.
- **Netzwerk:** Nur für den Abgleich und nur nach Deiner ausdrücklichen Wahl: zum gewählten Cloud-Anbieter nach Anmeldung (Abschnitt 5) oder zu gekoppelten Geräten (Abschnitt 6). Dazu das Laden der Web-App selbst (Abschnitt 7).

## 5. Cloud-Abgleich (optional)

Der Cloud-Abgleich ist **freiwillig**. Er ist nur aktiv, wenn Du ein Konto ausdrücklich verbindest. Anbieter ist Google Drive.

Dann gilt:

- Die App legt beim Anbieter je Gerät eine Datei mit dem Stand der Bibliothek an (Bibliothek, Loops, Tempo und geteilte Einstellungen mit Gerät-ID), dazu die letzten Stände als Sicherung und die Audiodateien. Andere Daten überträgt sie nicht.
- **Google Drive:** Die App fragt nur das Recht `drive.file` an. Damit sieht und bearbeitet sie **nur Dateien, die die App selbst anlegt** (Ordner `WoodshedPlayer` in «Meine Ablage»). Auf Deine übrigen Dateien hat sie keinen Zugriff.
- Titel, die Du mit *Nicht hochladen* markierst, und Titel in Ordnern ohne *Synchronisieren* bleiben als Datei auf dem Gerät. Ihre Metadaten wandern trotzdem mit.
- Die Anmeldung läuft direkt bei Deinem Anbieter, am Mac im Anmeldefenster des Systems über OAuth mit PKCE, im Browser per Weiterleitung. Wir sehen Dein Passwort nicht. Die Zugangstokens speichert die App nur lokal (am Desktop im Schlüsselbund bzw. in der Anmeldeinformationsverwaltung des Systems, im Browser im Speicher der Seite, IndexedDB).
- Für die Verarbeitung dort gilt die [Datenschutzerklärung von Google](https://policies.google.com/privacy).
- **Abmelden** entfernt die Tokens und beendet jeden Netzverkehr zum Anbieter. Lokale Daten bleiben erhalten. Die Dateien beim Anbieter löschst Du in Deinem Konto.

**Zur Nutzung von Google-Daten:** Die Nutzung von Informationen, die Google-APIs an Woodshed Player übermitteln, entspricht der [Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy), einschliesslich der Anforderungen an die eingeschränkte Nutzung (Limited Use). Woodshed Player verwendet diese Daten nur, um Deine Bibliothek zwischen Deinen Geräten abzugleichen. Nicht verwendet werden sie für Werbung, zum Verkauf oder für Profile.

## 6. Direkte Verbindung zwischen Geräten (optional)

Ohne Cloud-Konto kannst Du Geräte direkt miteinander koppeln, sobald diese Funktion umgesetzt ist. Die Kopplung startest Du selbst, z. B. über einen QR-Code.

- Bibliothek und Audiodateien gehen **nur direkt** zwischen Deinen gekoppelten Geräten, Ende-zu-Ende verschlüsselt. Wir und Dritte können sie nicht lesen.
- Damit sich zwei Geräte finden, nutzt die App für den Verbindungsaufbau **öffentliche Relays** und **STUN-Server**. Über sie laufen nur verschlüsselte Verbindungsdaten, **keine Inhalte**. Ihre Betreiber sehen die **IP-Adresse** Deines Geräts und den **Zeitpunkt** der Verbindung.
- Hebst Du die Kopplung auf, endet der Verbindungsaufbau. Ohne Kopplung gibt es keine Verbindung.

## 7. Web-Version und diese Seite

Die Web-Version (Browser) lädt alles von der eigenen Seite, auch die Audioverarbeitung. Schriften kommen nicht von Google. Gewählte Audiodateien und die Bibliothek liegen im privaten Speicher des Browsers (Origin Private File System) und verlassen das Gerät nicht, ausser mit dem Abgleich.

Die Web-Version und diese Seite werden über GitHub Pages ausgeliefert. Beim Laden sieht der Hosting-Anbieter GitHub Deine IP-Adresse. Das ist technisch unvermeidbar.

Die Web-Version liegt unter <https://ingen63.github.io/Woodshed-Player/app/>. Ein Service Worker in Deinem Browser setzt dort nur Sicherheits-Header auf die Dateien der eigenen Seite, damit die Audioverarbeitung im Browser laufen kann; er sendet nichts und speichert nichts über Dich.

## 8. Keine Weitergabe

Wir geben keine Daten weiter. Ohne Abgleich verlassen keine Daten das Gerät. Mit Cloud-Konto gehen die Daten nur zum gewählten Anbieter, mit direkter Verbindung nur zu Deinen gekoppelten Geräten. Wo der Anbieter die Daten speichert, regeln seine Bedingungen (Abschnitt 5).

## 9. Deine Rechte

Du hast nach der Datenschutz-Grundverordnung (DSGVO) bzw. dem anwendbaren Recht insbesondere das Recht auf Auskunft, Berichtigung, Löschung, Einschränkung der Verarbeitung, Datenübertragbarkeit und Widerspruch sowie das Recht, Dich bei einer Aufsichtsbehörde zu beschweren.

Da wir keine personenbezogenen Daten auf Servern speichern, betreffen die meisten Rechte Deine eigenen Geräte und Konten. Fragen beantworten wir unter {{CONTACT_EMAIL}}.

## 10. Kinder

Die App richtet sich nicht gezielt an Kinder unter 16 Jahren. Wir erheben wissentlich keine Daten von Kindern.

## 11. Änderungen

Wir passen diese Erklärung an, wenn sich die App ändert, etwa wenn ein neuer Abgleich hinzukommt. Die jeweils aktuelle Fassung steht unter <https://ingen63.github.io/Woodshed-Player/datenschutz.html>.
