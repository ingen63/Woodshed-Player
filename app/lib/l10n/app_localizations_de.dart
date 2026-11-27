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
  String get newSubfolder => 'Neuer Unterordner';

  @override
  String get newSubfolderEllipsis => 'Neuer Unterordner …';

  @override
  String deleteFolderTreeText(int folders, int tracks) {
    String _temp0 = intl.Intl.pluralLogic(
      folders,
      locale: localeName,
      other: '$folders Ordner werden gelöscht: dieser und seine Unterordner.',
      one: '1 Ordner wird gelöscht.',
    );
    String _temp1 = intl.Intl.pluralLogic(
      tracks,
      locale: localeName,
      other:
          '$tracks Titel kommen unter «Ohne Ordner», ihre Audiodateien bleiben.',
      one: '1 Titel kommt unter «Ohne Ordner», seine Audiodatei bleibt.',
      zero: 'Darin sind keine Titel.',
    );
    return '$_temp0 $_temp1';
  }

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
  String get libraryMore => 'Weitere Aktionen';

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
  String get recordingErrorInvalidArgument =>
      'Schwelle oder Pause der scharfen Aufnahme liegen ausserhalb des erlaubten Bereichs.';

  @override
  String get recordingArmed => 'Scharf';

  @override
  String get recordingArmedTooltip =>
      'Scharf über die Kommandozeile: Die Aufnahme beginnt mit dem ersten Ton und endet nach einer Pause. Ein Klick bricht ab; sobald sie aufnimmt, beendet ein Klick sie.';

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
  String get recordingMicrophoneDeniedBrowser =>
      'Der Browser lässt diese Website das Mikrofon nicht verwenden. Erlaube das Mikrofon für diese Website in den Website-Einstellungen des Browsers und starte die Aufnahme dann neu.';

  @override
  String get recordingMicrophoneSilentBrowser =>
      'Vom Mikrofon kommt nur Stille. Prüfe, welches Mikrofon der Browser für diese Website verwendet und ob es stummgeschaltet ist.';

  @override
  String get recordingStoppedInBackground =>
      'Die Aufnahme ist beendet, weil die App in den Hintergrund ging oder der Bildschirm gesperrt wurde. Was bis dahin aufgenommen war, liegt in der Bibliothek.';

  @override
  String get recordingStorageFull =>
      'Die Aufnahme ist beendet, weil der Speicher dieses Browsers voll ist. Was bis dahin aufgenommen war, liegt in der Bibliothek. Lösche Titel oder Aufnahmen, um Platz zu schaffen.';

  @override
  String get armedMicrophoneDeniedBrowser =>
      'Der Browser lässt diese Website das Mikrofon nicht verwenden, darum ist «Scharf» wieder aus. Erlaube das Mikrofon für diese Website in den Website-Einstellungen des Browsers und schalte es dann wieder ein.';

  @override
  String get armedStoppedInBackground =>
      '«Scharf» ist aus, weil die App in den Hintergrund ging oder der Bildschirm gesperrt wurde. Eine laufende Aufnahme wurde gespeichert.';

  @override
  String get armedStorageFull =>
      '«Scharf» ist aus, weil der Speicher dieses Browsers voll ist. Eine laufende Aufnahme wurde bis dahin gespeichert.';

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
  String get openFileHintDialog => 'Öffne eine MP3-, WAV- oder FLAC-Datei.';

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
  String get menuServices => 'Dienste';

  @override
  String get menuHide => 'Woodshed Player ausblenden';

  @override
  String get menuHideOthers => 'Andere ausblenden';

  @override
  String get menuShowAll => 'Alle einblenden';

  @override
  String get menuQuit => 'Woodshed Player beenden';

  @override
  String get menuEdit => 'Bearbeiten';

  @override
  String get menuUndo => 'Widerrufen';

  @override
  String get menuRedo => 'Wiederholen';

  @override
  String get menuCut => 'Ausschneiden';

  @override
  String get menuCopy => 'Kopieren';

  @override
  String get menuPaste => 'Einsetzen';

  @override
  String get menuDelete => 'Löschen';

  @override
  String get menuSelectAll => 'Alles auswählen';

  @override
  String get menuSpeech => 'Sprachausgabe';

  @override
  String get menuStartSpeaking => 'Sprachausgabe starten';

  @override
  String get menuStopSpeaking => 'Sprachausgabe stoppen';

  @override
  String get menuView => 'Darstellung';

  @override
  String get menuFullScreen => 'Vollbildmodus aktivieren';

  @override
  String get menuWindow => 'Fenster';

  @override
  String get menuMinimize => 'Im Dock ablegen';

  @override
  String get menuZoom => 'Zoomen';

  @override
  String get menuBringAllToFront => 'Alle nach vorne bringen';

  @override
  String get menuHelp => 'Hilfe';

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
  String get sortPlaylistBy => 'Sortieren nach';

  @override
  String sortPlaylistOption(String key, String direction) {
    String _temp0 = intl.Intl.selectLogic(key, {
      'title': 'Titel',
      'artist': 'Artist',
      'duration': 'Dauer',
      'other': 'Hinzugefügt',
    });
    String _temp1 = intl.Intl.selectLogic(direction, {
      'descending': 'absteigend',
      'other': 'aufsteigend',
    });
    return '$_temp0, $_temp1';
  }

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

  @override
  String get selectTracks => 'Auswählen';

  @override
  String selectionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ausgewählt',
      one: '1 ausgewählt',
    );
    return '$_temp0';
  }

  @override
  String get selectionActions => 'Aktionen für die ausgewählten Titel';

  @override
  String get selectionDone => 'Fertig';

  @override
  String deleteTracksTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Titel löschen?',
      one: '1 Titel löschen?',
    );
    return '$_temp0';
  }

  @override
  String get deleteTracksText =>
      'Die Titel werden aus der App entfernt. Die Originaldateien bleiben unverändert.';

  @override
  String get exportEllipsis => 'Als MP3 exportieren …';

  @override
  String get exportHere => 'Hierhin exportieren';

  @override
  String exportTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Titel werden exportiert',
      one: '1 Titel wird exportiert',
    );
    return '$_temp0';
  }

  @override
  String exportProgress(int index, int total, String title) {
    return '$index von $total: $title';
  }

  @override
  String exportDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Titel exportiert.',
      one: '1 Titel exportiert.',
      zero: 'Kein Titel exportiert.',
    );
    return '$_temp0';
  }

  @override
  String exportCancelled(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Export abgebrochen. $count Titel exportiert.',
      one: 'Export abgebrochen. 1 Titel exportiert.',
      zero: 'Export abgebrochen. Kein Titel exportiert.',
    );
    return '$_temp0';
  }

  @override
  String get exportResultTitle => 'Export';

  @override
  String exportFailedNotLoaded(String title) {
    return '«$title» liess sich nicht aus der Cloud laden.';
  }

  @override
  String exportFailedFormat(String title) {
    return '«$title»: Diese Datei lässt sich nicht lesen.';
  }

  @override
  String exportFailedEncoder(String title) {
    return '«$title»: MP3 ist nicht verfügbar, der Encoder fehlt.';
  }

  @override
  String exportFailedWrite(String title) {
    return '«$title»: Die Datei liess sich nicht schreiben.';
  }

  @override
  String exportFailed(String title) {
    return '«$title» liess sich nicht exportieren.';
  }

  @override
  String get armedSwitch => 'Scharf';

  @override
  String get armedSwitchTooltip =>
      'Nimmt beim Üben von selbst über das Mikrofon auf: Sobald Du spielst, beginnt eine Aufnahme; sie endet nach einer Pause oder mit der Leertaste. Danach geht «Scharf» aus, ausser es ist eingestellt, für die nächste Aufnahme an zu bleiben. Die Aufnahmen kommen in die Bibliothek nach Recordings › Datum.';

  @override
  String get armedWaiting => 'Scharf, wartet auf einen Ton';

  @override
  String get armedSettings => 'Schwelle, Pause und Ende';

  @override
  String get armedThreshold => 'Beginnt über';

  @override
  String get armedSilence => 'Endet nach einer Pause von';

  @override
  String get armedOffAfterTake => 'Nach einer Aufnahme ausschalten';

  @override
  String get armedLevel => 'Pegel des Mikrofons';

  @override
  String get armedLevelOff => 'Der Pegel erscheint, solange «Scharf» an ist.';

  @override
  String get armedBusy =>
      'Es läuft schon eine Aufnahme. Beende sie und schalte «Scharf» dann ein.';

  @override
  String get armedMicrophoneDenied =>
      'Woodshed Player darf das Mikrofon nicht verwenden, darum ist «Scharf» wieder aus. Erteile den Zugriff unter Systemeinstellungen › Datenschutz & Sicherheit › Mikrofon und schalte es dann wieder ein.';

  @override
  String get armedFailed =>
      '«Scharf» konnte das Mikrofon nicht starten und ist wieder aus.';

  @override
  String get recordingLockedByArmed =>
      '«Scharf» ist an: Das Mikrofon nimmt beim Üben von selbst auf. Schalte «Scharf» aus, um mit diesem Knopf aufzunehmen.';

  @override
  String armedThresholdValue(int db) {
    final intl.NumberFormat dbNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String dbString = dbNumberFormat.format(db);

    return '$dbString dBFS';
  }

  @override
  String armedSilenceValue(int seconds) {
    final intl.NumberFormat secondsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String secondsString = secondsNumberFormat.format(seconds);

    return '$secondsString s';
  }

  @override
  String armedRecordingLabel(String duration) {
    return 'Scharf, nimmt auf $duration';
  }

  @override
  String get helpTitle => 'Woodshed Player-Hilfe';

  @override
  String get helpShortcutsTitle => 'Tastenkürzel';

  @override
  String get helpShortcutsShow => 'Tastenkürzel anzeigen';

  @override
  String get helpShortcutsGeneral => 'Allgemein';

  @override
  String get helpShortcutsPractice => 'Üben und Metronom';

  @override
  String get helpKeyEscape => 'Esc';

  @override
  String get helpKeyDelete => 'Entf';

  @override
  String get helpKeyBackspace => 'Rücktaste';

  @override
  String get helpKeyClick => 'Klick';

  @override
  String get helpShortcutSwitchArea => 'Zu Player, Üben, Metronom wechseln';

  @override
  String get helpShortcutOpen => 'Titel hinzufügen';

  @override
  String get helpShortcutSearch => 'In der Bibliothek suchen';

  @override
  String get helpShortcutPlayPause => 'Abspielen / Pause';

  @override
  String get helpShortcutShuffle => 'Zufall an / aus';

  @override
  String get helpShortcutRepeat => 'Wiederholen: aus, Liste, Titel';

  @override
  String get helpShortcutMute => 'Stumm an / aus';

  @override
  String get helpShortcutPreviousNext => 'Vorheriger / nächster Titel';

  @override
  String get helpShortcutSeek => '15 s zurück / vor';

  @override
  String get helpShortcutVolume => 'Lauter / leiser';

  @override
  String get helpShortcutPracticePlayPause =>
      'Titel abspielen / Pause (Üben), Metronom starten / stoppen (Metronom)';

  @override
  String get helpShortcutMetronome => 'Metronom an / aus';

  @override
  String get helpShortcutTap => 'Tap-Tempo';

  @override
  String get helpShortcutSpeed => 'Tempo langsamer / schneller';

  @override
  String get helpShortcutBpm => 'Metronom +1 / −1 BPM';

  @override
  String get helpShortcutBpm10 => 'Metronom +10 / −10 BPM';

  @override
  String get helpShortcutLoopStart => 'Loop-Anfang an der Wiedergabeposition';

  @override
  String get helpShortcutLoopEnd => 'Loop-Ende an der Wiedergabeposition';

  @override
  String get helpShortcutDeleteTrack =>
      'Geladenen Titel löschen (mit Rückfrage)';

  @override
  String get helpShortcutEndSelection => 'Auswahl aufheben, Suche leeren';

  @override
  String get helpShortcutDeleteSelection =>
      'Ausgewählte Titel löschen (mit Rückfrage)';

  @override
  String get helpShortcutRangeClick => 'Titel bis hier auswählen';

  @override
  String get helpShortcutToggleClick => 'Einen Titel aus- oder abwählen';

  @override
  String get helpAreasTitle => 'Bereiche';

  @override
  String get helpAreasBody =>
      'Woodshed Player hat drei Bereiche: Player für Deine Bibliothek und die einfache Wiedergabe, Üben für Wellenform, Loop, Tempo und Steigerung, und Metronom mit allen Einstellungen.\n\nGewechselt wird mit «Player | Üben | Metronom» oben im Fenster, am Phone mit der Tab-Leiste unten, oder mit der Tastatur. Ein Wechsel hält weder Titel noch Metronom an; Position, Loop und Tempo bleiben. Ein Punkt am Reiter zeigt, was läuft. Läuft in einem anderen Bereich etwas, zeigt eine Mini-Leiste es an und startet oder hält es mit einem Tipp an.\n\nAm Desktop steht die Bibliothek neben dem Player. Am Tablet öffnet der Knopf «Bibliothek» sie in jedem Bereich. Nach einem Neustart öffnet die App den zuletzt gewählten Bereich.';

  @override
  String get helpPlayerTitle => 'Player';

  @override
  String get helpPlayerBody =>
      'Der Player zeigt Cover, Titel, einen Fortschrittsbalken und die Lautstärke. Darunter liegt die Steuerung: Zufall, Zurück, Play/Pause, Weiter und Wiederholen.\n\nZufall spielt jeden Titel der Liste einmal je Durchgang. Zurück springt an den Anfang des Titels, in seinen ersten 3 Sekunden zum vorherigen Titel. Weiter springt zum nächsten Titel. Wiederholen wechselt zwischen aus, der Liste und dem Titel (mit kleiner 1); ein Punkt zeigt, dass es an ist.\n\nEin Titel spielt in der Liste, dem Ordner oder der Playlist, aus der Du ihn gewählt hast.';

  @override
  String get helpLibraryTitle => 'Bibliothek';

  @override
  String get helpLibraryBody =>
      'Titel kommen mit + oben in der Bibliothek dazu, oder Du ziehst Audiodateien ins Fenster (Mac und Browser); auf einen Ordner oder eine Playlist gezogen, landen sie dort. Jede Datei wird nur einmal gespeichert, erkannt an ihrem Inhalt.\n\nOrdner: «Neuer Ordner» im Menü mit den drei Punkten im Kopf der Bibliothek legt einen auf oberster Ebene an, «Neuer Unterordner …» im Menü eines Ordners einen darin, beliebig tief. Ein Klick klappt einen Ordner auf und zu. Titel oder ganze Ordner auf einen Ordner ziehen verschiebt sie (am iPhone und iPad erst lange drücken). «Ordner löschen» löscht auch seine Unterordner; die Titel bleiben in der Bibliothek unter «Ohne Ordner».\n\nSortiert wird mit dem Knopf «Sortieren», gesucht mit dem Suchfeld.\n\nDas Menü eines Titels (Rechtsklick oder die drei Punkte) bearbeitet Titel und Artist (nur in der Bibliothek, die Audiodatei bleibt unverändert), verschiebt ihn in einen Ordner, fügt ihn zu einer Playlist hinzu und löscht ihn nach einer Rückfrage.\n\nMehrere Titel wählst Du mit ⌘-Klick oder ⇧-Klick aus (Ctrl-Klick ausserhalb von Apple); am iPhone und iPad einen Titel lange drücken oder «Auswählen» wählen. Die ausgewählten Titel lassen sich gemeinsam ziehen, zu einer Playlist hinzufügen, verschieben oder löschen.\n\nPlaylists sind Listen von Titeln in eigener Reihenfolge. + neben «Playlists» legt eine an; Titel kommen durch Ziehen auf die Playlist oder mit «Zu Playlist hinzufügen» dazu. «Abspielen» spielt ihre Titel nacheinander.';

  @override
  String get helpPracticeTitle => 'Üben';

  @override
  String get helpPracticeBody =>
      'Die Wellenform zeigt oben den ganzen Titel (ein Tipp springt dorthin) und darunter den Ausschnitt um den Loop oder die Wiedergabeposition.\n\nLoop: «S hier» und «E hier» setzen Anfang und Ende an die Wiedergabeposition, die Tasten S und E tun dasselbe während der Wiedergabe. Die Marker S und E in der Wellenform lassen sich ziehen, die Zeiten als mm:ss.d eintippen. In der Loop-Leiste stehen auch «Zum Loop-Anfang», «Ganzer Titel» und Loop an/aus. Jeder Titel merkt sich seinen Loop und sein Tempo.\n\nTempo: von 0,1× bis 2× mit dem Regler oder der Schnellwahl. Die Tonhöhe bleibt gleich.\n\nAnfang und Ende abschneiden: «Anfang und Ende abschneiden …» im Menü eines Titels. Die beiden Griffe ziehen oder die Zeiten eintippen, mit «Probehören» prüfen, dann «Kürzen …». Die Audiodatei wird wirklich kürzer; das lässt sich nicht rückgängig machen.';

  @override
  String get helpMetronomeTitle => 'Metronom';

  @override
  String get helpMetronomeBody =>
      'Das Metronom läuft von 20 bis 300 BPM: −/+ (gedrückt halten wiederholt), der Regler, oder das Tempo mit «Tap» antippen. Wähle die Taktart (4/4, 3/4, 2/4, 6/8) und die Unterteilung (Viertel, Achtel, Triolen, Sechzehntel); eine Änderung wirkt sofort. Titel und Metronom spielen nie gleichzeitig.\n\nAutomatische Tempo-Steigerung: nach Takten (Start- und Ziel-BPM, Schritt, alle wie viele Takte) oder nach Zeit (Start- und Ziel-BPM über 1 bis 60 Minuten). Am Ziel beginnt sie wieder beim Start-BPM.\n\nSteigerung nach Durchgängen, im Bereich Üben: Die Geschwindigkeit des Titels steigt stufenweise mit den Durchgängen durch den Loop, zum Beispiel von 60 % auf 100 %, +5 % alle 10 Durchgänge. Ein Durchgang zählt beim Sprung vom Loop-Ende zum Anfang. Das Regler-Symbol öffnet die Einstellungen.';

  @override
  String get helpSyncTitle => 'Abgleich';

  @override
  String get helpSyncBody =>
      'Der Abgleich ist aus, bis Du ihn wählst. Dann hält er Bibliothek, Einstellungen und Audiodateien auf Deinen Geräten gleich: über Google Drive mit Deinem Google-Konto, wobei die App nur die Dateien sieht, die sie selbst anlegt, oder direkt zwischen Deinen gekoppelten Geräten ohne Konto. Die direkte Verbindung kommt mit einer späteren Version.\n\nDie Zeile «Abgleich: …» im Fuss der Bibliothek öffnet die Einstellungen: Aus oder Google Drive, anmelden oder abmelden, jetzt abgleichen, eine Sicherung wiederherstellen.\n\nOhne Konto und ohne gekoppelte Geräte baut die App keine Verbindung auf: Alles bleibt auf diesem Gerät.';

  @override
  String get helpAppearanceTitle => 'Darstellung und Sprache';

  @override
  String get helpAppearanceBody =>
      'Wähle System, Hell oder Dunkel unter «Darstellung» im Menü mit den drei Punkten im Kopf der Bibliothek. System folgt der Einstellung Deines Geräts, auch während die App läuft.\n\nDie App folgt der Sprache Deines Systems: Deutsch oder Englisch, bei jeder anderen Sprache Englisch. Zahlen und Grössen stehen in der Schreibweise der Sprache, am Mac wechselt die Menüleiste mit.';

  @override
  String get helpRecordingTitle => 'Aufnahme';

  @override
  String get helpRecordingBody =>
      '«Aufnahme» oben rechts startet und stoppt eine Aufnahme. Das Menü daneben wählt die Quelle für dieses Gerät: Systemton (ab macOS 14.2; Player und Metronom sind ausgenommen) oder Mikrofon. Die Aufnahme wird verlustfrei als FLAC gespeichert und erscheint als neuer Titel in der Bibliothek, benannt nach Datum und Uhrzeit. Beim ersten Mal fragt macOS nach der Berechtigung.\n\nScharf: In Üben und Metronom nimmt der Schalter «Scharf» von selbst über das Mikrofon auf. Sobald der Pegel über die Schwelle steigt, beginnt eine Aufnahme, und zwar 1 Sekunde früher; nach einer Pause der eingestellten Länge endet sie. Die Leertaste spielt oder pausiert wie gewohnt und beendet zugleich eine laufende Aufnahme. Danach geht «Scharf» aus; soll es für die nächste Aufnahme scharf bleiben, schalte in seinen Einstellungen «Nach einer Aufnahme ausschalten» aus. Jede Aufnahme landet in der Bibliothek im Ordner Recordings › Datum. Der Pfeil neben dem Schalter stellt Schwelle, Pause und das Ausschalten nach einer Aufnahme ein. Solange «Scharf» an ist, ist «Aufnahme» gesperrt.';

  @override
  String get helpRecordingBodyBrowser =>
      '«Aufnahme» oben rechts startet und stoppt eine Aufnahme über das Mikrofon. Die Aufnahme wird verlustfrei als FLAC im Speicher dieses Browsers gesichert und erscheint als neuer Titel in der Bibliothek, benannt nach Datum und Uhrzeit. Beim ersten Mal fragt der Browser, ob diese Website das Mikrofon verwenden darf; wurde es verweigert, erlaube es in den Website-Einstellungen des Browsers. Geht die App in den Hintergrund oder wird der Bildschirm gesperrt, endet die Aufnahme und wird gespeichert; während der Aufnahme bleibt der Bildschirm an.\n\nScharf: In Üben und Metronom nimmt der Schalter «Scharf» von selbst über das Mikrofon auf. Sobald der Pegel über die Schwelle steigt, beginnt eine Aufnahme, und zwar 1 Sekunde früher; nach einer Pause der eingestellten Länge endet sie. Die Leertaste spielt oder pausiert wie gewohnt und beendet zugleich eine laufende Aufnahme. Danach geht «Scharf» aus; soll es für die nächste Aufnahme scharf bleiben, schalte in seinen Einstellungen «Nach einer Aufnahme ausschalten» aus. Jede Aufnahme landet in der Bibliothek im Ordner Recordings › Datum. Der Pfeil neben dem Schalter stellt Schwelle, Pause und das Ausschalten nach einer Aufnahme ein. Solange «Scharf» an ist, ist «Aufnahme» gesperrt; im Hintergrund geht «Scharf» aus.';

  @override
  String get helpExportTitle => 'Export als MP3';

  @override
  String get helpExportBody =>
      '«Als MP3 exportieren …» im Menü eines Titels oder mehrerer ausgewählter Titel schreibt sie als MP3-Dateien in einen Ordner Deiner Wahl, benannt «Titel - Artist - Jahr.mp3», mit Titel, Artist, Album und Jahr als Tags. Nichts wird überschrieben.\n\nMP3-Dateien werden ohne neues Kodieren übernommen; WAV, FLAC, M4A und Aufnahmen werden mit 192 kbit/s kodiert. Exportiert wird die Originaldatei; Tempo und Loop ändern sie nicht.';

  @override
  String get helpCommandLineTitle => 'Kommandozeile';

  @override
  String get helpCommandLineBody =>
      'Das Programm der App ist zugleich ihre Kommandozeile. Kopiere das Skript tools/woodshed aus dem Quelltext in einen Ordner Deines Suchpfads, zum Beispiel ~/bin/woodshed.\n\nwoodshed play --title \"<Titel>\" spielt einen Titel der Bibliothek. woodshed record wartet auf den ersten Ton, nimmt auf und hört nach einer Pause von selbst auf. woodshed --help nennt alle Befehle und Optionen.\n\nDer Befehl spricht nur mit der App auf demselben Mac, nie über das Netz.';

  @override
  String get helpWebTitle => 'Web-App';

  @override
  String get helpWebBody =>
      'Installieren: Am iPhone und iPad Teilen antippen, dann «Zum Home-Bildschirm»; unter Android über das Menü des Browsers. Danach startet die App wie jede andere.\n\nOhne Verbindung: Nach dem ersten Besuch startet die App auch offline. Ein neuer Stand ersetzt den alten beim nächsten Start mit Verbindung.\n\nAudio-Cache: Mit Abgleich haben die Audiodateien auf diesem Gerät eine Obergrenze, 2 GB, wenn Du sie nicht änderst; ein Tipp auf die Speicherzeile im Fuss der Bibliothek stellt sie ein. Darüber verlieren die am längsten nicht gespielten Titel ihre Datei auf diesem Gerät, sofern sie in der Cloud liegt. Sie bleiben in der Bibliothek mit «Nur in der Cloud» und werden beim Abspielen wieder geladen. «Offline halten» im Menü eines Titels behält seine Datei.';

  @override
  String get helpShortcutsBody =>
      'Die meisten Funktionen haben ein Tastenkürzel. Die Übersicht nennt sie alle, nach Bereich gruppiert; die Taste ? öffnet sie jederzeit, ausser beim Tippen in einem Textfeld. Kürzel mit ⌘ gehen ausserhalb von Apple mit Ctrl.';
}
