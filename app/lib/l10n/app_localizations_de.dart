// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get library => 'Bibliothek';

  @override
  String get backToLibrary => 'Zurück zur Bibliothek';

  @override
  String get practiceMetronome => 'Üben · Metronom';

  @override
  String get noFolder => 'Ohne Ordner';

  @override
  String get noTracksWithoutFolder => 'Keine Titel ohne Ordner';

  @override
  String get addMp3Ellipsis => 'MP3 hinzufügen …';

  @override
  String get renameFolder => 'Ordner umbenennen';

  @override
  String get renameEllipsis => 'Umbenennen …';

  @override
  String deleteNamedTitle(String name) {
    return '«$name» löschen?';
  }

  @override
  String get deleteFolderText =>
      'Die Titel bleiben in der Bibliothek und erscheinen unter «Ohne Ordner».';

  @override
  String get deleteFolder => 'Ordner löschen';

  @override
  String get emptyFolder => 'Leer – Titel hierher ziehen';

  @override
  String get newFolder => 'Neuer Ordner';

  @override
  String get newFolderEllipsis => 'Neuer Ordner …';

  @override
  String get moveToFolder => 'In Ordner verschieben';

  @override
  String get delete => 'Löschen';

  @override
  String get deleteTrackText =>
      'Der Titel wird aus der App entfernt. Die Originaldatei bleibt unverändert.';

  @override
  String get nameHint => 'Name';

  @override
  String get editTrackEllipsis => 'Titel und Artist bearbeiten …';

  @override
  String get editTrackTitle => 'Titel bearbeiten';

  @override
  String get titleLabel => 'Titel';

  @override
  String get artistLabel => 'Artist';

  @override
  String get save => 'Sichern';

  @override
  String addMp3Shortcut(String shortcut) {
    return 'MP3 hinzufügen ($shortcut)';
  }

  @override
  String newFolderShortcut(String shortcut) {
    return 'Neuer Ordner ($shortcut)';
  }

  @override
  String get sort => 'Sortieren';

  @override
  String get sortAlphabetical => 'Alphabetisch';

  @override
  String get sortDateAdded => 'Hinzugefügt';

  @override
  String get sortCustom => 'Eigene Reihenfolge';

  @override
  String get appearance => 'Darstellung';

  @override
  String get appearanceSystem => 'System';

  @override
  String get appearanceLight => 'Hell';

  @override
  String get appearanceDark => 'Dunkel';

  @override
  String get noTracks => 'Keine Titel';

  @override
  String get emptyLibraryHintDrop =>
      'Füge MP3-, WAV- oder FLAC-Dateien mit + hinzu oder zieh sie hierher.';

  @override
  String get emptyLibraryHint =>
      'Füge MP3-, WAV- oder FLAC-Dateien mit + hinzu.';

  @override
  String get emptyLibraryHintBrowser =>
      'Füge MP3-, WAV- oder FLAC-Dateien mit + aus der Dateiauswahl des Browsers hinzu.';

  @override
  String get addMp3 => 'MP3 hinzufügen';

  @override
  String get folderActions => 'Ordner-Aktionen';

  @override
  String get trackActions => 'Aktionen';

  @override
  String storageUsed(String size) {
    return '$size belegt';
  }

  @override
  String storageFree(String size) {
    return '$size frei';
  }

  @override
  String get storagePersisted => 'dauerhaft gespeichert';

  @override
  String get storageNotPersisted => 'nicht dauerhaft gespeichert';

  @override
  String get recording => 'Aufnahme';

  @override
  String recordingFileName(String stamp) {
    return 'Aufnahme $stamp';
  }

  @override
  String recordingFailed(String detail) {
    return 'Aufnahme nicht möglich: $detail';
  }

  @override
  String get recordingErrorInvalidPath => 'Kein Dateipfad für die Aufnahme.';

  @override
  String get recordingErrorUnsupported =>
      'Aufnahme braucht macOS 14.2 oder neuer.';

  @override
  String get recordingErrorTap =>
      'Der Systemton konnte nicht abgegriffen werden.';

  @override
  String get recordingErrorTapFormat =>
      'Der Systemton hat ein unerwartetes Format.';

  @override
  String get recordingErrorNoOutput => 'Kein Ausgabegerät gefunden.';

  @override
  String get recordingErrorAggregate =>
      'Das Aufnahmegerät konnte nicht eingerichtet werden.';

  @override
  String get recordingErrorOutOfMemory => 'Zu wenig Speicher für die Aufnahme.';

  @override
  String get recordingErrorFile =>
      'Die Aufnahmedatei konnte nicht angelegt werden.';

  @override
  String get recordingErrorIoProc =>
      'Der Audiostrom für die Aufnahme konnte nicht eingerichtet werden.';

  @override
  String get recordingErrorStart =>
      'Die Aufnahme konnte nicht gestartet werden.';

  @override
  String recordingErrorUnknown(int code) {
    return 'Unbekannter Fehler ($code).';
  }

  @override
  String get recordingSilent =>
      'Es kommt nur Stille an. Läuft gerade Musik? Sonst die Berechtigung erteilen: Systemeinstellungen › Datenschutz & Sicherheit › Bildschirm- & Systemaudioaufnahme.';

  @override
  String get recordingTooltip =>
      'Nimmt den Systemton auf (ohne Mikrofon). Die Aufnahme wird nur lokal gespeichert und danach in die Bibliothek übernommen.';

  @override
  String get noTrackSelected => 'Kein Titel ausgewählt';

  @override
  String get openFileHintDrop =>
      'Öffne eine MP3-, WAV- oder FLAC-Datei oder zieh sie ins Fenster.';

  @override
  String get openFileHintFiles =>
      'Öffne eine MP3-, WAV- oder FLAC-Datei aus «Dateien».';

  @override
  String get openFileHintBrowser =>
      'Öffne eine MP3-, WAV- oder FLAC-Datei über die Dateiauswahl des Browsers.';

  @override
  String get openFile => 'Datei öffnen';

  @override
  String loopLength(double seconds) {
    final intl.NumberFormat secondsNumberFormat =
        intl.NumberFormat.decimalPatternDigits(
          locale: localeName,
          decimalDigits: 1,
        );
    final String secondsString = secondsNumberFormat.format(seconds);

    return '$secondsString s';
  }

  @override
  String loopPass(String current, String total) {
    return 'Durchgang $current von $total';
  }

  @override
  String get loopOn => 'Loop an';

  @override
  String get loopOff => 'Loop aus';

  @override
  String get loopLabel => 'LOOP';

  @override
  String get setStartHere => 'S hier';

  @override
  String get setStartHereTooltip =>
      'Aktuelle Wiedergabeposition als Anfang übernehmen';

  @override
  String get setEndHere => 'E hier';

  @override
  String get setEndHereTooltip =>
      'Aktuelle Wiedergabeposition als Ende übernehmen';

  @override
  String get toLoopStart => 'Zum Loop-Anfang';

  @override
  String get jumpToLoopStart => 'Zum Loop-Start';

  @override
  String get wholeTrack => 'Ganzer Titel';

  @override
  String get loopTooShort =>
      'Das Ende muss mindestens 1 Sekunde nach dem Anfang liegen.';

  @override
  String get speed => 'Tempo';

  @override
  String get speedTooltip => 'Die Tonhöhe bleibt unverändert.';

  @override
  String rate(double rate) {
    final intl.NumberFormat rateNumberFormat =
        intl.NumberFormat.decimalPatternDigits(
          locale: localeName,
          decimalDigits: 2,
        );
    final String rateString = rateNumberFormat.format(rate);

    return '$rateString×';
  }

  @override
  String percent(int value) {
    return '$value %';
  }

  @override
  String get rampTitle => 'Steigerung';

  @override
  String get rampSettingsOpen => 'Einstellen';

  @override
  String get rampSettingsClose => 'Einstellungen schliessen';

  @override
  String rampSummary(int step, int passes) {
    String _temp0 = intl.Intl.pluralLogic(
      passes,
      locale: localeName,
      other: '$passes Durchgängen',
      one: '1 Durchgang',
    );
    return '+$step % nach $_temp0';
  }

  @override
  String get rampStartLevel => 'Startstufe';

  @override
  String get rampTargetLevel => 'Zielstufe';

  @override
  String get rampStepSize => 'Schrittweite';

  @override
  String rampStepOption(int step) {
    return '+$step %';
  }

  @override
  String get rampPassesPerLevel => 'Durchgänge pro Stufe';

  @override
  String get rampNotCountingHint =>
      'Gezählt wird nur bei eingeschaltetem Tempo und aktivem Loop.';

  @override
  String get rampHint =>
      'Ein Durchgang zählt beim Sprung vom Loop-Ende zum Anfang. Loop oder Tempo von Hand ändern setzt den Zähler zurück.';

  @override
  String rampStatus(int percent, int passes, int total) {
    return '$percent % · $passes von $total';
  }

  @override
  String rampStatusTarget(int percent, int passes) {
    String _temp0 = intl.Intl.pluralLogic(
      passes,
      locale: localeName,
      other: '$passes Durchgänge',
      one: '1 Durchgang',
    );
    return '$percent % · Ziel erreicht · $_temp0';
  }

  @override
  String get back15 => '15 Sekunden zurück';

  @override
  String get forward15 => '15 Sekunden vor';

  @override
  String get play => 'Wiedergabe';

  @override
  String get pause => 'Pause';

  @override
  String get spaceKey => 'Leertaste';

  @override
  String get volume => 'Lautstärke';

  @override
  String get metronome => 'Metronom';

  @override
  String get subdivisionQuarter => 'Viertel';

  @override
  String get subdivisionEighth => 'Achtel';

  @override
  String get subdivisionTriplet => 'Triolen';

  @override
  String get subdivisionSixteenth => 'Sechzehntel';

  @override
  String get metronomeStartKey => 'Start (M)';

  @override
  String get metronomeStopKey => 'Stopp (M)';

  @override
  String get start => 'Start';

  @override
  String get stop => 'Stopp';

  @override
  String get slower => 'Langsamer (↓)';

  @override
  String get faster => 'Schneller (↑)';

  @override
  String bpm(int bpm) {
    return '$bpm BPM';
  }

  @override
  String get tap => 'Tap';

  @override
  String get tapKey => 'Tap (T)';

  @override
  String get metronomeKeysHint =>
      'Tasten: M = Start/Stopp, ↑ / ↓ = Tempo ±1 (mit Shift ±10), T = Tap-Tempo. Titel und Metronom laufen nie gleichzeitig.';

  @override
  String get meterAndSound => 'Takt und Klang';

  @override
  String get autoTempoRamp => 'Automatische Tempo-Steigerung';

  @override
  String get rampByTimeHint =>
      'Das Tempo ändert sich in 1-BPM-Schritten gleichmässig über die Dauer, jeweils am Taktanfang. Ist das Ziel erreicht, bleibt es einen Schritt lang und beginnt dann wieder beim Start-BPM.';

  @override
  String get rampByBarsHint =>
      'Das Tempo steigt jeweils am Taktanfang. Ist das Ziel erreicht, bleibt es gleich viele Takte und beginnt dann wieder beim Start-BPM.';

  @override
  String get bars => 'Takte';

  @override
  String get time => 'Zeit';

  @override
  String get startBpm => 'Start-BPM';

  @override
  String get targetBpm => 'Ziel-BPM';

  @override
  String get durationMinutes => 'Dauer (Minuten)';

  @override
  String get step => 'Schritt';

  @override
  String bpmStep(int step) {
    return '+$step BPM';
  }

  @override
  String get everyBars => 'Alle … Takte';

  @override
  String get done => 'Fertig';

  @override
  String get settings => 'Einstellungen';

  @override
  String moduleRampTime(int start, int target, int minutes) {
    return 'Auto $start→$target BPM in $minutes min';
  }

  @override
  String moduleRampBars(int step, int bars) {
    String _temp0 = intl.Intl.pluralLogic(
      bars,
      locale: localeName,
      other: '$bars Takte',
      one: '1 Takt',
    );
    return 'Auto +$step BPM / $_temp0';
  }

  @override
  String moduleDetails(String meter, String subdivision) {
    return 'BPM · $meter · $subdivision';
  }

  @override
  String loadNotFound(String file) {
    return 'Die Datei «$file» wurde nicht gefunden. Wurde sie verschoben oder gelöscht?';
  }

  @override
  String loadUnsupported(String file) {
    return 'Die Datei «$file» ist kein unterstütztes Audioformat (MP3, WAV, FLAC) oder beschädigt.';
  }

  @override
  String loadUnreadable(String file) {
    return 'Die Datei «$file» kann nicht gelesen werden. Fehlen die Zugriffsrechte?';
  }

  @override
  String get loadNoDevice =>
      'Kein Audiogerät verfügbar. Bitte Kopfhörer oder Lautsprecher prüfen und erneut versuchen.';

  @override
  String loadOutOfMemory(String file) {
    return 'Die Datei «$file» ist zu gross für den freien Arbeitsspeicher.';
  }

  @override
  String get loadCancelled => 'Das Laden wurde abgebrochen.';

  @override
  String get loadBusy =>
      'Der Audio-Kern ist gerade ausgelastet. Bitte erneut versuchen.';

  @override
  String loadUnsupportedSampleRate(int min, int max) {
    final intl.NumberFormat minNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String minString = minNumberFormat.format(min);
    final intl.NumberFormat maxNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String maxString = maxNumberFormat.format(max);

    return 'Die Audio-Ausgabe läuft mit einer nicht unterstützten Samplerate. Unterstützt werden $minString bis $maxString kHz.';
  }

  @override
  String get loadInvalid => 'Ungültige Datei-Angabe.';

  @override
  String loadUnknown(int code) {
    return 'Unbekannter Fehler beim Laden (Code $code).';
  }

  @override
  String libraryCorrupt(String backup) {
    return 'Die Bibliothek war beschädigt und wurde als «$backup» aufgehoben.';
  }

  @override
  String get libraryTooNew =>
      'Diese Bibliothek wurde mit einer neueren Version von Woodshed Player gespeichert. Bitte aktualisiere die App. Bis dahin wird nichts gespeichert.';

  @override
  String librarySaveFailed(String detail) {
    return 'Bibliothek konnte nicht gespeichert werden: $detail';
  }

  @override
  String importFailed(String files) {
    return 'Folgende Dateien konnten nicht importiert werden:\n$files';
  }

  @override
  String get dontUpload => 'Nicht hochladen';

  @override
  String get syncFolder => 'Synchronisieren';

  @override
  String get fileOnOneDevice => 'Datei nur auf einem Gerät';

  @override
  String get cloudStateTooNew =>
      'Die Bibliothek in der Cloud wurde mit einer neueren Version von Woodshed Player gespeichert. Bitte aktualisiere die App. Bis dahin wird nichts abgeglichen.';

  @override
  String trackNotOnDevice(String title) {
    return 'Die Audiodatei von «$title» liegt nur auf einem anderen Gerät und nicht in der Cloud.';
  }

  @override
  String get aboutApp => 'Über Woodshed Player';

  @override
  String aboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String get aboutLicense =>
      'Open Source unter der MIT-Lizenz. Der Name «Woodshed Player» ist davon nicht umfasst.';

  @override
  String get privacyPolicy => 'Datenschutzerklärung';

  @override
  String get termsOfUse => 'Nutzungsbedingungen';

  @override
  String get sourceCode => 'Quelltext';

  @override
  String aboutTag(String tag) {
    return 'Tag $tag';
  }

  @override
  String get aboutNoTag => 'Ohne Tag';

  @override
  String aboutBuildDate(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Gebaut am $dateString';
  }

  @override
  String get onlyInCloud => 'Nur in der Cloud';

  @override
  String get loadingFromCloud => 'Wird aus der Cloud geladen …';

  @override
  String get keepOffline => 'Offline halten';

  @override
  String storageCacheLimit(String size) {
    return 'Grenze $size';
  }

  @override
  String get cacheLimitTitle => 'Offline-Speicher für Audio';

  @override
  String get cacheLimitHint =>
      'Audiodateien auf diesem Gerät bis zu dieser Grenze. Darüber werden die am längsten nicht gespielten Titel von diesem Gerät entfernt; sie bleiben in der Bibliothek und in der Cloud und werden beim Abspielen wieder geladen. Titel mit «Offline halten» bleiben immer. Die Einstellung gilt nur für dieses Gerät.';

  @override
  String cacheLimitUsed(String size) {
    return '$size Audio auf diesem Gerät';
  }

  @override
  String get installHint =>
      'App installieren: Teilen antippen, dann «Zum Home-Bildschirm».';

  @override
  String get close => 'Schliessen';

  @override
  String heldHint(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Abgleich: $count Titel und Ordner, die nur auf diesem Gerät waren, behalten?',
      one: 'Abgleich: 1 Titel oder Ordner, der nur auf diesem Gerät war, behalten?',
    );
    return '$_temp0';
  }

  @override
  String get heldDecide => 'Entscheiden …';

  @override
  String get heldTitle => 'Titel und Ordner behalten?';

  @override
  String heldText(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Dieses Gerät war lange offline. Diese $count Titel und Ordner wurden nie abgeglichen und sind inzwischen vielleicht auf einem anderen Gerät gelöscht worden:',
      one: 'Dieses Gerät war lange offline. Dieser Titel oder Ordner wurde nie abgeglichen und ist inzwischen vielleicht auf einem anderen Gerät gelöscht worden:',
    );
    return '$_temp0';
  }

  @override
  String heldMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'und $count weitere',
      one: 'und 1 weiterer',
    );
    return '$_temp0';
  }

  @override
  String get heldExplain =>
      'Behalten: Sie bleiben hier und kommen auf Deine anderen Geräte. Entfernen: Sie werden auf diesem Gerät gelöscht, samt Audiodatei; die Titel eines entfernten Ordners oder einer entfernten Playlist bleiben.';

  @override
  String get heldKeep => 'Behalten';

  @override
  String get heldRemove => 'Entfernen';

  @override
  String get heldLater => 'Später';

  @override
  String get playlists => 'Playlists';

  @override
  String get newPlaylist => 'Neue Playlist';

  @override
  String get newPlaylistEllipsis => 'Neue Playlist …';

  @override
  String get renamePlaylist => 'Playlist umbenennen';

  @override
  String get deletePlaylist => 'Playlist löschen';

  @override
  String get deletePlaylistText => 'Die Titel bleiben in der Bibliothek.';

  @override
  String get playPlaylist => 'Abspielen';

  @override
  String get playlistActions => 'Playlist-Aktionen';

  @override
  String get addToPlaylist => 'Zu Playlist hinzufügen';

  @override
  String get removeFromPlaylist => 'Aus Playlist entfernen';

  @override
  String get emptyPlaylist => 'Leer – Titel hierher ziehen';

  @override
  String get playlistOnAllDevices => 'Auf allen Geräten';

  @override
  String get playlistOnThisDevice => 'Nur auf diesem Gerät';
}
