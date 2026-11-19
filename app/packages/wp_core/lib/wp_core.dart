/// Dart-Anbindung des Audio-Kerns (core/include/wp_core.h).
/// Alle Aufrufe sind kurz und laufen direkt im Haupt-Isolate. Laden geht mit [WpPlayer.loadAsync] im
/// Hintergrund; [WpPlayer.load] wartet dagegen, bis die ganze Datei dekodiert ist.
/// Ein Test (app/test/ffi_coverage_test.dart) prüft, dass jede Funktion aus wp_core.h hier angebunden ist.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'wp_types.dart';

export 'wp_types.dart';

String? _libraryPath;

/// Nur für Tests: Pfad der Kern-Bibliothek (z. B. `core/build/libwp_core.dylib`), vor dem ersten Aufruf setzen.
set wpCoreLibraryPath(String path) => _libraryPath = path;

final DynamicLibrary _lib = () {
  if (_libraryPath != null) return DynamicLibrary.open(_libraryPath!);
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.open('wp_core.framework/wp_core');
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('libwp_core.so');
  }
  if (Platform.isWindows) return DynamicLibrary.open('wp_core.dll');
  throw UnsupportedError('Platform not supported: ${Platform.operatingSystem}');
}();

final class _Player extends Opaque {}

final _create = _lib
    .lookupFunction<Pointer<_Player> Function(), Pointer<_Player> Function()>(
      'wp_create',
    );
final _destroy = _lib
    .lookupFunction<
      Void Function(Pointer<_Player>),
      void Function(Pointer<_Player>)
    >('wp_destroy');
final _load = _lib
    .lookupFunction<
      Int32 Function(Pointer<_Player>, Pointer<Utf8>),
      int Function(Pointer<_Player>, Pointer<Utf8>)
    >('wp_load');
final _loadAsync = _lib
    .lookupFunction<
      Int32 Function(Pointer<_Player>, Pointer<Utf8>),
      int Function(Pointer<_Player>, Pointer<Utf8>)
    >('wp_load_async');
final _loadState = _lib
    .lookupFunction<
      Int32 Function(Pointer<_Player>),
      int Function(Pointer<_Player>)
    >('wp_load_state');
final _loadProgress = _lib
    .lookupFunction<
      Double Function(Pointer<_Player>),
      double Function(Pointer<_Player>)
    >('wp_load_progress');
final _loadWait = _lib
    .lookupFunction<
      Int32 Function(Pointer<_Player>),
      int Function(Pointer<_Player>)
    >('wp_load_wait');
final _fileDuration = _lib
    .lookupFunction<
      Double Function(Pointer<Utf8>),
      double Function(Pointer<Utf8>)
    >('wp_file_duration');
final _errorMessage = _lib
    .lookupFunction<Pointer<Utf8> Function(Int32), Pointer<Utf8> Function(int)>(
      'wp_error_message',
    );
final _play = _lib
    .lookupFunction<
      Void Function(Pointer<_Player>),
      void Function(Pointer<_Player>)
    >('wp_play');
final _pause = _lib
    .lookupFunction<
      Void Function(Pointer<_Player>),
      void Function(Pointer<_Player>)
    >('wp_pause');
final _isPlaying = _lib
    .lookupFunction<
      Int32 Function(Pointer<_Player>),
      int Function(Pointer<_Player>)
    >('wp_is_playing');
final _seek = _lib
    .lookupFunction<
      Void Function(Pointer<_Player>, Double),
      void Function(Pointer<_Player>, double)
    >('wp_seek');
final _setRate = _lib
    .lookupFunction<
      Void Function(Pointer<_Player>, Double),
      void Function(Pointer<_Player>, double)
    >('wp_set_rate');
final _setLoop = _lib
    .lookupFunction<
      Void Function(Pointer<_Player>, Double, Double),
      void Function(Pointer<_Player>, double, double)
    >('wp_set_loop');
final _setVolume = _lib
    .lookupFunction<
      Void Function(Pointer<_Player>, Float),
      void Function(Pointer<_Player>, double)
    >('wp_set_volume');
final _position = _lib
    .lookupFunction<
      Double Function(Pointer<_Player>),
      double Function(Pointer<_Player>)
    >('wp_position');
final _duration = _lib
    .lookupFunction<
      Double Function(Pointer<_Player>),
      double Function(Pointer<_Player>)
    >('wp_duration');
final _loopPasses = _lib
    .lookupFunction<
      Int64 Function(Pointer<_Player>),
      int Function(Pointer<_Player>)
    >('wp_loop_passes');
final _waveform = _lib
    .lookupFunction<
      Int32 Function(
        Pointer<_Player>,
        Double,
        Double,
        Int32,
        Pointer<Float>,
        Pointer<Float>,
      ),
      int Function(
        Pointer<_Player>,
        double,
        double,
        int,
        Pointer<Float>,
        Pointer<Float>,
      )
    >('wp_waveform');

final _mStart = _lib
    .lookupFunction<
      Void Function(Pointer<_Player>),
      void Function(Pointer<_Player>)
    >('wp_metro_start');
final _mStop = _lib
    .lookupFunction<
      Void Function(Pointer<_Player>),
      void Function(Pointer<_Player>)
    >('wp_metro_stop');
final _mIsRunning = _lib
    .lookupFunction<
      Int32 Function(Pointer<_Player>),
      int Function(Pointer<_Player>)
    >('wp_metro_is_running');
final _mSetBpm = _lib
    .lookupFunction<
      Void Function(Pointer<_Player>, Int32),
      void Function(Pointer<_Player>, int)
    >('wp_metro_set_bpm');
final _mBpm = _lib
    .lookupFunction<
      Int32 Function(Pointer<_Player>),
      int Function(Pointer<_Player>)
    >('wp_metro_bpm');
final _mSetMeter = _lib
    .lookupFunction<
      Void Function(Pointer<_Player>, Int32),
      void Function(Pointer<_Player>, int)
    >('wp_metro_set_meter');
final _mSetSub = _lib
    .lookupFunction<
      Void Function(Pointer<_Player>, Int32),
      void Function(Pointer<_Player>, int)
    >('wp_metro_set_subdivision');
final _mSetVolume = _lib
    .lookupFunction<
      Void Function(Pointer<_Player>, Float),
      void Function(Pointer<_Player>, double)
    >('wp_metro_set_volume');
final _mSetRamp = _lib
    .lookupFunction<
      Void Function(Pointer<_Player>, Int32, Int32, Int32, Int32, Int32),
      void Function(Pointer<_Player>, int, int, int, int, int)
    >('wp_metro_set_ramp');
final _mSetRampTimed = _lib
    .lookupFunction<
      Void Function(Pointer<_Player>, Int32, Int32, Int32, Int32),
      void Function(Pointer<_Player>, int, int, int, int)
    >('wp_metro_set_ramp_timed');

final _recAvailable = _lib.lookupFunction<Int32 Function(), int Function()>(
  'wp_rec_available',
);
final _recStart = _lib
    .lookupFunction<Int32 Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>(
      'wp_rec_start',
    );
final _recStop = _lib.lookupFunction<Void Function(), void Function()>(
  'wp_rec_stop',
);
final _recIsRecording = _lib.lookupFunction<Int32 Function(), int Function()>(
  'wp_rec_is_recording',
);
final _recSeconds = _lib.lookupFunction<Double Function(), double Function()>(
  'wp_rec_seconds',
);
final _recLevel = _lib.lookupFunction<Float Function(), double Function()>(
  'wp_rec_level',
);
final _recOnlySilence = _lib.lookupFunction<Int32 Function(), int Function()>(
  'wp_rec_only_silence',
);
final _recOsStatus = _lib.lookupFunction<Int32 Function(), int Function()>(
  'wp_rec_os_status',
);
final _recError = _lib
    .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
      'wp_rec_error',
    );

/// Ein Player mit eigenem Audiogerät.
class WpPlayer {
  WpPlayer() : _p = _create() {
    if (_p == nullptr) throw WpException('Could not create audio core');
  }

  final Pointer<_Player> _p;

  /// Lädt eine Datei (MP3, WAV, FLAC). Wirft bei Fehlern.
  void load(String path) {
    final c = path.toNativeUtf8();
    try {
      final r = _load(_p, c);
      if (r != 0) {
        throw WpException(
          'Could not load file: ${_errorMessage(r).toDartString()}',
        );
      }
    } finally {
      malloc.free(c);
    }
  }

  /// Startet das Laden im Hintergrund. [WpCode.ok] oder Fehlercode (< 0); ein laufendes Laden wird abgebrochen.
  int loadAsync(String path) {
    final c = path.toNativeUtf8();
    try {
      return _loadAsync(_p, c);
    } finally {
      malloc.free(c);
    }
  }

  /// `WpCode.load*` oder Fehlercode (< 0) des letzten Ladens.
  int get loadState => _loadState(_p);

  /// Fortschritt 0–1 des laufenden bzw. letzten Ladens.
  double get loadProgress => _loadProgress(_p);

  /// Wartet, bis das laufende Laden fertig ist. [WpCode.ok] oder Fehlercode.
  int loadWait() => _loadWait(_p);

  /// English text of the core for an error code, for logs only (UI: `loadErrorMessage`).
  static String errorMessage(int code) => _errorMessage(code).toDartString();

  void play() => _play(_p);
  void pause() => _pause(_p);
  bool get isPlaying => _isPlaying(_p) != 0;
  void seek(double seconds) => _seek(_p, seconds);

  /// 0,1–2,0, Tonhöhe bleibt gleich.
  set rate(double r) => _setRate(_p, r);

  /// Loop A–B in Sekunden; `b <= a + 1` schaltet ihn aus.
  void setLoop(double a, double b) => _setLoop(_p, a, b);
  void clearLoop() => _setLoop(_p, 0, 0);
  set volume(double v) => _setVolume(_p, v);
  double get position => _position(_p);
  double get duration => _duration(_p);

  /// Loop-Durchgänge seit dem Start (#29); Seek zählt nicht. Massgebend ist die Differenz zweier Abfragen.
  int get loopPasses => _loopPasses(_p);

  /// Wellenform des geladenen Titels (#28): [count] gleich lange Abschnitte über [start]–[end] Sekunden,
  /// je Abschnitt Minimum und Maximum (−1…1). Schnell, auch für die Übersicht des ganzen Titels.
  /// `null`, wenn kein Titel geladen ist, `count < 1`, `start >= end` oder der Bereich ausserhalb liegt.
  WpWaveform? waveform(double start, double end, int count) {
    if (count < 1) return null;
    final mins = malloc<Float>(count);
    final maxs = malloc<Float>(count);
    try {
      if (_waveform(_p, start, end, count, mins, maxs) != WpCode.ok) {
        return null;
      }
      return WpWaveform(
        Float32List.fromList(mins.asTypedList(count)),
        Float32List.fromList(maxs.asTypedList(count)),
      );
    } finally {
      malloc.free(mins);
      malloc.free(maxs);
    }
  }

  void dispose() => _destroy(_p);

  // ---- Metronom (läuft mit und ohne Titel) ----
  void metronomeStart() => _mStart(_p);
  void metronomeStop() => _mStop(_p);
  bool get metronomeRunning => _mIsRunning(_p) != 0;
  set metronomeBpm(int bpm) => _mSetBpm(_p, bpm);

  /// Aktuelles Tempo; ändert sich bei automatischer Steigerung.
  int get metronomeBpm => _mBpm(_p);

  /// Schläge pro Takt: 2, 3, 4 oder 6 (6/8).
  set metronomeMeter(int beats) => _mSetMeter(_p, beats);

  /// Klicks pro Schlag 1–4.
  set metronomeSubdivision(int clicks) => _mSetSub(_p, clicks);
  set metronomeVolume(double v) => _mSetVolume(_p, v);
  void metronomeRamp({
    required bool enabled,
    required int start,
    required int target,
    required int step,
    required int everyBars,
  }) => _mSetRamp(_p, enabled ? 1 : 0, start, target, step, everyBars);

  /// Steigerung nach Zeit (#23): 1-BPM-Stufen gleichmässig über [seconds], Wechsel am Taktanfang.
  void metronomeTimedRamp({
    required bool enabled,
    required int start,
    required int target,
    required int seconds,
  }) => _mSetRampTimed(_p, enabled ? 1 : 0, start, target, seconds);
}

/// Dauer einer Datei in Sekunden, ohne sie zu laden. Negativ = Fehlercode ([WpCode]).
double wpFileDuration(String path) {
  final c = path.toNativeUtf8();
  try {
    return _fileDuration(c);
  } finally {
    malloc.free(c);
  }
}

/// Aufnahme des Systemtons (nur macOS 14.2+).
abstract final class WpRecorder {
  static bool get available => _recAvailable() != 0;

  /// Starts recording as WAV. Throws [WpRecordingException] with the error code if it fails.
  static void start(String wavPath) {
    final c = wavPath.toNativeUtf8();
    try {
      final code = _recStart(c);
      if (code != 0) {
        throw WpRecordingException(
          code,
          _recOsStatus(),
          _recError().toDartString(),
        );
      }
    } finally {
      malloc.free(c);
    }
  }

  static void stop() => _recStop();
  static bool get isRecording => _recIsRecording() != 0;
  static double get seconds => _recSeconds();

  /// Spitzenpegel seit der letzten Abfrage (0–1).
  static double get level => _recLevel();

  /// Bisher kam nur Stille an (keine Berechtigung oder es läuft nichts).
  static bool get onlySilence => _recOnlySilence() != 0;
}
