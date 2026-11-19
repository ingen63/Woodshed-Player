// #10/AK5: golden files of every version of `library.json` (test/golden/README.md). The current version
// reads all of them, in a store in memory with generated audio bytes, never the real library. The expected
// values are read by hand from the golden files.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/library/library.dart';

import 'fakes.dart';

/// Every golden file of `library.json`: name → the version that wrote it.
const goldens = {
  'library_swift_legacy.json': 'format 1, Swift app: [Track]',
  'library_swift.json': 'format 1, Swift app: {folders, tracks}',
  'library_v2_36.json': 'format 2 (#36): one loop field per track',
  'library_v2.json': 'format 2 (#37): loops per ID, noUpload, folder sync',
};

Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));
String sha(String s) => crypto.sha256.convert(utf8.encode(s)).toString();

// Swift golden files: former UUIDs; after the migration the ID is the SHA-256 of the audio file.
const uuid1 = '0F0E0D0C-0B0A-0908-0706-050403020100';
const uuid2 = '99999999-8888-7777-6666-555555555555';
const etueden = '11111111-2222-3333-4444-555555555555';
final t1 = 'a1' * 32, t2 = 'b2' * 32, t3 = 'c3' * 32;

/// A store with [golden] as `library.json` and the audio files its tracks name.
MemoryFileStore goldenStore(String golden) {
  final store = MemoryFileStore();
  store.files[Library.indexName] = File('test/golden/$golden')
      .readAsBytesSync();
  if (golden.startsWith('library_swift')) {
    store.files['Tracks/$uuid1.mp3'] = bytes('mp3');
    store.files['Tracks/$uuid1.artwork'] = bytes('jpg');
    store.files['Tracks/$uuid2.flac'] = bytes('flac');
  } else {
    store.files['Tracks/$t1.mp3'] = bytes('mp3 a1');
    store.files['Tracks/$t2.flac'] = bytes('flac b2');
  }
  return store;
}

Library open(MemoryFileStore store) => Library(
  store,
  probe: (_) => 1,
  readSource: (_) async => null,
  now: () => DateTime.utc(2026, 11, 19),
  saveDelay: Duration.zero,
  random: Random(1),
);

Future<Library> loadGolden(String golden) async {
  final l = open(goldenStore(golden));
  await l.load();
  return l;
}

void main() {
  test('#10/AK5 every golden file of library.json is listed', () {
    final files = Directory('test/golden')
        .listSync()
        .map((e) => e.uri.pathSegments.last)
        .where((n) => n.startsWith('library') && n.endsWith('.json'))
        .toSet();
    expect(files, goldens.keys.toSet());
    final readme = File('test/golden/README.md').readAsStringSync();
    for (final g in goldens.keys) {
      expect(readme, contains(g), reason: 'README.md names $g');
    }
  });

  group('#10/AK5 the current version reads every golden file', () {
    for (final g in goldens.keys) {
      test('$g (${goldens[g]}): no message, nothing dropped', () async {
        final l = await loadGolden(g);
        expect(l.lastError, isNull);
        expect(l.droppedMissing, 0);
        expect(l.readOnly, isFalse);
        expect(l.tracks, hasLength(2));
        // every track shows in an existing folder or without one
        final folders = l.folders.map((f) => f.id).toSet();
        for (final t in l.tracks) {
          expect(t.folderId == null || folders.contains(t.folderId), isTrue);
        }
      });
    }

    for (final g in ['library_swift_legacy.json', 'library_swift.json']) {
      test('$g: Swift fields, loop and tempo carried over', () async {
        final l = await loadGolden(g);
        final a = l.track(sha('mp3'))!;
        expect(a.title, 'Übung in C');
        expect(a.artist, 'Testband');
        expect(a.duration, 183.456);
        expect(a.settings.speed, 0.75);
        expect(a.activeLoopRange, const LoopRange(12.5, 47));
        expect(l.track(sha('flac'))!.title, 'sinus');
        if (g == 'library_swift.json') {
          expect(a.folderId, etueden);
          expect(l.folders.map((f) => f.name), ['Etüden', 'Swing 2']);
        } else {
          // [Track] has no folders: the folder ID of the entry points nowhere, the track shows without one
          expect(a.folderId, isNull);
          expect(l.folders, isEmpty);
        }
      });
    }

    for (final g in ['library_v2_36.json', 'library_v2.json']) {
      test('$g: stamps, tombstones, loop, settings', () async {
        final l = await loadGolden(g);
        final a = l.track(t1)!;
        // the later title from the second device
        expect(a.title, 'Übung in G (langsam)');
        expect(a.folderId, etueden);
        expect(a.settings.speedEnabled, isTrue);
        expect(a.settings.speed, 0.75);
        expect(a.settings.rampEnabled, isTrue);
        expect(a.settings.rampTarget, 90);
        expect(a.settings.rampPasses, 4);
        expect(
          (a.settings.loopEnabled, a.settings.loopStart, a.settings.loopEnd),
          (true, 12.5, 47.0),
        );
        // #36: the one loop gets the ID «0»; #37: the active one of two IDs
        expect(a.loopId, g == 'library_v2_36.json' ? '0' : '5e1f0a2b');
        expect(l.track(t2)!.noUpload, g == 'library_v2.json');
        expect(l.track(t3), isNull, reason: 'deleted');
        expect(l.state.tracks[t3]!.alive, isFalse, reason: 'tombstone kept');
        expect(l.folders.map((f) => f.name), ['Etüden']);
        expect(l.folders.single.sync, g != 'library_v2.json');
        expect(l.sortOrder, TrackSortOrder.custom);
        expect(l.appearance, Appearance.dark);
        expect(l.metronomePreset?['meter'], 3);
      });
    }

    test('library_v2.json is what the current version writes', () async {
      // A changed format needs a new golden file (README.md); then this test names the change.
      final store = goldenStore('library_v2.json');
      Object? json() =>
          jsonDecode(utf8.decode(store.files[Library.indexName]!));
      final before = json();
      final l = open(store);
      await l.load();
      await l.save();
      expect(
        json(),
        before,
      ); // same contents (the order of keys carries no meaning)
    });
  });
}

extension on Track {
  LoopRange? get activeLoopRange => loopId == null ? null : loops[loopId];
}
