// #13/AK5: the flow of the app smoke test (lib/app/smoke.dart) with the fake core; the built app runs
// it with the real core in tools/smoke_app.sh. Also the generated sine file and the state waiting.
// #60: «repo» = checks of the repository's files, scripts and workflows (POSIX paths and shells);
// they run on Linux and macOS, the Windows job leaves them out (--exclude-tags repo).
@Tags(['repo'])
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/app/smoke.dart';
import 'package:wp_core/wp_core.dart';

import 'fakes.dart';

/// Lets the smoke flow run until it waits for the next change.
Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('wp_smoke_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File wav() =>
      File('${tmp.path}/Sine.wav')..writeAsBytesSync(sineWav(seconds: 2));

  test('#13/AK5 sineWav: PCM header and samples of the rule', () {
    final b = ByteData.sublistView(sineWav(seconds: 0.5, rate: 8000));
    // 0.5 s at 8000 Hz = 4000 frames of 2 bytes, plus 44 bytes of header.
    expect(b.lengthInBytes, 44 + 8000);
    expect(String.fromCharCodes(b.buffer.asUint8List(0, 4)), 'RIFF');
    expect(b.getUint32(24, Endian.little), 8000);
    expect(b.getUint32(40, Endian.little), 8000);
    // sample 0 is sin(0) = 0; sample 5 at 440 Hz: 8000 · sin(2π · 0.275) = 8000 · sin(99°)
    // = 8000 · 0.98769 = 7901.5 → 7902
    expect(b.getInt16(44, Endian.little), 0);
    expect(b.getInt16(44 + 10, Endian.little), 7902);
  });

  test('#13/AK5 waitFor: answers on a change, the guard ends a hang', () async {
    final state = ValueNotifier(0);
    final f = waitFor(state, () => state.value == 2, guard: kForever);
    state.value = 1;
    await settle();
    state.value = 2;
    expect(await f, isTrue);
    expect(await waitFor(state, () => true, guard: Duration.zero), isTrue);
    final hang = await waitFor(
      state,
      () => false,
      guard: const Duration(milliseconds: 1),
    );
    expect(hang, isFalse);
  });

  test('#13/AK5 smokeRun: import, play past 0.5 s, pause', () async {
    final a = TestApp(Directory('${tmp.path}/lib'), duration: 2);
    await a.library.load();
    a.core.applyPlayImmediately = true;
    final run = smokeRun(a.controller, wav().path, guard: kForever);
    while (a.core.loadState != WpCode.loadRunning) {
      await settle();
    }
    a.finishLoads(2);
    while (!a.core.calls.contains('play')) {
      await settle();
    }
    expect(a.core.volumeValue, 0);
    expect(a.core.calls, contains('seek 0.0'));
    a.core.pos = 0.4;
    a.tick();
    await settle();
    expect(a.core.calls, isNot(contains('pause'))); // 0.4 s is not enough
    a.core.pos = 0.6;
    a.tick();
    expect(await run, isNull);
    expect(a.core.calls.last, 'pause');
    expect(a.library.tracks.single.title, 'Sine');
  });

  test('#13/AK5 smokeRun names the failed step', () async {
    final a = TestApp(Directory('${tmp.path}/lib'), duration: 2);
    await a.library.load();
    // nothing to import
    expect(
      await smokeRun(a.controller, '${tmp.path}/missing.wav'),
      'import failed',
    );

    // the core cannot load the file
    final b = TestApp(Directory('${tmp.path}/lib2'), duration: 2);
    await b.library.load();
    final run = smokeRun(b.controller, wav().path, guard: kForever);
    while (b.core.loadState != WpCode.loadRunning) {
      await settle();
    }
    b.core.failLoad(WpCode.unsupportedFormat);
    b.tick();
    expect(await run, 'load failed, code ${WpCode.unsupportedFormat}');

    // playback does not start: the guard ends the wait
    final c = TestApp(Directory('${tmp.path}/lib3'), duration: 2);
    await c.library.load();
    final stuck = smokeRun(
      c.controller,
      wav().path,
      guard: const Duration(milliseconds: 20),
    );
    while (c.core.loadState != WpCode.loadRunning) {
      await settle();
    }
    c.finishLoads(2);
    expect(await stuck, 'no playback, position 0.0 s');
  });

  group('#13/AK5 tools/smoke_app.sh', () {
    // slow: runs tools/smoke_app.sh as a shell process
    test('passes on exit code 0 with «smoke: ok», WP_SMOKE=1 set', () {
      final r = smokeScript(
        tmp,
        r'[ "$WP_SMOKE" = 1 ] || exit 3; echo "smoke: ok"; exit 0',
      );
      expect(r.exitCode, 0, reason: '${r.stdout}');
      expect(r.stdout, contains('smoke: ok'));
      expect(r.stdout, contains('smoke_app: passed, exit code 0'));
    });

    // slow: runs tools/smoke_app.sh twice as a shell process
    test('fails on another exit code or without «smoke: ok»', () {
      var r = smokeScript(tmp, 'echo "smoke: FAILED, no playback"; exit 1');
      expect(r.exitCode, 1);
      expect(r.stdout, contains('smoke: FAILED, no playback'));
      expect(r.stdout, contains('failed, exit code 1'));
      r = smokeScript(tmp, 'echo crashed; exit 0');
      expect(r.exitCode, 1);
      expect(r.stdout, contains('crashed')); // the end of the log
    });

    // slow: runs tools/smoke_app.sh twice as a shell process
    test(
      '#161/AK5 mode «google» sets WP_SMOKE=google, other modes are refused',
      () {
        var r = smokeScript(
          tmp,
          r'[ "$WP_SMOKE" = google ] || exit 3; echo "smoke: ok"; exit 0',
          mode: 'google',
        );
        expect(r.exitCode, 0, reason: '${r.stdout}');
        expect(r.stdout, contains('smoke_app: passed, exit code 0'));
        r = smokeScript(tmp, 'echo "smoke: ok"; exit 0', mode: 'cloud');
        expect(r.exitCode, 2);
        expect(r.stdout, contains('unknown mode cloud'));
      },
    );

    test('names the missing build', () {
      final r = smokeScript(tmp, null);
      expect(r.exitCode, 2);
      expect(r.stdout, contains('flutter build macos --release'));
    });
  });
}

const kForever = Duration(days: 1);

/// Runs tools/smoke_app.sh against a fake app whose binary runs [script] (sh).
/// #161: [mode] is the second argument of the script («google»).
ProcessResult smokeScript(Directory tmp, String? script, {String? mode}) {
  final bin = File('${tmp.path}/Fake.app/Contents/MacOS/Woodshed Player');
  if (script != null) {
    bin
      ..createSync(recursive: true)
      ..writeAsStringSync('#!/bin/sh\n$script\n');
    Process.runSync('chmod', ['+x', bin.path]);
  }
  return Process.runSync('../tools/smoke_app.sh', [
    '${tmp.path}/Fake.app',
    ?mode,
  ]);
}
