// #61: rules of the migration from format 1 (migration.dart, #36/AK3), one per test; found by mutation
// testing (make mutants). Works on stores in memory, never on the real library.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/library/migration.dart';

import 'fakes.dart';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));
String _hash(String s) => crypto.sha256.convert(utf8.encode(s)).toString();

Map<String, Object?> _entry(String id, String fileName, {String? hash}) => {
  'id': id,
  'fileName': fileName,
  'title': id,
  'dateAdded': 0,
  'duration': 1,
  'customOrder': 0,
  'contentHash': ?hash,
};

Uint8List _index(List<Map<String, Object?>> tracks) =>
    _bytes(jsonEncode({'folders': <Object?>[], 'tracks': tracks}));

void main() {
  group('#36/AK3 migration of the former library.json', () {
    test(
      'a file name without extension (or only a dot at the start) gets .mp3',
      () async {
        final store = MemoryFileStore()
          ..files['Tracks/NOEXT'] = _bytes('one')
          ..files['Tracks/.flac'] = _bytes('two');
        final r = await migrateLegacyLibrary(
          store,
          _index([_entry('A', 'NOEXT'), _entry('B', '.flac')]),
        );
        expect(r.tracks.map((t) => t.fileName), [
          '${_hash('one')}.mp3',
          '${_hash('two')}.mp3',
        ]);
      },
    );

    test('every entry without its audio file counts as missing', () async {
      final store = MemoryFileStore()..files['Tracks/C.mp3'] = _bytes('c');
      final r = await migrateLegacyLibrary(
        store,
        _index([
          _entry('A', 'A.mp3'), // no file, no stored hash
          _entry('B', 'B.mp3', hash: _hash('b')), // stored hash, but no file
          _entry('C', 'C.mp3'),
        ]),
      );
      expect(r.missing, 2);
      expect(r.tracks.single.id, _hash('c'));
    });

    test('the ID mapping is written only when it gets a new entry', () async {
      final store = MemoryFileStore()..files['Tracks/A.mp3'] = _bytes('a');
      final raw = _index([_entry('A', 'A.mp3')]);
      await migrateLegacyLibrary(store, raw);
      final ids = store.files[legacyIdsName]!;
      expect(jsonDecode(utf8.decode(ids)), {'A': _hash('a')});
      // a repeated run (after an interruption) knows every ID already
      await migrateLegacyLibrary(store, raw);
      expect(identical(store.files[legacyIdsName], ids), isTrue);
    });
  });
}
