// #10/AK3, AK8: damaged `library.json` and repeated migration, as random tests over the golden files
// (test/golden/). Stores in memory with generated audio bytes, never the real library.
// - AK3: a damaged file (changed types, missing fields, wrong references, extreme values, truncated) never
//   crashes the load. Either the library opens consistently and can be saved and loaded again without a
//   message, or the user gets an understandable message (in every language) and the file is kept.
// - AK8: bringing an already migrated `library.json` up to date a second time changes nothing and reports
//   nothing, for the golden files and for damaged files that still open.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/library/migration.dart';
import 'package:woodshed_player/ui/messages.dart';

import '../fakes.dart';
import '../golden_files_test.dart'
    show goldens, goldenStore, open, t1, t2, t3, uuid1, uuid2, etueden;
import 'corrupt.dart';
import 'property.dart';

final en = lookupAppLocalizations(const Locale('en'));

/// Store of [golden] with `library.json` replaced by [bytes].
MemoryFileStore damagedStore(String golden, Uint8List bytes) =>
    goldenStore(golden)..files[Library.indexName] = bytes;

Object? decoded(MemoryFileStore s) =>
    jsonDecode(utf8.decode(s.files[Library.indexName]!));

/// The library is usable: unique tracks, each in an existing folder or none.
void checkConsistent(Library l, String what) {
  final ids = l.tracks.map((t) => t.id).toList();
  expect(ids.toSet().length, ids.length, reason: 'duplicate track: $what');
  final folders = l.folders.map((f) => f.id).toSet();
  for (final t in l.tracks) {
    expect(
      t.folderId == null || folders.contains(t.folderId),
      isTrue,
      reason: 'track in a missing folder: $what',
    );
    expect(t.duration.isFinite && t.settings.speed.isFinite, isTrue);
  }
  expect(l.sortedTracks.length + 0, ids.length, reason: 'sorted list: $what');
}

/// Loads, saves, loads and saves again: the second round must change nothing and report nothing.
Future<void> checkIdempotent(MemoryFileStore store, String what) async {
  final first = open(store);
  await first.load();
  expect(first.lastError, isNull, reason: 'first load: $what');
  await first.save();
  expect(first.lastError, isNull, reason: 'first save: $what');
  final once = decoded(store);
  final second = open(store);
  await second.load();
  expect(second.lastError, isNull, reason: 'second load: $what');
  expect(second.droppedMissing, 0, reason: 'second load dropped: $what');
  await second.save();
  expect(second.lastError, isNull, reason: 'second save: $what');
  expect(decoded(store), once, reason: 'second migration changed: $what');
  expect(
    {for (final t in second.tracks) t.id: t.toShared()},
    {for (final t in first.tracks) t.id: t.toShared()},
    reason: what,
  );
}

const ids = [
  '0F0E0D0C-0B0A-0908-0706-050403020100',
  '99999999-8888-7777-6666-555555555555',
  '11111111-2222-3333-4444-555555555555',
  'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE',
  '5e1f0a2b',
  '0f0f0f0f',
];

void main() {
  final goldenNames = goldens.keys.toList();
  Object? golden(String g) =>
      jsonDecode(File('test/golden/$g').readAsStringSync());
  final referenceIds = [...ids, t1, t2, t3, uuid1, uuid2, etueden];

  group('#10/AK3 damaged library.json', () {
    final outcomes = <String, int>{};
    property('damaged library.json never crashes and is reported', (r) async {
      final g = pick(r, goldenNames);
      final (bytes, damage) = corrupt(r, golden(g), ids: referenceIds);
      final what = '$g, $damage';
      final store = damagedStore(g, bytes);
      final l = open(store);
      await l.load(); // must not throw
      final msg = l.lastError;
      switch (msg) {
        case null:
          outcomes['opened'] = (outcomes['opened'] ?? 0) + 1;
          checkConsistent(l, what);
          await l.save();
          expect(l.lastError, isNull, reason: 'save failed: $what');
          final again = open(store);
          await again.load();
          expect(again.lastError, isNull, reason: 'reload: $what');
          expect(
            {for (final t in again.tracks) t.id: t.toShared()},
            {for (final t in l.tracks) t.id: t.toShared()},
            reason: 'reload changed the library: $what',
          );
        case LibraryCorrupt(:final backupName):
          outcomes['corrupt'] = (outcomes['corrupt'] ?? 0) + 1;
          // the damaged file is kept, the library is empty and works
          expect(store.files[backupName], bytes, reason: what);
          expect(l.tracks, isEmpty);
          l.lastError = null; // shown by the UI
          await l.save();
          expect(l.lastError, isNull, reason: 'save after reset: $what');
        case LibraryTooNew():
          outcomes['tooNew'] = (outcomes['tooNew'] ?? 0) + 1;
          expect(l.readOnly, isTrue);
          await l.save();
          expect(store.files[Library.indexName], bytes, reason: 'overwritten');
        default:
          fail('unexpected message $msg: $what');
      }
      if (msg != null) {
        for (final loc in [de, en]) {
          expect(libraryMessageText(loc, msg), isNotEmpty);
        }
      }
    });

    test(
      'a number beyond the range of a double makes the file damaged',
      () async {
        // #10 regression (found bug 13, regressions.json seed 1819282202).
        // 1e400 is valid JSON, Dart reads it as infinity, which could never be written again.
        final text = File('test/golden/library_v2.json').readAsStringSync();
        final bytes = Uint8List.fromList(
          utf8.encode(
            text.replaceFirst('"duration": 183.5', '"duration": 1e400'),
          ),
        );
        final store = damagedStore('library_v2.json', bytes);
        final l = open(store);
        await l.load();
        final msg = l.lastError;
        expect(msg, isA<LibraryCorrupt>());
        expect(store.files[(msg as LibraryCorrupt).backupName], bytes);
        expect(libraryMessageText(en, msg), contains(msg.backupName));
      },
    );

    tearDownAll(() {
      // ignore: avoid_print
      print('damaged library.json: $outcomes');
    });
  });

  group('#10/AK8 migration is idempotent', () {
    for (final g in goldenNames) {
      test(
        '$g: a second migration changes nothing and reports nothing',
        () async {
          await checkIdempotent(goldenStore(g), g);
        },
      );
    }

    test(
      'migrateLegacyLibrary twice on the same file gives the same result',
      () async {
        for (final g in ['library_swift.json', 'library_swift_legacy.json']) {
          final store = goldenStore(g);
          final raw = store.files[Library.indexName]!;
          final a = await migrateLegacyLibrary(store, raw);
          final files = Map.of(store.files);
          final b = await migrateLegacyLibrary(store, raw);
          expect(
            b.tracks.map((t) => t.toShared()),
            a.tracks.map((t) => t.toShared()),
          );
          expect(b.missing, a.missing);
          expect(store.files.keys.toSet(), files.keys.toSet(), reason: g);
        }
      },
    );

    property('migration twice changes nothing and reports nothing', (r) async {
      // damaged files that still open behave the same as the golden files
      final g = pick(r, goldenNames);
      final (bytes, damage) = corrupt(r, golden(g), ids: referenceIds);
      final probe = open(damagedStore(g, bytes));
      await probe.load();
      if (probe.lastError != null) return; // reported (AK3), nothing to migrate
      await checkIdempotent(damagedStore(g, bytes), '$g, $damage');
    });
  });
}
