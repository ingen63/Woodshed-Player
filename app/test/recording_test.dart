// #4: recording of the system audio on the Mac, with a fake recorder and a temporary library.
// #113: microphone as a second source, recorded as FLAC, with the permission of the fake platform.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/app/recording_controller.dart';
import 'package:woodshed_player/ui/messages.dart';
import 'package:woodshed_player/ui/recording_button.dart';
import 'package:woodshed_player/ui/style.dart';
import 'package:wp_core/wp_types.dart';
import 'package:woodshed_player/library/device_settings.dart';

import 'fakes.dart';

final stamp = DateTime(2026, 11, 19, 14, 5, 9);

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('wp_rec_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<(TestApp, FakeRecorder)> pump(
    WidgetTester tester, {
    Locale locale = testLocale,
    Set<WpRecSource>? sources,
    WpRecSource? chosen,
  }) async {
    final app = TestApp(Directory('${tmp.path}/lib'));
    final rec = FakeRecorder();
    if (sources != null) rec.sources = sources;
    app.files.recordings = (Directory('${tmp.path}/rec')..createSync()).path;
    await tester.runAsync(app.library.load);
    if (chosen != null) {
      await tester.runAsync(() => app.library.setRecordingSource(chosen.name));
    }
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
    // The record button itself: the row also holds the source menu and hints (#113).
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('recordingButton')).last,
        matching: find.byType(TextButton),
      ),
    );
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
    '#157/AK7 #157/AK8: a recording ended by the browser names the reason at the button',
    (tester) async {
      final (app, rec) = await pump(tester);
      for (final (reason, text) in [
        (RecordingInterruption.storageFull, de.recordingStorageFull),
        (RecordingInterruption.background, de.recordingStoppedInBackground),
        (
          RecordingInterruption.failed,
          de.recordingFailed(de.recordingErrorFile),
        ),
      ]) {
        await tapRecord(tester);
        rec.interruption = reason;
        final problem = find.byKey(const Key('recordingProblem'));
        await pumpUntil(
          tester,
          () => problem.evaluate().isNotEmpty,
          'ended by itself: $reason',
        );
        expect(tester.widget<IconButton>(problem).tooltip, text);
        expect(find.byKey(const Key('recordingDuration')), findsNothing);
        await tester.runAsync(() async {
          for (var i = 0; i < 20; i++) {
            app.finishLoads();
            await pumpEventQueue();
          }
        });
        await tester.pump();
      }
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

  testWidgets('#4/AK4, #118/AK1: after stopping the system audio is a new FLAC title named after date and '
      'time', (tester) async {
    final (app, rec) = await pump(tester);
    await tapRecord(tester);
    expect(rec.source, WpRecSource.system);
    expect(rec.path, endsWith('Aufnahme 2026-11-19 14.05.09.flac'));
    await tester.runAsync(() => tapRecord(tester));
    await waitUntil(
      tester,
      () => app.library.tracks.isNotEmpty,
      'recording in the library',
    );
    final t = app.library.tracks.single;
    expect(t.title, 'Aufnahme 19.11.2026 14:05:09');
    expect(t.fileName, endsWith('.flac'));
    // Renamable like any title (#24).
    expect(app.library.editMetadata(t.id, title: 'Etüde'), isTrue);
    expect(app.library.track(t.id)!.title, 'Etüde');
  });

  test('#4/AK4: the title follows the locale', () async {
    await initializeDateFormatting();
    final en = lookupAppLocalizations(const Locale('en'));
    expect(recordingTitle(de, stamp), 'Aufnahme 19.11.2026 14:05:09');
    expect(recordingTitle(en, stamp), 'Recording 11/19/2026 2:05:09 PM');
  });

  // #118: new recordings are FLAC (AK1); older WAV recordings keep playing (AK5).
  for (final (ext, criterion) in [('flac', '#118/AK1'), ('wav', '#118/AK5')]) {
    test(
      '#4/AK4, $criterion: a $ext recording plays with tempo and loop like any title',
      () async {
        final app = TestApp(Directory('${tmp.path}/lib'));
        await app.library.load();
        final file = File('${tmp.path}/Recording.$ext')..writeAsStringSync(ext);
        var finished = false;
        final added = app.controller
            .addRecording(file.path, title: 'Aufnahme 1')
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
        expect(app.library.tracks.single.fileName, endsWith('.$ext'));
      },
    );
  }

  // ---- #113: microphone ----

  Future<void> chooseSource(WidgetTester tester, WpRecSource s) async {
    await tester.tap(find.byKey(const Key('recordingSource')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('recordingSource:${s.name}')).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    '#113/AK1: microphone or system audio can be chosen; the choice stays on this device',
    (tester) async {
      final (app, rec) = await pump(tester);
      // System audio until something is chosen, as before #113.
      expect(app.library.recordingSource, isNull);
      await tester.tap(find.byKey(const Key('recordingSource')));
      await tester.pumpAndSettle();
      final items = tester
          .widgetList<CheckedPopupMenuItem<WpRecSource>>(
            find.byType(CheckedPopupMenuItem<WpRecSource>),
          )
          .toList();
      expect(items.map((i) => i.value), [
        WpRecSource.system,
        WpRecSource.microphone,
      ]);
      expect(items.map((i) => i.checked), [true, false]);
      expect(find.text(de.recordingSourceMicrophone), findsOneWidget);
      expect(find.text(de.recordingSourceSystem), findsOneWidget);
      await tester.tap(find.byKey(const Key('recordingSource:microphone')));
      await tester.pumpAndSettle();
      expect(app.library.recordingSource, 'microphone');
      expect(
        app.library.device.toJson()['recordingSource'],
        'microphone',
      ); // device-local, never synced
      await tapRecord(tester);
      expect(rec.source, WpRecSource.microphone);
      // The menu is hidden while recording, so the source cannot change mid-take.
      expect(find.byKey(const Key('recordingSource')), findsNothing);
      await tester.runAsync(() => tapRecord(tester));
      await chooseSource(tester, WpRecSource.system);
      await tester.runAsync(() => tapRecord(tester));
      expect(rec.source, WpRecSource.system);
      expect(rec.path, endsWith('.flac')); // #118/AK1
      await tester.runAsync(() => tapRecord(tester));
    },
  );

  testWidgets(
    '#113/AK1: without the system audio (macOS before 14.2) only the microphone, no menu',
    (tester) async {
      final (_, rec) = await pump(
        tester,
        sources: {WpRecSource.microphone},
        chosen: WpRecSource.system,
      );
      expect(find.byKey(const Key('recordingSource')), findsNothing);
      await tapRecord(tester);
      expect(rec.source, WpRecSource.microphone);
      await tester.runAsync(() => tapRecord(tester));
    },
  );

  testWidgets(
    '#113/AK2: a microphone recording starts and stops by the same button, with duration and level',
    (tester) async {
      final (app, rec) = await pump(tester, chosen: WpRecSource.microphone);
      final tooltip = tester.widget<Tooltip>(
        find.ancestor(
          of: find.text(de.recording),
          matching: find.byType(Tooltip),
        ),
      );
      expect(tooltip.message, de.recordingTooltipMicrophone);
      await tapRecord(tester);
      expect(rec.recording, isTrue);
      expect(app.files.microphoneAsked, 1);
      rec
        ..seconds = 12
        ..level = 0.3;
      await pumpUntil(
        tester,
        () => find.text('00:12').evaluate().isNotEmpty,
        'duration shown',
      );
      final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const Key('recordingLevel')),
      );
      expect(bar.value, closeTo(0.3, 1e-9));
      await tester.runAsync(() async => tapRecord(tester));
      expect(rec.recording, isFalse);
      expect(find.byKey(const Key('recordingDuration')), findsNothing);
    },
  );

  testWidgets(
    '#113/AK3: after stopping the microphone take is a FLAC title named after date and time',
    (tester) async {
      final (app, rec) = await pump(tester, chosen: WpRecSource.microphone);
      await tapRecord(tester);
      expect(rec.path, endsWith('Aufnahme 2026-11-19 14.05.09.flac'));
      await tester.runAsync(() => tapRecord(tester));
      await waitUntil(
        tester,
        () => app.library.tracks.isNotEmpty,
        'recording in the library',
      );
      final t = app.library.tracks.single;
      expect(t.title, 'Aufnahme 19.11.2026 14:05:09');
      expect(t.fileName, endsWith('.flac'));
      expect(app.library.editMetadata(t.id, title: 'Etüde'), isTrue);
      expect(app.library.track(t.id)!.title, 'Etüde');
    },
  );

  testWidgets(
    '#113/AK4: refused microphone permission explains where to grant it, no recording, no title',
    (tester) async {
      final (app, rec) = await pump(tester, chosen: WpRecSource.microphone);
      app.files.microphoneGranted = false;
      await tester.runAsync(() => tapRecord(tester));
      await tester.pump();
      expect(app.files.microphoneAsked, 1);
      expect(rec.recording, isFalse);
      expect(rec.path, isNull);
      expect(Directory(app.files.recordings!).listSync(), isEmpty);
      expect(app.library.tracks, isEmpty);
      expect(find.byKey(const Key('recordingDuration')), findsNothing);
      final problem = find.byKey(const Key('recordingProblem'));
      expect(
        tester.widget<IconButton>(problem).tooltip,
        de.recordingMicrophoneDenied,
      );
      await tester.tap(problem);
      await tester.pumpAndSettle();
      expect(find.text(de.recordingMicrophoneDenied), findsOneWidget);
      expect(
        de.recordingMicrophoneDenied,
        contains('Datenschutz & Sicherheit › Mikrofon'),
      );
      final en = lookupAppLocalizations(const Locale('en'));
      expect(
        en.recordingMicrophoneDenied,
        contains('Privacy & Security › Microphone'),
      );
      await tester.tap(find.text(de.ok));
      await tester.pumpAndSettle();
      // Granted later: the hint goes away and the take starts.
      app.files.microphoneGranted = true;
      await tester.runAsync(() => tapRecord(tester));
      await tester.pump();
      expect(rec.recording, isTrue);
      expect(find.byKey(const Key('recordingProblem')), findsNothing);
      await tester.runAsync(() => tapRecord(tester));
    },
  );

  testWidgets('#113/AK4: the system audio does not ask for the microphone', (
    tester,
  ) async {
    final (app, rec) = await pump(tester, chosen: WpRecSource.system);
    app.files.microphoneGranted = false;
    await tapRecord(tester);
    expect(app.files.microphoneAsked, 0);
    expect(rec.recording, isTrue);
    await tester.runAsync(() => tapRecord(tester));
  });

  testWidgets(
    '#113/AK4: only silence from the microphone points to the input device',
    (tester) async {
      final (_, rec) = await pump(tester, chosen: WpRecSource.microphone);
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
      expect(
        tester.widget<IconButton>(problem).tooltip,
        de.recordingMicrophoneSilent,
      );
      expect(de.recordingMicrophoneSilent, contains('Ton › Eingang'));
      await tester.runAsync(() => tapRecord(tester));
      // Choosing a source clears the hint of the last take.
      await chooseSource(tester, WpRecSource.system);
      expect(find.byKey(const Key('recordingProblem')), findsNothing);
    },
  );

  testWidgets(
    '#140/AK5: the button shows the armed state of the command line; a click cancels it',
    (tester) async {
      final app = TestApp(Directory('${tmp.path}/lib'));
      app.files.recordings = (Directory('${tmp.path}/rec')..createSync()).path;
      await tester.runAsync(app.library.load);
      final rec = FakeRecorder();
      final recording = RecordingController(
        app: app.controller,
        recorder: rec,
        now: () => stamp,
      );
      addTearDown(recording.dispose);
      await tester.pumpWidget(
        MaterialApp(
          locale: testLocale,
          localizationsDelegates: testDelegates,
          supportedLocales: testLocales,
          theme: woodshedTheme(Brightness.light),
          home: Scaffold(
            body: Center(
              child: RecordingButton(
                controller: app.controller,
                recorder: rec,
                recording: recording,
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('recordingArmed')), findsNothing);
      // armed as the command line does it (the clock of the ticker is the test's)
      await recording.start(de, title: 'Take', arming: const Arming());
      await tester.pump();
      expect(find.text(de.recordingArmed), findsOneWidget);
      expect(de.recordingArmed, 'Scharf');
      expect(find.byKey(const Key('recordingArmedMark')), findsOneWidget);
      expect(find.byKey(const Key('recordingDuration')), findsNothing);
      expect(find.byKey(const Key('recordingSource')), findsNothing);
      final tooltip = tester.widget<Tooltip>(
        find.ancestor(
          of: find.text(de.recordingArmed),
          matching: find.byType(Tooltip),
        ),
      );
      expect(tooltip.message, de.recordingArmedTooltip);
      // the first sound: the button shows the recording and its length
      rec
        ..gate = WpRecGate.recording
        ..keptSeconds = 7;
      await pumpUntil(
        tester,
        () => find.text('00:07').evaluate().isNotEmpty,
        'recording shown',
      );
      expect(find.byKey(const Key('recordingArmed')), findsNothing);
      // armed again; a click cancels without a title
      rec.gate = WpRecGate.armed;
      await pumpUntil(
        tester,
        () => find.text(de.recordingArmed).evaluate().isNotEmpty,
        'armed shown',
      );
      final path = rec.path!;
      await tester.runAsync(() => tapRecord(tester));
      await tester.pump();
      expect(rec.recording, isFalse);
      expect(find.text(de.recordingArmed), findsNothing);
      expect(find.text(de.recording), findsOneWidget);
      expect(File(path).existsSync(), isFalse);
      expect(app.library.tracks, isEmpty);
      expect(await recording.done, isA<RecordingCancelled>());
    },
  );

  test('#113/AK1: the recording source is stored in device.json', () {
    const d = DeviceSettings(deviceId: '0123456789abcdef');
    expect(d.toJson(), isNot(contains('recordingSource')));
    final m = d.copyWith(recordingSource: 'microphone');
    expect(m.toJson()['recordingSource'], 'microphone');
    expect(m.copyWith(area: 'player').recordingSource, 'microphone');
    expect(WpRecSource.named('microphone'), WpRecSource.microphone);
    expect(WpRecSource.named('system'), WpRecSource.system);
    expect(WpRecSource.named('tape'), isNull);
    expect(WpRecSource.named(null), isNull);
    expect(WpRecSource.microphone.extension, 'flac');
    expect(WpRecSource.system.extension, 'flac'); // #118/AK1
  });

  test('#113/AK6: no microphone recording on iPhone/iPad (#157: the browser records)', () async {
    final stub = File('../core/src/recorder_stub.cpp').readAsStringSync();
    expect(stub, contains('int wp_rec_source_available(int) { return 0; }'));
    expect(
      stub,
      contains(
        'int wp_rec_start_source(const char *, int) { return WP_REC_ERR_UNSUPPORTED; }',
      ),
    );
    final ios = File('packages/wp_core/ios/Classes/wp_recorder.cpp')
        .readAsStringSync();
    expect(ios, contains('recorder_stub.cpp'));
    // #157: the browser asks the recorder of the web core
    final web = File('lib/app/file_platform_web.dart').readAsStringSync();
    expect(
      web,
      contains(
        'Future<bool> microphoneAccess() async => await microphone?.call() ?? false;',
      ),
    );
    final iosPlist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(iosPlist, isNot(contains('NSMicrophoneUsageDescription')));
  });

  test('#4/AK6: no recording on iPhone/iPad (#157: in the browser where it can)', () {
    final ios = File('packages/wp_core/ios/Classes/wp_recorder.cpp')
        .readAsStringSync();
    expect(ios, contains('recorder_stub.cpp'));
    final stub = File('../core/src/recorder_stub.cpp').readAsStringSync();
    expect(stub, contains('int wp_rec_available(void) { return 0; }'));
    final native = File('lib/app/platform_native.dart').readAsStringSync();
    expect(
      native,
      matches(RegExp(r'WpRecorder\.available\s*\?\s*RecordingButton\(')),
    );
    // #157/AK1: the browser has the button only with a recorder (getUserMedia)
    final web = File('lib/app/platform_web.dart').readAsStringSync();
    expect(web, contains('final recorder = await WebRecorder.create(core);'));
  });
}
