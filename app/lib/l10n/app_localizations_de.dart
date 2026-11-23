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
  String get recordingErrorNoInput =>
      'Kein Mikrofon gefunden, oder es liess sich nicht öffnen.';

  @override
  String get recordingSource => 'Aufnahmequelle';

  @override
  String get recordingSourceSystem => 'Systemton';

  @override
  String get recordingSourceMicrophone => 'Mikrofon';

  @override
  String get recordingTooltipMicrophone =>
      'Nimmt über das Mikrofon auf (das Standard-Eingabegerät). Die Aufnahme wird nur lokal gespeichert und danach in die Bibliothek übernommen.';

  @override
  String get recordingMicrophoneDenied =>
      'Woodshed Player darf das Mikrofon nicht verwenden. Erteile den Zugriff unter Systemeinstellungen › Datenschutz & Sicherheit › Mikrofon und starte die Aufnahme dann neu.';

  @override
  String get recordingMicrophoneSilent =>
      'Vom Mikrofon kommt nur Stille. Prüfe das Eingabegerät unter Systemeinstellungen › Ton › Eingang.';

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

  @override
  String get areas => 'Bereiche';

  @override
  String get areaPlayer => 'Player';

  @override
  String get areaPractice => 'Üben';

  @override
  String get areaMetronome => 'Metronom';

  @override
  String areaRunning(String area) {
    return '$area, läuft';
  }

  @override
  String get shuffle => 'Zufällige Wiedergabe';

  @override
  String get shuffleOn => 'Zufällige Wiedergabe an';

  @override
  String get repeatOff => 'Wiederholen: aus';

  @override
  String get repeatList => 'Wiederholen: Liste';

  @override
  String get repeatTrack => 'Wiederholen: Titel';

  @override
  String get previousTrack => 'Zum Anfang oder vorheriger Titel';

  @override
  String get nextTrack => 'Nächster Titel';

  @override
  String playingFrom(String list) {
    return 'Aus «$list»';
  }

  @override
  String get chooseOtherTrack => 'Anderen Titel wählen ›';

  @override
  String miniPaused(String time) {
    return 'pausiert · $time';
  }

  @override
  String get miniPlayTrack => 'Titel abspielen, stoppt das Metronom';

  @override
  String miniMetronome(int bpm) {
    return 'Metronom · $bpm BPM';
  }

  @override
  String get searchLibrary => 'Suchen';

  @override
  String get noSearchResults => 'Keine Treffer';

  @override
  String get trimTrackEllipsis => 'Anfang und Ende abschneiden …';

  @override
  String get trimUnavailable => 'Dieser Dateityp lässt sich nicht kürzen.';

  @override
  String trimTitle(String title) {
    return '«$title» kürzen';
  }

  @override
  String get trimStart => 'Anfang';

  @override
  String get trimEnd => 'Ende';

  @override
  String trimRemaining(String length) {
    return 'Bleibt: $length';
  }

  @override
  String get trimTimeHint => 'mm:ss.d';

  @override
  String get trimRangeInvalid =>
      'Es muss mindestens 1 s bleiben, und das Ende muss nach dem Anfang liegen.';

  @override
  String get trimPreview => 'Probehören';

  @override
  String get trimStopPreview => 'Stopp';

  @override
  String get trimApply => 'Kürzen …';

  @override
  String get trimConfirmTitle => 'Audiodatei kürzen?';

  @override
  String trimConfirmText(String title, String start, String end) {
    return 'Die Audiodatei von «$title» behält nur $start bis $end. Die abgeschnittenen Teile werden gelöscht; das lässt sich nicht rückgängig machen.';
  }

  @override
  String get trimConfirm => 'Kürzen';

  @override
  String get trimming => 'Wird gekürzt …';

  @override
  String trimFailedFormat(String title) {
    return '«$title» konnte nicht gekürzt werden: Dieser Dateityp lässt sich nicht kürzen, oder die Datei ist beschädigt.';
  }

  @override
  String trimFailedMultipleTracks(String title) {
    return '«$title» konnte nicht gekürzt werden: Die Datei hat mehrere Audiospuren. Der Titel ist unverändert.';
  }

  @override
  String trimFailedFragmented(String title) {
    return '«$title» konnte nicht gekürzt werden: Die Datei ist ein fragmentiertes MP4, das sich nicht kürzen lässt. Der Titel ist unverändert.';
  }

  @override
  String trimFailedTooShort(String title) {
    return '«$title» wurde nicht gekürzt: Es muss mindestens 1 s bleiben.';
  }

  @override
  String trimFailedNotOnDevice(String title) {
    return '«$title» konnte nicht gekürzt werden: Die Audiodatei ist nicht auf diesem Gerät.';
  }

  @override
  String trimFailedNoSpace(String title) {
    return '«$title» konnte nicht gekürzt werden: Es ist nicht genug Speicherplatz frei. Der Titel ist unverändert.';
  }

  @override
  String trimFailedMemory(String title) {
    return '«$title» konnte nicht gekürzt werden: Es ist nicht genug Arbeitsspeicher frei. Der Titel ist unverändert.';
  }

  @override
  String trimFailedReadOnly(String title) {
    return '«$title» konnte nicht gekürzt werden: Die Bibliothek stammt aus einer neueren Version der App und ist schreibgeschützt.';
  }

  @override
  String trimFailedOther(String title) {
    return '«$title» konnte nicht gekürzt werden: Die Datei liess sich nicht lesen oder schreiben. Der Titel ist unverändert.';
  }

  @override
  String get settings => 'Einstellungen';

  @override
  String get syncSection => 'Abgleich';

  @override
  String get syncOff => 'Aus – alles bleibt auf diesem Gerät';

  @override
  String get syncGoogle => 'Google Drive';

  @override
  String get syncGoogleWebOnly =>
      'Auf iPhone und iPad läuft der Abgleich mit Google Drive in der Web-App.';

  @override
  String get syncSignIn => 'Mit Google anmelden';

  @override
  String get syncSigningIn => 'Warte auf die Anmeldung im Browser …';

  @override
  String get syncSignInFailed =>
      'Die Anmeldung hat nicht geklappt. Versuch es noch einmal.';

  @override
  String get syncSignInAgain =>
      'Die Anmeldung bei Google ist abgelaufen. Melde Dich neu an, damit der Abgleich weiterläuft.';

  @override
  String get syncBrowserDone =>
      'Angemeldet. Du kannst dieses Fenster schliessen und zu Woodshed Player zurückkehren.';

  @override
  String get syncNotSignedIn => 'Nicht angemeldet';

  @override
  String get syncSignOut => 'Abmelden';

  @override
  String get syncSignOutText =>
      'Die Anmeldung wird von diesem Gerät entfernt und der Abgleich hört auf. Die Bibliothek bleibt auf diesem Gerät, die Dateien in Google Drive bleiben dort.';

  @override
  String get syncStatusOff => 'Aus';

  @override
  String get syncStatusWaiting => 'Wartet auf den ersten Abgleich';

  @override
  String get syncStatusIdle => 'Aktuell';

  @override
  String get syncStatusSyncing => 'Gleicht ab …';

  @override
  String get syncStatusOffline =>
      'Keine Verbindung – Änderungen warten und gehen später hinaus';

  @override
  String get syncStatusFailed => 'Einige Dateien liessen sich nicht abgleichen';

  @override
  String get syncStatusTooNew =>
      'In Google Drive liegt ein neueres Format. Aktualisiere die App.';

  @override
  String get syncStatusForeign =>
      'In Google Drive liegt eine andere Bibliothek.';

  @override
  String syncLastSync(String time) {
    return 'Letzter Abgleich: $time';
  }

  @override
  String get syncNever => 'Noch nicht abgeglichen';

  @override
  String syncErrors(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Dateien fehlgeschlagen',
      one: '1 Datei fehlgeschlagen',
    );
    return '$_temp0';
  }

  @override
  String get syncDevices => 'Letzter Abgleich je Gerät';

  @override
  String get syncThisDevice => 'Dieses Gerät';

  @override
  String syncDevice(String id) {
    return 'Gerät $id';
  }

  @override
  String get syncUnknown => 'unbekannt';

  @override
  String get syncNow => 'Jetzt abgleichen';

  @override
  String get syncRestoreEllipsis => 'Sicherung wiederherstellen …';

  @override
  String get syncRestoreTitle => 'Sicherung wiederherstellen';

  @override
  String get syncRestoreText =>
      'Die Bibliothek geht auf den gewählten Stand zurück, auf allen Geräten. Was seither geändert wurde, ist dann rückgängig gemacht.';

  @override
  String get syncRestoreNone => 'Noch keine Sicherungen.';

  @override
  String syncBackupOf(String time) {
    return 'Stand vom $time';
  }

  @override
  String get syncRestoreDone => 'Sicherung wiederhergestellt.';

  @override
  String get syncFoldersTitle => 'Ordner abgleichen';

  @override
  String get syncFoldersText =>
      'Wähle die Ordner, deren Audiodateien nach Google Drive gehen. Titel, Ordner und Einstellungen werden immer abgeglichen.';

  @override
  String syncFree(String size) {
    return 'Frei in Google Drive: $size';
  }

  @override
  String get syncFreeUnknown => 'Freier Platz in Google Drive unbekannt';

  @override
  String get syncNoFolders => 'Keine Ordner: Alle Titel werden abgeglichen.';

  @override
  String get syncStart => 'Abgleich starten';

  @override
  String syncLine(String status) {
    return 'Abgleich: $status';
  }
}
