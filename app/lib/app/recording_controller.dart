// State of the recording (#4, #113, #118), shared by the record button and the command line (#140):
// which source, whether a recording runs or is armed, its length and level, and what became of it.
// An armed recording (#140) records the source all the time but keeps only 1 s before the first
// sound up to 2 s after the last; the core detects sound and silence (sound_gate.cpp), this class
// stops the recording once the core reports the end and adds it to the library.
// #147: the armed practice recording (practice_recording.dart) reserves the recording while it is on;
// then the record button and the command line are refused. Its takes are named and placed when the
// sound comes ([RecordingNaming]), and the next take can be armed while the last one is still being
// added to the library.
// #157: in the browser the recorder of the web core (recorder_web.dart) records the microphone; files are
// then names in the page's storage, so existence and deletion go through the [Recorder].
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:wp_core/wp_types.dart';

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
    double? tailSeconds,
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

  /// #157: why the recorder ended the running recording by itself; null while it runs as asked. The
  /// controller then stops and saves what was recorded.
  RecordingInterruption? get interruption;

  /// #157: a recording file at [path] exists (natively a file, in the browser one of the recorder).
  bool exists(String path);

  /// #157: removes the recording file at [path] (a cancelled armed recording); gone already is fine.
  void delete(String path);
}

/// #157: why a recording ended without a stop (the browser).
enum RecordingInterruption {
  /// AK7: the app went to the background or the screen was locked.
  background,

  /// AK8: the storage is full; the file holds what was recorded until then.
  storageFull,

  /// The recording could not go on (the file or the core failed).
  failed,
}

/// #157: [Recorder.exists] and [Recorder.delete] for files of the file system (desktop, tests).
mixin RecordingFiles {
  bool exists(String path) => File(path).existsSync();

  void delete(String path) {
    try {
      File(path).deleteSync();
    } on FileSystemException {
      // already gone
    }
  }
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
    this.tailSeconds,
  });

  /// A sample louder than this (dBFS) is sound.
  final double thresholdDb;

  /// This much silence ends the recording.
  final double silenceSeconds;

  /// #147: kept after the last sound; null: the core's default (2 s, the command line).
  final double? tailSeconds;
}

/// #147: title and folder path (from the top level) of a recording that started at [started] (the
/// first frame of the file).
typedef RecordingNaming = ({String title, List<String> folders}) Function(
  DateTime started,
);

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
    required this.recorder,
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
  RecordingNaming? _naming;
  List<String> _folders = const [];
  bool _select = true;
  DateTime? _startedAt;
  Object? _owner;
  Object? _reservedBy;
  Future<void>? _saving;
  WpRecordingException? _error;
  RecordingInterruption? _interruption;
  bool _micDenied = false;
  Completer<RecordingOutcome>? _done;

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

  /// #157/AK7, AK8: why the last recording ended by itself; cleared by the next start or [choose].
  RecordingInterruption? get interruption => _interruption;

  /// #113/AK4: the microphone permission was refused at the last start.
  bool get microphoneDenied => _micDenied;

  /// Source of the running recording.
  WpRecSource? get recordingSource => _recordingSource;

  /// #147: the owner given to [start] for the current recording (null: the record button or the
  /// command line).
  Object? get owner => _owner;

  /// #147/AK11: the recording is reserved (by the armed practice recording); others are refused.
  bool get reserved => _reservedBy != null;

  /// #147/AK11: reserves the recording for [owner]; starts of others return [RecordingBusy]. False if
  /// another recording runs or another owner holds it.
  bool reserve(Object owner) {
    if (identical(_reservedBy, owner)) return true;
    if (_reservedBy != null || busy) return false;
    _reservedBy = owner;
    notifyListeners();
    return true;
  }

  /// #147: gives the recording free again.
  void release(Object owner) {
    if (!identical(_reservedBy, owner)) return;
    _reservedBy = null;
    notifyListeners();
  }

  /// #147: when the current recording began (its first frame); null before the sound came.
  DateTime? get startedAt => _startedAt;

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
    _interruption = null;
    _error = null;
    _silent = false;
    notifyListeners();
  }

  /// Starts recording [source] (default: [source]); with [arming] armed (#140). The title is [title]
  /// or the date and time in the language of [l]; [artist] and [year] (#140) are set if given. Returns null once it
  /// runs ([done] then tells how it ended), otherwise why it did not start.
  /// #147: [owner] must hold the reservation if there is one; [naming] gives title and folders once the
  /// recording begins; with [select] false the new title is neither loaded nor played.
  Future<RecordingOutcome?> start(
    AppLocalizations l, {
    WpRecSource? source,
    String? title,
    String? artist,
    int? year,
    Arming? arming,
    Object? owner,
    RecordingNaming? naming,
    bool select = true,
  }) async {
    if (busy || !identical(_reservedBy, owner)) return const RecordingBusy();
    _starting = true;
    _interruption = null;
    try {
      final from = source ?? this.source;
      final at = now();
      final files = app.files;
      // #113/AK4: macOS asks the first time; refused, there is a hint and no file, so no empty title.
      if (from == WpRecSource.microphone && !await files.microphoneAccess()) {
        // #147/AK12: «Armed» gives its own hint; the record button stays without one.
        _micDenied = owner == null;
        notifyListeners();
        return const RecordingMicrophoneDenied();
      }
      final dir = await files.recordingsDir();
      if (dir == null) return const RecordingNoFolder();
      final path = freePath(
        '$dir/${l.recordingFileName(fileStamp(at))}',
        from.extension,
        recorder.exists,
      );
      try {
        if (arming == null) {
          recorder.start(path, from);
        } else {
          recorder.startArmed(
            path,
            from,
            thresholdDb: arming.thresholdDb,
            silenceSeconds: arming.silenceSeconds,
            tailSeconds: arming.tailSeconds,
          );
        }
      } on WpRecordingException catch (e) {
        debugPrint(e.toString());
        // #162/AK3: nothing of the failed start stays behind
        if (recorder.exists(path)) recorder.delete(path);
        // #162/AK3: the system refused the microphone (Windows privacy setting): the same hint as
        // a refused permission
        if (e.code == WpRecCode.accessDenied) {
          _micDenied = owner == null;
          notifyListeners();
          return const RecordingMicrophoneDenied();
        }
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
      _owner = owner;
      _naming = naming;
      _folders = const [];
      _select = select;
      _startedAt = null;
      if (!_armed) _began(at, 0);
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
    // #157/AK7, AK8: ended by the recorder: saved like a stop, with the reason for the hint
    final interruption = recorder.interruption;
    if (interruption != null) {
      _interruption = interruption;
      unawaited(stop());
      return;
    }
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
          if (_startedAt == null) _began(now(), _seconds);
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

  /// #147: the recording began at [at] minus [kept] seconds (the first frame of the file); [naming]
  /// now gives its title and folders.
  void _began(DateTime at, double kept) {
    final started = at.subtract(
      Duration(microseconds: (kept * Duration.microsecondsPerSecond).round()),
    );
    _startedAt = started;
    final naming = _naming;
    if (naming == null) return;
    final n = naming(started);
    _title = n.title;
    _folders = n.folders;
  }

  /// Stops the recording. Still armed (#140/AK14): nothing is kept, the empty file is removed and no
  /// title appears. Otherwise the file becomes a new title of the library and plays (#4). #147: the
  /// recording is idle at once, so the next one can start while this one is added to the library;
  /// the future completes once it is added.
  Future<void> stop() {
    if (_phase == RecordingPhase.idle) return _saving ?? Future.value();
    return _saving = _stop();
  }

  Future<void> _stop() async {
    // Armed and nothing kept yet: cancelled. Read before stopping, the core resets on the next start.
    final cancelled = _armed && recorder.gate == WpRecGate.armed;
    final seconds = _armed ? recorder.keptSeconds : recorder.seconds;
    recorder.stop();
    if (!cancelled && _startedAt == null) _began(now(), seconds);
    _ticker?.cancel();
    _ticker = null;
    // Everything of this recording is read before the listeners hear of the end: one of them may
    // start the next recording (#147).
    final done = _done!;
    final path = _path;
    final title = _title, artist = _artist, year = _year;
    final folders = _folders, select = _select;
    _phase = RecordingPhase.idle;
    _seconds = seconds;
    _silent = false;
    notifyListeners();
    if (cancelled) {
      if (path != null) recorder.delete(path);
      done.complete(const RecordingCancelled());
      return;
    }
    Track? track;
    if (path != null && recorder.exists(path)) {
      track = await app.addRecording(
        path,
        title: title,
        artist: artist,
        year: year,
        folders: folders,
        select: select,
      );
    }
    done.complete(RecordingSaved(track, track?.duration ?? seconds));
  }

  /// #147: `[base].[extension]`, or with « 2», « 3» … if that file [exists] already (two takes in the
  /// same second).
  static String freePath(
    String base,
    String extension,
    bool Function(String path) exists,
  ) {
    var path = '$base.$extension';
    for (var n = 2; exists(path); n++) {
      path = '$base $n.$extension';
    }
    return path;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    if (recorder.isRecording) recorder.stop();
    super.dispose();
  }
}
