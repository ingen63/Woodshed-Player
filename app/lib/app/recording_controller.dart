// State of the recording (#4, #113, #118), shared by the record button and the command line (#140):
// which source, whether a recording runs or is armed, its length and level, and what became of it.
// An armed recording (#140) records the source all the time but keeps only 1 s before the first
// sound up to 2 s after the last; the core detects sound and silence (sound_gate.cpp), this class
// stops the recording once the core reports the end and adds it to the library.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:wp_core/wp_core.dart';

import '../library/track.dart';
import '../time_format.dart';
import '../ui/messages.dart';
import 'app_controller.dart';

/// The recorder of the core; tests replace it with a fake (#4).
abstract class Recorder {
  /// [source] records on this platform (#113).
  bool sourceAvailable(WpRecSource source);

  /// Records [source] into [path]. Throws [WpRecordingException] if recording cannot start.
  void start(String path, WpRecSource source);

  /// #140: records [source] into [path], armed: the file holds only 1 s before the first sound up
  /// to 2 s after the last. Throws [WpRecordingException] if recording cannot start.
  void startArmed(
    String path,
    WpRecSource source, {
    required double thresholdDb,
    required double silenceSeconds,
  });
  void stop();
  bool get isRecording;
  double get seconds;

  /// #140: state of the armed recording; [WpRecGate.off] without arming.
  WpRecGate get gate;

  /// #140: seconds in the file (armed: from 1 s before the first sound).
  double get keptSeconds;

  /// Peak level since the last query, 0–1.
  double get level;

  /// Only silence so far: no permission, or nothing is playing.
  bool get onlySilence;
}

/// [Recorder] of the audio core.
class CoreRecorder implements Recorder {
  const CoreRecorder();
  @override
  bool sourceAvailable(WpRecSource source) =>
      WpRecorder.sourceAvailable(source);
  @override
  void start(String path, WpRecSource source) =>
      WpRecorder.startSource(path, source);
  @override
  void startArmed(
    String path,
    WpRecSource source, {
    required double thresholdDb,
    required double silenceSeconds,
  }) => WpRecorder.startArmed(
    path,
    source,
    thresholdDb: thresholdDb,
    silenceSeconds: silenceSeconds,
  );
  @override
  void stop() => WpRecorder.stop();
  @override
  bool get isRecording => WpRecorder.isRecording;
  @override
  double get seconds => WpRecorder.seconds;
  @override
  WpRecGate get gate => WpRecorder.gate;
  @override
  double get keptSeconds => WpRecorder.keptSeconds;
  @override
  double get level => WpRecorder.level;
  @override
  bool get onlySilence => WpRecorder.onlySilence;
}

/// What the recording is doing.
enum RecordingPhase {
  idle,

  /// #140: recording the source, waiting for the first sound; nothing is kept yet.
  armed,
  recording,
}

/// #140: settings of an armed recording.
class Arming {
  const Arming({
    this.thresholdDb = WpRecArming.defaultThresholdDb,
    this.silenceSeconds = WpRecArming.defaultSilenceSeconds,
  });

  /// A sample louder than this (dBFS) is sound.
  final double thresholdDb;

  /// This much silence ends the recording.
  final double silenceSeconds;
}

/// How a recording ended, or why it did not start.
sealed class RecordingOutcome {
  const RecordingOutcome();
}

/// Stopped and added to the library as [track] ([seconds] long); [track] is null if the library
/// could not take the file.
class RecordingSaved extends RecordingOutcome {
  const RecordingSaved(this.track, this.seconds);
  final Track? track;
  final double seconds;
}

/// #140: stopped while armed; no file, no title.
class RecordingCancelled extends RecordingOutcome {
  const RecordingCancelled();
}

/// The core could not start the recording (#44).
class RecordingFailed extends RecordingOutcome {
  const RecordingFailed(this.error);
  final WpRecordingException error;
}

/// #113/AK4: the microphone permission was refused; nothing was recorded.
class RecordingMicrophoneDenied extends RecordingOutcome {
  const RecordingMicrophoneDenied();
}

/// Another recording runs or is armed (#140/AK17).
class RecordingBusy extends RecordingOutcome {
  const RecordingBusy();
}

/// No folder for recordings.
class RecordingNoFolder extends RecordingOutcome {
  const RecordingNoFolder();
}

class RecordingController extends ChangeNotifier {
  RecordingController({
    required this.app,
    this.recorder = const CoreRecorder(),
    this.now = DateTime.now,
    this.tick = const Duration(milliseconds: 33),
  });

  final AppController app;
  final Recorder recorder;

  /// Clock for the name of the recording.
  final DateTime Function() now;

  /// How often the length, the level and the state of the core are read.
  final Duration tick;

  /// Seconds of only silence before the hint (no permission, or nothing plays).
  static const silentAfter = 3.0;

  Timer? _ticker;
  RecordingPhase _phase = RecordingPhase.idle;
  bool _starting = false;
  bool _armed = false;
  double _seconds = 0, _level = 0;
  bool _silent = false;
  String? _path;
  String? _title;
  String? _artist;
  int? _year;
  WpRecSource? _recordingSource;
  WpRecordingException? _error;
  bool _micDenied = false;
  Completer<RecordingOutcome>? _done;
  Future<void>? _stopping;

  RecordingPhase get phase => _phase;

  /// A recording runs, is armed or is starting.
  bool get busy => _starting || _phase != RecordingPhase.idle;

  /// Seconds in the file so far.
  double get seconds => _seconds;

  /// Peak level since the last tick, 0–1.
  double get level => _level;

  /// Only silence for [silentAfter] seconds: no permission, or nothing is playing.
  bool get silent => _silent;

  /// Error of the core when the last recording could not start (#44).
  WpRecordingException? get error => _error;

  /// #113/AK4: the microphone permission was refused at the last start.
  bool get microphoneDenied => _micDenied;

  /// Source of the running recording.
  WpRecSource? get recordingSource => _recordingSource;

  /// What became of the current recording; completes once it is stopped. Null before the first.
  Future<RecordingOutcome>? get done => _done?.future;

  /// #113/AK1: the sources this platform records, in menu order.
  List<WpRecSource> get sources => [
    for (final s in WpRecSource.values)
      if (recorder.sourceAvailable(s)) s,
  ];

  /// The source last chosen on this device; the system audio until one is chosen (as before #113).
  WpRecSource get source {
    final all = sources;
    final chosen = WpRecSource.named(app.library.recordingSource);
    if (chosen != null && all.contains(chosen)) return chosen;
    return all.isEmpty ? WpRecSource.system : all.first;
  }

  /// #113/AK1: remembers [s] on this device; clears the hints of the last start.
  void choose(WpRecSource s) {
    // The library takes the new source at once and saves it in the background.
    unawaited(app.library.setRecordingSource(s.name));
    _micDenied = false;
    _error = null;
    _silent = false;
    notifyListeners();
  }

  /// Starts recording [source] (default: [source]); with [arming] armed (#140). The title is [title]
  /// or the date and time in the language of [l]; [artist] and [year] (#140) are set if given. Returns null once it
  /// runs ([done] then tells how it ended), otherwise why it did not start.
  Future<RecordingOutcome?> start(
    AppLocalizations l, {
    WpRecSource? source,
    String? title,
    String? artist,
    int? year,
    Arming? arming,
  }) async {
    if (busy) return const RecordingBusy();
    _starting = true;
    try {
      final from = source ?? this.source;
      final at = now();
      final files = app.files;
      // #113/AK4: macOS asks the first time; refused, there is a hint and no file, so no empty title.
      if (from == WpRecSource.microphone && !await files.microphoneAccess()) {
        _micDenied = true;
        notifyListeners();
        return const RecordingMicrophoneDenied();
      }
      final dir = await files.recordingsDir();
      if (dir == null) return const RecordingNoFolder();
      final path =
          '$dir/${l.recordingFileName(fileStamp(at))}.${from.extension}';
      try {
        if (arming == null) {
          recorder.start(path, from);
        } else {
          recorder.startArmed(
            path,
            from,
            thresholdDb: arming.thresholdDb,
            silenceSeconds: arming.silenceSeconds,
          );
        }
      } on WpRecordingException catch (e) {
        debugPrint(e.toString());
        _error = e;
        notifyListeners();
        return RecordingFailed(e);
      }
      _armed = arming != null;
      _phase = _armed ? RecordingPhase.armed : RecordingPhase.recording;
      _recordingSource = from;
      _path = path;
      _title = title ?? recordingTitle(l, at);
      _artist = artist;
      _year = year;
      _seconds = 0;
      _level = 0;
      _silent = false;
      _error = null;
      _micDenied = false;
      _done = Completer<RecordingOutcome>();
      _ticker = Timer.periodic(tick, (_) => _update());
      notifyListeners();
      return null;
    } finally {
      _starting = false;
    }
  }

  void _update() {
    if (_phase == RecordingPhase.idle) return;
    final total = recorder.seconds;
    _level = recorder.level;
    _silent = total > silentAfter && recorder.onlySilence;
    if (_armed) {
      _seconds = recorder.keptSeconds;
      switch (recorder.gate) {
        case WpRecGate.armed:
          _phase = RecordingPhase.armed;
        case WpRecGate.recording:
          _phase = RecordingPhase.recording;
        case WpRecGate.done:
          // #140/AK9: silence long enough, the core has written the end of the file.
          unawaited(stop());
        case WpRecGate.off:
          break;
      }
    } else {
      _seconds = total;
    }
    notifyListeners();
  }

  /// Stops the recording. Still armed (#140/AK14): nothing is kept, the empty file is removed and no
  /// title appears. Otherwise the file becomes a new title of the library and plays (#4).
  Future<void> stop() => _stopping ??= _stop().whenComplete(() {
    _stopping = null;
  });

  Future<void> _stop() async {
    if (_phase == RecordingPhase.idle) return;
    // Armed and nothing kept yet: cancelled. Read before stopping, the core resets on the next start.
    final cancelled = _armed && recorder.gate == WpRecGate.armed;
    final seconds = _armed ? recorder.keptSeconds : recorder.seconds;
    recorder.stop();
    _ticker?.cancel();
    _ticker = null;
    _phase = RecordingPhase.idle;
    _seconds = seconds;
    _silent = false;
    notifyListeners();
    final done = _done!;
    final path = _path;
    if (cancelled) {
      if (path != null) _delete(path);
      done.complete(const RecordingCancelled());
      return;
    }
    Track? track;
    if (path != null && File(path).existsSync()) {
      track = await app.addRecording(
        path,
        title: _title,
        artist: _artist,
        year: _year,
      );
    }
    done.complete(RecordingSaved(track, track?.duration ?? seconds));
  }

  static void _delete(String path) {
    try {
      File(path).deleteSync();
    } on FileSystemException {
      // already gone
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    if (recorder.isRecording) recorder.stop();
    super.dispose();
  }
}
