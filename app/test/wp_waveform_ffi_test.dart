// #28/AK6: the Dart binding returns the core's waveform. Runs against the library from core/build
// (cmake --build core/build) and is skipped with the reason if it is missing or there is no audio
// device; WP_MACOS_CORE_REQUIRED=1 and WP_AUDIO_DEVICE_REQUIRED=1 (nightly job «macos» on the null
// device, #125) make that a failure.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wp_core/wp_core.dart';

import 'required_resource.dart';

const _sr = 48000;

/// 16-Bit-Stereo-WAV mit Sinus 440 Hz der Amplitude [amp].
File _sineWav(Directory dir, double seconds, double amp) {
  final frames = (seconds * _sr).round();
  final b = BytesBuilder();
  void u16(int v) => b.add([v & 0xff, (v >> 8) & 0xff]);
  void u32(int v) => [v & 0xffff, v >> 16].forEach(u16);
  b.add('RIFF'.codeUnits);
  u32(36 + frames * 4);
  b.add('WAVE'.codeUnits);
  b.add('fmt '.codeUnits);
  u32(16);
  u16(1);
  u16(2);
  u32(_sr);
  u32(_sr * 4);
  u16(4);
  u16(16);
  b.add('data'.codeUnits);
  u32(frames * 4);
  for (var i = 0; i < frames; i++) {
    final s = (amp * 32767 * sin(2 * pi * 440 * i / _sr)).round() & 0xffff;
    u16(s);
    u16(s);
  }
  return File('${dir.path}/sinus.wav')..writeAsBytesSync(b.takeBytes());
}

void main() {
  test('Wellenform eines Sinus mit Amplitude 0,5 und Fehlerfälle', () {
    if (!needs(
      macosCoreRequired,
      available: coreAvailable,
      reason: coreMissing,
    )) {
      return;
    }
    wpCoreLibraryPath = coreLibrary.absolute.path;
    final dir = Directory.systemTemp.createTempSync('wp_waveform_');
    final player = WpPlayer();
    try {
      expect(player.waveform(0, 1, 10), isNull, reason: 'no title yet');
      final r = player.loadAsync(_sineWav(dir, 2, 0.5).path);
      if (!needs(
        audioDeviceRequired,
        available: r != WpCode.deviceUnavailable,
        reason: 'no audio device',
      )) {
        return;
      }
      expect(player.loadWait(), WpCode.ok);
      final w = player.waveform(0, player.duration, 100)!;
      expect(w.length, 100);
      expect(w.min, everyElement(closeTo(-0.5, 0.01)));
      expect(w.max, everyElement(closeTo(0.5, 0.01)));
      expect(player.waveform(0.5, 1.5, 20)!.length, 20);
      expect(player.waveform(1, 1, 10), isNull);
      expect(player.waveform(1, 5, 10), isNull);
      expect(player.waveform(0, 1, 0), isNull);
    } finally {
      player.dispose();
      dir.deleteSync(recursive: true);
    }
  });
}
