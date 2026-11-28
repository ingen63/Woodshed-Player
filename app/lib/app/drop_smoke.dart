// #163: smoke test of dropping files in the built Windows and Linux app (WP_SMOKE=drop,
// tools/smoke_app.sh). No file manager on the CI runners, so the runner's own drop code takes a drop
// put together like one from Explorer or the file manager (Windows: CF_HDROP through the window's
// IDropTarget; Linux: a text/uri-list through the GTK drop handling). The flow checks what reaches
// the app: the paths of the audio files unchanged (drive letter, backslash, UNC, umlauts; in the URI
// with space, «#» and «%»), no other files (also none without a type in a folder with a dot), the position on a playlist, its highlight, and the
// tracks in that playlist. A real drag from Explorer or a file manager stays unchecked here.
import 'dart:async';
import 'dart:io';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart' show listEquals;

import 'app_controller.dart';
import 'file_drop.dart';
import 'file_platform.dart';
import 'smoke.dart';

/// The files the smoke test drops: two audio files and two other files in a folder with umlauts,
/// a dot and characters a URI escapes.
class DropSmokeFiles {
  const DropSmokeFiles(this.first, this.second, this.others);

  /// Paths of the audio files as the drop hands them over.
  final String first, second;

  /// Files that are no audio: a text file and one without a type (in a folder with a dot).
  final List<String> others;

  /// Titles of the two audio files in the library.
  static const titles = ['Ärger öü ß', 'Zweite Datei Ä'];
}

/// The same file as UNC path over the administrative share of this computer (`\\localhost\C$\…`)
/// for a Windows path with a drive letter.
String uncPath(String drivePath) =>
    '\\\\localhost\\${drivePath[0]}\$${drivePath.substring(2)}';

/// Creates the files in [dir]. On [windows] the second one is named by its UNC path (#163/AK2).
DropSmokeFiles dropSmokeFiles(Directory dir, {required bool windows}) {
  final sep = windows ? '\\' : '/';
  final folder = Directory('${dir.path}$sepÜbungen Café #1 50% v1.2')
    ..createSync(recursive: true);
  String create(String name, List<int> bytes) =>
      (File('${folder.path}$sep$name')..writeAsBytesSync(bytes)).absolute.path;
  final first = create('${DropSmokeFiles.titles[0]}.wav', sineWav(seconds: 1));
  final second = create(
    '${DropSmokeFiles.titles[1]}.WAV',
    sineWav(seconds: 1, freq: 660),
  );
  final others = [
    create('Notiz.txt', 'no audio'.codeUnits),
    create('Liesmich', 'no audio'.codeUnits),
  ];
  return DropSmokeFiles(first, windows ? uncPath(second) : second, others);
}

/// Polls [value] until it is not null, at most for [guard]; null if it stayed null.
Future<T?> pollFor<T>(
  T? Function() value, {
  required Duration guard,
  Duration every = const Duration(milliseconds: 20),
}) async {
  final end = DateTime.now().add(guard);
  for (;;) {
    final v = value();
    if (v != null || !DateTime.now().isBefore(end)) return v;
    await Future<void>.delayed(every);
  }
}

/// The smoke flow of dropping files on a started app. [seen] collects the drag events the platform
/// reports; [find] gives a point of the window on a drop target (null while it is not shown);
/// [drop] hands paths to the runner's drop code as a drop at a point and answers whether the window
/// took them. Returns null when every step worked, otherwise the step that failed.
Future<String?> smokeDrop(
  AppController c, {
  required DropSmokeFiles files,
  required List<FileDragEvent> seen,
  required Offset? Function(FileDropTarget target) find,
  required Future<bool> Function(List<String> paths, Offset at) drop,
  Duration guard = const Duration(seconds: 30),
}) async {
  final list = c.library.createPlaylist('Drop');
  final target = PlaylistDropTarget(list.id);
  final at = await pollFor(() => find(target), guard: guard);
  if (at == null) return 'playlist not shown';
  final lit = <FileDropTarget?>[];
  void hover() => lit.add(c.fileDropHover.value);
  c.fileDropHover.addListener(hover);
  try {
    // AK1, AK2: the audio files land in the playlist they are dropped on; the other files stay out
    if (!await drop([files.first, files.second, ...files.others], at)) {
      return 'drop refused';
    }
    final dropped = await pollFor(
      () => seen.whereType<FileDragDrop>().firstOrNull,
      guard: guard,
    );
    if (dropped == null) return 'no drop reported';
    if (!listEquals(dropped.paths, [files.first, files.second])) {
      return 'dropped ${dropped.paths}';
    }
    final where = dropped.position;
    if (where == null || (where - at).distance > 1.5) {
      return 'dropped at $where, not at $at';
    }
    if (!lit.contains(target)) return 'playlist not highlighted';
    List<String> titles() => [
      for (final t in c.library.playlistTracks(list.id)) t.title,
    ];
    if (!await waitFor(
      c.library,
      () => listEquals(titles(), DropSmokeFiles.titles),
      guard: guard,
    )) {
      return 'playlist holds ${titles()}';
    }
    // no audio file: nothing is dropped
    seen.clear();
    if (await drop(files.others, at)) return 'other files taken';
    if (seen.whereType<FileDragDrop>().isNotEmpty) return 'other files dropped';
    return null;
  } finally {
    c.fileDropHover.removeListener(hover);
  }
}
