// #157: recording in the browser with the real core (make test-web): the microphone is a generated 1 kHz
// sine in the core's AudioContext, handed over as a MediaStream instead of getUserMedia, so the test runs
// without a microphone and without a permission prompt. Checks the constraints, the level in the file,
// the title in the library, a refused permission and that the microphone is closed after the recording.
// Rules as in the UI tests (#13/AK2): wait for states, the guard only protects against a hang.
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:web/web.dart' as web;
import 'package:woodshed_player/app/app_controller.dart';
import 'package:woodshed_player/app/file_platform_web.dart';
import 'package:woodshed_player/app/file_store_web.dart';
import 'package:woodshed_player/app/platform_web.dart';
import 'package:woodshed_player/app/practice_recording.dart';
import 'package:woodshed_player/app/recorder_web.dart';
import 'package:woodshed_player/app/recording_controller.dart';
import 'package:woodshed_player/app/smoke.dart';
import 'package:woodshed_player/l10n/app_localizations.dart';
import 'package:woodshed_player/player/audio_core_web.dart';
import 'package:woodshed_player/player/audio_session_web.dart';
import 'package:woodshed_player/ui/recording_button.dart';
import 'package:woodshed_player/ui/style.dart';
import 'package:wp_core/wp_types.dart';

const hangGuard = Duration(seconds: 30);
final en = lookupAppLocalizations(const Locale('en'));

/// −12 dBFS as a peak amplitude.
final minus12 = math.pow(10, -12 / 20).toDouble();

/// The audio sessions the recorder of [start] asked for, in order (#158).
final sessions = <AudioSessionType>[];

/// A microphone that plays a 1 kHz sine at −12 dBFS; remembers the constraints it was opened with.
class SineMicrophone {
  SineMicrophone(this.ctx, {this.silent = false});
  final web.AudioContext ctx;

  /// The sine starts silent. Armed tests need this: a sine that sounds until the test schedules its phases
  /// would start a take of its own on a slow machine.
  final bool silent;
  final opened = <JSObject>[];
  web.MediaStream? stream;

  /// Level of the sine; tests schedule phases of sound and silence on it.
  web.GainNode? gain;

  JSPromise<web.MediaStream> open(JSObject constraints) {
    opened.add(constraints);
    final osc = ctx.createOscillator()..frequency.value = 1000;
    final gain = this.gain = ctx.createGain()
      ..gain.value = silent ? 0 : minus12;
    final out = ctx.createMediaStreamDestination();
    osc.connect(gain);
    gain.connect(out);
    osc.start();
    stream = out.stream;
    return Future.value(out.stream).toJS;
  }
}

JSPromise<web.MediaStream> refused(JSObject constraints) =>
    Future<web.MediaStream>.error(
      web.DOMException('Permission denied', 'NotAllowedError'),
    ).toJS;

Future<(AppController, WebRecorder, RecordingController, SineMicrophone)>
start({
  Duration releaseAfter = Duration.zero,
  int? storageLimit,
  bool silentMic = false,
}) async {
  final c = await createAppController();
  final core = c.player.core as WebAudioCore;
  final mic = SineMicrophone(core.context, silent: silentMic);
  sessions.clear();
  final rec = (await WebRecorder.create(
    core,
    open: mic.open,
    releaseAfter: releaseAfter,
    storageLimit: storageLimit,
    watchPage: false,
    setSession: (t) {
      sessions.add(t);
      return true;
    },
  ))!;
  final files = c.files as WebFilePlatform;
  files.microphone = rec.acquire;
  files.recording = rec.take;
  return (c, rec, RecordingController(app: c, recorder: rec), mic);
}

void main() {
  setUpAll(initializeDateFormatting);
  setUp(() => OpfsFileStore.clear(libraryDir));
  tearDown(() => OpfsFileStore.clear(libraryDir));

  test('#157/AK1 Chrome can record: the record button has the microphone as its only source', () async {
    expect(WebRecorder.supported, isTrue);
    final c = await createAppController();
    final recording = recordingFor(c);
    expect(recording, isNotNull);
    expect(recording!.sources, [WpRecSource.microphone]);
    expect(recording.source, WpRecSource.microphone);
    expect(recordingButtonFor(c), isNotNull);
  });

  test('#157/AK1 without getUserMedia (old browser, no HTTPS) there is no record button', () async {
    final proto =
        (globalContext['MediaDevices']! as JSObject)['prototype']! as JSObject;
    final saved = proto['getUserMedia'];
    proto.delete('getUserMedia'.toJS);
    addTearDown(() => proto['getUserMedia'] = saved);
    expect(WebRecorder.supported, isFalse);
    final c = await createAppController();
    expect(recordingFor(c), isNull);
    expect(recordingButtonFor(c), isNull);
    expect(await c.files.microphoneAccess(), isFalse);
    expect(await c.files.recordingsDir(), isNull);
  });

  test('#157/AK2 #157/AK3 #157/AK9 a take of the generated microphone: level, FLAC title, microphone closed', () async {
    final (c, rec, recording, mic) = await start();
    expect(
      rec.microphoneOpen,
      isFalse,
    ); // AK9: nothing open before the recording
    expect(await recording.start(en), isNull);
    // AK2: without echo cancellation, noise suppression and automatic gain
    final audio = mic.opened.single['audio']! as JSObject;
    for (final key in [
      'echoCancellation',
      'noiseSuppression',
      'autoGainControl',
    ]) {
      expect((audio[key]! as JSBoolean).toDart, isFalse, reason: key);
    }
    expect(rec.microphoneOpen, isTrue);
    expect(
      await waitFor(recording, () => recording.seconds > 1.5, guard: hangGuard),
      isTrue,
    );
    expect(recording.level, greaterThan(0.2));
    await recording.stop();
    final outcome = await recording.done!;
    expect(outcome, isA<RecordingSaved>());
    final track = (outcome as RecordingSaved).track;
    expect(track, isNotNull);
    // AK3: a FLAC title in the library (OPFS), named like on the Mac
    expect(track!.fileName, endsWith('.flac'));
    expect(c.library.hasFile(track.id), isTrue);
    expect(track.title, startsWith('Recording '));
    expect(rec.exists('recordings/x.flac'), isFalse);
    // AK2: the sine arrives at −12 dBFS ± 1 dB
    final bytes = (await c.library.readAudio(track))!;
    final buffer = await (c.player.core as WebAudioCore).context
        .decodeAudioData(bytes.buffer.toJS)
        .toDart;
    final ch = buffer.getChannelData(0).toDart;
    final from = (0.5 * buffer.sampleRate).round();
    var peak = 0.0;
    for (var i = from; i < ch.length - from; i++) {
      peak = math.max(peak, ch[i].abs());
    }
    final db = 20 * math.log(peak) / math.ln10;
    expect(db, closeTo(-12, 1), reason: 'peak $peak');
    expect(buffer.duration, greaterThan(1.4));
    // AK3: it plays with tempo and loop like every title
    expect(await c.select(track), isTrue);
    expect(c.player.duration, closeTo(buffer.duration, 0.05));
    c.player.setVolume(0);
    c.player.setSpeedEnabled(true);
    c.player.setSpeed(0.5);
    c.player.setLoopStart(0.25);
    c.player.setLoopEnd(1.4);
    final loop = c.player.activeLoop!;
    expect(loop.$1, closeTo(0.25, 1e-6));
    expect(loop.$2, closeTo(1.4, 1e-6));
    // AK9: the microphone closes shortly after the stop, its tracks end
    expect(
      await waitFor(rec, () => !rec.microphoneOpen, guard: hangGuard),
      isTrue,
    );
    for (final t in mic.stream!.getTracks().toDart) {
      expect(t.readyState, 'ended');
    }
    // #158: 'play-and-record' only while the microphone is open
    expect(sessions, [
      AudioSessionType.playAndRecord,
      AudioSessionType.playback,
    ]);
  });

  test('#157/AK6 a refused permission starts nothing and asks for the permission of the website', () async {
    final c = await createAppController();
    final core = c.player.core as WebAudioCore;
    final rec = (await WebRecorder.create(core, open: refused))!;
    final files = c.files as WebFilePlatform;
    files.microphone = rec.acquire;
    final recording = RecordingController(app: c, recorder: rec);
    expect(await recording.start(en), isA<RecordingMicrophoneDenied>());
    expect(recording.microphoneDenied, isTrue);
    expect(recording.busy, isFalse);
    expect(rec.problem, MicrophoneProblem.denied);
    expect(rec.microphoneOpen, isFalse);
    expect(c.library.tracks, isEmpty);
  });

  testWidgets(
    '#157/AK6 the record button names the permission of the website, not a macOS path',
    (tester) async {
      final recording = (await tester.runAsync(() async {
        final c = await createAppController();
        final rec = (await WebRecorder.create(
          c.player.core as WebAudioCore,
          open: refused,
        ))!;
        (c.files as WebFilePlatform).microphone = rec.acquire;
        final recording = RecordingController(app: c, recorder: rec);
        await recording.start(en);
        return recording;
      }))!;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: woodshedTheme(Brightness.light),
          home: Scaffold(
            body: Center(
              child: RecordingButton(
                controller: recording.app,
                recording: recording,
              ),
            ),
          ),
        ),
      );
      final hint = tester.widget<IconButton>(
        find.byKey(const Key('recordingProblem')),
      );
      expect(hint.tooltip, en.recordingMicrophoneDeniedBrowser);
      expect(hint.tooltip, isNot(contains('System Settings')));
      // only the microphone: no source menu
      expect(find.byKey(const Key('recordingSource')), findsNothing);
    },
  );

  test('#157/AK4 #157/AK5 «Armed» in the browser: sound starts a take 1 s early, the pause ends it, filed by date', () async {
    final (c, rec, recording, mic) = await start(silentMic: true);
    await c.library.setArmSettings(thresholdDb: -30, silenceSeconds: 1);
    final practice = PracticeRecording(app: c, recording: recording);
    c.setArea(AppArea.metronome);
    expect(await practice.turnOn(en), isNull);
    expect(practice.on, isTrue);
    // the sine is silent for 1.5 s, sounds 1 s, then stays silent
    final g = mic.gain!.gain;
    final t0 = (c.player.core as WebAudioCore).context.currentTime;
    g
      ..cancelScheduledValues(0)
      ..setValueAtTime(0, t0)
      ..setValueAtTime(minus12, t0 + 1.5)
      ..setValueAtTime(0, t0 + 2.5);
    expect(
      await waitFor(practice, () => practice.takeRunning, guard: hangGuard),
      isTrue,
    );
    // the take ends after the pause and is saved
    expect(await recording.done, isA<RecordingSaved>());
    // #156: after the take «Armed» goes off by itself
    expect(practice.on, isFalse);
    final take = c.library.tracks.single;
    expect(take.title, matches(RegExp(r'^\d\d:\d\d:\d\d$')));
    final day = c.library.folders.firstWhere((f) => f.id == take.folderId);
    expect(day.name, matches(RegExp(r'^\d{4}-\d\d-\d\d$')));
    final top = c.library.folders.firstWhere((f) => f.id == day.parentId);
    expect(top.name, recordingsFolder);
    final bytes = (await c.library.readAudio(take))!;
    final buffer = await (c.player.core as WebAudioCore).context
        .decodeAudioData(bytes.buffer.toJS)
        .toDart;
    // 1 s lead-in + 1 s sound + 1 s tail
    expect(buffer.duration, closeTo(3.0, 0.15));
    final ch = buffer.getChannelData(0).toDart;
    final first = ch.indexWhere((v) => v.abs() > 0.03);
    expect(first / buffer.sampleRate, closeTo(1.0, 0.1));
    expect(
      await waitFor(rec, () => !rec.microphoneOpen, guard: hangGuard),
      isTrue,
    );
    practice.dispose();
  });

  test('#157/AK7 in the background a recording ends and is saved, the microphone closes', () async {
    final (c, rec, recording, _) = await start();
    expect(await recording.start(en), isNull);
    expect(
      await waitFor(recording, () => recording.seconds > 0.5, guard: hangGuard),
      isTrue,
    );
    rec.pageHidden();
    final outcome = await recording.done!;
    expect(outcome, isA<RecordingSaved>());
    expect((outcome as RecordingSaved).track, isNotNull);
    expect(recording.interruption, RecordingInterruption.background);
    expect(c.library.tracks, hasLength(1));
    expect(
      await waitFor(rec, () => !rec.microphoneOpen, guard: hangGuard),
      isTrue,
    );
  });

  test('#157/AK7 «Armed» goes off in the background with the reason', () async {
    final (c, rec, recording, _) = await start(silentMic: true);
    final practice = PracticeRecording(app: c, recording: recording);
    expect(await practice.turnOn(en), isNull);
    rec.pageHidden();
    expect(
      await waitFor(practice, () => !practice.on, guard: hangGuard),
      isTrue,
    );
    expect(practice.problem, PracticeArmProblem.background);
    expect(c.library.tracks, isEmpty); // it was waiting for sound
    practice.dispose();
  });

  test(
    '#157/AK8 a full storage ends the recording with what was stored',
    () async {
      final (c, _, recording, _) = await start(storageLimit: 6000);
      expect(await recording.start(en), isNull);
      final outcome = await recording.done!;
      expect(recording.interruption, RecordingInterruption.storageFull);
      final track = (outcome as RecordingSaved).track!;
      final bytes = (await c.library.readAudio(track))!;
      expect(bytes.length, lessThanOrEqualTo(6000));
      final buffer = await (c.player.core as WebAudioCore).context
          .decodeAudioData(bytes.buffer.toJS)
          .toDart;
      expect(buffer.duration, greaterThan(0.05));
    },
  );
}
