// #147: the armed practice recording (PracticeRecording) with a fake recorder and a temporary library:
// start with lead-in, end after a pause with a 1 s tail, end with the space bar, several takes in a row,
// names and folders, the settings per device, and the lock of the record button and the command line.
// The detection of sound and silence itself is tested in the core (core/tests/sound_gate_tests.cpp).
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:woodshed_player/app/app_controller.dart';
import 'package:woodshed_player/app/command_line.dart';
import 'package:woodshed_player/app/practice_recording.dart';
import 'package:woodshed_player/app/recording_controller.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:wp_core/wp_types.dart';

import 'fakes.dart';

class _Output implements CommandOutput {
  final lines = <String>[];
  @override
  void out(String line) => lines.add('out $line');
  @override
  void err(String line) => lines.add('err $line');
}

void main() {
  late Directory tmp;
  late TestApp app;
  late FakeRecorder rec;
  late RecordingController recording;
  late PracticeRecording practice;
  var clock = DateTime(2026, 11, 25, 9, 30, 15);

  setUpAll(initializeDateFormatting);
  setUp(() async {
    clock = DateTime(2026, 11, 25, 9, 30, 15);
    tmp = Directory.systemTemp.createTempSync('wp_practice_rec_test');
    app = TestApp(Directory('${tmp.path}/lib'));
    await app.library.load();
    app.files.recordings = (Directory('${tmp.path}/rec')..createSync()).path;
    rec = FakeRecorder();
    recording = RecordingController(
      app: app.controller,
      recorder: rec,
      now: () => clock,
      tick: const Duration(milliseconds: 1),
    );
    practice = PracticeRecording(app: app.controller, recording: recording);
    // #147 tests the switch staying on after a take; #156 turns that off by default (group 'off after
    // a take').
    await app.library.setArmKeepsOn(true);
  });
  tearDown(() {
    practice.dispose();
    recording.dispose();
    tmp.deleteSync(recursive: true);
  });

  /// Waits until the core is armed for the next take (a new start of the fake recorder).
  Future<void> armed(int starts) => eventually(
    () =>
        rec.starts == starts &&
        rec.gate == WpRecGate.armed &&
        recording.phase == RecordingPhase.armed,
    'armed for take $starts',
  );

  /// The sound came: the core writes from [kept] seconds before now.
  Future<void> sound({double kept = 1}) async {
    rec
      ..keptSeconds = kept
      ..gate = WpRecGate.recording;
    await eventually(() => practice.takeRunning, 'take running');
  }

  /// The core reports the pause: the take ends with [kept] seconds in the file.
  Future<void> pause(int tracks, {double kept = 3}) async {
    rec
      ..keptSeconds = kept
      ..gate = WpRecGate.done;
    await eventually(
      () => app.library.tracks.length == tracks,
      'take $tracks saved',
    );
  }

  /// Stops a recording of the record button, finishing the load of its new title on the way.
  Future<void> stopButton() async {
    var stopped = false;
    unawaited(recording.stop().then((_) => stopped = true));
    await eventually(() {
      app.finishLoads();
      return stopped;
    }, 'stopped');
  }

  String? folderName(Track t) =>
      app.library.folders.where((f) => f.id == t.folderId).firstOrNull?.name;

  group('switch', () {
    test('#147/AK1: on, it arms the microphone, whatever source the record button has', () async {
      recording.choose(WpRecSource.system);
      expect(await practice.turnOn(de), isNull);
      expect(practice.on, isTrue);
      await armed(1);
      expect(rec.source, WpRecSource.microphone);
      expect(
        recording.source,
        WpRecSource.system,
      ); // the button keeps its choice
      expect(practice.takeRunning, isFalse);
      expect(practice.seconds, 0);
      await practice.turnOff();
    });

    test(
      '#147/AK9: default threshold -30 dBFS, pause 5 s, and the tail of 1 s',
      () async {
        expect(practice.thresholdDb, -30);
        expect(practice.silenceSeconds, 5);
        await practice.turnOn(de);
        await armed(1);
        expect(rec.arming, (thresholdDb: -30.0, silenceSeconds: 5.0));
        expect(rec.tailSeconds, 1.0);
        await practice.turnOff();
      },
    );

    test('#147/AK10: level and duration only of its own take', () async {
      await practice.turnOn(de);
      await armed(1);
      rec.level = 0.5;
      await eventually(() => practice.level == 0.5, 'level');
      expect(practice.seconds, 0);
      rec.seconds = 12;
      await sound(kept: 4);
      await eventually(() => practice.seconds == 4, 'duration');
      await practice.turnOff();
      expect(practice.level, 0);
      expect(practice.seconds, 0);
    });

    test('#147: turning on twice arms once', () async {
      await practice.turnOn(de);
      expect(await practice.turnOn(de), isNull);
      await armed(1);
      expect(rec.starts, 1);
      await practice.turnOff();
      await practice.turnOff(); // off twice does nothing more
      expect(practice.on, isFalse);
    });
  });

  group('takes', () {
    test(
      '#147/AK2: a take starts when the sound comes, its start 1 s before',
      () async {
        await practice.turnOn(de);
        await armed(1);
        clock = DateTime(2026, 11, 25, 9, 31, 0);
        await sound(kept: 1);
        expect(recording.startedAt, DateTime(2026, 11, 25, 9, 30, 59));
        await pause(1);
        expect(app.library.tracks.single.title, '09:30:59');
        await practice.turnOff();
      },
    );

    test('#147/AK3: the pause ends the take; it is saved, not loaded, and the next one is armed', () async {
      await practice.turnOn(de);
      await armed(1);
      await sound();
      expect(rec.recording, isTrue);
      await pause(1, kept: 7);
      expect(rec.tailSeconds, 1.0);
      expect(app.controller.player.hasTrack, isFalse); // not loaded, not played
      await armed(2);
      expect(practice.on, isTrue);
      await practice.turnOff();
    });

    test('#147/AK4: the space bar ends a running take at once; armed it does nothing', () async {
      await practice.turnOn(de);
      await armed(1);
      await practice.endTake(); // still waiting for sound
      expect(rec.recording, isTrue);
      expect(app.library.tracks, isEmpty);
      await sound();
      rec.keptSeconds = 2.5;
      await practice.endTake();
      expect(app.library.tracks, hasLength(1));
      expect(practice.on, isTrue);
      await armed(2);
      await practice.turnOff();
    });

    test('#147/AK5: three phases of playing with pauses between them give three takes', () async {
      await practice.turnOn(de);
      for (var i = 1; i <= 3; i++) {
        await armed(i);
        clock = DateTime(2026, 11, 25, 10, i, 0);
        await sound();
        await pause(i);
      }
      await armed(4);
      expect(practice.on, isTrue);
      expect(app.library.tracks.map((t) => t.title), [
        '10:00:59',
        '10:01:59',
        '10:02:59',
      ]);
      // all in the same folder of the day
      expect(app.library.tracks.map((t) => t.folderId).toSet(), hasLength(1));
      await practice.turnOff();
      expect(app.library.tracks, hasLength(3));
    });

    test('#147/AK6: off while recording stops and saves the take; armed, off leaves nothing', () async {
      await practice.turnOn(de);
      await armed(1);
      final empty = rec.path!;
      await practice.turnOff();
      expect(rec.recording, isFalse);
      expect(File(empty).existsSync(), isFalse);
      expect(app.library.tracks, isEmpty);
      await practice.turnOn(de);
      await armed(2);
      await sound();
      await practice.turnOff();
      expect(app.library.tracks, hasLength(1));
      expect(rec.recording, isFalse);
      expect(recording.phase, RecordingPhase.idle);
    });

    test(
      '#147/AK6: the switch stays on when the area changes to Player',
      () async {
        app.controller.setArea(AppArea.practice);
        await practice.turnOn(de);
        await armed(1);
        app.controller.setArea(AppArea.player);
        expect(practice.on, isTrue);
        expect(rec.recording, isTrue);
        await practice.turnOff();
      },
    );

    test('#147/AK7: takes go to Recordings › date, the folders are created once and used again', () async {
      final existing = app.library.createFolder(recordingsFolder);
      await practice.turnOn(de);
      await armed(1);
      await sound();
      await pause(1);
      final t = app.library.tracks.single;
      expect(folderName(t), '2026-11-25');
      final day = app.library.folders.firstWhere((f) => f.id == t.folderId);
      expect(day.parentId, existing.id);
      await armed(2);
      clock = DateTime(2026, 11, 26, 8, 0, 1);
      await sound();
      await pause(2);
      final next = app.library.tracks.firstWhere((x) => x.id != t.id);
      expect(folderName(next), '2026-11-26');
      expect(
        app.library.folders.where((f) => f.name == recordingsFolder),
        hasLength(1),
      );
      expect(app.library.folders, hasLength(3));
      await practice.turnOff();
    });

    test('#147/AK7: the take is a FLAC file of its own, also two in the same second', () async {
      await practice.turnOn(de);
      await armed(1);
      final first = rec.path!;
      await sound();
      await pause(1);
      await armed(2);
      expect(rec.path, isNot(first));
      expect(first, endsWith('.flac'));
      expect(rec.path, endsWith(' 2.flac'));
      await practice.turnOff();
    });

    test('#147/AK8: in Practice with a loaded track the take is named «<Title> <HH:MM:SS>»', () async {
      final src = File('${tmp.path}/Etude.mp3')..writeAsStringSync('audio');
      final r = await app.library.importFiles([src.path]);
      final loaded = app.controller.select(r.imported.single);
      app.finishLoads();
      expect(await loaded, isTrue);
      app.controller.setArea(AppArea.practice);
      await practice.turnOn(de);
      await armed(1);
      clock = DateTime(2026, 11, 25, 7, 5, 9);
      await sound();
      await pause(2);
      expect(
        app.library.tracks.map((t) => t.title),
        contains('Etude 07:05:08'),
      );
      // In the area Metronome only the time.
      app.controller.setArea(AppArea.metronome);
      await armed(2);
      await sound();
      await pause(3);
      expect(app.library.tracks.map((t) => t.title), contains('07:05:08'));
      await practice.turnOff();
    });
  });

  group('settings', () {
    test('#147/AK9: threshold and pause are kept on this device and limited to their range', () async {
      practice.setThresholdDb(-45);
      practice.setSilenceSeconds(12);
      expect(practice.thresholdDb, -45);
      expect(practice.silenceSeconds, 12);
      await eventually(
        () =>
            File('${tmp.path}/lib/${DeviceSettings.fileName}')
                .readAsStringSync()
                .contains('"armSilenceSeconds":12'),
        'saved',
      );
      final again = TestApp(Directory('${tmp.path}/lib'));
      await again.library.load();
      expect(again.library.armThresholdDb, -45);
      expect(again.library.armSilenceSeconds, 12);
      practice.setThresholdDb(-80);
      practice.setSilenceSeconds(0.5);
      expect(practice.thresholdDb, -60);
      expect(practice.silenceSeconds, 1);
      practice.setThresholdDb(6);
      practice.setSilenceSeconds(31);
      expect(practice.thresholdDb, 0);
      expect(practice.silenceSeconds, 30);
    });

    test('#147/AK9: new settings arm anew while waiting, a running take keeps its own', () async {
      await practice.turnOn(de);
      await armed(1);
      practice.setThresholdDb(-40);
      await practice.applySettings();
      await armed(2);
      expect(rec.arming, (thresholdDb: -40.0, silenceSeconds: 5.0));
      expect(app.library.tracks, isEmpty); // the empty arming left nothing
      await sound();
      practice.setSilenceSeconds(9);
      await practice.applySettings();
      expect(practice.takeRunning, isTrue);
      await pause(1);
      await armed(3);
      expect(rec.arming, (thresholdDb: -40.0, silenceSeconds: 9.0));
      await practice.turnOff();
    });

    test('#147/AK9: unreadable values in device.json fall back', () {
      final d = DeviceSettings(
        deviceId: '0123456789abcdef',
        armThresholdDb: -20,
        armSilenceSeconds: 3,
      );
      expect(d.toJson()['armThresholdDb'], -20);
      expect(d.toJson()['armSilenceSeconds'], 3);
      expect(
        const DeviceSettings(deviceId: '0123456789abcdef').toJson(),
        isNot(contains('armThresholdDb')),
      );
      final copy = d.copyWith(armThresholdDb: -10);
      expect(copy.armThresholdDb, -10);
      expect(copy.armSilenceSeconds, 3);
    });
  });

  group('off after a take', () {
    setUp(() => app.library.setArmKeepsOn(false));

    test('#156/AK1: by default the switch goes off after a take', () async {
      final fresh = TestApp(Directory('${tmp.path}/fresh'));
      await fresh.library.load();
      expect(fresh.library.armKeepsOn, isFalse);
      expect(
        const DeviceSettings(deviceId: '0123456789abcdef').armKeepsOn,
        isFalse,
      );
    });

    test('#156/AK2: the pause ends the take, it is saved and the switch goes off', () async {
      await practice.turnOn(de);
      await armed(1);
      await sound();
      await pause(1);
      await eventually(() => !practice.on, 'switch off');
      expect(recording.phase, RecordingPhase.idle);
      expect(recording.reserved, isFalse);
      expect(rec.recording, isFalse);
      // Sound afterwards starts nothing: one take for three phases of playing.
      rec.gate = WpRecGate.recording;
      const quiet = Duration(milliseconds: 20);
      await Future<void>.delayed(quiet); // absence: no new take is armed
      expect(rec.starts, 1);
      expect(app.library.tracks, hasLength(1));
    });

    test(
      '#156/AK2: the space bar ends the take and the switch goes off',
      () async {
        await practice.turnOn(de);
        await armed(1);
        await sound();
        rec.keptSeconds = 2.5;
        await practice.endTake();
        expect(app.library.tracks, hasLength(1));
        await eventually(() => !practice.on, 'switch off');
        expect(rec.starts, 1);
      },
    );

    test(
      '#156/AK2: new settings while waiting arm anew, the switch stays on',
      () async {
        await practice.turnOn(de);
        await armed(1);
        practice.setThresholdDb(-40);
        await practice.applySettings();
        await armed(2);
        expect(practice.on, isTrue);
        await practice.turnOff();
      },
    );

    test('#156/AK3: set to stay on, three phases give three takes', () async {
      practice.setKeepsOn(true);
      expect(practice.keepsOn, isTrue);
      await practice.turnOn(de);
      for (var i = 1; i <= 3; i++) {
        await armed(i);
        await sound();
        await pause(i);
      }
      await armed(4);
      expect(practice.on, isTrue);
      await practice.turnOff();
    });

    test(
      '#156/AK4: changed during a take, the new choice applies when it ends',
      () async {
        await practice.turnOn(de);
        await armed(1);
        await sound();
        practice.setKeepsOn(true);
        await pause(1);
        await armed(2);
        expect(practice.on, isTrue);
        await sound();
        practice.setKeepsOn(false);
        await pause(2);
        await eventually(() => !practice.on, 'switch off');
        expect(rec.starts, 2);
      },
    );

    test('#156/AK1: the choice is kept on this device', () async {
      practice.setKeepsOn(true);
      await eventually(
        () =>
            File('${tmp.path}/lib/${DeviceSettings.fileName}')
                .readAsStringSync()
                .contains('"armKeepsOn":true'),
        'saved',
      );
      final again = TestApp(Directory('${tmp.path}/lib'));
      await again.library.load();
      expect(again.library.armKeepsOn, isTrue);
      practice.setKeepsOn(false);
      await eventually(
        () =>
            !File('${tmp.path}/lib/${DeviceSettings.fileName}')
                .readAsStringSync()
                .contains('armKeepsOn'),
        'saved off',
      );
      expect(
        const DeviceSettings(deviceId: '0123456789abcdef')
            .copyWith(armKeepsOn: true)
            .copyWith(armThresholdDb: -3)
            .armKeepsOn,
        isTrue,
      );
    });
  });

  group('lock', () {
    test(
      '#147/AK11: while on, the record button cannot start a recording',
      () async {
        await practice.turnOn(de);
        await armed(1);
        expect(recording.reserved, isTrue);
        expect(await recording.start(de), isA<RecordingBusy>());
        await practice.turnOff();
        expect(recording.reserved, isFalse);
        expect(await recording.start(de), isNull);
        await stopButton();
      },
    );

    test(
      '#147/AK11: while on, `woodshed record` ends with exit code 1',
      () async {
        await practice.turnOn(de);
        await armed(1);
        final out = _Output();
        final handler = CommandHandler(
          app: app.controller,
          recording: recording,
          texts: () => de,
        );
        final code = await handler.run(
          const CommandRequest(command: 'record'),
          out,
          Completer<void>().future,
        );
        expect(code, CliExit.failed);
        expect(out.lines.single, contains('Armed'));
        expect(rec.starts, 1);
        await practice.turnOff();
      },
    );

    test(
      '#147/AK11: with another recording running the switch stays off',
      () async {
        expect(await recording.start(de), isNull);
        expect(await practice.turnOn(de), PracticeArmProblem.busy);
        expect(practice.on, isFalse);
        expect(practice.problem, PracticeArmProblem.busy);
        expect(recording.reserved, isFalse);
        await stopButton();
        expect(await practice.turnOn(de), isNull);
        expect(practice.problem, isNull);
        await practice.turnOff();
      },
    );

    test('#147/AK12: microphone refused: the switch goes off with the hint, no file', () async {
      app.files.microphoneGranted = false;
      expect(await practice.turnOn(de), PracticeArmProblem.microphoneDenied);
      expect(practice.on, isFalse);
      expect(practice.problem, PracticeArmProblem.microphoneDenied);
      expect(recording.reserved, isFalse);
      expect(rec.starts, 0);
      // the record button keeps no hint of its own
      expect(recording.microphoneDenied, isFalse);
      expect(de.armedMicrophoneDenied, contains('Mikrofon'));
      expect(
        de.armedMicrophoneDenied,
        contains('Systemeinstellungen › Datenschutz & Sicherheit › Mikrofon'),
      );
    });

    test('#147: a failing core turns the switch off', () async {
      rec.failWith = const WpRecordingException(-11, 0, 'No input device');
      expect(await practice.turnOn(de), PracticeArmProblem.failed);
      expect(practice.on, isFalse);
      expect(recording.error?.code, -11);
    });

    test('#147: no folder for recordings turns the switch off', () async {
      app.files.recordings = null;
      expect(await practice.turnOn(de), PracticeArmProblem.failed);
      expect(practice.on, isFalse);
    });

    test(
      '#147: switched off while the permission is asked, nothing is recorded',
      () async {
        final asked = practice.turnOn(de);
        await practice.turnOff();
        expect(await asked, isNull);
        expect(rec.recording, isFalse);
        expect(practice.on, isFalse);
        expect(recording.phase, RecordingPhase.idle);
      },
    );
  });

  group('listeners', () {
    test(
      '#147/AK9, AK10: the switch tells its listeners of each change',
      () async {
        var told = 0;
        int? startsWhenOn;
        practice.addListener(() {
          told++;
          if (practice.on) startsWhenOn ??= rec.starts;
        });
        practice.setThresholdDb(-35);
        expect(told, 1);
        practice.setSilenceSeconds(6);
        expect(told, 2);
        await practice.turnOn(de);
        // on shows before the microphone is armed
        expect(startsWhenOn, 0);
        await armed(1);
        final before = told;
        await practice.turnOff();
        expect(told, greaterThan(before));
        expect(practice.on, isFalse);
      },
    );

    test('#147/AK11: a refused start is told', () async {
      expect(await recording.start(de), isNull);
      var told = 0;
      practice.addListener(() => told++);
      expect(await practice.turnOn(de), PracticeArmProblem.busy);
      expect(told, 1);
      await stopButton();
    });

    test(
      '#147: disposed, it lets the recording go and hears nothing more',
      () async {
        final other = PracticeRecording(
          app: app.controller,
          recording: recording,
        );
        await other.turnOn(de);
        await armed(1);
        other.dispose();
        expect(recording.reserved, isFalse);
        expect(() => other.addListener(() {}), throwsStateError);
        // the recording goes on telling its other listeners without error, nothing is armed anew
        await recording.stop();
        await Future<void>.delayed(Duration.zero);
        expect(rec.starts, 1);
      },
    );
  });

  group('recording controller', () {
    test('#147/AK11: reserving twice by the same owner holds, others are refused; listeners hear it', () {
      final owner = Object();
      var told = 0;
      recording.addListener(() => told++);
      expect(recording.reserve(owner), isTrue);
      expect(told, 1);
      expect(recording.reserve(owner), isTrue);
      expect(recording.reserve(Object()), isFalse);
      recording.release(Object()); // not the owner: nothing
      expect(recording.reserved, isTrue);
      expect(told, 1);
      recording.release(owner);
      expect(recording.reserved, isFalse);
      expect(told, 2);
    });

    test('#147/AK8: stopped before the ticker saw the sound, the take is still named by its start', () async {
      final slow = RecordingController(
        app: app.controller,
        recorder: rec,
        now: () => DateTime(2026, 11, 25, 12, 0, 10),
        tick: const Duration(hours: 1),
      );
      addTearDown(slow.dispose);
      expect(
        await slow.start(
          de,
          arming: const Arming(),
          naming: (t) => practiceTakeNaming(null, t),
          select: false,
        ),
        isNull,
      );
      rec
        ..keptSeconds = 4
        ..gate = WpRecGate.recording;
      await slow.stop();
      expect(app.library.tracks.single.title, '12:00:06');
      expect(slow.startedAt, DateTime(2026, 11, 25, 12, 0, 6));
    });

    test(
      '#147: a recording of the record button is still loaded and played',
      () async {
        expect(await recording.start(de, title: 'Button'), isNull);
        await stopButton();
        final t = app.library.tracks.single;
        expect(app.controller.player.trackId, t.id);
        expect(t.folderId, isNull);
      },
    );

    test('#147/AK7: freePath counts up past taken names', () {
      final base = '${tmp.path}/rec/Take';
      expect(RecordingController.freePath(base, 'flac'), '$base.flac');
      File('$base.flac').writeAsStringSync('a');
      expect(RecordingController.freePath(base, 'flac'), '$base 2.flac');
      File('$base 2.flac').writeAsStringSync('b');
      expect(RecordingController.freePath(base, 'flac'), '$base 3.flac');
    });
  });

  group('names', () {
    test('#147/AK8: «<Title> <HH:MM:SS>», or only the time', () {
      final t = DateTime(2026, 1, 2, 3, 4, 5);
      expect(practiceTakeNaming('Blues in F', t).title, 'Blues in F 03:04:05');
      expect(practiceTakeNaming(null, t).title, '03:04:05');
      expect(practiceTakeNaming('  ', t).title, '03:04:05');
      expect(practiceTakeNaming(' Waltz ', t).title, 'Waltz 03:04:05');
      expect(
        practiceTakeNaming(null, DateTime(2026, 12, 31, 23, 59, 59)).title,
        '23:59:59',
      );
    });

    test('#147/AK7: folders Recordings › YYYY-MM-DD', () {
      expect(practiceTakeNaming(null, DateTime(2026, 3, 4, 5)).folders, [
        'Recordings',
        '2026-03-04',
      ]);
      expect(dateStamp(DateTime(987, 10, 11)), '0987-10-11');
      expect(clockStamp(DateTime(2026, 1, 1, 13, 7, 9)), '13:07:09');
    });

    test(
      '#147/AK7: folderPath creates what is missing and uses what exists',
      () {
        final Library lib = app.library;
        expect(lib.folderPath(const []), isNull);
        final a = lib.folderPath(const ['Recordings', '2026-11-25'])!;
        expect(lib.folders, hasLength(2));
        expect(lib.folderPath(const ['Recordings', '2026-11-25']), a);
        expect(lib.folders, hasLength(2));
        final b = lib.folderPath(const ['Recordings', '2026-11-26'])!;
        expect(b, isNot(a));
        expect(lib.folders, hasLength(3));
        // a folder of the same name elsewhere is not the one
        final other = lib.createFolder('Other');
        lib.createFolder('2026-11-27', parentId: other.id);
        final c = lib.folderPath(const ['Recordings', '2026-11-27'])!;
        expect(
          lib.folders.firstWhere((f) => f.id == c).parentId,
          isNot(other.id),
        );
      },
    );
  });
}
