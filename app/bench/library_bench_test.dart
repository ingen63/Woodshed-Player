// #59/AK3, AK4: load test of the library with 10'000 invented tracks in 500 folders. Runs nightly with
// `make bench` (tag «bench», folder bench/ outside test/, so `flutter test` and `make test` skip it).
// The library lives in a temp folder with empty track files; never the real library.
// - AK3: load, sort and save take at most 1 s each; merging two states of this size (#37) at most 2 s.
// - AK4: the resident size of the test process is checked against [rssLimit] after every step
//   (ProcessInfo.maxRss, the same on macOS and Linux). There is no hard cap as in the core: ulimit -v has
//   no effect on macOS, and the VM reserves far more address space than it uses, so an address space
//   limit would not hit its memory. The check stops the run at the next step.
// The times are those of the test VM (JIT), the app runs AOT and is faster. Measured values: docs/TESTS.md.
@Tags(['bench'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/app/file_store_io.dart';
import 'package:woodshed_player/library/library.dart';

const trackCount = 10000;
const folderCount = 500;
const stepLimit = Duration(seconds: 1);
const mergeLimit = Duration(seconds: 2);

/// #59/AK4: upper bound of the test process (the test VM alone needs about 200 MiB).
const rssLimit = 1024 * 1024 * 1024;

final clock = DateTime.utc(2026, 11, 20, 12);
final words = [
  'Blue',
  'Night',
  'Swing',
  'Minor',
  'Waltz',
  'Train',
  'River',
  'Song',
  'Etude',
  'Groove', //
  'Shuffle',
  'Bossa',
  'Ballad',
  'Rhythm',
  'Changes',
  'Valse',
  'Gypsy',
  'Moon',
  'Street',
  'Dance',
];

String hex(String s) => crypto.sha256.convert(utf8.encode(s)).toString();

String inventedTitle(Random r, int i) =>
    '${words[r.nextInt(words.length)]} ${words[r.nextInt(words.length)]} ${r.nextInt(120)}'
    '${i.isEven ? '' : ' (Take ${r.nextInt(9) + 1})'}';

/// Shared state of one device: [trackCount] tracks in [folderCount] folders, every track with settings and
/// one loop, as an imported library looks after a while.
SharedState inventedState(Random r, String device) {
  final stamp = Hlc(clock.millisecondsSinceEpoch, 0, device);
  final folders = <String, StampedRecord>{
    for (var f = 0; f < folderCount; f++)
      'F${f.toString().padLeft(5, '0')}': StampedRecord.create(
        TrackFolder(id: 'F$f', name: 'Folder ${r.nextInt(1000)}').toShared(),
        stamp,
      ),
  };
  final folderIds = folders.keys.toList();
  final tracks = <String, StampedRecord>{};
  for (var i = 0; i < trackCount; i++) {
    final id = hex('track $i');
    final t = Track(
      id: id,
      fileName: '$id.mp3',
      originalFileName: 'track$i.mp3',
      title: inventedTitle(r, i),
      artist: 'Band ${r.nextInt(300)}',
      duration: 60 + r.nextDouble() * 600,
      hasArtwork: false,
      dateAdded: clock.subtract(Duration(minutes: r.nextInt(500000))),
      customOrder: i,
      settings: PlaybackSettings(
        speedEnabled: r.nextBool(),
        speed: 0.5 + r.nextInt(10) / 10,
        loopEnabled: true,
        loopStart: 10,
        loopEnd: 20,
      ),
      folderId: folderIds[r.nextInt(folderCount)],
      loopId: 'L$i',
    );
    tracks[id] = StampedRecord.create(t.toShared(), stamp);
  }
  return SharedState(tracks: tracks, folders: folders);
}

/// The same library as another device saw it later: a fifth of the titles edited, 500 tracks deleted,
/// 1000 new tracks (without a file here) and 50 folders renamed.
SharedState remoteState(SharedState base, Random r) {
  final stamp = Hlc(
    clock.millisecondsSinceEpoch + 60000,
    0,
    'bbbbbbbbbbbbbbbb',
  );
  final tracks = <String, StampedRecord>{};
  var n = 0;
  for (final e in base.tracks.entries) {
    final k = n++ % 20;
    tracks[e.key] = switch (k) {
      0 => e.value.delete(stamp),
      1 || 2 || 3 || 4 => e.value.update({
        ...e.value.values,
        'title': inventedTitle(r, n),
        'speed': 0.75,
      }, stamp),
      _ => e.value,
    };
  }
  for (var i = 0; i < 1000; i++) {
    final id = hex('remote track $i');
    tracks[id] = StampedRecord.create({
      ...base.tracks.values.first.values,
      'fileName': '$id.mp3',
      'title': inventedTitle(r, i),
    }, stamp);
  }
  var f = 0;
  final folders = {
    for (final e in base.folders.entries)
      e.key: f++ % 10 == 0
          ? e.value.update({...e.value.values, 'name': 'Renamed $f'}, stamp)
          : e.value,
  };
  return SharedState(tracks: tracks, folders: folders);
}

final results = <String, Duration>{};

Future<T> timed<T>(
  String name,
  Duration limit,
  Future<T> Function() step,
) async {
  final w = Stopwatch()..start();
  final value = await step();
  w.stop();
  results[name] = w.elapsed;
  final rss = ProcessInfo.maxRss;
  // ignore: avoid_print
  print(
    'BENCH library.$name ${w.elapsedMilliseconds} ms (limit ${limit.inMilliseconds}), '
    'max RSS ${(rss / (1 << 20)).toStringAsFixed(0)} MiB',
  );
  expect(rss, lessThan(rssLimit), reason: '#59/AK4 memory limit after $name');
  expect(w.elapsed, lessThanOrEqualTo(limit), reason: '#59/AK3 $name');
  return value;
}

void main() {
  late Directory dir;
  late SharedState state;
  late Library library;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('wp_bench_library_');
    state = inventedState(Random(59), 'aaaaaaaaaaaaaaaa');
    final store = IoFileStore(dir);
    await store.write(
      Library.indexName,
      Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(state.toJson())),
      ),
    );
    Directory('${dir.path}/Tracks').createSync();
    for (final id in state.tracks.keys) {
      File('${dir.path}/Tracks/$id.mp3').createSync();
    }
    library = Library(
      store,
      probe: (_) => 30,
      readSource: (_) async => null,
      now: () => clock,
      saveDelay: const Duration(hours: 1),
      random: Random(1),
    );
  });

  tearDownAll(() async {
    library.dispose();
    await dir.delete(recursive: true);
  });

  test('#59/AK3 load 10\'000 tracks in 500 folders within 1 s', () async {
    await timed('load', stepLimit, library.load);
    expect(library.tracks, hasLength(trackCount));
    expect(library.folders, hasLength(folderCount));
    expect(library.lastError, isNull);
  });

  test('#59/AK3 sort within 1 s per order', () async {
    for (final order in TrackSortOrder.values) {
      library.sortOrder = order;
      final sorted = await timed(
        'sort_${order.name}',
        stepLimit,
        () async => library.sortedTracks,
      );
      expect(sorted, hasLength(trackCount));
    }
    final folders = await timed(
      'sort_folders',
      stepLimit,
      () async => library.sortedFolders,
    );
    final inFolder = await timed(
      'sort_in_folder',
      stepLimit,
      () async => library.sortedTracksIn(folders.first.id),
    );
    expect(inFolder.every((t) => t.folderId == folders.first.id), isTrue);
  });

  test('#59/AK3 save within 1 s', () async {
    final t = library.tracks.first;
    library.editMetadata(t.id, title: 'Edited title', artist: 'Band 1');
    await timed('save', stepLimit, library.save);
    final saved = jsonDecode(
      File('${dir.path}/${Library.indexName}').readAsStringSync(),
    ) as Map<String, Object?>;
    expect((saved['tracks'] as Map).length, trackCount);
  });

  test('#59/AK3 merge two states of this size (#37) within 2 s', () async {
    final remote = remoteState(state, Random(37));
    await timed(
      'merge_state',
      mergeLimit,
      () async => library.state.merge(remote),
    );
    await timed('merge_library', mergeLimit, () => library.mergeRemote(remote));
    expect(library.tracks, hasLength(trackCount - trackCount ~/ 20 + 1000));
    expect(library.lastError, isNull);
  });
}
