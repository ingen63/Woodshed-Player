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
  String get practiceMetronome => 'Practice · Metronome';

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
  String get noTracks => 'No tracks';

  @override
  String get emptyLibraryHintDrop =>
      'Add MP3, WAV or FLAC files with + or drag them here.';

  @override
  String get emptyLibraryHint => 'Add MP3, WAV or FLAC files with +.';

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
  String get recordingSilent =>
      'Only silence is coming in. Is music playing? Otherwise grant the permission: System Settings › Privacy & Security › Screen & System Audio Recording.';

  @override
  String get recordingTooltip =>
      'Records the system audio (without microphone). The recording is only stored locally and then added to the library.';

  @override
  String get noTrackSelected => 'No track selected';

  @override
  String get openFileHintDrop =>
      'Open an MP3, WAV or FLAC file or drag it into the window.';

  @override
  String get openFileHintFiles => 'Open an MP3, WAV or FLAC file from “Files”.';

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
  String get tap => 'Tap';

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
  String get done => 'Done';

  @override
  String get settings => 'Settings';

  @override
  String moduleRampTime(int start, int target, int minutes) {
    return 'Auto $start→$target BPM in $minutes min';
  }

  @override
  String moduleRampBars(int step, int bars) {
    String _temp0 = intl.Intl.pluralLogic(
      bars,
      locale: localeName,
      other: '$bars bars',
      one: '1 bar',
    );
    return 'Auto +$step BPM / $_temp0';
  }

  @override
  String moduleDetails(String meter, String subdivision) {
    return 'BPM · $meter · $subdivision';
  }

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
  String librarySaveFailed(String detail) {
    return 'The library could not be saved: $detail';
  }

  @override
  String importFailed(String files) {
    return 'The following files could not be imported:\n$files';
  }
}
