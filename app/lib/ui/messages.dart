// UI texts that depend on data (#43): errors, storage line, sort order, ramp status. The texts themselves
// live in lib/l10n/app_*.arb; numbers are formatted for the user's locale.
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

String libraryMessageText(AppLocalizations l, LibraryMessage m) => switch (m) {
  LibraryCorrupt(:final backupName) => l.libraryCorrupt(backupName),
  LibrarySaveFailed(:final detail) => l.librarySaveFailed(detail),
  ImportFailed(:final files) => l.importFailed(files.join('\n')),
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
