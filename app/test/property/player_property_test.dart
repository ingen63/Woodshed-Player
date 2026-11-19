// #10/AK1: random tests of loop bounds and time format.
// - Loop bounds are valid after every change: inside the file (0 ≤ start, end ≤ duration) and, in a
//   title of at least 1 s, end ≥ start + 1 s; the core gets exactly the active loop. A title shorter than
//   1 s has no loop.
// - parse(format(x)) == x for times in whole seconds and in tenths.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/library/playback_settings.dart';
import 'package:woodshed_player/player/player_service.dart';
import 'package:woodshed_player/time_format.dart';

import '../fakes.dart';
import 'property.dart';

/// Times around and beyond the title: negative, inside, at the edges, after the end.
double randomTime(Random r, double duration) => switch (r.nextInt(6)) {
  0 => -r.nextInt(100) / 10,
  1 => 0,
  2 => duration,
  3 => duration + r.nextInt(100) / 10,
  4 => duration - r.nextInt(20) / 10,
  _ => r.nextDouble() * duration,
};

PlaybackSettings randomStored(Random r, double duration) => PlaybackSettings(
  speedEnabled: r.nextBool(),
  speed: r.nextInt(25) / 10,
  loopEnabled: r.nextBool(),
  loopStart: r.nextBool() ? 0 : randomTime(r, duration),
  loopEnd: r.nextBool() ? 0 : randomTime(r, duration),
);

void checkLoop(PlayerService s, FakeCore core, String after) {
  const eps = 1e-9;
  final st = s.settings;
  final d = s.duration;
  // In a title shorter than 1 s there is no loop; both bounds only stay inside the file.
  expect(
    st.loopStart >= 0 &&
        st.loopStart <= d &&
        st.loopEnd >= 0 &&
        st.loopEnd <= d,
    isTrue,
    reason: 'loop ${st.loopStart}–${st.loopEnd} outside 0–$d after $after',
  );
  if (d >= PlayerService.minLoopSeconds) {
    expect(
      st.loopEnd - st.loopStart >= PlayerService.minLoopSeconds - eps,
      isTrue,
      reason:
          'loop ${st.loopStart}–${st.loopEnd} shorter than 1 s after $after',
    );
  }
  final active = s.activeLoop;
  expect(core.loop, active, reason: 'core loop after $after');
  if (active != null) {
    expect(active.$2 - active.$1, greaterThanOrEqualTo(1 - eps));
    expect(st.loopEnabled, isTrue);
  } else {
    expect(
      !st.loopEnabled || d < PlayerService.minLoopSeconds,
      isTrue,
      reason: 'loop on, but none in the core after $after',
    );
  }
}

void main() {
  group('#10/AK1 loop bounds', () {
    property('loop bounds are valid after every change', (r) async {
      final core = FakeCore();
      final timers = <FakeTimer>[];
      final s = PlayerService(
        core,
        timerFactory: (d, f) {
          final t = FakeTimer(d, f);
          timers.add(t);
          return t;
        },
      );
      final duration = switch (r.nextInt(4)) {
        0 => r.nextInt(10) / 10 + 0.1, // shorter than 1 s
        1 => 1.0 + r.nextInt(5) / 10,
        _ => 2 + r.nextDouble() * 600,
      };
      final loaded = s.load(
        'a.mp3',
        trackId: 'a',
        settings: randomStored(r, duration),
      );
      core.finishLoad(duration);
      for (final t in timers.where((t) => t.active).toList()) {
        t.onTick(t);
      }
      expect(await loaded, isTrue);
      checkLoop(s, core, 'load of ${s.settings}');
      for (var i = 0, n = 5 + r.nextInt(30); i < n; i++) {
        final t = randomTime(r, duration);
        final op = switch (r.nextInt(7)) {
          0 => () => s.setLoopStart(t),
          1 => () => s.setLoopEnd(t),
          2 => () => s.setLoopEnabled(r.nextBool()),
          3 => () => s.setSpeed(r.nextInt(30) / 10),
          4 => () => s.adjustSpeed(r.nextInt(7) - 3),
          5 => () => s.setRamp(enabled: r.nextBool(), start: r.nextInt(250)),
          _ => () => s.updateSettings(
            (x) => x.copyWith(
              loopStart: randomTime(r, duration),
              loopEnd: randomTime(r, duration),
              loopEnabled: r.nextBool(),
            ),
          ),
        };
        final before = s.settings;
        op();
        checkLoop(s, core, 'step $i from $before');
      }
      s.dispose();
    });
  });

  group('#10/AK1 loop bounds of stored settings', () {
    Future<PlayerService> loaded(double duration, PlaybackSettings st) async {
      final core = FakeCore();
      final timers = <FakeTimer>[];
      final s = PlayerService(
        core,
        timerFactory: (d, f) {
          final t = FakeTimer(d, f);
          timers.add(t);
          return t;
        },
      );
      final f = s.load('a.mp3', trackId: 'a', settings: st);
      core.finishLoad(duration);
      for (final t in timers.toList()) {
        t.onTick(t);
      }
      await f;
      return s;
    }

    test(
      'a loop end beyond the duration keeps 1 s: start moves back',
      () async {
        // Loop 10–11 s from another device, here the file is 10.5 s long: end 10.5, start 10.5 − 1 = 9.5.
        final s = await loaded(
          10.5,
          const PlaybackSettings(loopEnabled: true, loopStart: 10, loopEnd: 11),
        );
        expect((s.settings.loopStart, s.settings.loopEnd), (9.5, 10.5));
        expect(s.activeLoop, (9.5, 10.5));
      },
    );

    test(
      'a stored loop shorter than 1 s gets its end at start + 1 s',
      () async {
        // 3.0–3.4 s in a 60 s title: end = 3.0 + 1 = 4.0.
        final s = await loaded(
          60,
          const PlaybackSettings(loopEnabled: true, loopStart: 3, loopEnd: 3.4),
        );
        expect(s.activeLoop, (3.0, 4.0));
      },
    );
  });

  group('#10/AK1 time format', () {
    property('parse(format(x)) == x for times', (r) {
      // whole seconds up to 100 h: mm:ss and h:mm:ss
      final whole = r.nextInt(360000).toDouble();
      expect(parseTime(formatTime(whole)), whole, reason: formatTime(whole));
      // tenths: 01:23.4
      final tenths = r.nextInt(3600000) / 10;
      final p = parseTime(formatTimePrecise(tenths));
      expect(p, isNotNull, reason: formatTimePrecise(tenths));
      expect((p! - tenths).abs() < 1e-6, isTrue, reason: '$tenths → $p');
      // the time field picks either form and still reads back
      final f = parseTime(formatTimeField(tenths));
      expect(
        (f! - tenths).abs() < 1e-6,
        isTrue,
        reason: formatTimeField(tenths),
      );
      // and a formatted text comes back unchanged
      expect(formatTime(parseTime(formatTime(whole))!), formatTime(whole));
      // any time: format drops the fraction, parse(format(x)) == floor(x)
      final any = r.nextDouble() * 360000;
      expect(parseTime(formatTime(any)), any.floorToDouble());
    });
  });
}
