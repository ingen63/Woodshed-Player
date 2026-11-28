// #162: the recording of Windows and Linux on the Dart side, with a fake recorder and a temporary
// library: a microphone the system refuses (WP_REC_ERR_ACCESS_DENIED) gives the hint of the setting and
// leaves nothing behind, the hints and the help name the settings of Windows and Linux, and the check of
// the smoke test reads the bit depth of a FLAC file. The core itself is tested with its artificial input
// (core/tests/recorder_desktop_tests.cpp); the built app in CI with tools/smoke_app.sh <app> record.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:woodshed_player/app/practice_recording.dart';
import 'package:woodshed_player/app/recording_controller.dart';
import 'package:woodshed_player/app/recording_smoke.dart';
import 'package:woodshed_player/ui/armed_switch.dart';
import 'package:woodshed_player/ui/help_page.dart';
import 'package:woodshed_player/ui/messages.dart';
import 'package:wp_core/wp_types.dart';

import 'fakes.dart';

/// Like the core when the device refuses access after the file was created: the file is there, then
/// the start fails.
class _RefusingRecorder extends FakeRecorder {
  int refused = 0;

  @override
  void start(String path, WpRecSource source) {
    File(path).writeAsStringSync('');
    refused++;
    throw const WpRecordingException(
      WpRecCode.accessDenied,
      0,
      'The system refuses access to the microphone',
    );
  }
}

/// The STREAMINFO of a FLAC file with [bits] bits per sample, stereo, 48 kHz.
Uint8List flacHeader(int bits) {
  final b = Uint8List(42);
  b.setAll(0, 'fLaC'.codeUnits);
  b[4] = 0x80; // last metadata block, type 0 (STREAMINFO)
  b[7] = 34;
  // 48000 Hz = 0x0BB80 in 20 bits, 2 channels (1 in 3 bits), bits - 1 in 5 bits
  b[18] = 0x0B;
  b[19] = 0xB8;
  b[20] = 0x00 | (1 << 1) | ((bits - 1) >> 4);
  b[21] = ((bits - 1) & 0x0f) << 4;
  return b;
}

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final de = lookupAppLocalizations(const Locale('de'));

  group('#162/AK3: the system refuses the microphone', () {
    late Directory tmp;
    late TestApp app;
    late _RefusingRecorder rec;
    late RecordingController recording;
    late PracticeRecording practice;

    setUpAll(initializeDateFormatting);
    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('wp_rec_desktop_test');
      app = TestApp(Directory('${tmp.path}/lib'));
      await app.library.load();
      app.files.recordings = (Directory('${tmp.path}/rec')..createSync()).path;
      rec = _RefusingRecorder();
      recording = RecordingController(
        app: app.controller,
        recorder: rec,
        now: () => DateTime(2026, 11, 28, 10, 0, 0),
        tick: const Duration(milliseconds: 1),
      );
      practice = PracticeRecording(app: app.controller, recording: recording);
    });
    tearDown(() {
      practice.dispose();
      recording.dispose();
      tmp.deleteSync(recursive: true);
    });

    test(
      'the record button: nothing starts, the hint of the setting',
      () async {
        var told = 0;
        recording.addListener(() => told++);
        final logged = <String?>[];
        final print = debugPrint;
        debugPrint = (m, {wrapWidth}) => logged.add(m);
        final RecordingOutcome? outcome;
        try {
          outcome = await recording.start(de, source: WpRecSource.microphone);
        } finally {
          debugPrint = print;
        }
        expect(outcome, isA<RecordingMicrophoneDenied>());
        expect(rec.refused, 1);
        expect(logged.single, contains('WpRecordingException(-13)'));
        expect(recording.microphoneDenied, isTrue);
        expect(told, 1, reason: 'the button hears of the hint');
        expect(recording.error, isNull);
        expect(recording.busy, isFalse);
        expect(recording.phase, RecordingPhase.idle);
        // the file of the failed start is gone, no title came
        expect(Directory(app.files.recordings!).listSync(), isEmpty);
        expect(app.library.tracks, isEmpty);
        // choosing the source again clears the hint
        recording.choose(WpRecSource.microphone);
        expect(recording.microphoneDenied, isFalse);
      },
    );

    test('«Armed»: off again with its own hint', () async {
      final print = debugPrint;
      debugPrint = (m, {wrapWidth}) {};
      final PracticeArmProblem? problem;
      try {
        problem = await practice.turnOn(de);
      } finally {
        debugPrint = print;
      }
      expect(problem, PracticeArmProblem.microphoneDenied);
      expect(practice.on, isFalse);
      // #147/AK12: «Armed» gives the hint, the record button stays without one
      expect(recording.microphoneDenied, isFalse);
      expect(recording.reserved, isFalse);
      expect(Directory(app.files.recordings!).listSync(), isEmpty);
    });

    test('other errors of the core stay errors', () async {
      final fake = FakeRecorder()
        ..failWith = const WpRecordingException(WpRecCode.noInput, 0, 'x');
      final other = RecordingController(app: app.controller, recorder: fake);
      addTearDown(other.dispose);
      final print = debugPrint;
      debugPrint = (m, {wrapWidth}) {};
      final RecordingOutcome? outcome;
      try {
        outcome = await other.start(de, source: WpRecSource.microphone);
      } finally {
        debugPrint = print;
      }
      expect(outcome, isA<RecordingFailed>());
      expect(other.microphoneDenied, isFalse);
      expect(other.error?.code, WpRecCode.noInput);
    });
  });

  group('#162/AK3: the hints name the setting of the system', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('Windows: Settings › Privacy & security › Microphone', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(micSystem, MicSystem.windows);
      for (final armed in [false, true]) {
        expect(
          microphoneDeniedMessage(en, armed: armed),
          contains('Settings › Privacy & security › Microphone'),
        );
        expect(
          microphoneDeniedMessage(en, armed: armed),
          contains('Let desktop apps access your microphone'),
        );
        expect(
          microphoneDeniedMessage(de, armed: armed),
          contains('Einstellungen › Datenschutz und Sicherheit › Mikrofon'),
        );
      }
      expect(microphoneDeniedMessage(en), en.recordingMicrophoneDeniedWindows);
      expect(
        microphoneDeniedMessage(en, armed: true),
        en.armedMicrophoneDeniedWindows,
      );
      expect(microphoneSilentMessage(en), en.recordingMicrophoneSilentWindows);
      expect(microphoneSilentMessage(de), contains('System › Sound › Eingabe'));
    });

    test('Linux: the sound settings of the system', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(micSystem, MicSystem.linux);
      expect(microphoneDeniedMessage(en), en.recordingMicrophoneDeniedLinux);
      expect(
        microphoneDeniedMessage(de, armed: true),
        de.armedMicrophoneDeniedLinux,
      );
      expect(microphoneSilentMessage(en), en.recordingMicrophoneSilentLinux);
      for (final text in [
        en.recordingMicrophoneDeniedLinux,
        en.armedMicrophoneDeniedLinux,
        en.recordingMicrophoneSilentLinux,
      ]) {
        expect(text, contains('sound settings of the system'));
        expect(text, isNot(contains('System Settings')));
      }
    });

    test('macOS keeps its texts', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(micSystem, MicSystem.mac);
      expect(microphoneDeniedMessage(en), en.recordingMicrophoneDenied);
      expect(
        microphoneDeniedMessage(en, armed: true),
        en.armedMicrophoneDenied,
      );
      expect(microphoneSilentMessage(en), en.recordingMicrophoneSilent);
    });

    test('the switch «Armed» uses them', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final practice = PracticeRecording(
        app: TestApp(Directory.systemTemp).controller,
        recording: RecordingController(
          app: TestApp(Directory.systemTemp).controller,
          recorder: FakeRecorder(),
        ),
      );
      expect(
        armedProblemMessage(de, PracticeArmProblem.microphoneDenied, practice),
        de.armedMicrophoneDeniedWindows,
      );
    });

    test('every new text differs from the others and in each language', () {
      for (final l in [en, de]) {
        final texts = {
          l.recordingMicrophoneDenied,
          l.recordingMicrophoneDeniedWindows,
          l.recordingMicrophoneDeniedLinux,
          l.armedMicrophoneDenied,
          l.armedMicrophoneDeniedWindows,
          l.armedMicrophoneDeniedLinux,
          l.recordingMicrophoneSilent,
          l.recordingMicrophoneSilentWindows,
          l.recordingMicrophoneSilentLinux,
          l.helpRecordingBody,
          l.helpRecordingBodyDesktop,
        };
        expect(texts.length, 11, reason: l.localeName);
      }
      expect(
        en.recordingErrorAccessDenied,
        isNot(de.recordingErrorAccessDenied),
      );
      expect(
        recordingErrorMessage(
          en,
          const WpRecordingException(WpRecCode.accessDenied, 0, 'log'),
        ),
        en.recordingErrorAccessDenied,
      );
    });
  });

  group('#162/AK5: help', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('Windows and Linux: the microphone, no system audio', () {
      for (final p in [TargetPlatform.windows, TargetPlatform.linux]) {
        debugDefaultTargetPlatformOverride = p;
        final body = helpSectionBody(en, HelpSection.recording);
        expect(body, en.helpRecordingBodyDesktop);
        expect(body, isNot(contains('macOS')));
        expect(body, contains('Recordings › date'));
        expect(body, contains('Privacy & security › Microphone'));
      }
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(helpSectionBody(en, HelpSection.recording), en.helpRecordingBody);
    });
  });

  group('#162/AK4: the check of the smoke test', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('wp_flac_bits'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('reads the bits per sample of a FLAC file', () {
      for (final bits in [16, 24, 32]) {
        final f = File('${tmp.path}/$bits.flac')
          ..writeAsBytesSync(flacHeader(bits));
        expect(flacBits(f.path), bits);
      }
    });

    test('null for what is no FLAC file', () {
      expect(flacBits('${tmp.path}/missing.flac'), isNull);
      final short = File('${tmp.path}/short.flac')
        ..writeAsBytesSync(flacHeader(24).sublist(0, 21));
      expect(flacBits(short.path), isNull);
      final wav = File('${tmp.path}/x.wav')
        ..writeAsBytesSync([...'RIFF'.codeUnits, ...List.filled(40, 0)]);
      expect(flacBits(wav.path), isNull);
      // the first block is not STREAMINFO
      final other = flacHeader(24)..[4] = 0x84;
      final f = File('${tmp.path}/other.flac')..writeAsBytesSync(other);
      expect(flacBits(f.path), isNull);
    });
  });
}
