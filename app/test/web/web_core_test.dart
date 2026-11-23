// #13/AK4: the web app with the WASM core in a real browser (flutter test --platform chrome, make
// test-web): the services of platform_web.dart (WASM core in the AudioWorklet, loader worker, library in
// the OPFS), a generated sine file handed over like a picked file, then load, duration, waveform, play,
// pause, tempo, loop and metronome. Needs the core next to the test page (test/web/wp_core/, copied by
// make test-web from app/web/wp_core/) and Chrome with autoplay allowed (tools/chrome_autoplay.sh),
// because the AudioContext only runs after a user gesture otherwise.
// Rules as in the UI tests (#13/AK2): wait for states, the guard only protects against a hang.
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:woodshed_player/app/file_platform_web.dart';
import 'package:woodshed_player/app/file_store_web.dart';
import 'package:woodshed_player/app/platform_web.dart';
import 'package:woodshed_player/app/smoke.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/player/audio_core_web.dart';
import 'package:wp_core/wp_types.dart';

const hangGuard = Duration(seconds: 30);

void main() {
  setUp(() => OpfsFileStore.clear(libraryDir));
  tearDown(() => OpfsFileStore.clear(libraryDir));

  test('#97/AK6 an AudioContext faster than the core is replaced by one at its limit', () async {
    // Stands in for an output at 384 kHz: Chrome opens contexts up to 768 kHz.
    final fast = web.AudioContext(web.AudioContextOptions(sampleRate: 384000));
    final ctx = await WebAudioCore.supportedContext(fast);
    addTearDown(() => ctx.close().toDart);
    expect(ctx.sampleRate, WpSampleRate.max);
    expect(fast.state, 'closed');

    final usual = web.AudioContext(web.AudioContextOptions(sampleRate: 48000));
    addTearDown(() => usual.close().toDart);
    expect(
      identical(await WebAudioCore.supportedContext(usual), usual),
      isTrue,
    );
    final atLimit = web.AudioContext(
      web.AudioContextOptions(sampleRate: WpSampleRate.max),
    );
    addTearDown(() => atLimit.close().toDart);
    expect(
      identical(await WebAudioCore.supportedContext(atLimit), atLimit),
      isTrue,
    );
  });

  test(
    '#13/AK4 WASM core: load, play, pause, tempo, loop, metronome',
    () async {
      final c = await createAppController();
      final p = c.player, m = c.metronome;
      final core = p.core as WebAudioCore;
      addTearDown(p.pause);
      p.setVolume(0);
      m.setVolume(0);

      // Import like the file picker: the bytes are registered, the library stores them in the OPFS.
      final key = (c.files as WebFilePlatform).register(
        'Sine.wav',
        sineWav(seconds: 3),
      );
      final r = await c.importFiles([key]);
      expect(r.imported, hasLength(1));
      expect(p.error, isNull);
      expect(core.audioRunning, isTrue, reason: 'Chrome without autoplay flag');
      expect(p.hasTrack, isTrue);
      expect(p.duration, closeTo(3.0, 0.01)); // resampled to the context rate
      expect(c.library.hasFile(r.imported.single.id), isTrue);
      // waveform of the sine (amplitude 8000 / 32768 = 0.24) over the first second
      final w = p.waveform(0, 1, 10)!;
      expect(
        w.max.every((v) => v > 0.2 && v < 0.3),
        isTrue,
        reason: '${w.max}',
      );

      p.play();
      expect(
        await waitFor(p, () => p.position > 0.3, guard: hangGuard),
        isTrue,
      );
      expect(p.isPlaying, isTrue);
      p.pause();
      expect(await waitFor(p, () => !p.isPlaying, guard: hangGuard), isTrue);

      p.setSpeedEnabled(true);
      p.setSpeed(0.5);
      expect(p.settings.speed, 0.5);

      // loop 0.5 s – 1.6 s: playing from 1.2 s reaches the end and jumps back to the start
      p.setLoopStart(0.5);
      p.setLoopEnd(1.6);
      expect(p.activeLoop, (0.5, 1.6));
      p.seek(1.2);
      p.play();
      expect(
        await waitFor(p, () => p.position > 1.4, guard: hangGuard),
        isTrue,
      );
      expect(
        await waitFor(p, () => p.position < 1.0, guard: hangGuard),
        isTrue,
      );
      expect(p.position, greaterThanOrEqualTo(0.5));

      // metronome in the worklet; the player's polling reports the change
      m.toggle();
      expect(await waitFor(p, () => m.running, guard: hangGuard), isTrue);
      m.toggle();
      expect(await waitFor(p, () => !m.running, guard: hangGuard), isTrue);
      p.pause();
    },
  );

  test('#116/AK4 #116/AK8 trimming in the browser: the core in the loader worker cuts the file', () async {
    final c = await createAppController();
    final key = (c.files as WebFilePlatform).register(
      'Sine.wav',
      sineWav(seconds: 3),
    );
    final r = await c.importFiles([key]);
    final old = r.imported.single;
    // 44.1 kHz WAV, [0.5, 2.0] s: 66150 frames of 2 bytes after the 44-byte header
    final next = await c.trimTrack(old.id, 0.5, 2.0);
    expect(next, isNotNull, reason: '${c.message}');
    expect(c.library.track(old.id), isNull);
    final t = c.library.track(next!)!;
    expect(t.title, old.title);
    expect(t.duration, 1.5);
    final bytes = await c.library.readAudio(t);
    expect(bytes!.length, 44 + 66150 * 2);
    expect(
      await c.library.store.exists(Library.trackName(old.fileName)),
      isFalse,
    );
    // loaded again with the new file
    expect(c.player.trackId, next);
    expect(c.player.duration, closeTo(1.5, 0.01));
    // less than 1 s is refused by the core as well, the track stays
    final core = c.player.core as WebAudioCore;
    final short = await core.trim(bytes, 0.2, 0.9);
    expect(short.code, WpCode.invalidArgument);
  });

  test('#120/AK2 #120/AK4 #120/AK6 trimming an M4A in the browser: the core cuts it, the browser decodes the result', () async {
    // clicks3.m4a (AAC, clicks at 0.5, 1.0, 2.0 and 2.5 s), copied next to the test page by make test-web
    final response = await web.window.fetch('audio/clicks3.m4a'.toJS).toDart;
    expect(
      response.ok,
      isTrue,
      reason: 'audio/clicks3.m4a missing (make test-web)',
    );
    final m4a = (await response.arrayBuffer().toDart).toDart.asUint8List();
    final c = await createAppController();
    final key = (c.files as WebFilePlatform).register('Clicks.m4a', m4a);
    final old = (await c.importFiles([key])).imported.single;
    final next = await c.trimTrack(old.id, 0.7, 2.2);
    expect(next, isNotNull, reason: '${c.message}');
    expect(c.library.track(old.id), isNull);
    final t = c.library.track(next!)!;
    expect(t.title, old.title);
    expect(t.fileName, endsWith('.m4a'));
    expect((t.duration - 1.5).abs(), lessThanOrEqualTo(0.05));
    // the browser decodes the new file as it is played: it honours the edit list, so the file is as long
    // as the core says and starts where the cut is (the click at 1.0 s of the old file)
    final bytes = (await c.library.readAudio(t))!;
    final ctx = web.OfflineAudioContext(2.toJS, 44100, 44100);
    final buffer = await ctx
        .decodeAudioData(Uint8List.fromList(bytes).buffer.toJS)
        .toDart;
    expect((buffer.duration - t.duration).abs(), lessThanOrEqualTo(0.005));
    final left = buffer.getChannelData(0).toDart;
    final click = left.indexWhere((x) => x.abs() > 0.3) / buffer.sampleRate;
    // the cut: AAC frame 32 of the old file minus its priming of 2112 samples (as natively)
    const cutAt = (32 * 1024 - 2112) / 44100;
    expect(t.duration, closeTo((97 * 1024 - 2112) / 44100 - cutAt, 1e-9));
    expect((click - (1.0 - cutAt)).abs(), lessThanOrEqualTo(0.005));
    expect(
      left.take(441).every((x) => x.abs() < 0.01),
      isTrue,
      reason: 'no click at the start',
    );
    // loaded again with the new file, decoded by the browser
    expect(c.player.trackId, next);
    expect(c.player.duration, closeTo(t.duration, 0.01));
  });
}
