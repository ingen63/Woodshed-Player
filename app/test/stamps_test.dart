// #61: rules of the stamps and the shared state (stamps.dart, #36), one per test; found by mutation
// testing (make mutants).
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/library/stamps.dart';

void main() {
  group('#36/AK1 stamps', () {
    test('the time of a stamp is UTC', () {
      final t = const Hlc(1000, 0, 'a').time;
      expect(t.isUtc, isTrue);
      expect(t, DateTime.utc(1970, 1, 1, 0, 0, 1));
    });

    test('a stamp is neither greater nor smaller than an equal one', () {
      const a = Hlc(5, 1, 'a');
      const b = Hlc(5, 1, 'a');
      expect(a > b, isFalse);
      expect(a < b, isFalse);
      expect(a < const Hlc(5, 2, 'a'), isTrue);
      expect(const Hlc(5, 2, 'a') > a, isTrue);
    });

    test('parse rejects a stamp without device, counter or time', () {
      for (final s in ['1-2-', '1--d', '-2-d', '12d', '1-2d', '']) {
        expect(() => Hlc.parse(s), throwsFormatException, reason: s);
      }
      expect(Hlc.parse('1-2-d'), const Hlc(1, 2, 'd'));
      expect(Hlc.parse('1-2-d-e'), const Hlc(1, 2, 'd-e'));
    });

    test('parse accepts the largest time and counter, not more', () {
      final max = '${Hlc.maxMillis}-${Hlc.maxCounter}-d';
      expect(Hlc.parse(max), const Hlc(Hlc.maxMillis, Hlc.maxCounter, 'd'));
      expect(
        () => Hlc.parse('${Hlc.maxMillis + 1}-0-d'),
        throwsFormatException,
      );
      expect(
        () => Hlc.parse('0-${Hlc.maxCounter + 1}-d'),
        throwsFormatException,
      );
    });

    test('the clock counts up within the same millisecond', () {
      final c = HlcClock('d', now: () => DateTime.utc(2026));
      final t0 = c.tick();
      expect(c.tick(), Hlc(t0.millis, 1, 'd'));
    });

    test(
      'an observed stamp with a smaller counter in the same ms is ignored',
      () {
        final c = HlcClock('d', now: () => DateTime.utc(2026));
        final t0 = c.tick();
        c.tick();
        c.tick(); // counter 2
        c.observe(Hlc(t0.millis, 0, 'x'));
        expect(c.tick(), Hlc(t0.millis, 3, 'd'));
      },
    );

    test('an observed older stamp is ignored even with a higher counter', () {
      final c = HlcClock('d', now: () => DateTime.utc(2026));
      final t0 = c.tick();
      c.observe(Hlc(t0.millis - 1, 50, 'x'));
      expect(c.tick(), Hlc(t0.millis, 1, 'd'));
    });

    test('an observed stamp with a higher counter in the same ms counts', () {
      final c = HlcClock('d', now: () => DateTime.utc(2026));
      final t0 = c.tick();
      c.observe(Hlc(t0.millis, 7, 'x'));
      expect(c.tick(), Hlc(t0.millis, 8, 'd'));
    });
  });

  group('#36/AK1 equality of JSON values', () {
    test('numbers compare by value', () {
      expect(sameJson(47, 47.0), isTrue);
      expect(sameJson(47, 48), isFalse);
      expect(sameJson(47, '47'), isFalse);
    });

    test('lists compare element by element', () {
      expect(sameJson([1, 2], [1, 2.0]), isTrue);
      expect(sameJson([1, 2], [1, 3]), isFalse);
      expect(sameJson([1, 2], [1, 2, 3]), isFalse);
      expect(sameJson([1, 2, 3], [1, 2]), isFalse);
      expect(sameJson(<Object?>[], <Object?>[]), isTrue);
    });

    test('maps compare key by key', () {
      expect(sameJson({'a': 1}, {'a': 1.0}), isTrue);
      expect(sameJson({'a': 1}, {'a': 2}), isFalse);
      expect(sameJson({'a': 1}, {'b': 1}), isFalse);
      expect(sameJson({'a': 1}, {'a': 1, 'b': 2}), isFalse);
    });
  });

  group('#36/AK2 tombstones', () {
    test('a tombstone of exactly 90 days is kept, older ones go', () {
      final now = DateTime.utc(2026, 6, 1);
      final limit =
          now.millisecondsSinceEpoch -
          SharedState.tombstoneLifetime.inMilliseconds;
      StampedRecord deletedAt(int millis) => StampedRecord.create({
        't': 1,
      }, const Hlc(0, 0, 'd')).delete(Hlc(millis, 0, 'd'));
      final s = SharedState(
        tracks: {'exact': deletedAt(limit), 'older': deletedAt(limit - 1)},
        folders: {'exact': deletedAt(limit), 'older': deletedAt(limit - 1)},
      ).purge(now);
      expect(s.tracks.keys, ['exact']);
      expect(s.folders.keys, ['exact']);
    });
  });

  group('#98 tombstones after the 90 days', () {
    // Example of the issue: X stamped 2026-01-01 on A and B, A deletes it on 2026-01-02, B does not sync
    // any more; A purges on 2026-04-03 (horizon 2026-01-03).
    Hlc at(DateTime t, String device) =>
        Hlc(t.millisecondsSinceEpoch, 0, device);
    final created = DateTime.utc(2026, 1, 1);
    final deletedOn = DateTime.utc(2026, 1, 2);
    final purgedOn = DateTime.utc(2026, 4, 3);
    final x = StampedRecord.create({'title': 'X'}, at(created, 'a'));
    final gone = x.delete(at(deletedOn, 'a'));

    test('#98/AK2 a purged track does not come back, in both directions', () {
      final a = SharedState(tracks: {'x': gone}).purge(purgedOn);
      final b = SharedState(tracks: {'x': x}).purge(purgedOn);
      expect(a.tracks, isEmpty);
      expect(a.purged, at(deletedOn, 'a'));
      expect(b.purged, isNull); // nothing removed on b
      for (final m in [a.merge(b), b.merge(a)]) {
        expect(m.tracks['x']?.alive ?? false, isFalse);
        expect(m.purged, at(deletedOn, 'a'));
        expect(m.toJson(), a.merge(b).toJson());
      }
    });

    test('#98/AK2 the horizon survives saving and loading', () {
      final a = SharedState(tracks: {'x': gone}).purge(purgedOn);
      final again = SharedState.fromJson(a.toJson());
      expect(again.purged, a.purged);
      final m = again.merge(SharedState(tracks: {'x': x}));
      expect(m.tracks['x']!.alive, isFalse);
      // the next purge removes what is left of it
      expect(m.purge(purgedOn).tracks, isEmpty);
      expect(SharedState.fromJson(SharedState.empty.toJson()).purged, isNull);
    });

    test('#98/AK3 a purged folder does not come back, in both directions', () {
      final a = SharedState(folders: {'f': gone}).purge(purgedOn);
      final b = SharedState(folders: {'f': x}).purge(purgedOn);
      expect(a.folders, isEmpty);
      for (final m in [a.merge(b), b.merge(a)]) {
        expect(m.folders['f']?.alive ?? false, isFalse);
      }
    });

    test('#98/AK4 importing the track again after the horizon revives it', () {
      final a = SharedState(tracks: {'x': gone}).purge(purgedOn);
      final reimported = a.copyWith(
        tracks: {
          'x': StampedRecord.create({
            'title': 'X',
          }, at(DateTime.utc(2026, 4, 4), 'a')),
        },
      );
      final b = SharedState(tracks: {'x': x});
      for (final m in [reimported.merge(b), b.merge(reimported)]) {
        expect(m.tracks['x']!.alive, isTrue);
      }
    });

    test(
      '#98 records changed after the horizon or known to both sides stay',
      () {
        final a = SharedState(tracks: {'x': gone}).purge(purgedOn);
        final newer = StampedRecord.create({
          'title': 'Y',
        }, at(DateTime.utc(2026, 1, 3), 'b'));
        final b = SharedState(
          tracks: {'y': newer, 'z': x},
          folders: {'f': newer},
        );
        final both = a.copyWith(tracks: {'z': x});
        for (final m in [both.merge(b), b.merge(both)]) {
          expect(m.tracks.keys.toSet(), {'y', 'z'});
          expect(m.folders.keys, ['f']);
        }
        // a device that never purged anything loses nothing, however old
        final fresh = SharedState(tracks: {'x': x});
        expect(fresh.merge(SharedState.empty).tracks.keys, ['x']);
        expect(SharedState.empty.merge(fresh).tracks.keys, ['x']);
      },
    );

    test(
      '#98 merging with horizons stays commutative, associative and idempotent',
      () {
        final r = Random(98);
        Hlc h() => Hlc(r.nextInt(6), r.nextInt(2), 'abc'[r.nextInt(3)]);
        StampedRecord one() {
          final values = <String, Object?>{
            for (final k in ['title', 'speed'])
              if (r.nextBool()) k: r.nextInt(3),
          };
          return StampedRecord(values, {
            for (final k in values.keys) k: h(),
          }, r.nextInt(3) == 0 ? h() : null);
        }

        SharedState state() => SharedState(
          tracks: {
            for (final id in ['t1', 't2', 't3'])
              if (r.nextBool()) id: one(),
          },
          folders: {
            for (final id in ['f1', 'f2'])
              if (r.nextBool()) id: one(),
          },
          purged: r.nextBool() ? h() : null,
        );
        void same(SharedState a, SharedState b) =>
            expect(sameJson(a.toJson(), b.toJson()), isTrue);
        for (var i = 0; i < 500; i++) {
          final s = [state(), state(), state()];
          same(s[0].merge(s[1]), s[1].merge(s[0]));
          same(s[0].merge(s[1]).merge(s[2]), s[0].merge(s[1].merge(s[2])));
          final m = s[0].merge(s[1]);
          same(m.merge(m), m);
          same(m.merge(s[1]), m);
        }
      },
    );
  });
}
