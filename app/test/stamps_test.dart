// #61: rules of the stamps and the shared state (stamps.dart, #36), one per test; found by mutation
// testing (make mutants).
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
}
