// #116/AK4: the Dart binding cuts files with the core. Runs against the library from core/build
// (cmake --build core/build) and is skipped if it is missing; the formats themselves are tested in
// core/tests/trim_tests.cpp.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wp_core/wp_core.dart';

const _sr = 44100;

/// 16-bit mono WAV of [frames] frames; frame i holds i % 30000.
Uint8List _wav(int frames) {
  final b = BytesBuilder();
  void u16(int v) => b.add([v & 0xff, (v >> 8) & 0xff]);
  void u32(int v) => [v & 0xffff, v >> 16].forEach(u16);
  b.add('RIFF'.codeUnits);
  u32(36 + frames * 2);
  b.add('WAVE'.codeUnits);
  b.add('fmt '.codeUnits);
  u32(16);
  u16(1);
  u16(1);
  u32(_sr);
  u32(_sr * 2);
  u16(2);
  u16(16);
  b.add('data'.codeUnits);
  u32(frames * 2);
  for (var i = 0; i < frames; i++) {
    u16(i % 30000);
  }
  return b.takeBytes();
}

void main() {
  final lib = File('../core/build/libwp_core.dylib');
  final skip = !Platform.isMacOS || !lib.existsSync()
      ? 'core library missing (core/build)'
      : null;

  test(
    '#116/AK4 #116/AK7 wpTrim cuts a WAV exactly and refuses less than 1 s',
    () {
      wpCoreLibraryPath = lib.absolute.path;
      final wav = _wav(3 * _sr);
      // [0.5, 2.0] s: frames 22050 to 88200, 66150 frames of 2 bytes after the 44-byte header
      final r = wpTrim(wav, 0.5, 2.0);
      expect(r.code, WpCode.ok);
      expect(r.bytes!.length, 44 + 66150 * 2);
      expect(r.start, 0.5);
      expect(r.end, 2.0);
      expect(String.fromCharCodes(r.bytes!.sublist(0, 4)), 'RIFF');
      // first sample = old frame 22050 (value 22050)
      expect(r.bytes![44] | (r.bytes![45] << 8), 22050);
      final short = wpTrim(wav, 1.0, 1.9);
      expect(short.code, WpCode.invalidArgument);
      expect(short.bytes, isNull);
      final junk = wpTrim(Uint8List.fromList(List.filled(100, 7)), 0, 1);
      expect(junk.code, WpCode.unsupportedFormat);
      expect(wpTrim(Uint8List(0), 0, 1).code, WpCode.unsupportedFormat);
    },
    skip: skip,
  );
}
