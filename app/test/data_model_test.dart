// #36: data model with stamps, tombstones, format version, migration and the split between shared and
// device-local settings. Temporary folders and in-memory stores only, never the real library.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/app/file_store_io.dart';
import 'package:woodshed_player/app/library_settings_store.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/library/migration.dart';
import 'package:woodshed_player/library/stamps.dart';
import 'package:woodshed_player/metronome/metronome_controller.dart';
import 'package:woodshed_player/ui/messages.dart';

import 'fakes.dart';

late Directory tmp;
var clock = DateTime.utc(2026, 3, 1);

Library lib(FileStore store, {int seed = 1}) => Library(
  store,
  probe: (_) => 2.5,
  readSource: readLocalFile,
  now: () => clock,
  saveDelay: Duration.zero,
  random: Random(seed),
);

Future<Library> loaded(FileStore store, {int seed = 1}) async {
  final l = lib(store, seed: seed);
  await l.load();
  return l;
}

File source(String name, [String? content]) => File('${tmp.path}/src/$name')
  ..createSync(recursive: true)
  ..writeAsStringSync(content ?? 'audio $name');

String sha(String s) => crypto.sha256.convert(utf8.encode(s)).toString();

Map<String, Object?> fileJson(Directory base, [String name = 'library.json']) =>
    (jsonDecode(File('${base.path}/$name').readAsStringSync()) as Map)
        .cast<String, Object?>();

Hlc h(int millis, [int counter = 0, String device = 'a']) =>
    Hlc(millis, counter, device);

StampedRecord rec(Map<String, (Object?, Hlc)> fields, [Hlc? deleted]) =>
    StampedRecord(
      {for (final e in fields.entries) e.key: e.value.$1},
      {for (final e in fields.entries) e.key: e.value.$2},
      deleted,
    );

void main() {
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('wp_data_model');
    clock = DateTime.utc(2026, 3, 1);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group(
    '#36/AK1 stamps of time, counter and device ID; per field the higher wins',
    () {
      test(
        'order: time, then counter, then device ID; text form round trip',
        () {
          expect(h(2) > h(1, 9, 'z'), isTrue);
          expect(h(1, 2) > h(1, 1, 'z'), isTrue);
          expect(h(1, 1, 'b') > h(1, 1, 'a'), isTrue);
          final s = Hlc(1763560000000, 3, '3f2a9c1e5b7d4a60');
          expect(Hlc.parse('$s'), s);
          expect(() => Hlc.parse('kaputt'), throwsFormatException);
        },
      );

      test('clock rises even when the wall clock goes back or a newer stamp was seen', () {
        var wall = DateTime.utc(2026, 1, 1, 12);
        final c = HlcClock('d1', now: () => wall);
        final a = c.tick();
        final b = c.tick();
        expect(b > a, isTrue);
        expect(b.counter, 1);
        wall = wall.subtract(const Duration(hours: 1)); // clock set back
        final d = c.tick();
        expect(d > b, isTrue);
        c.observe(
          Hlc(
            wall.add(const Duration(days: 1)).millisecondsSinceEpoch,
            5,
            'zz',
          ),
        );
        final e = c.tick();
        expect(
          e.millis,
          wall.add(const Duration(days: 1)).millisecondsSinceEpoch,
        );
        expect(e.counter, 6);
        expect(e.device, 'd1');
      });

      test('every shared field of track, folder and settings carries a stamp with the device ID', () async {
        final base = Directory('${tmp.path}/lib');
        final l = await loaded(IoFileStore(base));
        final f = l.createFolder('Etüden');
        final t = (await l.importFiles([
          source('a.mp3').path,
        ], folderId: f.id)).imported.single;
        l.metronomePreset = {'meter': 3, 'volume': 0.5};
        l.flush();
        final s = l.state;
        for (final r in [s.tracks[t.id]!, s.folders[f.id]!, s.settings]) {
          expect(r.stamps.keys.toSet(), r.values.keys.toSet());
          expect(r.stamps.values.map((x) => x.device).toSet(), {
            l.device.deviceId,
          });
        }
        expect(
          s.tracks[t.id]!.values.keys,
          containsAll([
            'title',
            'artist',
            'folderId',
            'speed',
            'loop',
            'rampStart',
          ]),
        );
        // stored as text «millis-counter-device» in library.json
        final stored =
            ((fileJson(base)['tracks'] as Map)[t.id] as Map)['stamps'] as Map;
        expect(
          Hlc.parse(stored['title'] as String),
          s.tracks[t.id]!.stamps['title'],
        );
      });

      test(
        'a change stamps only the changed field, with a higher stamp',
        () async {
          final l = await loaded(MemoryFileStore());
          final t = (await l.importFiles([source('a.mp3').path]))
              .imported
              .single;
          final before = l.state.tracks[t.id]!;
          clock = clock.add(const Duration(seconds: 5));
          l.editMetadata(t.id, title: 'Neu');
          l.updateSettings(
            t.id,
            t.settings.copyWith(loopEnabled: true, loopStart: 1, loopEnd: 2),
          );
          l.flush();
          final after = l.state.tracks[t.id]!;
          final changed = [
            for (final k in after.stamps.keys)
              if (after.stamps[k] != before.stamps[k]) k,
          ];
          expect(changed..sort(), ['loop', 'title']);
          expect(after.stamps['title']! > before.stamps['title']!, isTrue);
        },
      );

      test('merge: per field the higher stamp wins, regardless of order', () {
        final a = rec({'title': ('A', h(10)), 'artist': ('X', h(30))});
        final b = rec({
          'title': ('B', h(20, 0, 'b')),
          'artist': ('Y', h(5, 0, 'b')),
        });
        for (final m in [a.merge(b), b.merge(a)]) {
          expect(m.values, {'title': 'B', 'artist': 'X'});
          expect(m.stamps['title'], h(20, 0, 'b'));
        }
      });

      test('merge is commutative, associative and idempotent (random inputs, shuffled order)', () {
        final r = Random(36);
        SharedState randomState() {
          StampedRecord one() => rec(
            {
              for (final k in ['title', 'artist', 'loop'])
                if (r.nextBool())
                  k: (
                    r.nextInt(3),
                    h(r.nextInt(5), r.nextInt(2), 'abc'[r.nextInt(3)]),
                  ),
            },
            r.nextInt(4) == 0 ? h(r.nextInt(5), 0, 'abc'[r.nextInt(3)]) : null,
          );
          return SharedState(
            tracks: {
              for (final id in ['t1', 't2', 't3'])
                if (r.nextBool()) id: one(),
            },
            folders: {
              for (final id in ['f1', 'f2'])
                if (r.nextBool()) id: one(),
            },
            settings: one(),
          );
        }

        String key(SharedState s) => jsonEncode(_sorted(s.toJson()));
        for (var i = 0; i < 300; i++) {
          final states = [randomState(), randomState(), randomState()];
          final ref = key(states[0].merge(states[1]).merge(states[2]));
          final shuffled = [...states]..shuffle(r);
          expect(key(shuffled[0].merge(shuffled[1].merge(shuffled[2]))), ref);
          expect(key(states[0].merge(states[0])), key(states[0]));
          final m = states[0].merge(states[1]);
          expect(key(m.merge(states[1])), key(m));
        }
      });
    },
  );

  group('#36/AK2 tombstones for 90 days; a newer change revives', () {
    test(
      'deleted track and folder stay as tombstones with their values',
      () async {
        final base = Directory('${tmp.path}/lib');
        final l = await loaded(IoFileStore(base));
        final f = l.createFolder('Weg');
        final t = (await l.importFiles([source('a.mp3').path])).imported.single;
        clock = clock.add(const Duration(minutes: 1));
        l.delete({t.id});
        l.deleteFolder(f.id);
        final again = await loaded(IoFileStore(base));
        expect(again.tracks, isEmpty);
        expect(again.folders, isEmpty);
        final tr = again.state.tracks[t.id]!;
        final fr = again.state.folders[f.id]!;
        expect(tr.alive, isFalse);
        expect(fr.alive, isFalse);
        expect(tr.values['title'], t.title);
        expect(tr.deleted!.device, l.device.deviceId);
      },
    );

    test('a newer change on another device revives, an older one does not', () {
      final dead = rec({'title': ('A', h(10))}, h(20));
      expect(dead.alive, isFalse);
      final older = rec({'title': ('B', h(15, 0, 'b'))});
      final newer = rec({'title': ('C', h(25, 0, 'b'))});
      expect(dead.merge(older).alive, isFalse);
      expect(older.merge(dead).alive, isFalse);
      final revived = dead.merge(newer);
      expect(revived.alive, isTrue);
      expect(revived.values['title'], 'C');
      expect(newer.merge(dead).alive, isTrue);
      final s = SharedState(folders: {'f': dead})
          .merge(SharedState(folders: {'f': newer}));
      expect(s.folders['f']!.alive, isTrue);
    });

    test('importing a deleted track again revives it', () async {
      final l = await loaded(MemoryFileStore());
      final t = (await l.importFiles([source('a.mp3').path])).imported.single;
      clock = clock.add(const Duration(minutes: 1));
      l.delete({t.id});
      expect(l.state.tracks[t.id]!.alive, isFalse);
      clock = clock.add(const Duration(minutes: 1));
      final r = await l.importFiles([source('b.mp3', 'audio a.mp3').path]);
      expect(r.imported.single.id, t.id);
      expect(l.state.tracks[t.id]!.alive, isTrue);
    });

    test('tombstones are removed after 90 days, not before', () async {
      final store = MemoryFileStore();
      final l = await loaded(store);
      final t = (await l.importFiles([source('a.mp3').path])).imported.single;
      final f = l.createFolder('Weg');
      l.delete({t.id});
      l.deleteFolder(f.id);
      clock = clock.add(const Duration(days: 89));
      final day89 = await loaded(store);
      expect(day89.state.tracks.keys, [t.id]);
      expect(day89.state.folders.keys, [f.id]);
      clock = clock.add(const Duration(days: 2));
      final day91 = await loaded(store);
      expect(day91.state.tracks, isEmpty);
      expect(day91.state.folders, isEmpty);
      expect(
        SharedState(
          tracks: {
            'x': rec({'title': ('A', h(1))}, h(2)),
          },
        ).purge(DateTime.utc(2030)).tracks,
        isEmpty,
      );
    });

    test('a track in a folder deleted on another device shows without folder', () async {
      final base = Directory('${tmp.path}/lib');
      final l = await loaded(IoFileStore(base));
      final f = l.createFolder('Weg');
      final t = (await l.importFiles([
        source('a.mp3').path,
      ], folderId: f.id)).imported.single;
      // the folder's tombstone arrives from elsewhere (as the sync engine will merge it, #37)
      final json = fileJson(base);
      ((json['folders'] as Map)[f.id] as Map)['deleted'] =
          '${Hlc(clock.add(const Duration(hours: 1)).millisecondsSinceEpoch, 0, 'b')}';
      File('${base.path}/library.json').writeAsStringSync(jsonEncode(json));
      final again = await loaded(IoFileStore(base));
      expect(again.folders, isEmpty);
      expect(again.track(t.id)!.folderId, isNull);
    });
  });

  group('#36/AK3 existing library.json migrated without loss, with backup', () {
    const uuid1 = '0F0E0D0C-0B0A-0908-0706-050403020100';
    const uuid2 = '99999999-8888-7777-6666-555555555555';
    const folder = '11111111-2222-3333-4444-555555555555';

    /// Library folder with the former format, audio, artwork, a recording and preferences.json.
    Directory legacyFolder() {
      final d = Directory('${tmp.path}/alt')..createSync();
      File('test/golden/library_swift.json').copySync('${d.path}/library.json');
      File('${d.path}/Tracks/$uuid1.mp3')
        ..createSync(recursive: true)
        ..writeAsStringSync('eins');
      File('${d.path}/Tracks/$uuid1.artwork').writeAsStringSync('cover');
      File('${d.path}/Tracks/$uuid2.flac').writeAsStringSync('zwei');
      File('${d.path}/preferences.json')
          .writeAsStringSync('{"sortOrder":"custom","appearance":"dark"}');
      return d;
    }

    void expectMigrated(Library l, Directory d) {
      final t1 = l.track(sha('eins'))!;
      final t2 = l.track(sha('zwei'))!;
      expect(t1.fileName, '${sha('eins')}.mp3');
      expect(t2.fileName, '${sha('zwei')}.flac');
      expect(t1.title, 'Übung in C');
      expect(t1.artist, 'Testband');
      expect(t1.album, 'Testalbum');
      expect(t1.duration, 183.456);
      expect(t1.customOrder, 2);
      expect(t1.folderId, folder);
      expect(t1.originalFileName, 'Übung in C.mp3');
      expect(t1.dateAdded, dateFromSwift(784123456.789));
      expect(
        t1.settings,
        const PlaybackSettings(
          speedEnabled: true,
          speed: 0.75,
          loopEnabled: true,
          loopStart: 12.5,
          loopEnd: 47,
        ),
      );
      expect(t2.settings, const PlaybackSettings());
      expect(l.folders.map((f) => (f.id, f.name)), [
        (folder, 'Etüden'),
        ('AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE', 'Swing 2'),
      ]);
      expect(l.sortOrder, TrackSortOrder.custom);
      expect(l.appearance, Appearance.dark);
      // files renamed to <hash>.<ext>, artwork too
      expect(
        File('${d.path}/Tracks/${t1.fileName}').readAsStringSync(),
        'eins',
      );
      expect(
        File('${d.path}/Tracks/${sha('eins')}.artwork').readAsStringSync(),
        'cover',
      );
      expect(l.artworkPath(t1), '${d.path}/Tracks/${sha('eins')}.artwork');
      expect(File('${d.path}/Tracks/$uuid1.mp3').existsSync(), isFalse);
      expect(fileJson(d)['formatVersion'], 2);
      expect(l.droppedMissing, 0);
    }

    test('migration in a temporary folder: everything carried over, backup and ID mapping kept', () async {
      final d = legacyFolder();
      final original = File('${d.path}/library.json').readAsStringSync();
      final l = await loaded(IoFileStore(d));
      expectMigrated(l, d);
      expect(File('${d.path}/$legacyBackupName').readAsStringSync(), original);
      expect(fileJson(d, legacyIdsName), {
        uuid1: sha('eins'),
        uuid2: sha('zwei'),
      });
      // opening again changes nothing
      final again = await loaded(IoFileStore(d));
      expectMigrated(again, d);
      expect(again.state.toJson(), l.state.toJson());
    });

    test('repeatable after an interruption (files partly renamed, library.json still old)', () async {
      final d = legacyFolder();
      final store = IoFileStore(d);
      // first run stopped after renaming the first track, before writing library.json
      await migrateLegacyLibrary(
        store,
        File('${d.path}/library.json').readAsBytesSync(),
      );
      File('${d.path}/Tracks/${sha('zwei')}.flac')
          .renameSync('${d.path}/Tracks/$uuid2.flac');
      expect(fileJson(d).containsKey('formatVersion'), isFalse);
      final l = await loaded(store);
      expectMigrated(l, d);
    });

    test('repeatable when the stored contentHash was missing and the file is already renamed', () async {
      final d = legacyFolder();
      final store = IoFileStore(d);
      await migrateLegacyLibrary(
        store,
        File('${d.path}/library.json').readAsBytesSync(),
      );
      // no old file names any more, only the ID mapping tells which file belongs to which entry
      expect(File('${d.path}/Tracks/$uuid1.mp3').existsSync(), isFalse);
      expectMigrated(await loaded(store), d);
    });

    test(
      'the oldest format [Track] and the browser store use the same migration',
      () async {
        final store = MemoryFileStore();
        store.files['library.json'] = File(
          'test/golden/library_swift_legacy.json',
        ).readAsBytesSync();
        final old = jsonDecode(
          File('test/golden/library_swift_legacy.json').readAsStringSync(),
        ) as List;
        for (final t in old.cast<Map>()) {
          await store.write(
            'Tracks/${t['fileName']}',
            utf8.encode('x${t['id']}'),
          );
        }
        final l = await loaded(store);
        expect(l.tracks, hasLength(old.length));
        expect(
          store.files.keys,
          containsAll([legacyBackupName, legacyIdsName]),
        );
        for (final t in l.tracks) {
          expect(
            store.files.keys,
            contains('Tracks/${t.id}.${t.fileName.split('.').last}'),
          );
        }
      },
    );

    test('metronome presets from metronome.json are taken over into the shared settings', () async {
      final store = MemoryFileStore();
      final l = await loaded(store);
      final legacy = File('${tmp.path}/metronome.json')
        ..writeAsStringSync('{"meter":3,"volume":0.4}');
      final s = LibrarySettingsStore(l, legacy: FileSettingsStore(legacy));
      expect(await s.load(), {'meter': 3, 'volume': 0.4});
      l.flush();
      final again = await loaded(store);
      expect(again.metronomePreset, {'meter': 3, 'volume': 0.4});
      // once in the shared settings, the old file no longer counts
      legacy.writeAsStringSync('{"meter":2}');
      expect(
        await LibrarySettingsStore(
          again,
          legacy: FileSettingsStore(legacy),
        ).load(),
        {'meter': 3, 'volume': 0.4},
      );
    });
  });

  group('#36/AK4 format version; a newer file is not overwritten', () {
    test('library.json carries the format version', () async {
      final base = Directory('${tmp.path}/lib');
      final l = await loaded(IoFileStore(base));
      await l.importFiles([source('a.mp3').path]);
      expect(fileJson(base)['formatVersion'], SharedState.formatVersion);
    });

    test(
      'a newer version is left untouched and reported («update the app»)',
      () async {
        final base = Directory('${tmp.path}/lib')..createSync();
        final newer = '{"formatVersion": 3, "tracks": {}, "neu": true}';
        File('${base.path}/library.json').writeAsStringSync(newer);
        File('${base.path}/Tracks/x.mp3')
          ..createSync(recursive: true)
          ..writeAsStringSync('x');
        final l = await loaded(IoFileStore(base));
        expect(l.readOnly, isTrue);
        expect(l.lastError, isA<LibraryTooNew>());
        expect((l.lastError! as LibraryTooNew).version, 3);
        l.sortOrder = TrackSortOrder.alphabetical;
        l.appearance = Appearance.dark;
        l.createFolder('X');
        final r = await l.importFiles([source('a.mp3').path]);
        expect(r.imported, isEmpty);
        l.delete({'x'});
        await l.save();
        expect(File('${base.path}/library.json').readAsStringSync(), newer);
        expect(Directory('${base.path}/Tracks').listSync(), hasLength(1));
      },
    );

    test('the message is in every language', () {
      const m = LibraryTooNew(3);
      for (final locale in AppLocalizations.supportedLocales) {
        final text = libraryMessageText(lookupAppLocalizations(locale), m);
        expect(text, isNotEmpty);
      }
      expect(
        libraryMessageText(lookupAppLocalizations(const Locale('en')), m),
        contains('update the app'),
      );
      expect(
        libraryMessageText(lookupAppLocalizations(const Locale('de')), m),
        contains('aktualisiere die App'),
      );
    });
  });

  group('#36/AK5 shared and device-local settings are separate', () {
    test('shared: sort order, appearance, metronome presets; device-local: device ID in device.json', () async {
      final base = Directory('${tmp.path}/lib');
      final l = await loaded(IoFileStore(base));
      l.sortOrder = TrackSortOrder.alphabetical;
      l.appearance = Appearance.dark;
      l.metronomePreset = {'meter': 3, 'rampEnabled': true};
      l.flush();
      final shared = ((fileJson(base)['settings'] as Map)['values'] as Map).keys
          .toSet();
      expect(shared, {
        'sortOrder',
        'appearance',
        'metronome.meter',
        'metronome.rampEnabled',
      });
      final device = fileJson(base, DeviceSettings.fileName);
      expect(device.keys, ['deviceId']);
      expect(
        File('${base.path}/library.json').readAsStringSync(),
        isNot(contains(base.path)),
      );
      // device ID stays on this device and is used for its stamps
      final again = await loaded(IoFileStore(base), seed: 99);
      expect(again.device.deviceId, l.device.deviceId);
      final other = await loaded(
        IoFileStore(Directory('${tmp.path}/other')),
        seed: 99,
      );
      expect(other.device.deviceId, isNot(l.device.deviceId));
    });

    test('track fields are shared, the file path is not stored', () async {
      final base = Directory('${tmp.path}/lib');
      final l = await loaded(IoFileStore(base));
      final t = (await l.importFiles([source('a.mp3').path])).imported.single;
      final values = l.state.tracks[t.id]!.values;
      expect(values['fileName'], '${t.id}.mp3');
      expect(
        values.values.whereType<String>().where((v) => v.contains('/')),
        isEmpty,
      );
      expect(l.localPath(t), '${base.path}/Tracks/${t.id}.mp3');
    });
  });
}

/// Sorted keys, so two equal states encode the same.
Object? _sorted(Object? v) => switch (v) {
  Map m => {
    for (final k in (m.keys.cast<String>().toList()..sort())) k: _sorted(m[k]),
  },
  List l => l.map(_sorted).toList(),
  _ => v,
};
