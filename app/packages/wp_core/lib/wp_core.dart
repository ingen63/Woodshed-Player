/// Dart-Anbindung des Audio-Kerns (core/include/wp_core.h).
/// Alle Aufrufe sind kurz und laufen direkt im Haupt-Isolate; nur [WpPlayer.load] dekodiert die
/// ganze Datei und kann bei langen Titeln etwas dauern.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

final DynamicLibrary _lib = () {
  if (Platform.isMacOS || Platform.isIOS) return DynamicLibrary.open('wp_core.framework/wp_core');
  if (Platform.isAndroid || Platform.isLinux) return DynamicLibrary.open('libwp_core.so');
  if (Platform.isWindows) return DynamicLibrary.open('wp_core.dll');
  throw UnsupportedError('Plattform nicht unterstützt: ${Platform.operatingSystem}');
}();

final class _Player extends Opaque {}

final _create = _lib.lookupFunction<Pointer<_Player> Function(), Pointer<_Player> Function()>('wp_create');
final _destroy = _lib.lookupFunction<Void Function(Pointer<_Player>), void Function(Pointer<_Player>)>('wp_destroy');
final _load = _lib.lookupFunction<Int32 Function(Pointer<_Player>, Pointer<Utf8>),
    int Function(Pointer<_Player>, Pointer<Utf8>)>('wp_load');
final _play = _lib.lookupFunction<Void Function(Pointer<_Player>), void Function(Pointer<_Player>)>('wp_play');
final _pause = _lib.lookupFunction<Void Function(Pointer<_Player>), void Function(Pointer<_Player>)>('wp_pause');
final _isPlaying =
    _lib.lookupFunction<Int32 Function(Pointer<_Player>), int Function(Pointer<_Player>)>('wp_is_playing');
final _seek = _lib.lookupFunction<Void Function(Pointer<_Player>, Double), void Function(Pointer<_Player>, double)>(
    'wp_seek');
final _setRate = _lib.lookupFunction<Void Function(Pointer<_Player>, Double),
    void Function(Pointer<_Player>, double)>('wp_set_rate');
final _setLoop = _lib.lookupFunction<Void Function(Pointer<_Player>, Double, Double),
    void Function(Pointer<_Player>, double, double)>('wp_set_loop');
final _setVolume = _lib.lookupFunction<Void Function(Pointer<_Player>, Float),
    void Function(Pointer<_Player>, double)>('wp_set_volume');
final _position =
    _lib.lookupFunction<Double Function(Pointer<_Player>), double Function(Pointer<_Player>)>('wp_position');
final _duration =
    _lib.lookupFunction<Double Function(Pointer<_Player>), double Function(Pointer<_Player>)>('wp_duration');

final _recAvailable = _lib.lookupFunction<Int32 Function(), int Function()>('wp_rec_available');
final _recStart = _lib.lookupFunction<Int32 Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>('wp_rec_start');
final _recStop = _lib.lookupFunction<Void Function(), void Function()>('wp_rec_stop');
final _recIsRecording = _lib.lookupFunction<Int32 Function(), int Function()>('wp_rec_is_recording');
final _recSeconds = _lib.lookupFunction<Double Function(), double Function()>('wp_rec_seconds');
final _recLevel = _lib.lookupFunction<Float Function(), double Function()>('wp_rec_level');
final _recOnlySilence = _lib.lookupFunction<Int32 Function(), int Function()>('wp_rec_only_silence');
final _recError = _lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>('wp_rec_error');

/// Ein Player mit eigenem Audiogerät.
class WpPlayer {
  WpPlayer() : _p = _create();

  final Pointer<_Player> _p;

  /// Lädt eine Datei (MP3, WAV, FLAC). Wirft bei Fehlern.
  void load(String path) {
    final c = path.toNativeUtf8();
    try {
      final r = _load(_p, c);
      if (r != 0) throw WpException('Datei konnte nicht geladen werden (Fehler $r)');
    } finally {
      malloc.free(c);
    }
  }

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

  void dispose() => _destroy(_p);
}

/// Aufnahme des Systemtons (nur macOS 14.2+).
abstract final class WpRecorder {
  static bool get available => _recAvailable() != 0;

  /// Startet die Aufnahme als WAV. Wirft mit Begründung, wenn es nicht geht.
  static void start(String wavPath) {
    final c = wavPath.toNativeUtf8();
    try {
      if (_recStart(c) != 0) throw WpException(_recError().toDartString());
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

class WpException implements Exception {
  WpException(this.message);
  final String message;
  @override
  String toString() => message;
}
