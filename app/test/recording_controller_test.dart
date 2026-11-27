// #140: the recording shared by the record button and the command line (RecordingController), with a
// fake recorder and a temporary library. The button itself: recording_test.dart.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:woodshed_player/app/recording_controller.dart';
import 'package:wp_core/wp_types.dart';

import 'fakes.dart';

void main() {
  late Directory tmp;
  late TestApp app;
  late FakeRecorder rec;
  late RecordingController recording;

  setUpAll(initializeDateFormatting);
  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('wp_rec_controller_test');
    app = TestApp(Directory('${tmp.path}/lib'));
    await app.library.load();
    app.files.recordings = (Directory('${tmp.path}/rec')..createSync()).path;
    rec = FakeRecorder();
    recording = RecordingController(
      app: app.controller,
      recorder: rec,
      now: () => DateTime(2026, 11, 19, 14, 5, 9),
      tick: const Duration(milliseconds: 1),
    );
  });
  tearDown(() {
    recording.dispose();
    tmp.deleteSync(recursive: true);
  });

  /// Stops the recording, finishing the load of the new title on the way.
  Future<void> stop() async {
    var stopped = false;
    unawaited(recording.stop().then((_) => stopped = true));
    await eventually(() {
      app.finishLoads();
      return stopped;
    }, 'stopped');
  }

  test('#140/AK5: a new controller is idle, without hints', () {
    expect(recording.phase, RecordingPhase.idle);
    expect(recording.busy, isFalse);
    expect(recording.silent, isFalse);
    expect(recording.microphoneDenied, isFalse);
    expect(recording.error, isNull);
    expect(recording.done, isNull);
    expect(recording.seconds, 0);
  });

  test('#140/AK6: choosing a source tells the button', () {
    var told = 0;
    recording.addListener(() => told++);
    recording.choose(WpRecSource.microphone);
    expect(told, 1);
    expect(recording.source, WpRecSource.microphone);
  });

  test('#140/AK17: a second start while the first one is still starting is refused', () async {
    final first = recording.start(de);
    final second = recording.start(de, arming: const Arming());
    expect(recording.busy, isTrue);
    expect(await second, isA<RecordingBusy>());
    expect(await first, isNull);
    expect(rec.arming, isNull); // the first, not armed
    await stop();
  });

  test('#140/AK15: the silence hint comes after more than 3 s of only silence, and goes with the stop', () async {
    expect(await recording.start(de), isNull);
    rec
      ..seconds = 3
      ..onlySilence = true;
    await eventually(() => recording.seconds == 3, 'tick');
    expect(recording.silent, isFalse);
    rec.seconds = 3.01;
    await eventually(() => recording.silent, 'silence reported');
    rec.onlySilence = false;
    rec.seconds = 4;
    await eventually(() => !recording.silent, 'sound arrived');
    rec.onlySilence = true;
    await eventually(() => recording.silent, 'silence again');
    await stop();
    expect(recording.silent, isFalse);
    expect(recording.seconds, 4);
  });

  test(
    '#140/AK9: armed, the length is what the core keeps; stopping saves it',
    () async {
      expect(
        await recording.start(de, title: 'T', arming: const Arming()),
        isNull,
      );
      rec
        ..seconds = 20
        ..keptSeconds = 6
        ..gate = WpRecGate.recording;
      await eventually(
        () => recording.phase == RecordingPhase.recording,
        'recording',
      );
      expect(recording.seconds, 6);
      await stop();
      final outcome = await recording.done!;
      expect(outcome, isA<RecordingSaved>());
      expect((outcome as RecordingSaved).track!.title, 'T');
    },
  );

  test('#140/AK14: stopping twice saves once', () async {
    expect(await recording.start(de, title: 'Once'), isNull);
    var stopped = 0;
    unawaited(recording.stop().then((_) => stopped++));
    unawaited(recording.stop().then((_) => stopped++));
    await eventually(() {
      app.finishLoads();
      return stopped == 2;
    }, 'stopped');
    expect(app.library.tracks, hasLength(1));
  });

  test(
    '#140: disposing stops a running recording and ends the controller',
    () async {
      final own = RecordingController(app: app.controller, recorder: rec);
      expect(await own.start(de), isNull);
      expect(rec.recording, isTrue);
      own.dispose();
      expect(rec.recording, isFalse);
      expect(() => own.addListener(() {}), throwsA(isA<Error>()));
    },
  );

  /// #157: waits until the recording ended by itself is saved, finishing loads on the way.
  Future<RecordingOutcome> ended() async {
    RecordingOutcome? outcome;
    unawaited(recording.done!.then((o) => outcome = o));
    await eventually(() {
      app.finishLoads();
      return outcome != null;
    }, 'ended and saved');
    return outcome!;
  }

  test('#157/AK7 #157/AK8: the recorder ends the recording by itself: saved, with the reason, until the next start', () async {
    expect(await recording.start(de), isNull);
    rec.seconds = 2;
    rec.interruption = RecordingInterruption.storageFull;
    final outcome = await ended();
    expect(outcome, isA<RecordingSaved>());
    expect((outcome as RecordingSaved).track, isNotNull);
    expect(rec.recording, isFalse);
    expect(recording.phase, RecordingPhase.idle);
    expect(recording.interruption, RecordingInterruption.storageFull);
    expect(await recording.start(de), isNull);
    expect(recording.interruption, isNull);
    rec.interruption = RecordingInterruption.background;
    await ended();
    expect(recording.interruption, RecordingInterruption.background);
    recording.choose(WpRecSource.microphone);
    expect(recording.interruption, isNull);
  });
}
