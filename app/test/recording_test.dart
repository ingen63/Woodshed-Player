// #4: recording of the system audio on the Mac, with a fake recorder and a temporary library.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/ui/messages.dart';
import 'package:woodshed_player/ui/recording_button.dart';
import 'package:woodshed_player/ui/style.dart';
import 'package:wp_core/wp_types.dart';

import 'fakes.dart';

/// Recorder without the core: writes a file on start, values are set by the test.
class FakeRecorder implements Recorder {
  String? path;
  bool recording = false;
  WpRecordingException? failWith;
  @override
  double seconds = 0;
  @override
  double level = 0;
  @override
  bool onlySilence = false;

  @override
  void start(String wavPath) {
    final e = failWith;
    if (e != null) throw e;
    path = wavPath;
    File(wavPath).writeAsStringSync('recorded audio');
    recording = true;
  }

  @override
  void stop() => recording = false;
  @override
  bool get isRecording => recording;
}

final stamp = DateTime(2026, 11, 19, 14, 5, 9);

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('wp_rec_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<(TestApp, FakeRecorder)> pump(
    WidgetTester tester, {
    Locale locale = testLocale,
  }) async {
    final app = TestApp(Directory('${tmp.path}/lib'));
    final rec = FakeRecorder();
    app.files.recordings = (Directory('${tmp.path}/rec')..createSync()).path;
    await tester.runAsync(app.library.load);
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: testDelegates,
        supportedLocales: testLocales,
        theme: woodshedTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: RecordingButton(
              controller: app.controller,
              recorder: rec,
              now: () => stamp,
            ),
          ),
        ),
      ),
    );
    return (app, rec);
  }

  Future<void> tapRecord(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('recordingButton')).last);
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    '#4/AK1: start and stop by button, duration and level visible while recording',
    (tester) async {
      final (_, rec) = await pump(tester);
      expect(find.byKey(const Key('recordingDuration')), findsNothing);
      expect(find.byKey(const Key('recordingLevel')), findsNothing);

      await tapRecord(tester);
      expect(rec.recording, isTrue);
      rec
        ..seconds = 75
        ..level = 0.6;
      await pumpUntil(
        tester,
        () => find.text('01:15').evaluate().isNotEmpty,
        'duration shown',
      );
      expect(find.text('01:15'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const Key('recordingLevel')),
      );
      expect(bar.value, closeTo(0.6, 1e-9));

      await tester.runAsync(() async => tapRecord(tester));
      expect(rec.recording, isFalse);
      expect(find.byKey(const Key('recordingDuration')), findsNothing);
    },
  );

  testWidgets(
    '#4/AK3: silence (permission denied) explains where to grant it',
    (tester) async {
      final (_, rec) = await pump(tester);
      await tapRecord(tester);
      rec
        ..seconds = 4
        ..onlySilence = true;
      final problem = find.byKey(const Key('recordingProblem'));
      await pumpUntil(
        tester,
        () => problem.evaluate().isNotEmpty,
        'silence reported',
      );
      await tester.tap(problem);
      await tester.pumpAndSettle();
      expect(find.text(de.recordingSilent), findsOneWidget);
      expect(
        de.recordingSilent,
        contains(
          'Datenschutz & Sicherheit › Bildschirm- & Systemaudioaufnahme',
        ),
      );
      final en = lookupAppLocalizations(const Locale('en'));
      expect(
        en.recordingSilent,
        contains('Privacy & Security › Screen & System Audio Recording'),
      );
      await tester.tap(find.text(de.ok));
      await tester.pumpAndSettle();
      rec.recording = false;
    },
  );

  testWidgets(
    '#4/AK3: a refused start shows the error of the core instead of recording',
    (tester) async {
      final (_, rec) = await pump(tester);
      const error = WpRecordingException(WpRecCode.tap, -1, 'log');
      rec.failWith = error;
      // #62: the refused start is logged; captured here instead of printed into the test output.
      final logged = <String?>[];
      final print = debugPrint;
      debugPrint = (m, {wrapWidth}) => logged.add(m);
      try {
        await tapRecord(tester);
      } finally {
        debugPrint = print;
      }
      expect(logged, [error.toString()]);
      expect(rec.recording, isFalse);
      expect(find.byKey(const Key('recordingDuration')), findsNothing);
      final problem = tester.widget<IconButton>(
        find.byKey(const Key('recordingProblem')),
      );
      expect(
        problem.tooltip,
        de.recordingFailed(recordingErrorMessage(de, error)),
      );
    },
  );

  testWidgets(
    '#4/AK4: after stopping the recording is a new title named after date and time',
    (tester) async {
      final (app, rec) = await pump(tester);
      await tapRecord(tester);
      expect(rec.path, endsWith('Aufnahme 2026-11-19 14.05.09.wav'));
      await tester.runAsync(() => tapRecord(tester));
      await waitUntil(
        tester,
        () => app.library.tracks.isNotEmpty,
        'recording in the library',
      );
      final t = app.library.tracks.single;
      expect(t.title, 'Aufnahme 19.11.2026 14:05:09');
      // Renamable like any title (#24).
      expect(app.library.editMetadata(t.id, title: 'Etüde'), isTrue);
      expect(app.library.track(t.id)!.title, 'Etüde');
    },
  );

  test('#4/AK4: the title follows the locale', () async {
    await initializeDateFormatting();
    final en = lookupAppLocalizations(const Locale('en'));
    expect(recordingTitle(de, stamp), 'Aufnahme 19.11.2026 14:05:09');
    expect(recordingTitle(en, stamp), 'Recording 11/19/2026 2:05:09 PM');
  });

  test(
    '#4/AK4: a recording plays with tempo and loop like any title',
    () async {
      final app = TestApp(Directory('${tmp.path}/lib'));
      await app.library.load();
      final wav = File('${tmp.path}/Recording.wav')..writeAsStringSync('wav');
      var finished = false;
      final added = app.controller
          .addRecording(wav.path, title: 'Aufnahme 1')
          .whenComplete(() => finished = true);
      // #78/AK1: wait for states, a time limit only against a hang
      await eventually(
        () => app.core.loadState == WpCode.loadRunning,
        'recording is loading',
      );
      await eventually(() {
        app.finishLoads(30);
        return finished;
      }, 'recording added');
      await added;
      expect(app.player.title, 'Aufnahme 1');
      app.player
        ..setSpeedEnabled(true)
        ..setSpeed(0.5)
        ..setLoopStart(2)
        ..setLoopEnd(6)
        ..setLoopEnabled(true);
      expect(app.core.rateValue, closeTo(0.5, 1e-9));
      expect(app.core.loop, (2.0, 6.0));
    },
  );

  test('#4/AK6: no recording on iPhone/iPad and in the browser', () {
    final ios = File('packages/wp_core/ios/Classes/wp_recorder.cpp')
        .readAsStringSync();
    expect(ios, contains('recorder_stub.cpp'));
    final stub = File('../core/src/recorder_stub.cpp').readAsStringSync();
    expect(stub, contains('int wp_rec_available(void) { return 0; }'));
    final native = File('lib/app/platform_native.dart').readAsStringSync();
    expect(native, contains('WpRecorder.available ? RecordingButton('));
    final web = File('lib/app/platform_web.dart').readAsStringSync();
    expect(
      web,
      contains('Widget? recordingButtonFor(AppController controller) => null;'),
    );
  });
}
