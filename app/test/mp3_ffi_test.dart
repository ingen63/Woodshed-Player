// #141/AK10, AK12, AK16: the Dart binding of the MP3 export, against the core from core/build and LAME
// from local/lame (tools/build-lame.sh) or WP_LAME_PATH. Skipped with the reason if one is missing;
// WP_MACOS_CORE_REQUIRED=1 and WP_LAME_REQUIRED=1 make that a failure (#125). The encoding itself is
// tested in core/tests/mp3_export_tests.cpp.
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/library/metadata.dart';
import 'package:wp_core/wp_core.dart';

import 'required_resource.dart';

String get lamePath =>
    Platform.environment['WP_LAME_PATH'] ??
    File('../local/lame/libmp3lame.dylib').absolute.path;

/// 16-bit stereo WAV, [seconds] of a 440 Hz sine at [rate].
Uint8List wav(double seconds, {int rate = 48000}) {
  final frames = (seconds * rate).round();
  final b = BytesBuilder();
  void u16(int v) => b.add([v & 0xff, (v >> 8) & 0xff]);
  void u32(int v) => [v & 0xffff, v >> 16].forEach(u16);
  b.add('RIFF'.codeUnits);
  u32(36 + frames * 4);
  b.add('WAVEfmt '.codeUnits);
  u32(16);
  u16(1);
  u16(2);
  u32(rate);
  u32(rate * 4);
  u16(4);
  u16(16);
  b.add('data'.codeUnits);
  u32(frames * 4);
  for (var i = 0; i < frames; i++) {
    final v = (12000 * sin(2 * pi * 440 * i / rate)).round() & 0xffff;
    u16(v);
    u16(v);
  }
  return b.takeBytes();
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('wp_mp3_ffi'));
  tearDown(() => tmp.deleteSync(recursive: true));

  bool ready() {
    if (!needs(
      macosCoreRequired,
      available: coreAvailable,
      reason: coreMissing,
    )) {
      return false;
    }
    wpCoreLibraryPath = coreLibrary.absolute.path;
    return needs(
      lameRequired,
      available: WpMp3.available(lamePath),
      reason: 'no LAME at $lamePath (tools/build-lame.sh)',
    );
  }

  test(
    '#141/AK16: without LAME the export says so and writes nothing',
    () async {
      if (!needs(
        macosCoreRequired,
        available: coreAvailable,
        reason: coreMissing,
      )) {
        return;
      }
      wpCoreLibraryPath = coreLibrary.absolute.path;
      expect(WpMp3.available('${tmp.path}/missing.dylib'), isFalse);
      final input = File('${tmp.path}/in.wav')..writeAsBytesSync(wav(0.2));
      final code = await WpMp3.export(
        '${tmp.path}/missing.dylib',
        input.path,
        '${tmp.path}/o.mp3',
      );
      expect(code, WpCode.encoderUnavailable);
      expect(File('${tmp.path}/o.mp3').existsSync(), isFalse);
    },
  );

  test('#141/AK10: a WAV becomes MP3 frames in a background isolate, with progress', () async {
    if (!ready()) return;
    final input = File('${tmp.path}/in.wav')..writeAsBytesSync(wav(1.5));
    final out = '${tmp.path}/out.mp3';
    final seen = <double>[];
    final code = await WpMp3.export(
      lamePath,
      input.path,
      out,
      onProgress: seen.add,
    );
    expect(code, WpCode.ok);
    expect(seen.last, 1.0);
    final bytes = File(out).readAsBytesSync();
    expect(bytes[0], 0xff);
    expect(bytes[1] & 0xe0, 0xe0);
    // 192 kbit/s for 1.5 s, within 10 %
    expect(bytes.length, closeTo(192000 / 8 * 1.5, 192000 / 8 * 1.5 * 0.1));
    expect(readMetadata(bytes).isEmpty, isTrue); // no tag: the app writes it
  });

  test(
    '#141/AK12: completing cancel stops the export and removes the file',
    () async {
      if (!ready()) return;
      final input = File('${tmp.path}/long.wav')..writeAsBytesSync(wav(60));
      final out = '${tmp.path}/long.mp3';
      final cancel = Completer<void>();
      final running = WpMp3.export(
        lamePath,
        input.path,
        out,
        cancel: cancel.future,
        onProgress: (f) {
          if (f > 0 && !cancel.isCompleted) cancel.complete();
        },
      );
      expect(await running, WpCode.cancelled);
      expect(File(out).existsSync(), isFalse);
    },
  );

  test('#141: a cancel completed after the end changes nothing', () async {
    if (!ready()) return;
    final input = File('${tmp.path}/in.wav')..writeAsBytesSync(wav(0.3));
    final cancel = Completer<void>();
    final code = await WpMp3.export(
      lamePath,
      input.path,
      '${tmp.path}/a.mp3',
      cancel: cancel.future,
      kbps: 320,
    );
    cancel.complete();
    await Future<void>.delayed(Duration.zero);
    expect(code, WpCode.ok);
    expect(File('${tmp.path}/a.mp3').existsSync(), isTrue);
  });
}
