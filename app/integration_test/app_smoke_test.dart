// #17/AK7, #30/AK13, #13/AK1: smoke test of the real app with the real audio core: start, import of a
// generated audio file (dropped onto the window), play/pause, set a loop, change the tempo; then
// play/pause in every size (desktop, tablet, phone). Rules in ui_helpers.dart (#13/AK2): waits for
// states, no fixed waiting time.
// #99: the same file also runs on an iOS simulator (FFI, start, controls), plus the check that the
// recording button is missing there (#4/AK6).
// Run: cd app && flutter test integration_test -d macos; iOS simulator: make test-ios
// Without an audio device (CI): WP_AUDIO_BACKEND=null (core plays to its null device).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/app/app_controller.dart';
import 'package:woodshed_player/app/platform_native.dart';
import 'package:wp_core/wp_core.dart';

import 'ui_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('#13/AK1, #17/AK7 start, import, play/pause, loop, tempo', (
    tester,
  ) async {
    final t = testFolder(seconds: 4);
    final c = await startApp(tester, t.dir);
    final p = c.player;
    expect(find.text(en.library), findsWidgets); // started
    expect(p.hasTrack, isFalse);

    // Import: the generated file dropped onto the window
    await dropFiles(tester, c, [t.wav]);
    await tester.pump();
    expect(find.byKey(const Key('track:Sine test tone')), findsOneWidget);
    // 4 s at 44.1 kHz, resampled to the device rate: still 4 s
    expect(p.duration, closeTo(4.0, 0.01));
    // #115: loop and tempo are in the area Practice
    await showArea(tester, AppArea.practice);
    expect(find.byKey(const Key('card:loop')), findsOneWidget);

    // Play/pause with the button; #115/AK12: a pause in Practice goes back to the start of the track
    await tester.tap(find.byKey(const Key('playPause')));
    await pumpUntil(tester, () => p.isPlaying && p.position > 0.2, 'playing');
    await tester.tap(find.byKey(const Key('playPause')));
    await pumpUntil(tester, () => !p.isPlaying && p.position == 0, 'paused');

    // Loop with the «here» buttons: start where playback was paused, end while playing at least 1 s
    // later (a loop needs 1 s, #22); playback then jumps back to the start.
    final start = p.position;
    await tester.tap(find.byKey(const Key('here:Anfang')));
    await tester.pump();
    expect(p.settings.loopEnabled, isTrue);
    expect(p.settings.loopStart, start);
    await tester.tap(find.byKey(const Key('playPause')));
    await pumpUntil(tester, () => p.position >= start + 1.2, 'start + 1.2 s');
    await tester.tap(find.byKey(const Key('here:Ende')));
    await tester.pump();
    final end = p.settings.loopEnd;
    expect(end, greaterThanOrEqualTo(start + 1.2));
    expect(p.activeLoop, (start, end));
    expect(
      tester
          .widget<Text>(find.byKey(const Key('loopInfo')))
          .textSpan!
          .toPlainText(),
      startsWith(en.loopLength(end - start)),
    );
    await pumpUntil(tester, () => p.position < start + 0.5, 'jump back');
    expect(p.isPlaying, isTrue);
    expect(p.position, greaterThanOrEqualTo(start));
    await tester.tap(find.byKey(const Key('playPause')));
    await pumpUntil(tester, () => !p.isPlaying, 'paused in the loop');

    // Tempo: switch the speed card on, preset 0.75×
    expect(p.settings.speedEnabled, isFalse);
    await tester.tap(find.byKey(Key('switch:${en.speed}')));
    await pumpUntil(tester, () => p.settings.speedEnabled, 'speed on');
    await tester.tap(find.byKey(const Key('preset:0.75')));
    await tester.pump();
    expect(p.settings.speedEnabled, isTrue);
    expect(p.settings.speed, 0.75);
    expect(
      tester.widget<Text>(find.byKey(const Key('speedValue'))).data,
      en.rate(0.75),
    );
  });

  testWidgets('#30/AK13 play/pause with the real core in every size', (
    tester,
  ) async {
    final t = testFolder(seconds: 3);
    final c = await startApp(tester, t.dir);
    final p = c.player;
    await dropFiles(tester, c, [t.wav]);

    for (final (name, size) in [
      ('desktop', desktopSize),
      ('tablet', tabletSize),
      ('phone', phoneSize),
    ]) {
      setSize(tester, size);
      await tester.pumpAndSettle();
      expect(find.byKey(Key('layout:$name')), findsOneWidget, reason: name);
      // #115: the waveform is in the area Practice
      await showArea(tester, AppArea.practice);
      expect(find.byKey(const Key('waveformOverview')), findsOneWidget);
      expect(find.byKey(const Key('waveformDetail')), findsOneWidget);

      // play/pause in the area Player, which keeps the position at a pause
      await showArea(tester, AppArea.player);
      if (name == 'phone') {
        await tester.tap(find.byKey(const Key('openPlayer')));
        await tester.pumpAndSettle();
      }
      p.seek(0);
      await pumpUntil(tester, () => p.position == 0, '$name: at 0');
      // #99: on iOS the controls are taller; at 1100 px the button sits just below the window
      await tester.ensureVisible(find.byKey(const Key('playPause')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('playPause')));
      await pumpUntil(
        tester,
        () => p.isPlaying && p.position > 0.2,
        '$name: playing',
      );
      final reached = p.position;
      await tester.tap(find.byKey(const Key('playPause')));
      await pumpUntil(tester, () => !p.isPlaying, '$name: paused');
      // #106/AK2: pause keeps the position reached while playing
      expect(p.position, greaterThanOrEqualTo(reached), reason: name);
      expect(p.position, greaterThan(0.2), reason: name);
      if (name == 'phone') {
        await tester.tap(find.byKey(const Key('backToLibrary')));
        await tester.pumpAndSettle();
      }
    }
  });

  testWidgets('#99/AK4, #4/AK6 recording button only where the core records', (
    tester,
  ) async {
    final t = testFolder(seconds: 1);
    final c = await startApp(
      tester,
      t.dir,
      recordingButton: recordingButtonFor,
    );
    // iPhone/iPad: the core has no recorder (recorder_stub.cpp) and the app shows no button;
    // macOS: both are there (desktop and tablet layout carry the button).
    expect(WpRecorder.available, !Platform.isIOS);
    expect(c.player.hasTrack, isFalse);
    for (final (name, size) in [
      ('desktop', desktopSize),
      ('tablet', tabletSize),
    ]) {
      setSize(tester, size);
      await tester.pumpAndSettle();
      expect(find.byKey(Key('layout:$name')), findsOneWidget, reason: name);
      expect(
        find.byKey(const Key('recordingButton')),
        Platform.isIOS ? findsNothing : findsOneWidget,
        reason: name,
      );
    }
  });
}
