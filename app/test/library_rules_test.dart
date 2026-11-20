// #61: rules of the library (library.dart), one per test; found by mutation testing (make mutants).
// Every test works on a library in memory (MemoryFileStore), never on the real library.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/library/library.dart';

import 'fakes.dart';

final _t0 = DateTime.utc(2026, 11, 1);

/// Import sources: name → contents (generated text, no real audio).
final _sources = <String, Uint8List>{};

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));
String _hash(Uint8List b) => crypto.sha256.convert(b).toString();

/// An MP3-like file whose ID3v2.3 tag holds a front cover.
Uint8List _withCover(String text, List<int> cover) {
  List<int> syncsafe(int v) => [
    v >> 21 & 0x7f,
    v >> 14 & 0x7f,
    v >> 7 & 0x7f,
    v & 0x7f,
  ];
  final apic = [0, ...'image/jpeg'.codeUnits, 0, 3, 0, ...cover];
  final frame = [
    ...'APIC'.codeUnits,
    ...[0, 0, 0, apic.length],
    0,
    0,
    ...apic,
  ];
  return Uint8List.fromList([
    ...'ID3'.codeUnits,
    3,
    0,
    0,
    ...syncsafe(frame.length),
    ...frame,
    ...utf8.encode(text),
  ]);
}

class _Lib {
  _Lib({
    MemoryFileStore? store,
    double? Function(String)? probe,
    this.saveDelay = Duration.zero,
    DateTime? now,
  }) : store = store ?? MemoryFileStore() {
    this.now = now ?? _t0;
    library = Library(
      this.store,
      probe: probe ?? (_) => 2.5,
      readSource: (s) async {
        if (s.startsWith('throw')) throw StateError('unreadable');
        return _sources[s];
      },
      now: () => this.now,
      saveDelay: saveDelay,
      random: Random(1),
    )..addListener(() => notified++);
  }

  final MemoryFileStore store;
  final Duration saveDelay;
  late DateTime now;
  late final Library library;
  var notified = 0;

  Future<Track> add(String name, {String? contents, Uint8List? bytes}) async {
    _sources[name] = bytes ?? _bytes(contents ?? 'audio $name');
    final r = await library.importFiles([name]);
    return [...r.imported, ...r.duplicates].single;
  }

  /// library.json as stored.
  Map<String, Object?> get saved =>
      (jsonDecode(utf8.decode(store.files[Library.indexName]!)) as Map)
          .cast<String, Object?>();
}

Future<_Lib> _loaded({
  MemoryFileStore? store,
  Duration saveDelay = Duration.zero,
  double? Function(String)? probe,
}) async {
  final l = _Lib(store: store, saveDelay: saveDelay, probe: probe);
  await l.library.load();
  return l;
}

/// A store that counts the writes of library.json.
class _CountingStore extends MemoryFileStore {
  var indexWrites = 0;
  @override
  Future<void> write(String name, Uint8List bytes) async {
    if (name == Library.indexName) indexWrites++;
    return super.write(name, bytes);
  }
}

/// A store whose used storage cannot be measured: only the library's own notifications remain.
class _NoStorageStore extends MemoryFileStore {
  @override
  Future<StorageInfo> storageInfo() async => throw StateError('no storage');
}

/// A store whose writes of library.json fail.
class _FailingStore extends MemoryFileStore {
  @override
  Future<void> write(String name, Uint8List bytes) async {
    if (name == Library.indexName) throw StateError('disk full');
    return super.write(name, bytes);
  }
}

void main() {
  setUp(_sources.clear);

  group('#16/AK1 loading tells the UI', () {
    test(
      'every kind of load notifies, also when storage cannot be measured',
      () async {
        final first = await _loaded(store: _NoStorageStore());
        expect(first.notified, 1);
        await first.add('a.mp3');

        final normal = await _loaded(store: first.store);
        expect(normal.notified, 1);

        final newer = _NoStorageStore()
          ..files[Library.indexName] = _bytes('{"formatVersion": 99}');
        expect((await _loaded(store: newer)).notified, 1);

        final damaged = _NoStorageStore()
          ..files[Library.indexName] = _bytes('{kaputt');
        expect((await _loaded(store: damaged)).notified, 1);
      },
    );

    test('a normal load notifies and measures the storage', () async {
      final a = await _loaded();
      await a.add('a.mp3');
      final b = await _loaded(store: a.store);
      expect(b.notified, greaterThan(0));
      expect(b.library.storage, isNotNull);
      final before = b.notified;
      await b.library.refreshStorage();
      expect(b.notified, before + 1);
    });
  });

  group('#16/AK6 missing files', () {
    test('a missing file is counted once and its record goes', () async {
      final a = await _loaded();
      final gone = await a.add('gone.mp3');
      final kept = await a.add('kept.mp3');
      a.store.files.remove(Library.trackName(gone.fileName));
      final b = await _loaded(store: a.store);
      expect(b.library.droppedMissing, 1);
      expect(b.library.tracks.map((t) => t.id), [kept.id]);
      expect(b.library.state.tracks.keys, [kept.id]);
    });

    test('a new load forgets what was missing before', () async {
      final a = await _loaded();
      final t = await a.add('a.mp3');
      // the record says another device imported it; the file is not here
      final file = a.store.files.remove(Library.trackName(t.fileName))!;
      final json = a.saved;
      final rec = ((json['tracks'] as Map)[t.id] as Map)
          .cast<String, Object?>();
      final stamps = (rec['stamps'] as Map).cast<String, Object?>();
      stamps['fileName'] =
          '${Hlc.parse(stamps['fileName'] as String).millis}-0-ffffffffffffffff';
      a.store.files[Library.indexName] = _bytes(jsonEncode(json));
      final b = _Lib(store: a.store);
      await b.library.load();
      expect(b.library.hasFile(t.id), isFalse);
      // the file arrives, and the next load (here of a damaged index) starts afresh
      a.store.files[Library.trackName(t.fileName)] = file;
      a.store.files[Library.indexName] = _bytes('{kaputt');
      await b.library.load();
      expect(b.library.hasFile(t.id), isTrue);
    });
  });

  group('#36/AK1 stamps after loading and merging', () {
    test(
      'a change after loading gets a stamp above every stamp in the file',
      () async {
        final a = await _loaded();
        await a.add('a.mp3');
        // the file comes from a device whose clock runs an hour ahead
        final later = _Lib(store: a.store)
          ..now = _t0.add(const Duration(hours: 1));
        await later.library.load();
        later.library.sortOrder = TrackSortOrder.alphabetical;
        final latest = later.library.state.latest!;
        final b = _Lib(store: a.store); // clock at _t0 again
        await b.library.load();
        b.library.sortOrder = TrackSortOrder.custom;
        expect(b.library.state.settings.stamps['sortOrder']! > latest, isTrue);
      },
    );

    test(
      'a change after merging gets a stamp above the remote stamps',
      () async {
        final remoteLib = _Lib()..now = _t0.add(const Duration(hours: 1));
        await remoteLib.library.load();
        remoteLib.library.sortOrder = TrackSortOrder.alphabetical;
        final remote = remoteLib.library.state;
        final b = await _loaded();
        await b.library.mergeRemote(remote);
        b.library.sortOrder = TrackSortOrder.custom;
        expect(
          b.library.state.settings.stamps['sortOrder']! > remote.latest!,
          isTrue,
        );
      },
    );

    test('unsaved local changes survive a merge', () async {
      final a = await _loaded(saveDelay: const Duration(hours: 1));
      final t = await a.add('a.mp3');
      a.library.updateSettings(
        t.id,
        t.settings.copyWith(speed: 0.75, speedEnabled: true),
      );
      await a.library.mergeRemote(SharedState.empty);
      expect(a.library.track(t.id)!.settings.speed, 0.75);
      a.library.dispose();
    });

    test('a merge notifies and cancels a pending save', () async {
      final store = _CountingStore();
      final a = await _loaded(
        store: store,
        saveDelay: const Duration(milliseconds: 30),
      );
      final t = await a.add('a.mp3');
      a.library.updateSettings(t.id, t.settings.copyWith(speed: 0.5));
      final before = a.notified;
      final writes = store.indexWrites;
      await a.library.mergeRemote(SharedState.empty);
      expect(a.notified, greaterThan(before));
      expect(store.indexWrites, writes + 1);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(store.indexWrites, writes + 1);
    });
  });

  group('#37 files of tracks deleted or added elsewhere', () {
    test(
      'a track deleted elsewhere loses its audio file and artwork here',
      () async {
        final a = await _loaded();
        final t = await a.add('cover.mp3', bytes: _withCover('a', [1, 2, 3]));
        expect(t.hasArtwork, isTrue);
        final remote = a.library.state.copyWith(
          tracks: {
            t.id: a.library.state.tracks[t.id]!.delete(
              Hlc(
                _t0.add(const Duration(hours: 1)).millisecondsSinceEpoch,
                0,
                'f',
              ),
            ),
          },
        );
        await a.library.mergeRemote(remote);
        expect(a.library.tracks, isEmpty);
        expect(
          a.store.files.keys.where((k) => k.startsWith('Tracks/')),
          isEmpty,
        );
        expect(a.library.hasFile(t.id), isTrue); // nothing absent any more
      },
    );

    test(
      'a track from elsewhere whose file is already here is not absent',
      () async {
        final other = await _loaded();
        final t = await other.add('a.mp3');
        final b = await _loaded();
        b.store.files[Library.trackName(t.fileName)] =
            other.store.files[Library.trackName(t.fileName)]!;
        await b.library.mergeRemote(other.library.state);
        expect(b.library.hasFile(t.id), isTrue);
      },
    );

    test(
      'a track from elsewhere without its file is absent until it arrives',
      () async {
        final other = await _loaded();
        final t = await other.add('a.mp3');
        final b = await _loaded();
        await b.library.mergeRemote(other.library.state);
        expect(b.library.hasFile(t.id), isFalse);
        // the next merge sees the file that arrived in the meantime
        b.store.files[Library.trackName(t.fileName)] =
            other.store.files[Library.trackName(t.fileName)]!;
        await b.library.mergeRemote(other.library.state);
        expect(b.library.hasFile(t.id), isTrue);
      },
    );

    test('a track deleted elsewhere is no longer absent; imported again it is here', () async {
      final other = await _loaded();
      final keep = await other.add('keep.mp3');
      final drop = await other.add('drop.mp3');
      final b = await _loaded();
      await b.library.mergeRemote(other.library.state);
      expect(
        [b.library.hasFile(keep.id), b.library.hasFile(drop.id)],
        [false, false],
      );
      other.now = _t0.add(const Duration(hours: 1));
      other.library.delete({drop.id});
      await b.library.mergeRemote(other.library.state);
      expect(b.library.hasFile(keep.id), isFalse); // still elsewhere only
      await b.add('drop.mp3'); // the same contents again, here
      expect(b.library.hasFile(drop.id), isTrue);
    });
  });

  group('#37/AK5 audio from the cloud', () {
    test('only bytes matching the hash of a known track are stored', () async {
      final a = await _loaded();
      final t = await a.add('a.mp3');
      expect(await a.library.addAudio('0' * 64, _bytes('x')), isFalse);
      expect(await a.library.addAudio(t.id, _bytes('other bytes')), isFalse);
    });

    test(
      'a stored file brings its artwork, notifies and measures storage',
      () async {
        final bytes = _withCover('b', [7, 7, 7]);
        final other = await _loaded();
        final t = await other.add('b.mp3', bytes: bytes);
        final b = await _loaded();
        await b.library.mergeRemote(other.library.state);
        final before = b.notified;
        b.store.files.clear();
        expect(await b.library.addAudio(t.id, bytes), isTrue);
        expect(b.store.files[Library.trackName(t.fileName)], bytes);
        expect(
          b.store.files.keys.where((k) => k != Library.trackName(t.fileName)),
          isNotEmpty, // the artwork
        );
        expect(b.library.hasFile(t.id), isTrue);
        expect(b.notified, greaterThanOrEqualTo(before + 2));
        expect(b.library.storage!.used, greaterThan(0));
      },
    );

    test(
      'a track in a folder this device does not know may be uploaded',
      () async {
        final a = await _loaded();
        final t = await a.add('a.mp3');
        expect(
          a.library.uploadable(t.copyWith(folderId: () => 'unknown')),
          isTrue,
        );
      },
    );

    test('«don\'t upload» and «sync» of a folder notify', () async {
      final a = await _loaded();
      final t = await a.add('a.mp3');
      final f = a.library.createFolder('F');
      var before = a.notified;
      a.library.setNoUpload({t.id}, true);
      expect(a.notified, before + 1);
      before = a.notified;
      a.library.setFolderSync(f.id, false);
      expect(a.notified, before + 1);
      expect(a.library.folders.single.sync, isFalse);
      before = a.notified;
      a.library.setFolderSync(f.id, false); // unchanged: nothing
      a.library.setFolderSync('unknown', true);
      expect(a.notified, before);
    });
  });

  group('#16/AK1 saving', () {
    test('a failed save is reported and notified', () async {
      final a = await _loaded(store: _FailingStore());
      final before = a.notified;
      await a.library.save();
      expect(a.library.lastError, isA<LibrarySaveFailed>());
      expect(a.notified, greaterThan(before));
    });

    test('several changes within the delay are saved once', () async {
      final store = _CountingStore();
      final a = await _loaded(
        store: store,
        saveDelay: const Duration(milliseconds: 30),
      );
      final t = await a.add('a.mp3');
      final writes = store.indexWrites;
      a.library.updateSettings(t.id, t.settings.copyWith(speed: 0.5));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      a.library.updateSettings(t.id, t.settings.copyWith(speed: 0.6));
      expect(store.indexWrites, writes);
      // wait for the save (a state, not a time), then for as long again
      await eventually(() => store.indexWrites != writes, 'delayed save');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(store.indexWrites, writes + 1);
      final tracks = (a.saved['tracks'] as Map)[t.id] as Map;
      expect((tracks['values'] as Map)['speed'], 0.6);
      a.library.dispose();
    });

    // On the fake clock of testWidgets: the timers run exactly when the test moves the clock.
    testWidgets('changes keep postponing the save until they stop', (
      tester,
    ) async {
      final store = _CountingStore();
      final a = _Lib(store: store, saveDelay: const Duration(milliseconds: 30));
      await a.library.load();
      final t = await a.add('a.mp3');
      final writes = store.indexWrites;
      for (final speed in [0.5, 0.6, 0.7, 0.8]) {
        a.library.updateSettings(t.id, t.settings.copyWith(speed: speed));
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(store.indexWrites, writes); // still changing: not saved yet
      await tester.pump(const Duration(milliseconds: 20));
      expect(store.indexWrites, writes + 1);
      await tester.pump(const Duration(milliseconds: 100));
      expect(store.indexWrites, writes + 1);
    });

    test('a direct save cancels the pending one', () async {
      final store = _CountingStore();
      final a = await _loaded(
        store: store,
        saveDelay: const Duration(milliseconds: 30),
      );
      final t = await a.add('a.mp3');
      final writes = store.indexWrites;
      a.library.updateSettings(t.id, t.settings.copyWith(speed: 0.5));
      await a.library.save();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(store.indexWrites, writes + 1);
    });

    test('flush saves a pending change at once, and only then', () async {
      final a = await _loaded(saveDelay: const Duration(hours: 1));
      final t = await a.add('a.mp3');
      final before = a.store.files[Library.indexName];
      a.library.flush(); // nothing pending: no write
      expect(identical(a.store.files[Library.indexName], before), isTrue);
      a.library.updateSettings(t.id, t.settings.copyWith(speed: 0.5));
      a.library.flush();
      final tracks = (a.saved['tracks'] as Map)[t.id] as Map;
      expect((tracks['values'] as Map)['speed'], 0.5);
      a.library.dispose();
    });

    test('dispose saves a pending change and ends the notifier', () async {
      final a = await _loaded(saveDelay: const Duration(hours: 1));
      final t = await a.add('a.mp3');
      a.library.updateSettings(t.id, t.settings.copyWith(speed: 0.25));
      a.library.dispose();
      final tracks = (a.saved['tracks'] as Map)[t.id] as Map;
      expect((tracks['values'] as Map)['speed'], 0.25);
      expect(() => a.library.addListener(() {}), throwsA(isA<Error>()));
    });

    test(
      'unchanged settings neither save nor notify; changed ones notify',
      () async {
        final a = await _loaded(saveDelay: const Duration(hours: 1));
        final t = await a.add('a.mp3');
        final before = a.notified;
        a.library.updateSettings(t.id, t.settings);
        a.library.flush();
        expect(a.notified, before);
        a.library.updateSettings(t.id, t.settings.copyWith(speed: 0.5));
        expect(a.notified, before + 1);
        a.library.dispose();
      },
    );
  });

  group('#16/AK4 import', () {
    test('custom order counts on from the highest', () async {
      final a = await _loaded();
      final t1 = await a.add('a.mp3');
      final t2 = await a.add('b.mp3');
      expect([t1.customOrder, t2.customOrder], [0, 1]);
    });

    test('the library is marked as importing while it imports', () async {
      final a = await _loaded(store: _NoStorageStore());
      _sources['a.mp3'] = _bytes('a');
      final seen = <bool>[];
      a.library.addListener(() => seen.add(a.library.isImporting));
      await a.library.importFiles(['a.mp3']);
      expect(seen, [true, false]);
    });

    test('a read-only library refuses the import and notifies', () async {
      final store = MemoryFileStore()
        ..files[Library.indexName] = _bytes('{"formatVersion": 99}');
      final a = await _loaded(store: store);
      final before = a.notified;
      _sources['a.mp3'] = _bytes('a');
      final r = await a.library.importFiles(['a.mp3']);
      expect(r.failed, ['a.mp3']);
      expect(a.notified, before + 1);
    });

    test(
      'a name that is only an extension keeps its name, the file gets .mp3',
      () async {
        final a = await _loaded();
        final t = await a.add('.flac');
        expect(t.title, '.flac');
        expect(t.fileName, endsWith('.mp3'));
      },
    );

    test('a source that cannot be read fails without leaving a file', () async {
      final a = await _loaded();
      final r = await a.library.importFiles(['throw.mp3']);
      expect(r.failed, ['throw.mp3']);
      expect(a.store.files.keys.where((k) => k.startsWith('Tracks/')), isEmpty);
    });

    test(
      'a duration of 0 is no audio; an unknown duration is accepted',
      () async {
        final zero = await _loaded(probe: (_) => 0);
        _sources['z.mp3'] = _bytes('z');
        expect((await zero.library.importFiles(['z.mp3'])).failed, ['z.mp3']);
        final unknown = await _loaded(probe: (_) => null);
        _sources['u.mp3'] = _bytes('u');
        final r = await unknown.library.importFiles(['u.mp3']);
        expect(r.imported.single.duration, 0);
      },
    );

    test('artwork is stored only when the file has one', () async {
      final a = await _loaded();
      final plain = await a.add('plain.mp3');
      expect(plain.hasArtwork, isFalse);
      final art = await a.add('art.mp3', bytes: _withCover('x', [5, 6]));
      expect(art.hasArtwork, isTrue);
      expect(
        a.store.files.values.where((v) => v.length == 2 && v[0] == 5),
        hasLength(1),
      );
    });
  });

  group('#16/AK5 deleting, moving and folders', () {
    test('deleting forgets a missing file and notifies', () async {
      final other = await _loaded();
      final t = await other.add('a.mp3');
      final b = await _loaded();
      await b.library.mergeRemote(other.library.state);
      expect(b.library.hasFile(t.id), isFalse);
      final before = b.notified;
      b.library.delete({t.id});
      expect(b.library.hasFile(t.id), isTrue);
      expect(b.notified, greaterThan(before));
    });

    test('moving down counts the target before removing the row', () async {
      final a = await _loaded();
      final t1 = await a.add('1.mp3');
      final t2 = await a.add('2.mp3');
      final t3 = await a.add('3.mp3');
      a.library.sortOrder = TrackSortOrder.custom;
      final before = a.notified;
      a.library.move(null, 0, 2); // first row before the third
      expect(a.library.sortedTracks.map((t) => t.id), [t2.id, t1.id, t3.id]);
      expect(a.notified, before + 1);
      final order = {
        for (final e in (a.saved['tracks'] as Map).entries)
          e.key: ((e.value as Map)['values'] as Map)['customOrder'],
      };
      expect(order[t2.id], 0);
      a.library.move(null, 2, 0); // up: the target is the row itself
      expect(a.library.sortedTracks.map((t) => t.id), [t3.id, t2.id, t1.id]);
      a.library.move(null, 1, 1); // onto itself: nothing moves
      expect(a.library.sortedTracks.map((t) => t.id), [t3.id, t2.id, t1.id]);
    });

    test('creating, renaming and deleting a folder save and notify', () async {
      final a = await _loaded();
      var before = a.notified;
      final f = a.library.createFolder('  ');
      expect(a.notified, before + 1);
      expect(
        ((a.saved['folders'] as Map)[f.id] as Map)['values'],
        containsPair('name', ''),
      );
      before = a.notified;
      a.library.renameFolder(f.id, 'Neu');
      expect(a.notified, before + 1);
      expect(
        ((a.saved['folders'] as Map)[f.id] as Map)['values'],
        containsPair('name', 'Neu'),
      );
      before = a.notified;
      a.library.deleteFolder(f.id);
      expect(a.notified, before + 1);
      expect(((a.saved['folders'] as Map)[f.id] as Map)['deleted'], isNotNull);
    });

    test('moving tracks into a folder saves and notifies', () async {
      final a = await _loaded();
      final t = await a.add('a.mp3');
      final f = a.library.createFolder('F');
      final before = a.notified;
      a.library.moveTracks({t.id}, f.id);
      expect(a.notified, before + 1);
      expect(
        (((a.saved['tracks'] as Map)[t.id] as Map)['values']
            as Map)['folderId'],
        f.id,
      );
    });

    test('dropping a track before another switches to custom order', () async {
      final a = await _loaded();
      final t1 = await a.add('1.mp3');
      final t2 = await a.add('2.mp3');
      a.library.placeTrack(t1.id, null, beforeId: t2.id);
      expect(a.library.sortOrder, TrackSortOrder.custom);
      expect(a.saved['settings'], isNotNull);
    });
  });

  group('#24 title and artist', () {
    test('unchanged title and artist are accepted', () async {
      final a = await _loaded();
      final t = await a.add('a.mp3');
      expect(
        a.library.editMetadata(t.id, title: t.title, artist: t.artist),
        isTrue,
      );
    });

    test('changing only the artist is saved', () async {
      final a = await _loaded();
      final t = await a.add('a.mp3');
      expect(
        a.library.editMetadata(t.id, title: t.title, artist: 'Neu'),
        isTrue,
      );
      expect(a.library.track(t.id)!.artist, 'Neu');
      expect(
        (((a.saved['tracks'] as Map)[t.id] as Map)['values'] as Map)['artist'],
        'Neu',
      );
    });
  });

  group('#42/AK5 duration from the core', () {
    test(
      'a missing duration is filled once and notified; 0 or less is ignored',
      () async {
        final a = await _loaded(probe: (_) => null);
        final t = await a.add('a.mp3');
        expect(t.duration, 0);
        var before = a.notified;
        a.library.fillDuration(t.id, 0);
        expect(a.library.track(t.id)!.duration, 0);
        expect(a.notified, before);
        a.library.fillDuration(t.id, 3.5);
        expect(a.library.track(t.id)!.duration, 3.5);
        expect(a.notified, before + 1);
        before = a.notified;
        a.library.fillDuration(t.id, 9);
        expect(a.library.track(t.id)!.duration, 3.5);
        expect(a.notified, before);
      },
    );
  });

  test('#36/AK1 track IDs are the SHA-256 of the contents', () async {
    final a = await _loaded();
    final t = await a.add('a.mp3', contents: 'abc');
    expect(t.id, _hash(_bytes('abc')));
  });
}
