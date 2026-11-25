// #146: subfolders in the library: tree, moving, cycle guard, deleting, old files and the sync. Libraries
// in memory only, never the real library.
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/library/folder_tree.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/sync/in_memory_provider.dart';

import 'fakes.dart';
import 'sync_test.dart' show Device, device, tick;

Library _lib(MemoryFileStore store, {int seed = 1}) => Library(
  store,
  probe: (_) => 2.5,
  readSource: (p) async => utf8.encode('audio $p'),
  saveDelay: Duration.zero,
  random: Random(seed),
);

Future<Library> _loaded(MemoryFileStore store, {int seed = 1}) async {
  final l = _lib(store, seed: seed);
  await l.load();
  return l;
}

TrackFolder _f(String id, [String? parent]) =>
    TrackFolder(id: id, name: id, parentId: parent);

Map<String, String?> _parents(List<TrackFolder> folders) => {
  for (final f in folders) f.id: f.parentId,
};

Hlc _h(int millis, [String device = 'a']) => Hlc(millis, 0, device);

List<String> _names(Library l) => [
  for (final e in l.folderTree) '${'  ' * e.depth}${e.folder.name}',
];

void main() {
  group('#146/AK9 tree', () {
    test('order: each folder followed by its subfolders, siblings by name', () {
      final order = folderTreeOrder([
        _f('a'),
        _f('a1', 'a'),
        _f('a2', 'a'),
        _f('b'),
        _f('b1', 'b'),
        _f('x', 'a1'),
      ]);
      expect(
        [for (final e in order) '${e.depth}${e.folder.id}'],
        ['0a', '1a1', '2x', '1a2', '0b', '1b1'],
      );
    });

    test('a folder whose parent is not in the list shows on the top level', () {
      final order = folderTreeOrder([_f('a', 'gone'), _f('b', 'a')]);
      expect(
        [for (final e in order) (e.folder.id, e.depth)],
        [('a', 0), ('b', 1)],
      );
    });

    test('subtree: the folder and all folders below it, at any depth', () {
      final all = [_f('a'), _f('b', 'a'), _f('c', 'b'), _f('d'), _f('e', 'd')];
      expect(folderSubtree(all, 'a'), {'a', 'b', 'c'});
      expect(folderSubtree(all, 'c'), {'c'});
      expect(folderSubtree(all, 'd'), {'d', 'e'});
    });

    test('valid tree: missing parent and own parent go to the top level', () {
      final r = validFolderTree([
        _f('a', 'gone'),
        _f('b', 'b'),
        _f('c', 'a'),
      ], (_) => null);
      expect(_parents(r), {'a': null, 'b': null, 'c': 'a'});
    });

    test('valid tree: a valid tree stays as it is', () {
      final input = [_f('a'), _f('b', 'a'), _f('c', 'b')];
      final r = validFolderTree(input, (_) => _h(1));
      expect(_parents(r), _parents(input));
      for (var i = 0; i < input.length; i++) {
        expect(identical(r[i], input[i]), isTrue);
      }
    });
  });

  group('#146/AK1 new subfolder', () {
    test(
      'a subfolder lies in the chosen folder; top level without parent',
      () async {
        final l = await _loaded(MemoryFileStore());
        final rec = l.createFolder('Recordings');
        final day = l.createFolder('2026-11-25', parentId: rec.id);
        final top = l.createFolder('Other');
        expect(day.parentId, rec.id);
        expect(top.parentId, isNull);
        expect(_names(l), ['Other', 'Recordings', '  2026-11-25']);
      },
    );

    test(
      'a parent that does not exist gives a folder on the top level',
      () async {
        final l = await _loaded(MemoryFileStore());
        expect(l.createFolder('x', parentId: 'nope').parentId, isNull);
      },
    );

    test('the subfolder survives a restart', () async {
      final store = MemoryFileStore();
      final l = await _loaded(store);
      final a = l.createFolder('A');
      final b = l.createFolder('B', parentId: a.id);
      await l.save();
      final again = await _loaded(store);
      expect(again.folder(b.id)?.parentId, a.id);
    });

    test('a track goes into a subfolder like into any folder', () async {
      final l = await _loaded(MemoryFileStore());
      final a = l.createFolder('A');
      final b = l.createFolder('B', parentId: a.id);
      await l.importFiles(['x.mp3']);
      final t = l.tracks.single;
      l.moveTracks({t.id}, b.id);
      expect(l.track(t.id)?.folderId, b.id);
      expect(l.sortedTracksIn(b.id).map((t) => t.id), [t.id]);
      expect(l.sortedTracksIn(a.id), isEmpty);
    });

    test(
      'listed tracks follow the tree: a subfolder right after its folder',
      () async {
        final l = await _loaded(MemoryFileStore());
        final a = l.createFolder('A');
        final z = l.createFolder('Z', parentId: a.id);
        final b = l.createFolder('B');
        await l.importFiles(['1.mp3']);
        await l.importFiles(['2.mp3']);
        await l.importFiles(['3.mp3']);
        final [t1, t2, t3] = l.tracks;
        l.moveTracks({t1.id}, b.id);
        l.moveTracks({t2.id}, z.id);
        l.moveTracks({t3.id}, a.id);
        expect(l.listedTracks.map((t) => t.id), [t3.id, t2.id, t1.id]);
        expect(l.sortedFolders.map((f) => f.name), ['A', 'Z', 'B']);
      },
    );
  });

  group('#146/AK3 moving folders', () {
    test('into another folder and back to the top level', () async {
      final store = MemoryFileStore();
      final l = await _loaded(store);
      final a = l.createFolder('A');
      final b = l.createFolder('B');
      expect(l.moveFolder(b.id, a.id), isTrue);
      expect(l.folder(b.id)?.parentId, a.id);
      expect(l.moveFolder(b.id, null), isTrue);
      expect(l.folder(b.id)?.parentId, isNull);
      await l.save();
      expect((await _loaded(store)).folder(b.id)?.parentId, isNull);
    });

    test('the folder takes its subfolders and tracks with it', () async {
      final l = await _loaded(MemoryFileStore());
      final a = l.createFolder('A');
      final b = l.createFolder('B');
      final c = l.createFolder('C', parentId: b.id);
      await l.importFiles(['x.mp3']);
      l.moveTracks({l.tracks.single.id}, c.id);
      l.moveFolder(b.id, a.id);
      expect(_names(l), ['A', '  B', '    C']);
      expect(l.tracks.single.folderId, c.id);
    });

    test('a move tells the listeners once', () async {
      final l = await _loaded(MemoryFileStore());
      final a = l.createFolder('A');
      final b = l.createFolder('B');
      var calls = 0;
      l.addListener(() => calls++);
      l.moveFolder(b.id, a.id);
      expect(calls, 1);
    });

    test('moving where it already is changes nothing', () async {
      final l = await _loaded(MemoryFileStore());
      final a = l.createFolder('A');
      final b = l.createFolder('B', parentId: a.id);
      var calls = 0;
      l.addListener(() => calls++);
      expect(l.moveFolder(b.id, a.id), isTrue);
      expect(calls, 0);
    });

    test('a folder that does not exist does not move', () async {
      final l = await _loaded(MemoryFileStore());
      final a = l.createFolder('A');
      expect(l.moveFolder('nope', a.id), isFalse);
      expect(l.canMoveFolder('nope', null), isFalse);
      expect(l.moveFolder(a.id, 'nope'), isFalse);
      expect(l.folder(a.id)?.parentId, isNull);
    });
  });

  group('#146/AK4 no cycles', () {
    test('not into itself and not into one of its subfolders', () async {
      final l = await _loaded(MemoryFileStore());
      final a = l.createFolder('A');
      final b = l.createFolder('B', parentId: a.id);
      final c = l.createFolder('C', parentId: b.id);
      var calls = 0;
      l.addListener(() => calls++);
      for (final target in [a.id, b.id, c.id]) {
        expect(l.canMoveFolder(a.id, target), isFalse, reason: target);
        expect(l.moveFolder(a.id, target), isFalse, reason: target);
      }
      expect(calls, 0);
      expect(_parents(l.folders), {a.id: null, b.id: a.id, c.id: b.id});
      // the other way round is fine
      expect(l.canMoveFolder(c.id, a.id), isTrue);
      expect(l.canMoveFolder(b.id, null), isTrue);
    });
  });

  group('#146/AK5 deleting a folder with subfolders', () {
    test('counts tracks and subfolders at every depth', () async {
      final l = await _loaded(MemoryFileStore());
      final a = l.createFolder('A');
      final b = l.createFolder('B', parentId: a.id);
      final c = l.createFolder('C', parentId: b.id);
      final other = l.createFolder('Other');
      for (final n in ['1', '2', '3', '4']) {
        await l.importFiles(['$n.mp3']);
      }
      final [t1, t2, t3, t4] = l.tracks;
      l.moveTracks({t1.id}, a.id);
      l.moveTracks({t2.id}, b.id);
      l.moveTracks({t3.id}, c.id);
      l.moveTracks({t4.id}, other.id);
      expect(l.folderContents(a.id), (tracks: 3, folders: 2));
      expect(l.folderContents(b.id), (tracks: 2, folders: 1));
      expect(l.folderContents(c.id), (tracks: 1, folders: 0));
    });

    test('removes the folder and everything below it, nothing else', () async {
      final store = MemoryFileStore();
      final l = await _loaded(store);
      final a = l.createFolder('A');
      final b = l.createFolder('B', parentId: a.id);
      l.createFolder('C', parentId: b.id);
      final other = l.createFolder('Other');
      final inOther = l.createFolder('In other', parentId: other.id);
      await l.importFiles(['1.mp3']);
      await l.importFiles(['2.mp3']);
      final [t1, t2] = l.tracks;
      l.moveTracks({t1.id}, b.id);
      l.moveTracks({t2.id}, inOther.id);
      l.deleteFolder(a.id);
      expect(_names(l), ['Other', '  In other']);
      expect(l.track(t1.id)?.folderId, isNull);
      expect(l.track(t2.id)?.folderId, inOther.id);
      await l.save();
      final again = await _loaded(store);
      expect(_names(again), ['Other', '  In other']);
      expect(again.state.folders.values.where((r) => !r.alive), hasLength(3));
    });
  });

  group('#146/AK6 folders with the same name', () {
    test('in different parents and on the same level', () async {
      final l = await _loaded(MemoryFileStore());
      final a = l.createFolder('Same');
      final b = l.createFolder('Same');
      final c = l.createFolder('Same', parentId: a.id);
      l.createFolder('Same', parentId: b.id);
      l.createFolder('Same', parentId: c.id);
      expect(l.folderTree, hasLength(5));
      expect(l.moveFolder(b.id, c.id), isTrue);
      expect(l.folderTree.map((e) => e.depth).reduce(max), 3);
    });
  });

  group('#146/AK7 a library.json without subfolders', () {
    test('folders without a parent are written as before', () async {
      final store = MemoryFileStore();
      final l = await _loaded(store);
      l.createFolder('A');
      await l.save();
      final j = jsonDecode(utf8.decode(store.files[Library.indexName]!)) as Map;
      final rec = (j['folders'] as Map).values.single as Map;
      expect((rec['values'] as Map).keys, unorderedEquals(['name', 'sync']));
    });

    test('a file of the former version is read unchanged, all folders on the top level', () async {
      final store = MemoryFileStore();
      const stamp = '2026-03-01T00:00:00.000Z-0000-aaaaaaaaaaaaaaaa';
      final old = {
        'formatVersion': SharedState.formatVersion,
        'tracks': <String, Object?>{},
        'folders': {
          for (final n in ['A', 'B', 'C'])
            'F-$n': {
              'values': {'name': n, 'sync': true},
              'stamps': {'name': stamp, 'sync': stamp},
            },
        },
        'settings': {
          'values': <String, Object?>{},
          'stamps': <String, Object?>{},
        },
      };
      final raw = utf8.encode(jsonEncode(SharedState.fromJson(old).toJson()));
      store.files[Library.indexName] = raw;
      final l = await _loaded(store);
      expect(l.lastError, isNull);
      expect(_names(l), ['A', 'B', 'C']);
      expect(l.folders.every((f) => f.parentId == null), isTrue);
      await l.save();
      expect(
        SharedState.fromJson(
          (jsonDecode(utf8.decode(store.files[Library.indexName]!)) as Map)
              .cast(),
        ).folders.values.every((r) => !r.values.containsKey('parent')),
        isTrue,
      );
    });

    test(
      'a folder moved back to the top level clears its stamped parent',
      () async {
        final store = MemoryFileStore();
        final l = await _loaded(store);
        final a = l.createFolder('A');
        final b = l.createFolder('B', parentId: a.id);
        await l.save();
        l.moveFolder(b.id, null);
        await l.save();
        final r = l.state.folders[b.id]!;
        expect(r.values.containsKey(TrackFolder.parentField), isTrue);
        expect(r.values[TrackFolder.parentField], isNull);
      },
    );
  });

  group('#146/AK2 open and closed per device', () {
    test(
      'a closed folder stays closed after a restart, only on this device',
      () async {
        final store = MemoryFileStore();
        final l = await _loaded(store);
        final a = l.createFolder('A');
        final b = l.createFolder('B', parentId: a.id);
        expect(l.folderClosed(b.id), isFalse);
        var calls = 0;
        l.addListener(() => calls++);
        await l.setFolderClosed(b.id, true);
        await l.setFolderClosed(b.id, true);
        expect(calls, 1);
        await l.save();
        final again = await _loaded(store);
        expect(again.folderClosed(b.id), isTrue);
        expect(again.folderClosed(a.id), isFalse);
        // device-local: not in the shared state
        expect(jsonEncode(again.state.toJson()), isNot(contains('closed')));
        await again.setFolderClosed(b.id, false);
        expect((await _loaded(store)).folderClosed(b.id), isFalse);
      },
    );

    test('valid tree: equal stamps break the tie by ID, a missing stamp counts as oldest', () {
      final tie = validFolderTree([_f('y', 'x'), _f('x', 'y')], (_) => _h(1));
      expect(_parents(tie), {'y': 'x', 'x': null});
      final none = validFolderTree([
        _f('x', 'y'),
        _f('y', 'x'),
      ], (id) => {'x': _h(1)}[id]);
      expect(_parents(none), {'x': 'y', 'y': null});
      final none2 = validFolderTree([
        _f('y', 'x'),
        _f('x', 'y'),
      ], (id) => {'y': _h(1)}[id]);
      expect(_parents(none2), {'y': 'x', 'x': null});
    });

    test('valid tree: the same result in any order of the folders', () {
      final all = [
        _f('a', 'b'),
        _f('b', 'c'),
        _f('c', 'a'),
        _f('d', 'e'),
        _f('e', 'd'),
      ];
      Hlc? stamp(String id) =>
          {'a': _h(4), 'b': _h(1), 'c': _h(7), 'd': _h(2), 'e': _h(3)}[id];
      final expected = {'a': 'b', 'b': null, 'c': 'a', 'd': null, 'e': 'd'};
      expect(_parents(validFolderTree(all, stamp)), expected);
      expect(_parents(validFolderTree(all.reversed.toList(), stamp)), expected);
    });

    test('the folder structure goes to the other device', () async {
      final cloud = InMemoryProvider();
      final a = await device(cloud, 1);
      final b = await device(cloud, 2);
      final rec = a.library.createFolder('Recordings');
      final day = a.library.createFolder('2026-11-25', parentId: rec.id);
      final t = await a.add('take.mp3', folderId: day.id);
      await a.sync.sync();
      await b.sync.sync();
      expect(_names(b.library), ['Recordings', '  2026-11-25']);
      expect(b.library.track(t.id)?.folderId, day.id);
      // moved back to the top level on b, seen on a
      tick();
      b.library.moveFolder(day.id, null);
      await b.sync.sync();
      await a.sync.sync();
      expect(_names(a.library), ['2026-11-25', 'Recordings']);
    });

    test(
      'concurrent moves into each other end in a valid tree on both devices',
      () async {
        final cloud = InMemoryProvider();
        final a = await device(cloud, 1);
        final b = await device(cloud, 2);
        final x = a.library.createFolder('X');
        final y = a.library.createFolder('Y');
        await a.sync.sync();
        await b.sync.sync();
        tick();
        a.library.moveFolder(x.id, y.id); // earlier
        tick();
        b.library.moveFolder(y.id, x.id); // later: wins
        await a.sync.sync();
        await b.sync.sync();
        await a.sync.sync();
        for (final d in [a, b]) {
          expect(_names(d.library), ['X', '  Y'], reason: '$d');
          expect(d.library.folder(x.id)?.parentId, isNull);
        }
        // still the same after a restart of each device and another round
        tick();
        await b.sync.sync();
        await a.sync.sync();
        final again = Device(cloud, 1)..store.files.addAll(a.store.files);
        await again.library.load();
        addTearDown(again.sync.dispose);
        expect(_names(again.library), ['X', '  Y']);
      },
    );

    test(
      'a folder put into one deleted elsewhere lands on the top level',
      () async {
        final cloud = InMemoryProvider();
        final a = await device(cloud, 1);
        final b = await device(cloud, 2);
        final x = a.library.createFolder('X');
        final y = a.library.createFolder('Y');
        await a.sync.sync();
        await b.sync.sync();
        tick();
        a.library.moveFolder(x.id, y.id);
        tick();
        b.library.deleteFolder(y.id);
        await a.sync.sync();
        await b.sync.sync();
        await a.sync.sync();
        expect(_names(a.library), ['X']);
        expect(_names(b.library), ['X']);
      },
    );
  });
}
