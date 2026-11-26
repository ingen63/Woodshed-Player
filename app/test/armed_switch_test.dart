// #147: the switch «Armed» in the window (ArmedSwitch in HomePage) with a fake recorder: where it shows,
// its states, the popover with threshold, level and pause, the space bar, and the hints. The logic of
// the takes: practice_recording_test.dart.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/app/app_controller.dart';
import 'package:woodshed_player/app/practice_recording.dart';
import 'package:woodshed_player/app/recording_controller.dart';
import 'package:woodshed_player/ui/armed_switch.dart';
import 'package:woodshed_player/ui/home_page.dart';
import 'package:woodshed_player/ui/recording_button.dart';
import 'package:woodshed_player/ui/style.dart';
import 'package:wp_core/wp_types.dart';

import 'fakes.dart';
import 'home_page_test.dart' show pumpApp;

const desktop = Size(1280, 900);

Finder byKey(String k) => find.byKey(Key(k));

class _Setup {
  _Setup(this.app, this.rec, this.recording, this.practice);
  final TestApp app;
  final FakeRecorder rec;
  final RecordingController recording;
  final PracticeRecording practice;
}

void main() {
  setUp(() => KeyboardPresence.instance.value = false);

  Future<_Setup> pump(WidgetTester tester, {Size size = desktop}) async {
    final app = await pumpApp(tester, size: size);
    final dir = Directory.systemTemp.createTempSync('wp_armed_rec');
    addTearDown(() => dir.deleteSync(recursive: true));
    app.files.recordings = dir.path;
    final rec = FakeRecorder();
    final recording = RecordingController(
      app: app.controller,
      recorder: rec,
      now: () => DateTime(2026, 11, 25, 9, 30, 15),
      tick: const Duration(milliseconds: 10),
    );
    final practice = PracticeRecording(
      app: app.controller,
      recording: recording,
    );
    addTearDown(() {
      practice.dispose();
      recording.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        locale: testLocale,
        localizationsDelegates: testDelegates,
        supportedLocales: testLocales,
        theme: woodshedTheme(Brightness.dark),
        home: HomePage(
          controller: app.controller,
          recordingButton: RecordingButton(
            controller: app.controller,
            recording: recording,
          ),
          practiceRecording: (
            arming: practice,
            widget: ArmedSwitch(practice: practice),
          ),
        ),
      ),
    );
    return _Setup(app, rec, recording, practice);
  }

  Future<void> area(WidgetTester tester, AppArea a) async {
    await tester.tap(byKey('area:${a.name}'));
    await tester.pumpAndSettle();
  }

  Future<void> toggle(WidgetTester tester) async {
    await tester.tap(byKey('armedToggle'));
    await tester.pump();
    await tester.pump();
  }

  Future<void> armed(WidgetTester tester, _Setup s, int starts) => pumpUntil(
    tester,
    () => s.rec.starts == starts && s.recording.phase == RecordingPhase.armed,
    'armed $starts',
  );

  group('#147/AK1 where the switch is', () {
    testWidgets('macOS: in Practice and Metronome, not in Player while off', (
      tester,
    ) async {
      await pump(tester);
      expect(byKey('armedSwitch'), findsNothing);
      await area(tester, AppArea.practice);
      expect(byKey('armedSwitch'), findsOneWidget);
      await area(tester, AppArea.metronome);
      expect(byKey('armedSwitch'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('iPhone/iPad: never, also in Practice', (tester) async {
      await pump(tester, size: const Size(820, 1180));
      await area(tester, AppArea.practice);
      expect(byKey('armedSwitch'), findsNothing);
      await area(tester, AppArea.metronome);
      expect(byKey('armedSwitch'), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });

  testWidgets(
    '#147/AK6, AK10: armed and recording look different; on, it stays in Player',
    (tester) async {
      final s = await pump(tester);
      await area(tester, AppArea.practice);
      expect(byKey('armedMark:off'), findsOneWidget);
      expect(byKey('armedLevel'), findsNothing);
      await toggle(tester);
      await armed(tester, s, 1);
      await tester.pump();
      expect(byKey('armedMark:armed'), findsOneWidget);
      expect(byKey('armedLevel'), findsOneWidget);
      expect(byKey('armedDuration'), findsNothing);
      s.rec
        ..level = 1
        ..keptSeconds = 65
        ..gate = WpRecGate.recording;
      await pumpUntil(
        tester,
        () => byKey('armedDuration').evaluate().isNotEmpty,
        'recording shown',
      );
      expect(byKey('armedMark:recording'), findsOneWidget);
      expect(find.text('01:05'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(byKey('armedLevel'));
      expect(bar.value, 1);
      // #147/AK6: in Player it stays on and visible
      await tester.tap(byKey('area:player'));
      await tester.pump();
      await tester.pump();
      expect(s.practice.on, isTrue);
      expect(byKey('armedSwitch'), findsOneWidget);
      // off: the take is saved (file work in real time)
      await tester.runAsync(() => toggle(tester));
      await waitUntil(
        tester,
        () => s.app.library.tracks.length == 4,
        'take saved',
      );
      await tester.pump();
      expect(byKey('armedSwitch'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('#147/AK9: popover with threshold, level meter and pause', (
    tester,
  ) async {
    final s = await pump(tester);
    await area(tester, AppArea.metronome);
    await tester.tap(byKey('armedSettingsButton'));
    await tester.pumpAndSettle();
    expect(byKey('armedSettings'), findsOneWidget);
    expect(byKey('armedMeter'), findsOneWidget);
    expect(byKey('armedLevelOff'), findsOneWidget); // off: no level yet
    final threshold = tester.widget<Text>(byKey('armedThresholdValue'));
    expect(threshold.data, contains('30 dBFS'));
    final pause = tester.widget<Text>(byKey('armedSilenceValue'));
    expect(pause.data, '5 s');
    final slider = tester.widget<Slider>(byKey('armedThresholdSlider'));
    expect(slider.min, -60);
    expect(slider.max, 0);
    slider.onChanged!(-42.4);
    slider.onChangeEnd!(-42.4);
    final silence = tester.widget<Slider>(byKey('armedSilenceSlider'));
    expect(silence.min, 1);
    expect(silence.max, 30);
    silence.onChanged!(8);
    await tester.pump();
    expect(s.practice.thresholdDb, -42);
    expect(s.practice.silenceSeconds, 8);
    expect(
      tester.widget<Text>(byKey('armedThresholdValue')).data,
      contains('42 dBFS'),
    );
    expect(tester.widget<Text>(byKey('armedSilenceValue')).data, '8 s');
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    '#156/AK1: popover switch «Switch off after a recording», on by default',
    (tester) async {
      final s = await pump(tester);
      await area(tester, AppArea.practice);
      await tester.tap(byKey('armedSettingsButton'));
      await tester.pumpAndSettle();
      Switch offAfter() => tester.widget<Switch>(byKey('armedOffAfterTake'));
      expect(offAfter().value, isTrue);
      expect(s.practice.keepsOn, isFalse);
      await tester.tap(byKey('armedOffAfterTake'));
      await tester.pump();
      expect(s.practice.keepsOn, isTrue);
      expect(offAfter().value, isFalse);
      await tester.tap(byKey('armedOffAfterTake'));
      await tester.pump();
      expect(s.practice.keepsOn, isFalse);
      expect(offAfter().value, isTrue);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  test('#147/AK10: the meter runs from -60 to 0 dBFS', () {
    expect(meterPosition(0), 0);
    expect(meterPosition(1), 1);
    expect(meterPosition(2), 1);
    expect(meterPosition(0.001), closeTo(0, 1e-9)); // -60 dBFS
    expect(meterPosition(0.0001), 0);
    expect(meterPosition(0.0316228), closeTo(0.5, 1e-4)); // -30 dBFS
  });

  testWidgets(
    '#147/AK4, #156/AK2: Space plays or pauses and ends the running take',
    (tester) async {
      final s = await pump(tester);
      await area(tester, AppArea.metronome);
      await toggle(tester);
      await armed(tester, s, 1);
      s.rec
        ..keptSeconds = 3
        ..gate = WpRecGate.recording;
      await pumpUntil(tester, () => s.practice.takeRunning, 'recording');
      expect(s.app.controller.metronome.running, isFalse);
      await tester.runAsync(() async {
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
      });
      expect(s.app.controller.metronome.running, isTrue); // Space as before
      expect(s.practice.takeRunning, isFalse);
      await waitUntil(
        tester,
        () => s.app.library.tracks.length == 4,
        'take saved',
      );
      // #156/AK2: by default the switch goes off after the take.
      await pumpUntil(tester, () => !s.practice.on, 'switch off');
      s.app.controller.metronome.stop();
      await s.practice.turnOff();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    '#147/AK11: while on, the record button only explains why it is locked',
    (tester) async {
      final s = await pump(tester);
      await area(tester, AppArea.practice);
      await toggle(tester);
      await armed(tester, s, 1);
      await tester.tap(
        find.descendant(
          of: byKey('recordingButton'),
          matching: find.byType(TextButton),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(de.recordingLockedByArmed), findsOneWidget);
      expect(s.rec.starts, 1);
      expect(byKey('recordingDuration'), findsNothing);
      await tester.tap(find.text(de.ok));
      await tester.pump(const Duration(milliseconds: 500));
      await s.practice.turnOff();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    '#147/AK11: with another recording running the switch stays off and says why',
    (tester) async {
      final s = await pump(tester);
      await area(tester, AppArea.practice);
      expect(await s.recording.start(de), isNull);
      await toggle(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(de.armedBusy), findsOneWidget);
      expect(s.practice.on, isFalse);
      await tester.tap(find.text(de.ok));
      await tester.pump(const Duration(milliseconds: 500));
      expect(byKey('armedProblem'), findsOneWidget);
      var stopped = false;
      await tester.runAsync(() async {
        unawaited(s.recording.stop().then((_) => stopped = true));
        await eventually(() {
          s.app.finishLoads();
          return stopped;
        }, 'stopped');
      });
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    '#147/AK12: microphone refused: off again, the hint names the settings',
    (tester) async {
      final s = await pump(tester);
      s.app.files.microphoneGranted = false;
      await area(tester, AppArea.practice);
      await toggle(tester);
      await tester.pumpAndSettle();
      expect(byKey('armedProblemDialog'), findsOneWidget);
      expect(find.text(de.armedMicrophoneDenied), findsOneWidget);
      expect(
        de.armedMicrophoneDenied,
        contains('Systemeinstellungen › Datenschutz & Sicherheit › Mikrofon'),
      );
      expect(s.practice.on, isFalse);
      expect(byKey('armedMark:off'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  test('#147/AK12: the failure of the core has its own text', () {
    final app = TestApp(Directory.systemTemp.createTempSync('wp_armed_msg'));
    final recording = RecordingController(
      app: app.controller,
      recorder: FakeRecorder(),
    );
    final practice = PracticeRecording(
      app: app.controller,
      recording: recording,
    );
    expect(
      armedProblemMessage(de, PracticeArmProblem.failed, practice),
      de.armedFailed,
    );
    expect(
      armedProblemMessage(de, PracticeArmProblem.busy, practice),
      de.armedBusy,
    );
  });
}
