// #124: sorting a playlist once by title, artist, duration or date added. Libraries in memory with generated
// audio bytes, a cloud in memory (InMemoryProvider); never the real library or a real account.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/sync/in_memory_provider.dart';
import 'package:woodshed_player/sync/sync_engine.dart';

import 'fakes.dart';

var clock = DateTime.utc(2026, 11, 1);

class Device {
  Device(this.cloud, this.seed) {
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
  final store = MemoryFileStore();
  late final Library library;
  late final CloudSync sync;

  Library open() => Library(
    store,
    probe: (_) => null, // durations come from [fillDuration]
    readSource: (s) async => Uint8List.fromList(utf8.encode('audio $s')),
    now: () => clock = clock.add(const Duration(seconds: 1)),
    saveDelay: Duration.zero,
    random: Random(seed),
  );

  /// Imports a track and sets its title, artist and duration; tracks are added in this order.
  Future<String> add(String title, String? artist, double seconds) async {
    final r = await library.importFiles(['$title.mp3']);
    final id = r.imported.single.id;
    library.editMetadata(id, title: title, artist: artist);
    library.fillDuration(id, seconds);
    return id;
  }

  List<String> titles(String playlistId) => [
    for (final t in library.playlistTracks(playlistId)) t.title,
  ];
}

Future<Device> device(InMemoryProvider cloud, int seed) async {
  final d = Device(cloud, seed);
  await d.library.load();
  addTearDown(d.sync.dispose);
  return d;
}

void main() {
  late InMemoryProvider cloud;
  late Device a;
  late String p;
  setUp(() async {
    cloud = InMemoryProvider();
    a = await device(cloud, 1);
    // added in this order: Alpha, beta 10, Beta 9, Delta
    final alpha = await a.add('Alpha', 'Zed', 30);
    final beta10 = await a.add('beta 10', 'amy', 10);
    final beta9 = await a.add('Beta 9', null, 20);
    final delta = await a.add('Delta', ' ', 10);
    p = a.library.createPlaylist('Band').id;
    a.library.addToPlaylist(p, [beta9, alpha, delta, beta10, alpha]);
  });

  List<String> sorted(PlaylistSortKey key, {bool descending = false}) {
    a.library.sortPlaylist(p, key, descending: descending);
    return a.titles(p);
  }

  group('#124 sorting a playlist', () {
    test('#124/AK1 by title, ascending and descending, in natural order', () {
      expect(sorted(PlaylistSortKey.title), [
        'Alpha',
        'Alpha',
        'Beta 9',
        'beta 10',
        'Delta',
      ]);
      expect(sorted(PlaylistSortKey.title, descending: true), [
        'Delta',
        'beta 10',
        'Beta 9',
        'Alpha',
        'Alpha',
      ]);
    });

    test('#124/AK1 by artist; tracks without an artist come last either way, by title', () {
      expect(sorted(PlaylistSortKey.artist), [
        'beta 10', // amy
        'Alpha', // Zed
        'Alpha',
        'Beta 9', // no artist
        'Delta', // blank artist
      ]);
      expect(sorted(PlaylistSortKey.artist, descending: true), [
        'Alpha',
        'Alpha',
        'beta 10',
        'Delta',
        'Beta 9',
      ]);
    });

    test('#124/AK1 by duration; equal durations go by title', () {
      expect(sorted(PlaylistSortKey.duration), [
        'beta 10', // 10 s
        'Delta', // 10 s
        'Beta 9', // 20 s
        'Alpha', // 30 s
        'Alpha',
      ]);
      expect(sorted(PlaylistSortKey.duration, descending: true), [
        'Alpha',
        'Alpha',
        'Beta 9',
        'Delta',
        'beta 10',
      ]);
    });

    test('#124/AK1 by date added, oldest or newest first', () {
      expect(sorted(PlaylistSortKey.dateAdded), [
        'Alpha',
        'Alpha',
        'beta 10',
        'Beta 9',
        'Delta',
      ]);
      expect(sorted(PlaylistSortKey.dateAdded, descending: true), [
        'Delta',
        'Beta 9',
        'beta 10',
        'Alpha',
        'Alpha',
      ]);
    });

    test('#124/AK2 equal rows keep their order; the old row of each new row is returned', () {
      // rows: 0 Beta 9, 1 Alpha, 2 Delta, 3 beta 10, 4 Alpha
      expect(a.library.sortPlaylist(p, PlaylistSortKey.title), [1, 4, 0, 3, 2]);
      // now: 0 Alpha, 1 Alpha, 2 Beta 9, 3 beta 10, 4 Delta; the two Alpha rows stay in order
      expect(
        a.library.sortPlaylist(p, PlaylistSortKey.dateAdded, descending: true),
        [4, 2, 3, 0, 1],
      );
    });

    test(
      '#124/AK2 the order, repeats included, is kept after a restart',
      () async {
        final before = sorted(PlaylistSortKey.duration, descending: true);
        final again = a.open();
        await again.load();
        expect([for (final t in again.playlistTracks(p)) t.title], before);
        expect(again.playlist(p)!.entries, a.library.playlist(p)!.entries);
      },
    );

    test('#124/AK2 sorting tells the listeners once and saves; an unknown playlist is left alone', () {
      var told = 0;
      a.library.addListener(() => told++);
      a.library.sortPlaylist(p, PlaylistSortKey.title);
      expect(told, 1);
      a.library.sortPlaylist(p, PlaylistSortKey.title); // already so
      expect(told, 1);
      expect(a.library.sortPlaylist('nope', PlaylistSortKey.title), isNull);
      expect(told, 1);
    });

    test('#124/AK2 an empty playlist sorts to nothing', () {
      final q = a.library.createPlaylist('Leer').id;
      expect(a.library.sortPlaylist(q, PlaylistSortKey.artist), isEmpty);
      expect(a.library.playlistTracks(q), isEmpty);
    });

    test('#124/AK3 after sorting, rows can still be moved', () {
      sorted(PlaylistSortKey.title);
      a.library.movePlaylistEntry(p, 4, 0); // Delta to the front
      expect(a.titles(p), ['Delta', 'Alpha', 'Alpha', 'Beta 9', 'beta 10']);
    });

    test('#124/AK4 a shared playlist sorted here has the same order on another device', () async {
      final b = await device(cloud, 2);
      await a.sync.sync();
      await b.sync.sync();
      final order = sorted(PlaylistSortKey.artist);
      await a.sync.sync();
      await b.sync.sync();
      expect(b.titles(p), order);
      expect(b.library.playlist(p)!.entries, a.library.playlist(p)!.entries);
    });
  });
}
