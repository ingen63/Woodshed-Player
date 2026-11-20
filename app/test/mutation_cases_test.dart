// #11: cases found by mutation testing (make mutants) in the Dart logic: time format, tap tempo,
// meter label, metronome control and its settings file. Each states the rule it checks.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/metronome/metronome_controller.dart';
import 'package:woodshed_player/metronome/metronome_settings.dart';
import 'package:woodshed_player/metronome/tap_tempo.dart';
import 'package:woodshed_player/time_format.dart';

import 'fakes.dart';

/// Tap tempo with a clock the test moves by hand.
class _Clock {
  var now = DateTime(2026, 11, 20);
  DateTime call() => now;
  void advance(int ms) => now = now.add(Duration(milliseconds: ms));
}

void main() {
  group('#11 time format', () {
    test('not a number shows 00:00.0, like a negative time', () {
      expect(formatTimePrecise(double.nan), '00:00.0');
      expect(formatTimePrecise(double.infinity), '00:00.0');
      expect(formatTimePrecise(-3), '00:00.0');
      expect(formatTime(double.nan), '00:00');
    });
  });

  group('#11 tap tempo (#3)', () {
    test(
      'a pause of exactly 2 s keeps the measurement, more than 2 s starts anew',
      () {
        final clock = _Clock();
        final tap = TapTempo(clock: clock.call);
        expect(tap.tap(), isNull);
        clock.advance(2000);
        expect(tap.tap(), 30); // 60'000 / 2000 ms
        clock.advance(2001);
        expect(tap.tap(), isNull); // more than 2 s: one tap again
      },
    );

    test('the mean of the last 5 taps (4 intervals)', () {
      final clock = _Clock();
      final tap = TapTempo(clock: clock.call);
      tap.tap();
      // intervals 1000, 500, 500, 500, 500 ms: the first tap drops out with the sixth, the mean of
      // the last four intervals is 500 ms = 120 BPM (with the first: 600 ms = 100 BPM)
      for (final ms in [1000, 500, 500, 500]) {
        clock.advance(ms);
        tap.tap();
      }
      clock.advance(500);
      expect(tap.tap(), 120);
      // five taps 1000, 1000, 1000, 400 ms apart: mean 850 ms = 71 BPM (the last three: 800 ms = 75)
      final t2 = TapTempo(clock: clock.call);
      t2.tap();
      for (final ms in [1000, 1000, 1000]) {
        clock.advance(ms);
        t2.tap();
      }
      clock.advance(400);
      expect(t2.tap(), 71);
    });

    test('two taps at the same moment give no tempo', () {
      final clock = _Clock();
      final tap = TapTempo(clock: clock.call);
      tap.tap();
      expect(tap.tap(), isNull);
    });
  });

  group('#11 metronome', () {
    test('6/8 is labelled 6/8, the other meters x/4', () {
      expect(MetronomeSettings.meterLabel(6), '6/8');
      expect(MetronomeSettings.meterLabel(4), '4/4');
      expect(MetronomeSettings.meterLabel(3), '3/4');
    });

    test('start and stop notify and report the running state', () {
      final running = <bool>[];
      final c = MetronomeController(
        FakeMetronome(),
        onRunningChanged: running.add,
      );
      var notifications = 0;
      c.addListener(() => notifications++);
      c.start();
      expect(notifications, 1);
      expect(c.running, isTrue);
      c.stop();
      expect(notifications, 2);
      expect(running, [true, false]);
    });

    // #61: the UI shows the stored settings once they are restored
    test('restore notifies', () async {
      final c = MetronomeController(FakeMetronome());
      var notifications = 0;
      c.addListener(() => notifications++);
      await c.restore();
      expect(notifications, 1);
    });

    test(
      'the settings file is written into a folder that does not exist yet',
      () async {
        final dir = await Directory.systemTemp.createTemp('wp_metronome_');
        addTearDown(() => dir.delete(recursive: true));
        final store = FileSettingsStore(
          File('${dir.path}/new/sub/metronome.json'),
        );
        await store.save({'bpm': 90});
        expect(await store.load(), {'bpm': 90});
      },
    );
  });
}
