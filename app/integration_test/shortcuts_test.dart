// #13/AK1: keyboard shortcuts in the real app with the real core (#3, #17): space play/pause, S/E loop
// start/end at the playhead, ←/→ speed ∓/± 0.05, M metronome on/off, T tap tempo, ↑/↓ metronome ±1
// (with shift ±10). Rules in ui_helpers.dart (#13/AK2): waits for states, no fixed waiting time; the
// tap clock is set by the test, so tap tempo does not depend on the machine's speed.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:woodshed_player/metronome/tap_tempo.dart';

import 'ui_helpers.dart';

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
    await dropFiles(tester, c, [t.wav]);
    await tester.pump();

    // Space: play, space again: pause
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await pumpUntil(tester, () => p.isPlaying && p.position > 0.2, 'playing');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await pumpUntil(tester, () => !p.isPlaying, 'paused');

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
