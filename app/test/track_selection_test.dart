// #122: several tracks selected together (TrackSelection) and the library functions for several tracks
// (placeTracks, listedTracks). The library lives in a temporary folder.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/app/track_selection.dart';
import 'package:woodshed_player/library/library.dart';

import 'fakes.dart';

const order = ['a', 'b', 'c', 'd', 'e'];

void main() {
  group('TrackSelection', () {
    test('#122/AK1 ⌘-click adds a track and takes it out again', () {
      final s = TrackSelection();
      var told = 0;
      s.addListener(() => told++);
      s.toggle('b');
      s.toggle('d');
      expect(s.ids, {'b', 'd'});
      expect(s.length, 2);
      expect(s.contains('b'), isTrue);
      expect(s.anchor, 'd');
      s.toggle('b');
      expect(s.ids, {'d'});
      expect(s.contains('b'), isFalse);
      expect(told, 3);
    });

    test('#122/AK1 ⇧-click selects the range from the anchor, both ways', () {
      final s = TrackSelection()..toggle('b');
      s.extend('d', order);
      expect(s.inOrder(order), ['b', 'c', 'd']);
      expect(s.anchor, 'b', reason: 'the anchor stays for the next ⇧-click');

      final up = TrackSelection()..toggle('d');
      up.extend('a', order);
      expect(up.inOrder(order), ['a', 'b', 'c', 'd']);
    });

    test('#122/AK1 a new selection is empty and not in the selection mode', () {
      final s = TrackSelection();
      expect(s.isEmpty, isTrue);
      expect(s.mode, isFalse);
      expect(s.anchor, isNull);
    });

    test('#122/AK1 ⇧-click from the first row of the list', () {
      final s = TrackSelection()..click('a');
      s.extend('c', order);
      expect(s.inOrder(order), ['a', 'b', 'c']);
    });

    test('#122/AK1 ⇧-click keeps the tracks chosen with ⌘-click', () {
      final s = TrackSelection()
        ..toggle('a')
        ..toggle('c');
      s.extend('d', order);
      expect(s.inOrder(order), ['a', 'c', 'd']);
    });

    test('#122/AK1 ⇧-click without an anchor selects the track only', () {
      final s = TrackSelection();
      var told = 0;
      s.addListener(() => told++);
      s.extend('c', order);
      expect(s.ids, {'c'});
      expect(s.anchor, 'c');
      expect(told, 1);
      // an anchor no longer listed (e.g. its folder closed) counts as none
      final gone = TrackSelection()..click('x');
      gone.extend('b', order);
      expect(gone.ids, {'b'});
      expect(gone.anchor, 'b');
    });

    test(
      '#122/AK1 a plain click ends the selection and is the anchor of ⇧-click',
      () {
        final s = TrackSelection()
          ..toggle('a')
          ..toggle('b');
        var told = 0;
        s.addListener(() => told++);
        s.click('d');
        expect(s.isEmpty, isTrue);
        expect(s.anchor, 'd');
        expect(told, 1);
        s.click('e');
        expect(told, 1, reason: 'nothing changed, nobody is told');
        s.extend('c', order);
        expect(s.inOrder(order), ['c', 'd', 'e']);
      },
    );

    test('#122/AK2 long press or «Select» starts the selection mode', () {
      final s = TrackSelection();
      var told = 0;
      s.addListener(() => told++);
      s.start('c');
      expect(s.mode, isTrue);
      expect(s.ids, {'c'});
      expect(s.anchor, 'c');
      expect(told, 1);
      s.start();
      expect(s.ids, {'c'});
      expect(told, 2);
      final empty = TrackSelection()..start();
      expect(empty.mode, isTrue);
      expect(empty.isEmpty, isTrue);
      expect(empty.anchor, isNull);
      // a plain click (outside the mode) ends it
      empty.click('a');
      expect(empty.mode, isFalse);
    });

    test(
      '#122/AK2 a plain click ends the mode even without selected tracks',
      () {
        final s = TrackSelection()..start();
        var told = 0;
        s.addListener(() => told++);
        s.click('a');
        expect(s.mode, isFalse);
        expect(told, 1);
      },
    );

    test('#122/AK3 the selected tracks in the order of the list', () {
      final s = TrackSelection()
        ..toggle('d')
        ..toggle('x')
        ..toggle('a')
        ..toggle('y');
      expect(s.inOrder(order), ['a', 'd', 'x', 'y']);
      expect(s.ids.toList(), ['d', 'x', 'a', 'y']);
    });

    test('#122/AK6 Escape or a click on an empty area ends the selection', () {
      final s = TrackSelection()
        ..start('a')
        ..toggle('b');
      var told = 0;
      s.addListener(() => told++);
      s.clear();
      expect(s.isEmpty, isTrue);
      expect(s.mode, isFalse);
      expect(told, 1);
      s.clear();
      expect(told, 1, reason: 'nothing to end');
      final mode = TrackSelection()..start();
      mode.clear();
      expect(mode.mode, isFalse);
    });

    test('ids is a copy', () {
      final s = TrackSelection()..toggle('a');
      expect(() => s.ids.add('b'), throwsUnsupportedError);
    });

    test('tracks no longer in the library leave the selection', () {
      final s = TrackSelection()
        ..toggle('a')
        ..toggle('b');
      var told = 0;
      s.addListener(() => told++);
      s.retain((id) => id != 'a');
      expect(s.ids, {'b'});
      expect(told, 1);
      s.retain((_) => true);
      expect(told, 1);
    });
  });

  group('Library', () {
    late Directory dir;
    late Library lib;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('wp_selection_test');
      lib = TestApp(Directory('${dir.path}/lib')).library;
      await lib.load();
      final src = Directory('${dir.path}/src')..createSync();
      await lib.importFiles([
        for (final t in ['A', 'B', 'C', 'D', 'E'])
          (File('${src.path}/$t.mp3')..writeAsStringSync('audio $t')).path,
      ]);
      lib.sortOrder = TrackSortOrder.alphabetical;
    });
    tearDown(() => dir.deleteSync(recursive: true));

    String id(String title) =>
        lib.tracks.firstWhere((t) => t.title == title).id;
    List<String> titles(String? folder) => [
      for (final t in lib.sortedTracksIn(folder)) t.title,
    ];

    test(
      '#122/AK3 listedTracks: without a folder first, then folder by folder',
      () {
        final z = lib.createFolder('Z');
        final m = lib.createFolder('M');
        lib.moveTracks({id('A')}, z.id);
        lib.moveTracks({id('B'), id('E')}, m.id);
        expect(
          [for (final t in lib.listedTracks) t.title],
          ['C', 'D', 'B', 'E', 'A'],
        );
      },
    );

    test('#122/AK4 placeTracks into a folder: all of them, positions kept', () {
      final f = lib.createFolder('F');
      lib.placeTracks({id('D'), id('B')}, f.id);
      expect(titles(f.id), ['B', 'D']);
      expect(titles(null), ['A', 'C', 'E']);
      expect(lib.sortOrder, TrackSortOrder.alphabetical);
    });

    test('#122/AK4 placeTracks before a track: together, in their order', () {
      lib.placeTracks({id('D'), id('E')}, null, beforeId: id('B'));
      expect(titles(null), ['A', 'D', 'E', 'B', 'C']);
      expect(lib.sortOrder, TrackSortOrder.custom);
    });

    test('#122/AK4 placeTracks before a track of another folder', () {
      final f = lib.createFolder('F');
      lib.moveTracks({id('A'), id('B')}, f.id);
      lib.placeTracks({id('C'), id('E')}, f.id, beforeId: id('B'));
      expect(titles(f.id), ['A', 'C', 'E', 'B']);
      expect(titles(null), ['D']);
    });

    test(
      '#122/AK4 placeTracks before an unknown track puts them at the end',
      () {
        lib.placeTracks({id('A')}, null, beforeId: 'gone');
        expect(titles(null), ['B', 'C', 'D', 'E', 'A']);
      },
    );

    test(
      '#122/AK4 placeTracks onto one of themselves or with none moves nothing',
      () {
        var told = 0;
        lib.addListener(() => told++);
        lib.placeTracks({id('A'), id('B')}, null, beforeId: id('B'));
        lib.placeTracks({}, null);
        expect(told, 0);
        expect(titles(null), ['A', 'B', 'C', 'D', 'E']);
        expect(lib.sortOrder, TrackSortOrder.alphabetical);
      },
    );

    test('placeTrack is placeTracks for one track', () {
      lib.placeTrack(id('E'), null, beforeId: id('A'));
      expect(titles(null), ['E', 'A', 'B', 'C', 'D']);
      lib.placeTrack(id('A'), null, beforeId: id('A'));
      expect(titles(null), ['E', 'A', 'B', 'C', 'D']);
    });
  });
}
