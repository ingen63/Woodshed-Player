// Export of tracks as MP3 files into a folder (#141/AK4–AK14). The order per track: its file (loaded
// from the cloud first if it is not on this device), then an MP3 source is copied with its frames
// unchanged and other formats are encoded by the core (LAME); the ID3 tag of the library goes in
// front. Tempo, loop and trimming in the app are not applied: the original file is exported.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:wp_core/wp_types.dart';

import '../library/export_name.dart';
import '../library/id3_tag.dart';
import '../library/library.dart';

/// Why one track was not exported (#141/AK13); the UI names it with the title.
enum ExportProblem {
  /// Only in the cloud, and loading it failed (AK14).
  notLoaded,

  /// Not a file the export can read.
  format,

  /// The MP3 encoder (LAME) is missing (AK16).
  encoderMissing,

  /// The file in the target folder cannot be written.
  write,

  /// Any other error.
  failed,
}

class ExportFailure {
  const ExportFailure(this.track, this.problem);
  final Track track;
  final ExportProblem problem;
}

class ExportResult {
  const ExportResult({
    required this.exported,
    required this.failures,
    required this.cancelled,
  });

  /// Names of the files written, in order.
  final List<String> exported;
  final List<ExportFailure> failures;

  /// Stopped by the user (AK12); the files written before stay.
  final bool cancelled;
}

/// Encodes [input] to the MP3 frames in [output]; returns a WpCode. See WpMp3.export.
typedef Mp3Encode = Future<int> Function(
  String input,
  String output, {
  Future<void>? cancel,
  void Function(double fraction)? onProgress,
});

/// Progress: track [index] (from 0) of [total], [fraction] of it done.
typedef ExportProgress = void Function(int index, int total, double fraction);

class TrackExporter {
  TrackExporter({
    required this.library,
    required this.fetchAudio,
    required this.encode,
  });

  final Library library;

  /// Loads the file of a track that is only in the cloud; false if that failed.
  final Future<bool> Function(Track track) fetchAudio;
  final Mp3Encode encode;

  /// Exports [tracks] into [folder]. Completing [cancel] stops after the current block (AK12).
  Future<ExportResult> run(
    List<Track> tracks,
    String folder, {
    Future<void>? cancel,
    ExportProgress? progress,
  }) async {
    var cancelled = false;
    unawaited(cancel?.then((_) => cancelled = true));
    final exported = <String>[];
    final failures = <ExportFailure>[];
    for (var i = 0; i < tracks.length; i++) {
      if (cancelled) break;
      progress?.call(i, tracks.length, 0);
      final t = tracks[i];
      // AK7: the files of this export are written before the next name is chosen, so a name used
      // earlier in it is taken like any file in the folder (macOS: whatever the case)
      final name = uniqueExportName(
        exportBaseName(t.title, t.artist, t.year),
        (n) => File('$folder/$n').existsSync(),
      );
      final problem = await _one(
        t,
        '$folder/$name',
        cancel,
        () => cancelled,
        (f) => progress?.call(i, tracks.length, f),
      );
      switch (problem) {
        case null:
          exported.add(name);
        case _Cancelled():
          cancelled = true;
        case final ExportProblem p:
          failures.add(ExportFailure(t, p));
      }
    }
    if (!cancelled) progress?.call(tracks.length, tracks.length, 0);
    return ExportResult(
      exported: exported,
      failures: failures,
      cancelled: cancelled,
    );
  }

  /// null when written, an [ExportProblem], or [_Cancelled].
  Future<Object?> _one(
    Track t,
    String target,
    Future<void>? cancel,
    bool Function() cancelled,
    void Function(double) onProgress,
  ) async {
    if (!library.hasFile(t.id) && !await fetchAudio(t)) {
      return ExportProblem.notLoaded;
    }
    final source = library.filePath(t);
    final tag = id3v2Tag(
      title: t.title,
      artist: t.artist,
      album: t.album,
      year: t.year,
    );
    if (_isMp3(t.fileName)) {
      final Uint8List bytes;
      try {
        bytes = await File(source).readAsBytes();
      } catch (_) {
        return ExportProblem.format;
      }
      final frames = mp3Frames(bytes);
      if (frames.isEmpty) return ExportProblem.format;
      // a cancel that came while the file was read (or before the export began)
      if (cancelled()) return const _Cancelled();
      return _write(target, tag, frames);
    }
    final part = '$target.part';
    final int code;
    try {
      code = await encode(source, part, cancel: cancel, onProgress: onProgress);
    } catch (_) {
      _remove(part);
      return ExportProblem.failed;
    }
    if (code != WpCode.ok) {
      _remove(part);
      return code == WpCode.cancelled ? const _Cancelled() : _problem(code);
    }
    try {
      return await _write(target, tag, await File(part).readAsBytes());
    } finally {
      _remove(part);
    }
  }

  static Future<ExportProblem?> _write(
    String target,
    Uint8List tag,
    Uint8List frames,
  ) async {
    try {
      final out = BytesBuilder(copy: false)
        ..add(tag)
        ..add(frames);
      await File(target).writeAsBytes(out.toBytes(), flush: true);
      return null;
    } catch (_) {
      _remove(target);
      return ExportProblem.write;
    }
  }

  static bool _isMp3(String fileName) =>
      fileName.toLowerCase().endsWith('.mp3');

  static ExportProblem _problem(int code) => switch (code) {
    WpCode.encoderUnavailable => ExportProblem.encoderMissing,
    WpCode.fileUnwritable => ExportProblem.write,
    WpCode.fileNotFound ||
    WpCode.unsupportedFormat ||
    WpCode.unsupportedSampleRate ||
    WpCode.fileUnreadable => ExportProblem.format,
    _ => ExportProblem.failed,
  };

  static void _remove(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}

/// The user stopped the export while this track was encoded; not a problem to report.
class _Cancelled {
  const _Cancelled();
}
