// #114: playlists next to folders. Libraries in memory with generated audio bytes, a cloud in memory
// (InMemoryProvider), the audio core as a fake; never the real library or a real account.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/sync/in_memory_provider.dart';
import 'package:woodshed_player/sync/sync_engine.dart';

import 'fakes.dart';

var clock = DateTime.utc(2026, 11, 1);

final sources = <String, Uint8List>{};

Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

/// One device: its own library in memory, the same cloud.
class Device {
  Device(this.cloud, this.seed, [MemoryFileStore? store])
    : store = store ?? MemoryFileStore() {
    library = open();
    sync = CloudSync(
      cloud,
      library,
      now: () => clock,
      changeDelay: const Duration(milliseconds: 20),
    );
  }

  final InMemoryProvider cloud;
  final int seed;
  final MemoryFileStore store;
  late final Library library;
  late final CloudSync sync;

  Library open() => Library(
    store,
    probe: (_) => 2.5,
    readSource: (s) async => sources[s],
    now: () => clock = clock.add(const Duration(seconds: 1)),
    saveDelay: Duration.zero,
    random: Random(seed),
  );

  Future<String> add(String name) async {
    sources.putIfAbsent(name, () => bytes('audio $name'));
    final r = await library.importFiles([name]);
    return [...r.imported, ...r.duplicates].single.id;
  }

  List<String> titles(String playlistId) => [
    for (final t in library.playlistTracks(playlistId)) t.title,
  ];

  String deviceFile() =>
      utf8.decode(cloud.files[CloudSync.deviceName(library.device.deviceId)]!);
}

Future<Device> device(InMemoryProvider cloud, int seed) async {
  final d = Device(cloud, seed);
  await d.library.load();
  addTearDown(d.sync.dispose);
  return d;
}

void main() {
  late InMemoryProvider cloud;
  setUp(() => cloud = InMemoryProvider());

  group('#114 playlists in the library', () {
    test('#114/AK1 create, rename and delete a playlist; its tracks stay in the library', () async {
      final a = await device(cloud, 1);
      final x = await a.add('Bossa.mp3');
      final p = a.library.createPlaylist('  Band  ');
      expect(a.library.playlists.single.name, 'Band');
      expect(a.library.createPlaylist(' ', fallback: 'New').name, 'New');
      a.library.addToPlaylist(p.id, [x]);
      a.library.renamePlaylist(p.id, 'Konzert');
      a.library.renamePlaylist(p.id, '   '); // blank keeps the name
      expect(a.library.playlist(p.id)!.name, 'Konzert');
      a.library.deletePlaylist(p.id);
      expect(a.library.playlist(p.id), isNull);
      expect(a.library.playlists.map((p) => p.name), ['New']);
      expect(a.library.track(x), isNotNull);
      expect(a.library.state.playlists[p.id]!.alive, isFalse);
    });

    test('#114/AK2 add tracks to a playlist and remove them; they stay in the library', () async {
      final a = await device(cloud, 1);
      final x = await a.add('Bossa.mp3');
      final y = await a.add('Zebra.mp3');
      final p = a.library.createPlaylist('Band');
      a.library.addToPlaylist(p.id, [x, y, 'unknown']);
      expect(a.titles(p.id), ['Bossa', 'Zebra']);
      a.library.addToPlaylist(p.id, [y], at: 0);
      expect(a.titles(p.id), ['Zebra', 'Bossa', 'Zebra']);
      a.library.removeFromPlaylist(p.id, 1);
      a.library.removeFromPlaylist(p.id, 7); // no such row
      expect(a.titles(p.id), ['Zebra', 'Zebra']);
      expect(a.library.tracks, hasLength(2));
    });

    test('#114/AK3 the same track in several playlists and several times in one, one file', () async {
      final a = await device(cloud, 1);
      final x = await a.add('Bossa.mp3');
      final p = a.library.createPlaylist('Band');
      final q = a.library.createPlaylist('Solo');
      a.library.addToPlaylist(p.id, [x, x]);
      a.library.addToPlaylist(p.id, [x]);
      a.library.addToPlaylist(q.id, [x]);
      expect(a.titles(p.id), ['Bossa', 'Bossa', 'Bossa']);
      expect(a.titles(q.id), ['Bossa']);
      expect(
        a.store.files.keys.where((k) => k.startsWith('Tracks/')),
        hasLength(1),
      );
    });

    test(
      '#114/AK4 the order changes by moving rows and is kept after a restart',
      () async {
        final a = await device(cloud, 1);
        final ids = [
          for (final n in ['A.mp3', 'B.mp3', 'C.mp3']) await a.add(n),
        ];
        final p = a.library.createPlaylist('Band');
        a.library.addToPlaylist(p.id, ids);
        a.library.movePlaylistEntry(p.id, 0, 3); // A to the end
        expect(a.titles(p.id), ['B', 'C', 'A']);
        a.library.movePlaylistEntry(p.id, 2, 0); // A back to the front
        a.library.movePlaylistEntry(p.id, 1, 3); // B to the end
        a.library.movePlaylistEntry(p.id, 5, 0); // no such row
        expect(a.titles(p.id), ['A', 'C', 'B']);
        final again = a.open();
        await again.load();
        expect(
          [for (final t in again.playlistTracks(p.id)) t.title],
          ['A', 'C', 'B'],
        );
      },
    );

    test(
      '#114/AK7 a track deleted from the library leaves every playlist',
      () async {
        final a = await device(cloud, 1);
        final x = await a.add('Bossa.mp3');
        final y = await a.add('Zebra.mp3');
        final p = a.library.createPlaylist('Band');
        final q = a.library.createPlaylist('Solo');
        a.library.addToPlaylist(p.id, [x, y, x]);
        a.library.addToPlaylist(q.id, [x]);
        a.library.delete({x});
        expect(a.titles(p.id), ['Zebra']);
        expect(a.titles(q.id), isEmpty);
        expect(a.library.playlist(p.id)!.entries, [y]);
      },
    );

    test(
      '#114/AK8 playlists are stored in library.json and read again',
      () async {
        final a = await device(cloud, 1);
        final x = await a.add('Bossa.mp3');
        final p = a.library.createPlaylist('Band');
        a.library.addToPlaylist(p.id, [x]);
        final json =
            jsonDecode(utf8.decode(a.store.files[Library.indexName]!)) as Map;
        expect((json['playlists'] as Map)[p.id]['values'], {
          'name': 'Band',
          'shared': true,
          'entries': [x],
        });
        expect(json['formatVersion'], SharedState.formatVersion);
        final again = a.open();
        await again.load();
        expect(again.playlists.single.name, 'Band');
      },
    );

    test('#114/AK8 a library.json without playlists (before #114) loads and is written as before', () async {
      final a = await device(cloud, 1);
      await a.add('Bossa.mp3');
      final json =
          jsonDecode(utf8.decode(a.store.files[Library.indexName]!)) as Map;
      expect(json.containsKey('playlists'), isFalse);
      expect(a.library.playlists, isEmpty);
    });

    test(
      '#114/AK9 a new playlist is shared; it can be kept on this device only',
      () async {
        final a = await device(cloud, 1);
        final p = a.library.createPlaylist('Band');
        expect(a.library.playlist(p.id)!.shared, isTrue);
        final x = await a.add('Bossa.mp3');
        a.library.addToPlaylist(p.id, [x, x]);
        final local = a.library.setPlaylistShared(p.id, false);
        expect(a.library.playlist(local)!.shared, isFalse);
        expect(a.library.playlists.single.name, 'Band');
        expect(a.titles(local), ['Bossa', 'Bossa']);
        expect(a.library.setPlaylistShared(local, false), local); // no change
        expect(a.library.setPlaylistShared('unknown', true), 'unknown');
        final again = a.open();
        await again.load();
        expect(again.playlist(local)!.shared, isFalse);
        expect(a.library.setPlaylistShared(local, true), local);
        expect(a.library.playlist(local)!.shared, isTrue);
      },
    );

    test(
      '#114/AK2, AK4 the first and the last row, and a row moved onto itself',
      () async {
        final a = await device(cloud, 1);
        final ids = [
          for (final n in ['A.mp3', 'B.mp3', 'C.mp3']) await a.add(n),
        ];
        final p = a.library.createPlaylist('Band');
        a.library.addToPlaylist(p.id, ids);
        a.library.movePlaylistEntry(p.id, 0, 2); // before the last row
        expect(a.titles(p.id), ['B', 'A', 'C']);
        a.library.movePlaylistEntry(p.id, 1, 1); // onto itself
        a.library.movePlaylistEntry(p.id, 1, 2); // just after itself
        expect(a.titles(p.id), ['B', 'A', 'C']);
        a.library.movePlaylistEntry(p.id, -1, 0);
        expect(a.titles(p.id), ['B', 'A', 'C']);
        a.library.removeFromPlaylist(p.id, 0);
        a.library.removeFromPlaylist(p.id, -1);
        a.library.removeFromPlaylist(p.id, 2);
        expect(a.titles(p.id), ['A', 'C']);
        a.library.addToPlaylist(p.id, [ids[1]], at: -3);
        a.library.addToPlaylist(p.id, [ids[1]], at: 99);
        expect(a.titles(p.id), ['B', 'A', 'C', 'B']);
        a.library.addToPlaylist('unknown', [ids[0]]);
        a.library.removeFromPlaylist('unknown', 0);
        expect(a.library.playlistTracks('unknown'), isEmpty);
      },
    );

    test('#114 every change of a playlist tells the listeners and is saved; no change, no message', () async {
      final a = await device(cloud, 1);
      final x = await a.add('Bossa.mp3');
      var notified = 0;
      a.library.addListener(() => notified++);
      String saved() => utf8.decode(a.store.files[Library.indexName]!);
      final p = a.library.createPlaylist('Band');
      expect(notified, 1);
      expect(saved(), contains('Band'));
      a.library.renamePlaylist(p.id, 'Konzert');
      expect(notified, 2);
      expect(saved(), contains('Konzert'));
      a.library.renamePlaylist(p.id, 'Konzert');
      a.library.renamePlaylist('unknown', 'X');
      expect(notified, 2);
      a.library.addToPlaylist(p.id, [x]);
      expect(notified, 3);
      final local = a.library.setPlaylistShared(p.id, false);
      expect(notified, 4);
      expect(saved(), contains(local));
      a.library.deletePlaylist(local);
      expect(notified, 5);
      a.library.deletePlaylist(local);
      expect(notified, 5);
    });

    test('#114/AK9 a playlist without the sharing field counts as shared', () {
      final p = Playlist.fromShared('p', const {'name': 'Band'});
      expect(p.shared, isTrue);
      expect(p.entries, isEmpty);
      expect(Playlist.fromShared('p', const {}).name, '');
    });

    test('#114 a damaged playlist in library.json counts as damaged', () async {
      final a = await device(cloud, 1);
      final p = a.library.createPlaylist('Band');
      final json =
          jsonDecode(utf8.decode(a.store.files[Library.indexName]!)) as Map;
      ((json['playlists'] as Map)[p.id]['values'] as Map)['entries'] = [1, 2];
      a.store.files[Library.indexName] = bytes(jsonEncode(json));
      final again = a.open();
      await again.load();
      expect(again.lastError, isA<LibraryCorrupt>());
    });
  });

  group('#114, #107 held playlists on this device', () {
    Future<Device> synced() async {
      final a = Device(cloud, 1);
      await a.library.load();
      addTearDown(a.sync.dispose);
      await a.library.markSynced();
      return a;
    }

    Future<void> horizon(Device a, {Map<String, StampedRecord>? known}) async {
      clock = clock.add(const Duration(days: 1));
      await a.library.mergeRemote(
        SharedState(
          purged: Hlc(clock.millisecondsSinceEpoch, 0, 'b'),
          playlists: known ?? const {},
        ),
      );
    }

    test('a held playlist without a record is dropped when loading', () async {
      final a = await synced();
      a.library.createPlaylist('Band');
      final raw = jsonDecode(
        utf8.decode(a.store.files[DeviceSettings.fileName]!),
      ) as Map;
      raw['heldPlaylists'] = ['ghost'];
      a.store.files[DeviceSettings.fileName] = bytes(jsonEncode(raw));
      final again = a.open();
      await again.load();
      expect(again.device.heldPlaylists, isEmpty);
      expect(again.heldNames, isEmpty);
    });

    test('more held playlists are remembered as they come', () async {
      final a = await synced();
      final p = a.library.createPlaylist('Band');
      await horizon(a);
      final q = a.library.createPlaylist('Solo');
      await horizon(a);
      expect(a.library.device.heldPlaylists, {p.id, q.id});
      final again = a.open();
      await again.load();
      expect(again.device.heldPlaylists, {p.id, q.id});
      expect(again.heldNames, ['Band', 'Solo']);
    });

    test('a held playlist deleted meanwhile is no longer held after a restart and stays deleted', () async {
      final a = await synced();
      final p = a.library.createPlaylist('Band');
      final q = a.library.createPlaylist('Solo');
      await horizon(a);
      a.library.deletePlaylist(p.id);
      await a.library.keepHeld();
      expect(a.library.playlist(p.id), isNull);
      expect(a.library.state.playlists[p.id]?.alive ?? false, isFalse);
      expect(a.library.state.playlists[q.id]!.alive, isTrue);

      final b = await synced();
      final r = b.library.createPlaylist('Etüden');
      await horizon(b);
      b.library.deletePlaylist(r.id);
      final again = b.open();
      await again.load();
      expect(again.device.heldPlaylists, isEmpty);
    });
  });

  group('#114 playlists between devices', () {
    test('#114/AK8 shared playlists are synced like folders: name, order and deletion', () async {
      final a = await device(cloud, 1);
      final b = await device(cloud, 2);
      final x = await a.add('Bossa.mp3');
      final y = await a.add('Zebra.mp3');
      final p = a.library.createPlaylist('Band');
      a.library.addToPlaylist(p.id, [x, y, x]);
      await a.sync.sync();
      await b.sync.sync();
      expect(b.titles(p.id), ['Bossa', 'Zebra', 'Bossa']);

      b.library.renamePlaylist(p.id, 'Konzert');
      b.library.movePlaylistEntry(p.id, 1, 0);
      await b.sync.sync();
      await a.sync.sync();
      expect(a.library.playlist(p.id)!.name, 'Konzert');
      expect(a.titles(p.id), ['Zebra', 'Bossa', 'Bossa']);

      a.library.deletePlaylist(p.id);
      await a.sync.sync();
      await b.sync.sync();
      expect(b.library.playlist(p.id), isNull);
      expect(b.library.track(x), isNotNull);
    });

    test('#114/AK7 a track deleted on another device leaves the playlists here too', () async {
      final a = await device(cloud, 1);
      final b = await device(cloud, 2);
      final x = await a.add('Bossa.mp3');
      final y = await a.add('Zebra.mp3');
      final p = a.library.createPlaylist('Band');
      a.library.addToPlaylist(p.id, [x, y]);
      await a.sync.sync();
      await b.sync.sync();
      b.library.delete({x});
      await b.sync.sync();
      await a.sync.sync();
      expect(a.titles(p.id), ['Zebra']);
    });

    test('#114/AK10 a playlist only on this device appears on no other device and never leaves it', () async {
      final a = await device(cloud, 1);
      final b = await device(cloud, 2);
      final x = await a.add('Bossa.mp3');
      final p = a.library.setPlaylistShared(
        a.library.createPlaylist('Geheim').id,
        false,
      );
      a.library.addToPlaylist(p, [x]);
      await a.sync.sync();
      await b.sync.sync();
      await a.sync.sync();
      expect(a.library.playlist(p)!.name, 'Geheim');
      expect(b.library.playlists, isEmpty);
      expect(a.deviceFile(), isNot(contains('Geheim')));
      expect(a.deviceFile(), isNot(contains(p)));
      expect(b.deviceFile(), isNot(contains('Geheim')));
      expect(a.library.state.playlists.containsKey(p), isFalse);
      // changes elsewhere and the purge horizon of others leave it alone
      b.library.createPlaylist('Offen');
      clock = clock.add(const Duration(days: 200));
      await b.sync.sync();
      await a.sync.sync();
      expect(a.library.playlist(p)!.name, 'Geheim');
      expect(a.library.heldNames, isEmpty);
      expect(a.library.playlists, hasLength(2));
      // deleted, it stays on this device as well
      a.library.deletePlaylist(p);
      await a.sync.sync();
      expect(a.library.state.playlists.containsKey(p), isFalse);
      expect(a.deviceFile(), isNot(contains(p)));
    });

    test('#114/AK10 a shared playlist made local disappears elsewhere and comes back once shared again', () async {
      final a = await device(cloud, 1);
      final b = await device(cloud, 2);
      final x = await a.add('Bossa.mp3');
      final p = a.library.createPlaylist('Band');
      a.library.addToPlaylist(p.id, [x]);
      await a.sync.sync();
      await b.sync.sync();
      expect(b.library.playlist(p.id), isNotNull);

      final local = a.library.setPlaylistShared(p.id, false);
      a.library.renamePlaylist(local, 'Nur hier');
      await a.sync.sync();
      await b.sync.sync();
      expect(b.library.playlists, isEmpty);
      expect(a.library.playlist(local)!.name, 'Nur hier');
      expect(a.deviceFile(), isNot(contains('Nur hier')));

      a.library.setPlaylistShared(local, true);
      await a.sync.sync();
      await b.sync.sync();
      expect(b.library.playlist(local)!.name, 'Nur hier');
      expect(b.titles(local), ['Bossa']);
    });

    test('#114/AK10 a playlist kept on this device is deleted for the other devices', () async {
      final a = await device(cloud, 1);
      final b = await device(cloud, 2);
      final p = a.library.createPlaylist('Band');
      await a.sync.sync();
      await b.sync.sync();
      a.library.setPlaylistShared(p.id, false);
      await a.sync.sync();
      await b.sync.sync();
      expect(b.library.state.playlists[p.id]!.alive, isFalse);
      expect(a.library.state.playlists[p.id]!.alive, isFalse);
    });

    test('#114 a damaged playlist in a device file skips that file', () async {
      final a = await device(cloud, 1);
      a.library.createPlaylist('Band');
      await a.sync.sync();
      final name = CloudSync.deviceName(a.library.device.deviceId);
      final j = jsonDecode(utf8.decode(cloud.files[name]!)) as Map;
      final rec = (j['playlists'] as Map).values.single as Map;
      (rec['values'] as Map)['name'] = 7;
      expect(
        () => CloudSync.decodeDevice(name, bytes(jsonEncode(j))),
        throwsFormatException,
      );
    });

    test(
      '#114, #107 an own playlist the purge horizon would kill is held back',
      () {
        final mine = SharedState(
          playlists: {
            'p': StampedRecord.create(const {
              'name': 'Band',
              'shared': true,
              'entries': <String>[],
            }, const Hlc(1000, 0, 'a')),
          },
        );
        const remote = SharedState(purged: Hlc(5000, 0, 'b'));
        expect(mine.lostTo(remote).playlists, {'p'});
        expect(mine.merge(remote).playlists['p']!.alive, isFalse);
        final kept = mine.restamp(
          const {},
          const {},
          const Hlc(6000, 0, 'a'),
          playlists: {'p'},
        );
        expect(kept.merge(remote).playlists['p']!.alive, isTrue);
        final first = mine.beforeFirstSync(remote, const Hlc(6000, 0, 'a'));
        expect(first.merge(remote).playlists['p']!.alive, isTrue);
      },
    );

    test(
      '#114, #107 a held playlist is named and kept or removed on request',
      () async {
        final store = MemoryFileStore();
        final a = Device(cloud, 1, store);
        await a.library.load();
        addTearDown(a.sync.dispose);
        await a.library.markSynced();
        final p = a.library.createPlaylist('Band');
        clock = clock.add(const Duration(days: 1));
        await a.library.mergeRemote(
          SharedState(purged: Hlc(clock.millisecondsSinceEpoch, 0, 'b')),
        );
        expect(a.library.heldNames, ['Band']);
        expect(a.library.state.playlists, isEmpty);
        expect(a.library.device.heldPlaylists, {p.id});
        await a.library.keepHeld();
        expect(a.library.heldNames, isEmpty);
        expect(a.library.state.playlists[p.id]!.alive, isTrue);

        final q = a.library.createPlaylist('Solo');
        clock = clock.add(const Duration(days: 1));
        await a.library.mergeRemote(
          SharedState(
            purged: Hlc(clock.millisecondsSinceEpoch, 0, 'b'),
            playlists: {p.id: a.library.state.playlists[p.id]!},
          ),
        );
        expect(a.library.heldNames, ['Solo']);
        await a.library.removeHeld();
        expect(a.library.playlist(q.id), isNull);
        expect(a.library.playlist(p.id), isNotNull);
      },
    );
  });
}
