// UI texts that depend on data (#43): errors, storage line, sort order, ramp status. The texts themselves
// live in lib/l10n/app_*.arb; numbers are formatted for the user's locale.
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:wp_core/wp_types.dart';

import '../l10n/app_localizations.dart';
import '../library/library.dart';
import '../metronome/loop_ramp.dart';
import '../player/audio_core.dart';

export '../l10n/app_localizations.dart';

extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Where the app runs, for hints that say how files come in (#42/AK4).
enum HintPlatform { browser, macOS, mobile }

HintPlatform get currentHintPlatform => kIsWeb
    ? HintPlatform.browser
    : Platform.isMacOS
    ? HintPlatform.macOS
    : HintPlatform.mobile;

/// Hint in the player without a track: drag into the window on macOS, «Files» on iPhone/iPad, the
/// browser's file picker on the web.
String openFileHint(AppLocalizations l, HintPlatform p) => switch (p) {
  HintPlatform.browser => l.openFileHintBrowser,
  HintPlatform.macOS => l.openFileHintDrop,
  HintPlatform.mobile => l.openFileHintFiles,
};

/// Hint in the empty library, as [openFileHint].
String emptyLibraryHint(AppLocalizations l, HintPlatform p) => switch (p) {
  HintPlatform.browser => l.emptyLibraryHintBrowser,
  HintPlatform.macOS => l.emptyLibraryHintDrop,
  HintPlatform.mobile => l.emptyLibraryHint,
};

/// Bytes with one decimal from KB on, in the locale's notation: «512 B», «1,2 GB» (de), «1.2 GB» (en).
String formatBytes(int bytes, String locale) {
  const units = ['KB', 'MB', 'GB', 'TB'];
  if (bytes < 1000) return '$bytes B';
  var v = bytes / 1000;
  var i = 0;
  while (v >= 999.95 && i < units.length - 1) {
    v /= 1000;
    i++;
  }
  return '${NumberFormat('0.0', locale).format(v)} ${units[i]}';
}

/// Storage line in the library footer (#35/AK5), e.g. «1,2 GB belegt · 58,0 GB frei · dauerhaft gespeichert».
String storageLabel(AppLocalizations l, StorageInfo s) {
  String size(int b) => formatBytes(b, l.localeName);
  return [
    l.storageUsed(size(s.used)),
    if (s.quota case final q?)
      l.storageFree(size(q - s.used < 0 ? 0 : q - s.used)),
    if (s.persisted case final p?)
      p ? l.storagePersisted : l.storageNotPersisted,
  ].join(' · ');
}

/// #15/AK3: understandable message for a load error of the core.
String loadErrorMessage(AppLocalizations l, LoadError e) => switch (e.code) {
  WpCode.fileNotFound => l.loadNotFound(e.file),
  WpCode.unsupportedFormat => l.loadUnsupported(e.file),
  WpCode.fileUnreadable => l.loadUnreadable(e.file),
  WpCode.deviceUnavailable => l.loadNoDevice,
  WpCode.outOfMemory => l.loadOutOfMemory(e.file),
  WpCode.cancelled => l.loadCancelled,
  WpCode.busy => l.loadBusy,
  WpCode.invalidArgument => l.loadInvalid,
  _ => l.loadUnknown(e.code),
};

/// #4/AK4: title of a new recording from date and time in the user's locale, e.g.
/// «Aufnahme 19.11.2026, 14:05:09» or «Recording 11/19/2026, 2:05:09 PM».
String recordingTitle(AppLocalizations l, DateTime t) =>
    l.recordingFileName(DateFormat.yMd(l.localeName).add_jms().format(t));

/// #44/AK1: localized message for a recording error of the core; the OSStatus stays a plain number.
String recordingErrorMessage(AppLocalizations l, WpRecordingException e) {
  final text = switch (e.code) {
    WpRecCode.invalidPath => l.recordingErrorInvalidPath,
    WpRecCode.unsupported => l.recordingErrorUnsupported,
    WpRecCode.tap => l.recordingErrorTap,
    WpRecCode.tapFormat => l.recordingErrorTapFormat,
    WpRecCode.noOutput => l.recordingErrorNoOutput,
    WpRecCode.aggregate => l.recordingErrorAggregate,
    WpRecCode.outOfMemory => l.recordingErrorOutOfMemory,
    WpRecCode.file => l.recordingErrorFile,
    WpRecCode.ioProc => l.recordingErrorIoProc,
    WpRecCode.start => l.recordingErrorStart,
    _ => l.recordingErrorUnknown(e.code),
  };
  return e.osStatus == 0 ? text : '$text (OSStatus ${e.osStatus})';
}

String libraryMessageText(AppLocalizations l, LibraryMessage m) => switch (m) {
  LibraryCorrupt(:final backupName) => l.libraryCorrupt(backupName),
  LibrarySaveFailed(:final detail) => l.librarySaveFailed(detail),
  LibraryTooNew() => l.libraryTooNew,
  ImportFailed(:final files) => l.importFailed(files.join('\n')),
  TrackNotOnDevice(:final title) => l.trackNotOnDevice(title),
};

String sortOrderLabel(AppLocalizations l, TrackSortOrder o) => switch (o) {
  TrackSortOrder.alphabetical => l.sortAlphabetical,
  TrackSortOrder.dateAdded => l.sortDateAdded,
  TrackSortOrder.custom => l.sortCustom,
};

/// #31/AK1: entries of the appearance menu.
String appearanceLabel(AppLocalizations l, Appearance a) => switch (a) {
  Appearance.system => l.appearanceSystem,
  Appearance.light => l.appearanceLight,
  Appearance.dark => l.appearanceDark,
};

/// #29/AK8: «75 % · 7 von 10», at the target «100 % · Ziel erreicht · 14 Durchgänge».
String rampStatus(AppLocalizations l, PlaybackSettings s, int passes) =>
    LoopRamp.atTarget(s)
    ? l.rampStatusTarget(s.speedPercent, passes)
    : l.rampStatus(s.speedPercent, passes, s.rampPasses);

/// Metronome subdivision (1 = quarters … 4 = sixteenths).
String subdivisionLabel(AppLocalizations l, int subdivision) =>
    switch (subdivision) {
      1 => l.subdivisionQuarter,
      2 => l.subdivisionEighth,
      3 => l.subdivisionTriplet,
      4 => l.subdivisionSixteenth,
      _ => '',
    };

/// Speed preset with one or two decimals in the locale's notation: «0,75», «1,0» (de), «0.75» (en).
String formatPreset(double v, String locale) =>
    NumberFormat('0.0#', locale).format(v);
