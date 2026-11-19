// #13/AK5: smoke test of the built app. Started with WP_SMOKE=1 (platform_native.dart), the app opens
// as usual, imports a sine file it generated itself into a temporary library, plays it until the
// position has moved, pauses and ends with exit code 0 (1 with the reason otherwise). No window
// interaction, no network, never the real library. Script: tools/smoke_app.sh.
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'app_controller.dart';

/// 16-bit mono WAV: [seconds] of a [freq] Hz sine at about a quarter of full scale.
Uint8List sineWav({double seconds = 3, double freq = 440, int rate = 44100}) {
  final n = (seconds * rate).round();
  final b = ByteData(44 + n * 2);
  void str(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      b.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  b.setUint32(4, 36 + n * 2, Endian.little);
  str(8, 'WAVEfmt ');
  b.setUint32(16, 16, Endian.little); // size of the fmt chunk
  b.setUint16(20, 1, Endian.little); // PCM
  b.setUint16(22, 1, Endian.little); // mono
  b.setUint32(24, rate, Endian.little);
  b.setUint32(28, rate * 2, Endian.little); // bytes per second
  b.setUint16(32, 2, Endian.little); // bytes per frame
  b.setUint16(34, 16, Endian.little); // bits per sample
  str(36, 'data');
  b.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    final v = (sin(2 * pi * freq * i / rate) * 8000).round();
    b.setInt16(44 + i * 2, v, Endian.little);
  }
  return b.buffer.asUint8List();
}

/// Completes with true as soon as [done] holds after a change of [state], or with the value of [done]
/// once [guard] has passed (protection against a hang, not a waiting time).
Future<bool> waitFor(
  Listenable state,
  bool Function() done, {
  required Duration guard,
}) {
  if (done()) return Future.value(true);
  final result = Completer<bool>();
  void check() {
    if (!result.isCompleted && done()) result.complete(true);
  }

  state.addListener(check);
  final hang = Timer(guard, () {
    if (!result.isCompleted) result.complete(done());
  });
  return result.future.whenComplete(() {
    state.removeListener(check);
    hang.cancel();
  });
}

/// The smoke flow on a started app: import [path], play until the position passes [playSeconds],
/// pause. Returns null when every step worked, otherwise the step that failed.
Future<String?> smokeRun(
  AppController c,
  String path, {
  double playSeconds = 0.5,
  Duration guard = const Duration(seconds: 60),
}) async {
  final imported = await c.importFiles([path]);
  if (imported.imported.length != 1) return 'import failed';
  final p = c.player;
  final loaded = await waitFor(
    p,
    () => p.error != null || (p.hasTrack && !p.isLoading),
    guard: guard,
  );
  if (p.error != null) return 'load failed, code ${p.error!.code}';
  if (!loaded) return 'track not loaded';
  if (p.duration <= playSeconds) return 'duration ${p.duration} s';
  p.setVolume(0); // silent: the check reads the position
  p.seek(0);
  p.play();
  if (!await waitFor(
    p,
    () => p.isPlaying && p.position >= playSeconds,
    guard: guard,
  )) {
    return 'no playback, position ${p.position} s';
  }
  p.pause();
  if (!await waitFor(p, () => !p.isPlaying, guard: guard)) {
    return 'pause failed';
  }
  return null;
}
