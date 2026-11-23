// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Cancel';

  @override
  String get library => 'Library';

  @override
  String get backToLibrary => 'Back to library';

  @override
  String get noFolder => 'No folder';

  @override
  String get noTracksWithoutFolder => 'No tracks without a folder';

  @override
  String get addMp3Ellipsis => 'Add MP3 …';

  @override
  String get renameFolder => 'Rename folder';

  @override
  String get renameEllipsis => 'Rename …';

  @override
  String deleteNamedTitle(String name) {
    return 'Delete “$name”?';
  }

  @override
  String get deleteFolderText =>
      'The tracks stay in the library and appear under “No folder”.';

  @override
  String get deleteFolder => 'Delete folder';

  @override
  String get emptyFolder => 'Empty – drag tracks here';

  @override
  String get newFolder => 'New folder';

  @override
  String get newFolderEllipsis => 'New folder …';

  @override
  String get moveToFolder => 'Move to folder';

  @override
  String get delete => 'Delete';

  @override
  String get deleteTrackText =>
      'The track is removed from the app. The original file stays unchanged.';

  @override
  String get nameHint => 'Name';

  @override
  String get editTrackEllipsis => 'Edit title and artist …';

  @override
  String get editTrackTitle => 'Edit track';

  @override
  String get titleLabel => 'Title';

  @override
  String get artistLabel => 'Artist';

  @override
  String get save => 'Save';

  @override
  String addMp3Shortcut(String shortcut) {
    return 'Add MP3 ($shortcut)';
  }

  @override
  String newFolderShortcut(String shortcut) {
    return 'New folder ($shortcut)';
  }

  @override
  String get sort => 'Sort';

  @override
  String get sortAlphabetical => 'Alphabetical';

  @override
  String get sortDateAdded => 'Date added';

  @override
  String get sortCustom => 'Custom order';

  @override
  String get appearance => 'Appearance';

  @override
  String get appearanceSystem => 'System';

  @override
  String get appearanceLight => 'Light';

  @override
  String get appearanceDark => 'Dark';

  @override
  String get noTracks => 'No tracks';

  @override
  String get emptyLibraryHintDrop =>
      'Add MP3, WAV or FLAC files with + or drag them here.';

  @override
  String get emptyLibraryHint => 'Add MP3, WAV or FLAC files with +.';

  @override
  String get emptyLibraryHintBrowser =>
      'Add MP3, WAV or FLAC files with + from the browser\'s file picker.';

  @override
  String get addMp3 => 'Add MP3';

  @override
  String get folderActions => 'Folder actions';

  @override
  String get trackActions => 'Actions';

  @override
  String storageUsed(String size) {
    return '$size used';
  }

  @override
  String storageFree(String size) {
    return '$size free';
  }

  @override
  String get storagePersisted => 'stored permanently';

  @override
  String get storageNotPersisted => 'not stored permanently';

  @override
  String get recording => 'Record';

  @override
  String recordingFileName(String stamp) {
    return 'Recording $stamp';
  }

  @override
  String recordingFailed(String detail) {
    return 'Recording not possible: $detail';
  }

  @override
  String get recordingErrorInvalidPath => 'No file path for the recording.';

  @override
  String get recordingErrorUnsupported =>
      'Recording requires macOS 14.2 or later.';

  @override
  String get recordingErrorTap => 'The system audio could not be tapped.';

  @override
  String get recordingErrorTapFormat =>
      'The system audio has an unexpected format.';

  @override
  String get recordingErrorNoOutput => 'No output device found.';

  @override
  String get recordingErrorAggregate =>
      'The recording device could not be set up.';

  @override
  String get recordingErrorOutOfMemory =>
      'Not enough memory for the recording.';

  @override
  String get recordingErrorFile => 'The recording file could not be created.';

  @override
  String get recordingErrorIoProc =>
      'The audio stream for the recording could not be set up.';

  @override
  String get recordingErrorStart => 'The recording could not be started.';

  @override
  String recordingErrorUnknown(int code) {
    return 'Unknown error ($code).';
  }

  @override
  String get recordingSilent =>
      'Only silence is coming in. Is music playing? Otherwise grant the permission: System Settings › Privacy & Security › Screen & System Audio Recording.';

  @override
  String get recordingTooltip =>
      'Records the system audio (without microphone). The recording is only stored locally and then added to the library.';

  @override
  String get recordingErrorNoInput =>
      'No microphone found, or it could not be opened.';

  @override
  String get recordingSource => 'Recording source';

  @override
  String get recordingSourceSystem => 'System audio';

  @override
  String get recordingSourceMicrophone => 'Microphone';

  @override
  String get recordingTooltipMicrophone =>
      'Records through the microphone (the default input device). The recording is only stored locally and then added to the library.';

  @override
  String get recordingMicrophoneDenied =>
      'Woodshed Player may not use the microphone. Grant access in System Settings › Privacy & Security › Microphone, then start the recording again.';

  @override
  String get recordingMicrophoneSilent =>
      'Only silence is coming from the microphone. Check the input device in System Settings › Sound › Input.';

  @override
  String get noTrackSelected => 'No track selected';

  @override
  String get openFileHintDrop =>
      'Open an MP3, WAV or FLAC file or drag it into the window.';

  @override
  String get openFileHintFiles => 'Open an MP3, WAV or FLAC file from “Files”.';

  @override
  String get openFileHintBrowser =>
      'Open an MP3, WAV or FLAC file with the browser\'s file picker.';

  @override
  String get openFile => 'Open file';

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
    return 'pass $current of $total';
  }

  @override
  String get loopOn => 'Loop on';

  @override
  String get loopOff => 'Loop off';

  @override
  String get loopLabel => 'LOOP';

  @override
  String get setStartHere => 'S here';

  @override
  String get setStartHereTooltip =>
      'Use the current playback position as start';

  @override
  String get setEndHere => 'E here';

  @override
  String get setEndHereTooltip => 'Use the current playback position as end';

  @override
  String get toLoopStart => 'To loop start';

  @override
  String get jumpToLoopStart => 'Jump to loop start';

  @override
  String get wholeTrack => 'Whole track';

  @override
  String get loopTooShort =>
      'The end must be at least 1 second after the start.';

  @override
  String get speed => 'Speed';

  @override
  String get speedTooltip => 'The pitch stays the same.';

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
    return '$value%';
  }

  @override
  String get rampTitle => 'Ramp-up';

  @override
  String get rampSettingsOpen => 'Settings';

  @override
  String get rampSettingsClose => 'Close settings';

  @override
  String rampSummary(int step, int passes) {
    String _temp0 = intl.Intl.pluralLogic(
      passes,
      locale: localeName,
      other: '$passes passes',
      one: '1 pass',
    );
    return '+$step% after $_temp0';
  }

  @override
  String get rampStartLevel => 'Start level';

  @override
  String get rampTargetLevel => 'Target level';

  @override
  String get rampStepSize => 'Step size';

  @override
  String rampStepOption(int step) {
    return '+$step%';
  }

  @override
  String get rampPassesPerLevel => 'Passes per level';

  @override
  String get rampNotCountingHint =>
      'Passes only count with speed on and an active loop.';

  @override
  String get rampHint =>
      'A pass counts at the jump from the loop end to the start. Changing loop or speed by hand resets the counter.';

  @override
  String rampStatus(int percent, int passes, int total) {
    return '$percent% · $passes of $total';
  }

  @override
  String rampStatusTarget(int percent, int passes) {
    String _temp0 = intl.Intl.pluralLogic(
      passes,
      locale: localeName,
      other: '$passes passes',
      one: '1 pass',
    );
    return '$percent% · target reached · $_temp0';
  }

  @override
  String get back15 => '15 seconds back';

  @override
  String get forward15 => '15 seconds forward';

  @override
  String get play => 'Play';

  @override
  String get pause => 'Pause';

  @override
  String get spaceKey => 'Space';

  @override
  String get volume => 'Volume';

  @override
  String get metronome => 'Metronome';

  @override
  String get subdivisionQuarter => 'Quarters';

  @override
  String get subdivisionEighth => 'Eighths';

  @override
  String get subdivisionTriplet => 'Triplets';

  @override
  String get subdivisionSixteenth => 'Sixteenths';

  @override
  String get metronomeStartKey => 'Start (M)';

  @override
  String get metronomeStopKey => 'Stop (M)';

  @override
  String get start => 'Start';

  @override
  String get stop => 'Stop';

  @override
  String get slower => 'Slower (↓)';

  @override
  String get faster => 'Faster (↑)';

  @override
  String bpm(int bpm) {
    return '$bpm BPM';
  }

  @override
  String get tapKey => 'Tap (T)';

  @override
  String get metronomeKeysHint =>
      'Keys: M = start/stop, ↑ / ↓ = tempo ±1 (with Shift ±10), T = tap tempo. Track and metronome never play at the same time.';

  @override
  String get meterAndSound => 'Meter and sound';

  @override
  String get autoTempoRamp => 'Automatic tempo increase';

  @override
  String get rampByTimeHint =>
      'The tempo changes evenly in 1 BPM steps over the duration, each time at the start of a bar. Once the target is reached, it stays for one step and then starts again at the start BPM.';

  @override
  String get rampByBarsHint =>
      'The tempo rises at the start of a bar. Once the target is reached, it stays for as many bars and then starts again at the start BPM.';

  @override
  String get bars => 'Bars';

  @override
  String get time => 'Time';

  @override
  String get startBpm => 'Start BPM';

  @override
  String get targetBpm => 'Target BPM';

  @override
  String get durationMinutes => 'Duration (minutes)';

  @override
  String get step => 'Step';

  @override
  String bpmStep(int step) {
    return '+$step BPM';
  }

  @override
  String get everyBars => 'Every … bars';

  @override
  String loadNotFound(String file) {
    return 'The file “$file” was not found. Was it moved or deleted?';
  }

  @override
  String loadUnsupported(String file) {
    return 'The file “$file” is not a supported audio format (MP3, WAV, FLAC) or is damaged.';
  }

  @override
  String loadUnreadable(String file) {
    return 'The file “$file” cannot be read. Are access rights missing?';
  }

  @override
  String get loadNoDevice =>
      'No audio device available. Please check headphones or speakers and try again.';

  @override
  String loadOutOfMemory(String file) {
    return 'The file “$file” is too large for the free memory.';
  }

  @override
  String get loadCancelled => 'Loading was cancelled.';

  @override
  String get loadBusy => 'The audio core is busy right now. Please try again.';

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

    return 'The audio output runs at an unsupported sample rate. Supported are $minString to $maxString kHz.';
  }

  @override
  String get loadInvalid => 'Invalid file reference.';

  @override
  String loadUnknown(int code) {
    return 'Unknown error while loading (code $code).';
  }

  @override
  String libraryCorrupt(String backup) {
    return 'The library was damaged and was kept as “$backup”.';
  }

  @override
  String get libraryTooNew =>
      'This library was saved by a newer version of Woodshed Player. Please update the app. Until then, nothing is saved.';

  @override
  String librarySaveFailed(String detail) {
    return 'The library could not be saved: $detail';
  }

  @override
  String importFailed(String files) {
    return 'The following files could not be imported:\n$files';
  }

  @override
  String get dontUpload => 'Don\'t upload';

  @override
  String get syncFolder => 'Sync';

  @override
  String get fileOnOneDevice => 'File only on one device';

  @override
  String get cloudStateTooNew =>
      'The library in the cloud was saved by a newer version of Woodshed Player. Please update the app. Until then, nothing is synced.';

  @override
  String trackNotOnDevice(String title) {
    return 'The audio file of «$title» is only on another device and not in the cloud.';
  }

  @override
  String get aboutApp => 'About Woodshed Player';

  @override
  String aboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String get aboutLicense =>
      'Open source under the MIT License. The name “Woodshed Player” is not covered by it.';

  @override
  String get privacyPolicy => 'Privacy policy';

  @override
  String get termsOfUse => 'Terms of use';

  @override
  String get sourceCode => 'Source code';

  @override
  String aboutTag(String tag) {
    return 'Tag $tag';
  }

  @override
  String get aboutNoTag => 'No tag';

  @override
  String aboutBuildDate(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Built on $dateString';
  }

  @override
  String get onlyInCloud => 'Only in the cloud';

  @override
  String get loadingFromCloud => 'Loading from the cloud …';

  @override
  String get keepOffline => 'Keep offline';

  @override
  String storageCacheLimit(String size) {
    return 'limit $size';
  }

  @override
  String get cacheLimitTitle => 'Offline storage for audio';

  @override
  String get cacheLimitHint =>
      'Audio files on this device up to this limit. Above it, the tracks played longest ago are removed from this device; they stay in the library and in the cloud and load again when played. Tracks marked «Keep offline» always stay. The setting applies to this device only.';

  @override
  String cacheLimitUsed(String size) {
    return '$size of audio on this device';
  }

  @override
  String get installHint =>
      'Install the app: tap Share, then «Add to Home Screen».';

  @override
  String get close => 'Close';

  @override
  String heldHint(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Sync: keep $count tracks and folders that were only on this device?',
      one: 'Sync: keep 1 track or folder that was only on this device?',
    );
    return '$_temp0';
  }

  @override
  String get heldDecide => 'Decide …';

  @override
  String get heldTitle => 'Keep tracks and folders?';

  @override
  String heldText(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'This device was offline for a long time. These $count tracks and folders were never synced and may have been deleted on another device meanwhile:',
      one: 'This device was offline for a long time. This track or folder was never synced and may have been deleted on another device meanwhile:',
    );
    return '$_temp0';
  }

  @override
  String heldMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'and $count more',
      one: 'and 1 more',
    );
    return '$_temp0';
  }

  @override
  String get heldExplain =>
      'Keep: they stay here and go to your other devices. Remove: they are deleted on this device, with their audio files; the tracks of a removed folder or playlist stay.';

  @override
  String get heldKeep => 'Keep';

  @override
  String get heldRemove => 'Remove';

  @override
  String get heldLater => 'Later';

  @override
  String get playlists => 'Playlists';

  @override
  String get newPlaylist => 'New playlist';

  @override
  String get newPlaylistEllipsis => 'New playlist …';

  @override
  String get renamePlaylist => 'Rename playlist';

  @override
  String get deletePlaylist => 'Delete playlist';

  @override
  String get deletePlaylistText => 'The tracks stay in the library.';

  @override
  String get playPlaylist => 'Play';

  @override
  String get playlistActions => 'Playlist actions';

  @override
  String get sortPlaylistBy => 'Sort by';

  @override
  String sortPlaylistOption(String key, String direction) {
    String _temp0 = intl.Intl.selectLogic(key, {
      'title': 'Title',
      'artist': 'Artist',
      'duration': 'Duration',
      'other': 'Date added',
    });
    String _temp1 = intl.Intl.selectLogic(direction, {
      'descending': 'descending',
      'other': 'ascending',
    });
    return '$_temp0, $_temp1';
  }

  @override
  String get addToPlaylist => 'Add to playlist';

  @override
  String get removeFromPlaylist => 'Remove from playlist';

  @override
  String get emptyPlaylist => 'Empty – drag tracks here';

  @override
  String get playlistOnAllDevices => 'On all devices';

  @override
  String get playlistOnThisDevice => 'Only on this device';

  @override
  String get areas => 'Areas';

  @override
  String get areaPlayer => 'Player';

  @override
  String get areaPractice => 'Practice';

  @override
  String get areaMetronome => 'Metronome';

  @override
  String areaRunning(String area) {
    return '$area, running';
  }

  @override
  String get shuffle => 'Shuffle';

  @override
  String get shuffleOn => 'Shuffle on';

  @override
  String get repeatOff => 'Repeat: off';

  @override
  String get repeatList => 'Repeat: list';

  @override
  String get repeatTrack => 'Repeat: track';

  @override
  String get previousTrack => 'To start or previous track';

  @override
  String get nextTrack => 'Next track';

  @override
  String playingFrom(String list) {
    return 'From «$list»';
  }

  @override
  String get chooseOtherTrack => 'Choose another track ›';

  @override
  String miniPaused(String time) {
    return 'paused · $time';
  }

  @override
  String get miniPlayTrack => 'Play track, stops the metronome';

  @override
  String miniMetronome(int bpm) {
    return 'Metronome · $bpm BPM';
  }

  @override
  String get searchLibrary => 'Search';

  @override
  String get noSearchResults => 'No matches';

  @override
  String get trimTrackEllipsis => 'Trim start and end …';

  @override
  String get trimUnavailable => 'This file type cannot be trimmed.';

  @override
  String trimTitle(String title) {
    return 'Trim «$title»';
  }

  @override
  String get trimStart => 'Start';

  @override
  String get trimEnd => 'End';

  @override
  String trimRemaining(String length) {
    return 'Remaining: $length';
  }

  @override
  String get trimTimeHint => 'mm:ss.d';

  @override
  String get trimRangeInvalid =>
      'At least 1 s must remain, and the end must lie after the start.';

  @override
  String get trimPreview => 'Listen';

  @override
  String get trimStopPreview => 'Stop';

  @override
  String get trimApply => 'Trim …';

  @override
  String get trimConfirmTitle => 'Trim the audio file?';

  @override
  String trimConfirmText(String title, String start, String end) {
    return 'The audio file of «$title» keeps only $start to $end. The parts cut off are deleted; this cannot be undone.';
  }

  @override
  String get trimConfirm => 'Trim';

  @override
  String get trimming => 'Trimming …';

  @override
  String trimFailedFormat(String title) {
    return '«$title» could not be trimmed: this file type cannot be trimmed, or the file is damaged.';
  }

  @override
  String trimFailedMultipleTracks(String title) {
    return '«$title» could not be trimmed: the file has several audio tracks. The track is unchanged.';
  }

  @override
  String trimFailedFragmented(String title) {
    return '«$title» could not be trimmed: the file is a fragmented MP4, which cannot be trimmed. The track is unchanged.';
  }

  @override
  String trimFailedTooShort(String title) {
    return '«$title» was not trimmed: at least 1 s must remain.';
  }

  @override
  String trimFailedNotOnDevice(String title) {
    return '«$title» could not be trimmed: its audio file is not on this device.';
  }

  @override
  String trimFailedNoSpace(String title) {
    return '«$title» could not be trimmed: there is not enough storage space. The track is unchanged.';
  }

  @override
  String trimFailedMemory(String title) {
    return '«$title» could not be trimmed: there is not enough memory. The track is unchanged.';
  }

  @override
  String trimFailedReadOnly(String title) {
    return '«$title» could not be trimmed: the library is from a newer version of the app and is read-only.';
  }

  @override
  String trimFailedOther(String title) {
    return '«$title» could not be trimmed: the file could not be read or written. The track is unchanged.';
  }

  @override
  String get settings => 'Settings';

  @override
  String get syncSection => 'Sync';

  @override
  String get syncOff => 'Off – everything stays on this device';

  @override
  String get syncGoogle => 'Google Drive';

  @override
  String get syncGoogleWebOnly =>
      'On iPhone and iPad, sync with Google Drive runs in the web app.';

  @override
  String get syncSignIn => 'Sign in with Google';

  @override
  String get syncSigningIn => 'Waiting for the sign-in in the browser …';

  @override
  String get syncSignInFailed => 'The sign-in did not work. Try again.';

  @override
  String get syncSignInAgain =>
      'The sign-in at Google has expired. Sign in again to keep syncing.';

  @override
  String get syncBrowserDone =>
      'Signed in. You can close this window and go back to Woodshed Player.';

  @override
  String get syncNotSignedIn => 'Not signed in';

  @override
  String get syncSignOut => 'Sign out';

  @override
  String get syncSignOutText =>
      'The sign-in is removed from this device and the sync stops. The library stays on this device, the files in Google Drive stay there too.';

  @override
  String get syncStatusOff => 'Off';

  @override
  String get syncStatusWaiting => 'Waiting for the first sync';

  @override
  String get syncStatusIdle => 'Up to date';

  @override
  String get syncStatusSyncing => 'Syncing …';

  @override
  String get syncStatusOffline =>
      'No connection – changes wait and are sent later';

  @override
  String get syncStatusFailed => 'Some files could not be synced';

  @override
  String get syncStatusTooNew =>
      'Google Drive holds a newer format. Update the app.';

  @override
  String get syncStatusForeign => 'Google Drive holds another library.';

  @override
  String syncLastSync(String time) {
    return 'Last sync: $time';
  }

  @override
  String get syncNever => 'Not synced yet';

  @override
  String syncErrors(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files failed',
      one: '1 file failed',
    );
    return '$_temp0';
  }

  @override
  String get syncDevices => 'Last sync per device';

  @override
  String get syncThisDevice => 'This device';

  @override
  String syncDevice(String id) {
    return 'Device $id';
  }

  @override
  String get syncUnknown => 'unknown';

  @override
  String get syncNow => 'Sync now';

  @override
  String get syncRestoreEllipsis => 'Restore backup …';

  @override
  String get syncRestoreTitle => 'Restore backup';

  @override
  String get syncRestoreText =>
      'The library goes back to the chosen state, on all devices. Changes made since then are undone.';

  @override
  String get syncRestoreNone => 'No backups yet.';

  @override
  String syncBackupOf(String time) {
    return 'State of $time';
  }

  @override
  String get syncRestoreDone => 'Backup restored.';

  @override
  String get syncFoldersTitle => 'Folders to sync';

  @override
  String get syncFoldersText =>
      'Choose the folders whose audio files go to Google Drive. Titles, folders and settings are always synced.';

  @override
  String syncFree(String size) {
    return 'Free in Google Drive: $size';
  }

  @override
  String get syncFreeUnknown => 'Free space in Google Drive unknown';

  @override
  String get syncNoFolders => 'No folders: every track is synced.';

  @override
  String get syncStart => 'Start sync';

  @override
  String syncLine(String status) {
    return 'Sync: $status';
  }

  @override
  String get selectTracks => 'Select';

  @override
  String selectionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selected',
      one: '1 selected',
    );
    return '$_temp0';
  }

  @override
  String get selectionActions => 'Actions for the selected tracks';

  @override
  String get selectionDone => 'Done';

  @override
  String deleteTracksTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $count tracks?',
      one: 'Delete 1 track?',
    );
    return '$_temp0';
  }

  @override
  String get deleteTracksText =>
      'The tracks are removed from the app. The original files stay unchanged.';
}
