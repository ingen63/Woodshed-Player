// #140: command line of the desktop app, the app's side: finding the title to play, the armed
// recording (with a fake recorder and a temporary library) and the local socket the program talks to.
// Arguments, help and the program's side of the socket: core/tests/cli_tests.cpp.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:woodshed_player/app/command_line.dart';
import 'package:woodshed_player/app/command_server.dart';
import 'package:woodshed_player/app/recording_controller.dart';
import 'package:woodshed_player/library/track.dart';
import 'package:wp_core/wp_types.dart';

import 'fakes.dart';

final stamp = DateTime(2026, 11, 19, 14, 5, 9);

/// What the command would print.
class Lines implements CommandOutput {
  final stdout = <String>[];
  final stderr = <String>[];
  @override
  void out(String line) => stdout.add(line);
  @override
  void err(String line) => stderr.add(line);
}

void main() {
  late Directory tmp;
  late TestApp app;
  late FakeRecorder rec;
  late RecordingController recording;
  late CommandHandler handler;
  var files = 0;

  setUpAll(initializeDateFormatting);
  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('wp_cli_test');
    app = TestApp(Directory('${tmp.path}/lib'));
    await app.library.load();
    app.files.recordings = (Directory('${tmp.path}/rec')..createSync()).path;
    rec = FakeRecorder();
    recording = RecordingController(
      app: app.controller,
      recorder: rec,
      now: () => stamp,
      tick: const Duration(milliseconds: 1),
    );
    handler = CommandHandler(
      app: app.controller,
      recording: recording,
      texts: () => de,
    );
  });
  tearDown(() {
    recording.dispose();
    tmp.deleteSync(recursive: true);
  });

  /// A title in the library with [title] and [artist].
  Future<Track> add(String title, [String? artist]) async {
    final f = File('${tmp.path}/track${files++}.mp3')
      ..writeAsStringSync('audio $files $title $artist');
    final r = await app.library.importFiles([f.path]);
    final t = r.imported.single;
    expect(
      app.library.editMetadata(t.id, title: title, artist: artist),
      isTrue,
    );
    return app.library.track(t.id)!;
  }

  /// Runs [r] to its end, finishing the loads of the fake core on the way.
  Future<int> run(CommandRequest r, Lines o, [Future<void>? interrupt]) async {
    int? code;
    unawaited(
      handler
          .run(r, o, interrupt ?? Completer<void>().future)
          .then((c) => code = c),
    );
    await eventually(() {
      app.finishLoads();
      return code != null;
    }, 'command finished');
    return code!;
  }

  CommandRequest play(String title, [String? artist]) =>
      CommandRequest(command: 'play', title: title, artist: artist);

  group('play', () {
    test('#140/AK1: loads the matching title and plays it, upper and lower case do not count', () async {
      await add('Blue Bossa', 'Trio');
      final wanted = await add('Autumn Leaves', 'Quartet');
      final o = Lines();
      expect(await run(play('autumn LEAVES', 'QUARTET'), o), CliExit.ok);
      expect(app.player.trackId, wanted.id);
      expect(app.player.isPlaying, isTrue);
      expect(o.stdout, ['Playing "Autumn Leaves" by Quartet.']);
      expect(o.stderr, isEmpty);
    });

    test('#140/AK2: without --artist a unique title is enough', () async {
      await add('Blue Bossa', 'Trio');
      final wanted = await add('Solar');
      final o = Lines();
      expect(await run(play(' solar '), o), CliExit.ok);
      expect(app.player.trackId, wanted.id);
      expect(o.stdout, ['Playing "Solar".']);
    });

    test(
      '#140/AK3: no match is an error with exit code 1 and plays nothing',
      () async {
        await add('Blue Bossa', 'Trio');
        for (final (request, text) in [
          (play('Solar'), 'No title "Solar" in the library.'),
          (
            play('Blue Bossa', 'Quartet'),
            'No title "Blue Bossa" by Quartet in the library.',
          ),
          (
            play('Blue'),
            'No title "Blue" in the library.',
          ), // whole title, not a part
        ]) {
          final o = Lines();
          expect(await run(request, o), CliExit.failed);
          expect(o.stderr, [text]);
          expect(o.stdout, isEmpty);
          expect(app.player.trackId, isNull);
          expect(app.player.isPlaying, isFalse);
        }
      },
    );

    test('#140/AK4: several matches are listed with title and artist, exit code 1, nothing plays', () async {
      await add('Solar', 'Trio');
      await add('solar', 'Quartet');
      await add('Solar');
      await add('Nardis', 'Trio');
      final o = Lines();
      expect(await run(play('SOLAR'), o), CliExit.failed);
      expect(o.stderr.first, '3 titles match; add --artist to choose one:');
      expect(
        o.stderr.skip(1),
        unorderedEquals([
          '  "Solar" by Trio',
          '  "solar" by Quartet',
          '  "Solar"',
        ]),
      );
      expect(app.player.trackId, isNull);
      // With the artist it is unique again.
      final o2 = Lines();
      expect(await run(play('solar', 'trio'), o2), CliExit.ok);
    });

    test('#140/AK1: matching ignores case and spaces, an empty artist matches none', () {
      Track t(String title, String? artist) => Track(
        id: '$title $artist',
        fileName: 'f.mp3',
        originalFileName: 'f.mp3',
        title: title,
        artist: artist,
        duration: 1,
        hasArtwork: false,
        dateAdded: DateTime.utc(2026),
        customOrder: 0,
      );
      final tracks = [
        t('Solar', 'Trio'),
        t('Solar', null),
        t('Nardis', 'trio'),
      ];
      expect(matchingTracks(tracks, 'solar', null), hasLength(2));
      expect(matchingTracks(tracks, ' SOLAR ', ' trio '), [tracks[0]]);
      expect(matchingTracks(tracks, 'Solar', ''), [tracks[1]]);
      expect(matchingTracks(tracks, 'Sol', null), isEmpty);
      expect(describeTrack('A', null), '"A"');
      expect(describeTrack('A', ' '), '"A"');
      expect(describeTrack('A', 'B'), '"A" by B');
    });

    test('#140/AK1: play without a title is a usage error', () async {
      final o = Lines();
      expect(await run(play('  '), o), CliExit.usage);
      expect(o.stderr, ['play needs --title.']);
      final o2 = Lines();
      expect(
        await run(const CommandRequest(command: 'pause'), o2),
        CliExit.usage,
      );
      expect(o2.stderr, ['Unknown command "pause".']);
    });
  });

  group('record', () {
    CommandRequest record({
      String? title,
      String? artist,
      int? year,
      String? source,
      double? silence,
      double? threshold,
    }) => CommandRequest(
      command: 'record',
      title: title,
      artist: artist,
      year: year,
      source: source,
      silenceSeconds: silence,
      thresholdDb: threshold,
    );

    /// Starts [r]; returns the future exit code once the recording is armed.
    Future<Future<int>> arm(
      CommandRequest r,
      Lines o, [
      Future<void>? interrupt,
    ]) async {
      final code = handler.run(r, o, interrupt ?? Completer<void>().future);
      await eventually(
        () => o.stdout.isNotEmpty || o.stderr.isNotEmpty,
        'armed or refused',
      );
      return code;
    }

    Future<int> finish(Future<int> code) async {
      int? result;
      unawaited(code.then((c) => result = c));
      await eventually(() {
        app.finishLoads();
        return result != null;
      }, 'recording finished');
      return result!;
    }

    test('#140/AK5, AK7, AK8, AK9, AK12, AK13: armed, then recording, then saved as a new title '
        'with title and artist; the command prints title and length and ends with 0', () async {
      final o = Lines();
      final code = await arm(record(title: 'Take 1', artist: 'Me'), o);
      // AK5: the command reports «armed», the shared state says so too (the button shows it)
      expect(o.stdout, [
        'Armed: waiting for sound from the system audio (threshold -50 dBFS, ends after 5 s '
            'of silence). Ctrl-C cancels.',
      ]);
      expect(recording.phase, RecordingPhase.armed);
      // AK7: armed with the default threshold and pause of the core
      expect(rec.arming, (thresholdDb: -50.0, silenceSeconds: 5.0));
      expect(rec.recording, isTrue);
      // AK8: sound came, the core keeps from 1 s before it
      rec
        ..gate = WpRecGate.recording
        ..keptSeconds = 3;
      await eventually(() => o.stdout.length == 2, 'recording reported');
      expect(o.stdout[1], 'Recording. Ctrl-C stops and saves.');
      expect(recording.phase, RecordingPhase.recording);
      expect(recording.seconds, 3);
      // AK9: the core reports the end after the pause; the app stops and saves it
      rec
        ..gate = WpRecGate.done
        ..keptSeconds = 12;
      expect(await finish(code), CliExit.ok);
      expect(rec.recording, isFalse);
      expect(recording.phase, RecordingPhase.idle);
      // AK12, AK13
      final t = app.library.tracks.single;
      expect(t.title, 'Take 1');
      expect(t.artist, 'Me');
      expect(t.fileName, endsWith('.flac'));
      expect(
        o.stdout.last,
        'Saved "Take 1" by Me, 00:30.',
      ); // the fake probe says 30 s
      expect(o.stderr, isEmpty);
      // The command no longer listens: a later recording prints nothing here.
      final lines = o.stdout.length;
      expect(await recording.start(de, arming: const Arming()), isNull);
      rec.gate = WpRecGate.recording;
      await eventually(
        () => recording.phase == RecordingPhase.recording,
        'next recording',
      );
      expect(o.stdout, hasLength(lines));
      rec.gate = WpRecGate.armed;
      await eventually(
        () => recording.phase == RecordingPhase.armed,
        'armed again',
      );
      await recording.stop();
    });

    test('#140/AK12: without --title the recording is named after date and time as before', () async {
      final o = Lines();
      final code = await arm(record(), o);
      expect(rec.path, endsWith('Aufnahme 2026-11-19 14.05.09.flac'));
      rec.gate = WpRecGate.done;
      expect(await finish(code), CliExit.ok);
      final t = app.library.tracks.single;
      expect(t.title, 'Aufnahme 19.11.2026 14:05:09');
      expect(t.artist, isNull);
      expect(o.stdout.last, 'Saved "Aufnahme 19.11.2026 14:05:09", 00:30.');
    });

    test(
      '#140/AK12a: --year goes into the metadata of the new title',
      () async {
        final o = Lines();
        final code = await arm(
          record(title: 'Take', artist: 'Me', year: 1937),
          o,
        );
        rec.gate = WpRecGate.done;
        expect(await finish(code), CliExit.ok);
        final t = app.library.tracks.single;
        expect(t.title, 'Take');
        expect(t.artist, 'Me');
        expect(t.year, 1937);
      },
    );

    test('#140/AK12a: without --year the year stays empty', () async {
      final code = await arm(record(title: 'Take'), Lines());
      rec.gate = WpRecGate.done;
      expect(await finish(code), CliExit.ok);
      expect(app.library.tracks.single.year, isNull);
    });

    test(
      '#140/AK12a: a year that is not four digits is refused before recording',
      () async {
        for (final year in [0, -1937, 10000]) {
          final o = Lines();
          expect(await run(record(year: year), o), CliExit.usage);
          expect(o.stderr.single, 'The year must have four digits, e.g. 1937.');
          expect(o.stdout, isEmpty);
        }
        expect(rec.path, isNull);
        expect(app.library.tracks, isEmpty);
        // the limits themselves are allowed
        for (final year in [1, 9999]) {
          final code = await arm(record(title: 'Y$year', year: year), Lines());
          rec.gate = WpRecGate.done;
          expect(await finish(code), CliExit.ok);
        }
        expect([for (final t in app.library.tracks) t.year], [1, 9999]);
      },
    );

    test(
      '#140/AK6: --source chooses, otherwise the source last chosen in the app',
      () async {
        await app.library.setRecordingSource(WpRecSource.microphone.name);
        var o = Lines();
        var code = await arm(record(), o);
        expect(rec.source, WpRecSource.microphone);
        expect(o.stdout.single, contains('from the microphone'));
        expect(app.files.microphoneAsked, 1);
        rec.gate = WpRecGate.done;
        expect(await finish(code), CliExit.ok);

        o = Lines();
        code = await arm(record(source: 'system'), o);
        expect(rec.source, WpRecSource.system);
        expect(o.stdout.single, contains('from the system audio'));
        rec.gate = WpRecGate.done;
        expect(await finish(code), CliExit.ok);
        // --source does not change the choice of the app
        expect(app.library.recordingSource, WpRecSource.microphone.name);

        o = Lines();
        code = await arm(record(source: 'mic'), o);
        expect(rec.source, WpRecSource.microphone);
        rec.gate = WpRecGate.done;
        expect(await finish(code), CliExit.ok);
      },
    );

    test('#140/AK6: an unknown or unavailable source is refused', () async {
      final o = Lines();
      expect(await run(record(source: 'line'), o), CliExit.usage);
      expect(o.stderr, ['The source "line" cannot record here.']);
      rec.sources = {WpRecSource.microphone};
      final o2 = Lines();
      expect(await run(record(source: 'system'), o2), CliExit.failed);
      expect(o2.stderr, ['The source "system" cannot record here.']);
      expect(rec.recording, isFalse);
    });

    test('#140/AK11: --silence and --threshold reach the core', () async {
      final o = Lines();
      final code = await arm(record(silence: 2.5, threshold: -40), o);
      expect(rec.arming, (thresholdDb: -40.0, silenceSeconds: 2.5));
      expect(
        o.stdout.single,
        contains('(threshold -40 dBFS, ends after 2.5 s of silence)'),
      );
      rec.gate = WpRecGate.done;
      expect(await finish(code), CliExit.ok);
    });

    test(
      '#140/AK11: settings out of range are refused before recording',
      () async {
        for (final (silence, threshold) in [
          (0.09, -50.0),
          (60.1, -50.0),
          (5.0, -120.1),
          (5.0, 0.1),
        ]) {
          final o = Lines();
          expect(
            await run(record(silence: silence, threshold: threshold), o),
            CliExit.usage,
          );
          expect(
            o.stderr.single,
            'The threshold must be -120 to 0 dBFS, the pause 0.1 to 60 s.',
          );
        }
        expect(rec.path, isNull);
        // the limits themselves are allowed
        final o = Lines();
        final code = await arm(record(silence: 0.1, threshold: -120), o);
        rec.gate = WpRecGate.done;
        expect(await finish(code), CliExit.ok);
        final o2 = Lines();
        final code2 = await arm(record(silence: 60, threshold: 0), o2);
        rec.gate = WpRecGate.done;
        expect(await finish(code2), CliExit.ok);
      },
    );

    test(
      '#140/AK14: Ctrl-C while armed cancels: no title, no file, exit code 130',
      () async {
        final o = Lines();
        final interrupt = Completer<void>();
        final code = await arm(record(title: 'Nothing'), o, interrupt.future);
        final path = rec.path!;
        expect(File(path).existsSync(), isTrue);
        interrupt.complete();
        expect(await finish(code), CliExit.cancelled);
        expect(o.stderr, ['Cancelled, nothing was recorded.']);
        expect(rec.recording, isFalse);
        expect(app.library.tracks, isEmpty);
        expect(File(path).existsSync(), isFalse);
        expect(recording.phase, RecordingPhase.idle);
      },
    );

    test(
      '#140/AK14: Ctrl-C while recording stops and saves like a stop',
      () async {
        final o = Lines();
        final interrupt = Completer<void>();
        final code = await arm(record(title: 'Kept'), o, interrupt.future);
        rec.gate = WpRecGate.recording;
        await eventually(() => o.stdout.length == 2, 'recording reported');
        interrupt.complete();
        expect(await finish(code), CliExit.ok);
        expect(app.library.tracks.single.title, 'Kept');
        expect(o.stdout.last, 'Saved "Kept", 00:30.');
      },
    );

    test('#140/AK14: Ctrl-C before the recording is armed cancels it as soon as it is', () async {
      final o = Lines();
      final interrupt = Completer<void>()..complete();
      expect(
        await finish(handler.run(record(), o, interrupt.future)),
        CliExit.cancelled,
      );
      expect(app.library.tracks, isEmpty);
    });

    test('#140/AK15: refused microphone names the place in System Settings, exit code 1', () async {
      app.files.microphoneGranted = false;
      final o = Lines();
      expect(await run(record(source: 'mic'), o), CliExit.failed);
      expect(
        o.stderr.single,
        contains('System Settings > Privacy & Security > Microphone'),
      );
      expect(o.stdout, isEmpty);
      expect(rec.recording, isFalse);
      expect(app.library.tracks, isEmpty);
    });

    test('#140/AK15: only digital silence while armed names the place of the system audio permission', () async {
      final o = Lines();
      final interrupt = Completer<void>();
      final code = await arm(record(), o, interrupt.future);
      rec
        ..seconds = 4
        ..onlySilence = true;
      await eventually(() => o.stderr.isNotEmpty, 'silence reported');
      expect(
        o.stderr.single,
        'Only silence so far. If something is playing, allow Woodshed Player in '
        'System Settings > Privacy & Security > Screen & System Audio Recording.',
      );
      // only once, over many ticks of 1 ms
      const ticks = Duration(milliseconds: 20);
      await Future<void>.delayed(ticks); // absence: no second hint
      expect(o.stderr, hasLength(1));
      interrupt.complete();
      expect(await finish(code), CliExit.cancelled);
    });

    test('#140/AK15: only silence from the microphone points to its input and permission', () async {
      final o = Lines();
      final interrupt = Completer<void>();
      final code = await arm(record(source: 'mic'), o, interrupt.future);
      rec
        ..seconds = 4
        ..onlySilence = true;
      await eventually(() => o.stderr.isNotEmpty, 'silence reported');
      expect(o.stderr.single, contains('System Settings > Sound > Input'));
      expect(o.stderr.single, contains('Privacy & Security > Microphone'));
      interrupt.complete();
      expect(await finish(code), CliExit.cancelled);
    });

    test(
      '#140/AK17: a running recording refuses record with a message',
      () async {
        final o = Lines();
        final interrupt = Completer<void>();
        final code = await arm(record(title: 'First'), o, interrupt.future);
        final o2 = Lines();
        expect(await run(record(title: 'Second'), o2), CliExit.failed);
        expect(o2.stderr, ['A recording is already running.']);
        // also one started with the button
        interrupt.complete();
        expect(await finish(code), CliExit.cancelled);
        expect(await recording.start(de), isNull);
        final o3 = Lines();
        expect(await run(record(), o3), CliExit.failed);
        expect(o3.stderr, ['A recording is already running.']);
        var stopped = false;
        unawaited(recording.stop().then((_) => stopped = true));
        await eventually(() {
          app.finishLoads();
          return stopped;
        }, 'stopped');
      },
    );

    test(
      '#140: a failed start of the core is reported with exit code 1',
      () async {
        rec.failWith = const WpRecordingException(
          WpRecCode.noInput,
          0,
          'No input device',
        );
        final o = Lines();
        expect(await run(record(source: 'mic'), o), CliExit.failed);
        expect(o.stderr, [
          'Recording not possible: No input device (code -11).',
        ]);
        expect(recording.busy, isFalse);
      },
    );

    test(
      '#140: without a recordings folder or without recording there is none',
      () async {
        app.files.recordings = null;
        final o = Lines();
        expect(await run(record(), o), CliExit.failed);
        expect(o.stderr, ['There is no folder for recordings.']);
        final none = CommandHandler(app: app.controller, texts: () => de);
        final o2 = Lines();
        expect(
          await none.run(record(), o2, Completer<void>().future),
          CliExit.failed,
        );
        expect(o2.stderr, ['Recording is not available on this platform.']);
      },
    );
  });

  group('request', () {
    test('#140: the JSON of the program becomes a request', () {
      final r = CommandRequest.fromJson(
        jsonDecode(
          '{"version":1,"command":"record","title":"T","artist":"A","source":"mic",'
          '"silence":3,"threshold":-40.5,"year":1937}',
        ),
      )!;
      expect(r.year, 1937);
      expect(r.command, 'record');
      expect(r.title, 'T');
      expect(r.artist, 'A');
      expect(r.source, 'mic');
      expect(r.silenceSeconds, 3.0);
      expect(r.thresholdDb, -40.5);
      final p = CommandRequest.fromJson({'version': 1, 'command': 'play'})!;
      expect(p.title, isNull);
      expect(p.silenceSeconds, isNull);
      expect(p.year, isNull);
    });

    test(
      '#140: requests of another version or with wrong types are refused',
      () {
        for (final json in <Object?>[
          null,
          'play',
          <String, Object?>{'command': 'play'},
          <String, Object?>{'version': 2, 'command': 'play'},
          <String, Object?>{'version': 1},
          <String, Object?>{'version': 1, 'command': 3},
          <String, Object?>{'version': 1, 'command': 'play', 'title': 3},
          <String, Object?>{'version': 1, 'command': 'play', 'artist': 3},
          <String, Object?>{'version': 1, 'command': 'record', 'source': 1},
          <String, Object?>{'version': 1, 'command': 'record', 'year': '1937'},
          <String, Object?>{'version': 1, 'command': 'record', 'year': 1937.5},
          <String, Object?>{'version': 1, 'command': 'record', 'silence': '3'},
          <String, Object?>{
            'version': 1,
            'command': 'record',
            'threshold': '3',
          },
        ]) {
          expect(CommandRequest.fromJson(json), isNull, reason: '$json');
        }
        expect(cliSource('system'), WpRecSource.system);
        expect(cliSource('mic'), WpRecSource.microphone);
        expect(cliSource('microphone'), isNull);
      },
    );
  });

  group('socket', () {
    late String path;
    CommandServer? server;
    setUp(() {
      // short: a socket path holds at most 103 bytes, the temp folder of macOS is long
      path =
          '/tmp/wp_cli_${pid}_${DateTime.now().microsecondsSinceEpoch % 1000000}.sock';
    });
    tearDown(() async {
      await server?.close();
      server = null;
    });

    /// One call of the program: sends [lines], returns what the app answers until it closes.
    Future<List<String>> call(
      List<String> lines, {
      FutureOr<void> Function(List<String> got, Socket s)? onLine,
    }) async {
      final s = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
      for (final l in lines) {
        s.write('$l\n');
      }
      final got = <String>[];
      await for (final l
          in s
              .cast<List<int>>()
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        got.add(l);
        await onLine?.call(got, s);
      }
      s.destroy();
      return got;
    }

    test('#140/AK1, AK3, AK19: a request over the local socket is answered line by line', () async {
      server = await CommandServer.start(path, handler);
      expect(server, isNotNull);
      expect(
        FileSystemEntity.typeSync(path),
        FileSystemEntityType.unixDomainSock,
      );
      final got = await call([
        '{"version":1,"command":"play","title":"Solar","artist":"Trio"}',
      ]);
      expect(got, ['err No title "Solar" by Trio in the library.', 'exit 1']);
      await add('Solar', 'Trio');
      final played = call(['{"version":1,"command":"play","title":"solar"}']);
      await eventually(() {
        app.finishLoads();
        return app.player.isPlaying;
      }, 'playing');
      expect(await played, ['out Playing "Solar" by Trio.', 'exit 0']);
    });

    test('#140/AK14: the line «stop» is Ctrl-C, other lines are not', () async {
      server = await CommandServer.start(path, handler);
      final got = await call(
        ['{"version":1,"command":"record","title":"T"}'],
        onLine: (got, s) async {
          if (got.length != 1) return;
          s.write('hello\n');
          await s.flush();
          const ticks = Duration(milliseconds: 50);
          // «hello» must not stop it
          await Future<void>.delayed(ticks); // absence: no stop
          expect(recording.phase, RecordingPhase.armed);
          s.write(' stop \n');
        },
      );
      expect(got.first, startsWith('out Armed:'));
      expect(got.skip(1), ['err Cancelled, nothing was recorded.', 'exit 130']);
      expect(app.library.tracks, isEmpty);
    });

    test(
      '#140/AK14: a program that goes away (closed terminal) counts as Ctrl-C',
      () async {
        server = await CommandServer.start(path, handler);
        final s = await Socket.connect(
          InternetAddress(path, type: InternetAddressType.unix),
          0,
        );
        s.write('{"version":1,"command":"record"}\n');
        await eventually(
          () => recording.phase == RecordingPhase.armed,
          'armed',
        );
        s.destroy();
        await eventually(
          () => recording.phase == RecordingPhase.idle,
          'cancelled',
        );
        expect(app.library.tracks, isEmpty);
      },
    );

    test('#140: a request the app does not understand ends with a message and code 2', () async {
      server = await CommandServer.start(path, handler);
      expect(await call(['not json']), [
        'err The app did not understand the request; are the app and the command the same version?',
        'exit 2',
      ]);
      expect(await call(['{"version":9,"command":"play"}']), hasLength(2));
      // a program that sends nothing and closes
      final s = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
      await s.close();
      s.destroy();
    });

    test('#140: messages with line breaks become several lines', () async {
      server = await CommandServer.start(path, handler);
      await add('Solar', 'Trio');
      await add('Solar', 'Quartet');
      final got = await call([
        '{"version":1,"command":"play","title":"Solar"}',
      ]);
      expect(got.first, 'err 2 titles match; add --artist to choose one:');
      expect(got, hasLength(4));
      expect(got.last, 'exit 1');
    });

    test(
      '#140/AK16: a socket file left by an earlier run is replaced',
      () async {
        // A crashed app leaves its socket file behind (a process that ends without removing it).
        final r = Process.runSync('python3', [
          '-c',
          'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])',
          path,
        ]);
        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(
          FileSystemEntity.typeSync(path),
          FileSystemEntityType.unixDomainSock,
        );
        server = await CommandServer.start(path, handler);
        expect(server, isNotNull);
        expect(
          await call(['{"version":1,"command":"play","title":"x"}']),
          hasLength(2),
        );
        await server!.close();
        server = null;
        expect(FileSystemEntity.typeSync(path), FileSystemEntityType.notFound);
      },
    );

    test(
      '#140: no socket where the path is too long or taken by a file',
      () async {
        final long = '/tmp/${'x' * 120}.sock';
        expect(await CommandServer.start(long, handler), isNull);
        // 103 bytes is the longest path that fits, 104 does not
        final stem = '/tmp/wp${pid}_${DateTime.now().microsecondsSinceEpoch}';
        final fits = '$stem${'x' * (maxSocketPath - 5 - stem.length)}.sock';
        expect(fits.length, maxSocketPath);
        server = await CommandServer.start(fits, handler);
        expect(server, isNotNull);
        await server!.close();
        server = null;
        expect(await CommandServer.start('${fits}x', handler), isNull);
        File(path).writeAsStringSync('not a socket');
        expect(await CommandServer.start(path, handler), isNull);
        expect(File(path).readAsStringSync(), 'not a socket'); // never deleted
        File(path).deleteSync();
        expect(maxSocketPath, 103);
      },
    );
  });
}
