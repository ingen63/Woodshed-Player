// #28/AK6: Die Dart-Anbindung liefert die Wellenform des Kerns. Läuft gegen die Bibliothek aus core/build
// (cmake --build core/build) und wird übersprungen, wenn sie fehlt oder kein Audiogerät da ist.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wp_core/wp_core.dart';

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
  final lib = File('../core/build/libwp_core.dylib');
  final skip = !Platform.isMacOS || !lib.existsSync()
      ? 'Kern-Bibliothek fehlt (core/build)'
      : null;

  test('Wellenform eines Sinus mit Amplitude 0,5 und Fehlerfälle', () {
    wpCoreLibraryPath = lib.absolute.path;
    final dir = Directory.systemTemp.createTempSync('wp_waveform_');
    final player = WpPlayer();
    try {
      expect(player.waveform(0, 1, 10), isNull, reason: 'noch kein Titel');
      final r = player.loadAsync(_sineWav(dir, 2, 0.5).path);
      if (r == WpCode.deviceUnavailable) {
        markTestSkipped('kein Audiogerät');
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
  }, skip: skip);
}
