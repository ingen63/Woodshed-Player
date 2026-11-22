// #115/AK8–AK10: order of a list being played: repeat, «Next», «Previous» and shuffle. Pure Dart, no player.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/player/play_queue.dart';

/// The rows a list of [length] plays from [q] until it ends (at most [limit] rows).
List<int> playAll(PlayQueue q, int length, Random r, {int limit = 50}) {
  final rows = [q.index];
  PlayQueue? n = q;
  while (rows.length < limit) {
    n = n!.next(length, random: r);
    if (n == null) break;
    rows.add(n.index);
  }
  return rows;
}

void main() {
  group('#115/AK8 repeat', () {
    test('a tap goes off → list → track → off', () {
      expect(Repeat.off.following, Repeat.list);
      expect(Repeat.list.following, Repeat.track);
      expect(Repeat.track.following, Repeat.off);
    });

    test('off: the list ends after its last row', () {
      expect(const PlayQueue('p', 1).next(3), const PlayQueue('p', 2));
      expect(const PlayQueue('p', 2).next(3), isNull);
      expect(const PlayQueue.folder('f', 2).next(3), isNull);
    });

    test('list: after the last row the first follows', () {
      expect(
        const PlayQueue('p', 2).next(3, repeat: Repeat.list),
        const PlayQueue('p', 0),
      );
      expect(
        const PlayQueue.folder(null, 0).next(3, repeat: Repeat.list),
        const PlayQueue.folder(null, 1),
      );
    });

    test('track: the same row again at its end, «Next» by hand moves on', () {
      const q = PlayQueue('p', 1);
      expect(q.next(3, repeat: Repeat.track), q);
      expect(
        q.next(3, repeat: Repeat.track, manual: true),
        const PlayQueue('p', 2),
      );
      expect(
        const PlayQueue('p', 2).next(3, repeat: Repeat.track, manual: true),
        const PlayQueue('p', 0),
      );
    });

    test('a row outside a list that got shorter ends it', () {
      expect(const PlayQueue('p', 3).next(3, repeat: Repeat.list), isNull);
      expect(const PlayQueue('p', 3).previous(3, repeat: Repeat.list), isNull);
    });
  });

  group('#115/AK9 next and previous', () {
    test('a folder goes on with its next row; previous goes back one row', () {
      const q = PlayQueue.folder('f', 1);
      expect(q.next(3, manual: true), const PlayQueue.folder('f', 2));
      expect(q.previous(3), const PlayQueue.folder('f', 0));
    });

    test(
      'before the first row: nothing, or the last row if the list repeats',
      () {
        expect(const PlayQueue('p', 0).previous(3), isNull);
        expect(
          const PlayQueue('p', 0).previous(3, repeat: Repeat.list),
          const PlayQueue('p', 2),
        );
        expect(
          const PlayQueue('p', 0).previous(3, repeat: Repeat.track),
          const PlayQueue('p', 2),
        );
      },
    );

    test('a folder and a playlist are different lists', () {
      expect(
        const PlayQueue('x', 0) == const PlayQueue.folder('x', 0),
        isFalse,
      );
      expect(const PlayQueue('x', 0).isPlaylist, isTrue);
      expect(const PlayQueue.folder('x', 0).isPlaylist, isFalse);
      expect(
        const PlayQueue.folder('x', 0).at(2),
        const PlayQueue.folder('x', 2),
      );
      expect(const PlayQueue('x', 0).at(2), const PlayQueue('x', 2));
    });
  });

  group('#115/AK10 shuffle', () {
    test('each row once per pass, starting with the row playing', () {
      for (var seed = 0; seed < 20; seed++) {
        final r = Random(seed);
        final q = const PlayQueue('p', 3).shuffle(6, r);
        expect(q.order.first, 3);
        expect(q.shuffled, isTrue);
        final rows = playAll(q, 6, r);
        expect(rows.length, 6, reason: 'seed $seed');
        expect(rows.toSet(), {0, 1, 2, 3, 4, 5}, reason: 'seed $seed');
      }
    });

    test('a row past the end of the list is not part of the order', () {
      final q = const PlayQueue('p', 3).shuffle(3, Random(1));
      expect(q.order.toSet(), {0, 1, 2});
    });

    test('the order is random', () {
      final orders = {
        for (var seed = 0; seed < 20; seed++)
          const PlayQueue('p', 0).shuffle(6, Random(seed)).order.join(),
      };
      expect(orders.length, greaterThan(5));
    });

    test('repeat list: a new pass, again each row once, not starting with the row just played', () {
      for (var seed = 0; seed < 30; seed++) {
        final r = Random(seed);
        var q = const PlayQueue('p', 0).shuffle(4, r);
        for (var i = 0; i < 3; i++) {
          q = q.next(4, random: r)!;
        }
        final last = q.index;
        final pass = <int>[];
        for (var i = 0; i < 4; i++) {
          q = q.next(4, repeat: Repeat.list, random: r)!;
          pass.add(q.index);
        }
        expect(pass.toSet(), {0, 1, 2, 3}, reason: 'seed $seed');
        expect(pass.first, isNot(last), reason: 'seed $seed');
      }
    });

    test('a list of one row repeats that row', () {
      final r = Random(1);
      final q = const PlayQueue('p', 0).shuffle(1, r);
      expect(q.next(1, random: r), isNull);
      expect(q.next(1, repeat: Repeat.list, random: r)?.index, 0);
    });

    test('previous goes back in the shuffled order', () {
      final r = Random(4);
      final q = const PlayQueue('p', 2).shuffle(5, r);
      final n = q.next(5, random: r)!;
      expect(n.previous(5, random: r), q);
      expect(q.previous(5, random: r), isNull);
      expect(
        q.previous(5, repeat: Repeat.list, random: r),
        q.at(q.order.last, order: q.order),
      );
    });

    test('a list that changed gets a new pass with the row playing', () {
      final r = Random(2);
      final q = const PlayQueue('p', 1).shuffle(3, r);
      final rows = playAll(q, 5, r);
      expect(rows.toSet(), {0, 1, 2, 3, 4});
      final back = q.previous(5, random: r);
      expect(back, isNull); // the new pass starts with row 1
    });

    test('shuffle off: the list goes on in its own order', () {
      final q = const PlayQueue('p', 1).shuffle(4, Random(3)).unshuffle();
      expect(q.shuffled, isFalse);
      expect(q, const PlayQueue('p', 1));
      expect(q.next(4), const PlayQueue('p', 2));
    });

    test('equal queues have equal hash codes; the order counts', () {
      final a = PlayQueue('p', 1, order: const [1, 0]);
      final b = PlayQueue('p', 1, order: const [1, 0]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == const PlayQueue('p', 1, order: [1, 2, 0]), isFalse);
      expect(a.toString(), contains('[1, 0]'));
      expect(
        const PlayQueue.folder('f', 0).toString(),
        'PlayQueue.folder(f, 0)',
      );
    });
  });
}
