// #13/AK1: keyboard shortcuts in the real app with the real core (#3, #17): space play/pause, S/E loop
// start/end at the playhead, ←/→ speed ∓/± 0.05, M metronome on/off, T tap tempo, ↑/↓ metronome ±1
// (with shift ±10). Rules in ui_helpers.dart (#13/AK2): waits for states, no fixed waiting time; the
// tap clock is set by the test, so tap tempo does not depend on the machine's speed.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:woodshed_player/app/app_controller.dart';
import 'package:woodshed_player/metronome/tap_tempo.dart';
import 'package:woodshed_player/player/play_queue.dart';

import 'ui_helpers.dart';

/// The command key of the platform: ⌘ on Apple, Ctrl elsewhere.
final command = Platform.isMacOS || Platform.isIOS
    ? LogicalKeyboardKey.metaLeft
    : LogicalKeyboardKey.controlLeft;

/// [key] with [modifier] held.
Future<void> withKey(
  WidgetTester tester,
  LogicalKeyboardKey modifier,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('#13/AK1 keyboard shortcuts', (tester) async {
    var now = DateTime.utc(2026);
    final t = testFolder(seconds: 4);
    final c = await startApp(
      tester,
      t.dir,
      tapTempo: TapTempo(clock: () => now),
    );
    final p = c.player, m = c.metronome;
    keepAppInFront(tester); // #134
    await dropFiles(tester, c, [t.wav]);
    await tester.pump();

    // #115/AK11 area Player: Space play/pause keeps the position, ⌥S shuffle, ⌥R repeat, M mute,
    // ⌘↑ louder (paused, so nothing sounds)
    expect(c.area, AppArea.player);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await pumpUntil(tester, () => p.isPlaying && p.position > 0.2, 'playing');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await pumpUntil(tester, () => !p.isPlaying, 'paused');
    expect(p.position, greaterThan(0.2));
    await withKey(tester, LogicalKeyboardKey.altLeft, LogicalKeyboardKey.keyS);
    expect(c.shuffle, isTrue, reason: focusInfo());
    // #134 regression: another app comes to the front between two shortcuts
    await sendToBack(tester);
    await withKey(tester, LogicalKeyboardKey.altLeft, LogicalKeyboardKey.keyR);
    expect(c.repeat, Repeat.list, reason: focusInfo());
    await tester.sendKeyEvent(
      LogicalKeyboardKey.keyM,
    ); // silent already: back to full
    expect(p.volume, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    expect(p.volume, 0);
    await withKey(tester, command, LogicalKeyboardKey.arrowUp);
    expect(p.volume, closeTo(0.1, 1e-9));
    p.setVolume(0);
    expect(m.running, isFalse); // M is not the metronome in Player

    // ⌘2: the area Practice with the practice shortcuts
    await withKey(tester, command, LogicalKeyboardKey.digit2);
    await tester.pumpAndSettle();
    expect(c.area, AppArea.practice, reason: focusInfo());

    // Space: play, space again: pause (#115/AK12: back to the start of the track)
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await pumpUntil(tester, () => p.isPlaying && p.position > 0.2, 'playing');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await pumpUntil(tester, () => !p.isPlaying && p.position == 0, 'paused');

    // S: loop start at the paused playhead, loop on; E while playing at least 1 s later: loop end,
    // playback jumps back to the start
    final start = p.position;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    expect(p.settings.loopEnabled, isTrue);
    expect(p.settings.loopStart, start);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await pumpUntil(tester, () => p.position >= start + 1.2, 'start + 1.2 s');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    final end = p.settings.loopEnd;
    expect(end, greaterThanOrEqualTo(start + 1.2));
    expect(p.activeLoop, (start, end));
    await pumpUntil(tester, () => p.position < start + 0.5, 'jump back');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await pumpUntil(tester, () => !p.isPlaying, 'paused in the loop');

    // → and ←: speed in steps of 0.05, switches the speed on (1.0 → 1.05 → 1.0 → 0.95)
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(p.settings.speedEnabled, isTrue);
    expect(p.settings.speed, closeTo(1.05, 1e-9));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(p.settings.speed, closeTo(0.95, 1e-9));

    // ↑/↓: metronome tempo ±1, with shift ±10
    m.setBpm(100);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(m.settings.bpm, 101);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(m.settings.bpm, 99);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(m.settings.bpm, 109);

    // T: tap tempo, taps 0.5 s apart = 60 / 0.5 = 120 BPM
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    now = now.add(const Duration(milliseconds: 500));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    expect(m.settings.bpm, 120);

    // M: metronome on in the core, M again: off
    expect(m.running, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await pumpUntil(tester, () => m.running, 'metronome running');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await pumpUntil(tester, () => !m.running, 'metronome stopped');
    await tester.pump();
  });
}
