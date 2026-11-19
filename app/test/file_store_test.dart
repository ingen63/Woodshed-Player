// #35: storage layer (FileStore) and tracks identified by the SHA-256 of their contents. File system only in
// temporary folders, never the real library; the browser is modelled with MemoryFileStore (no paths, like
// OPFS). tool/web_store_check.dart checks the real OPFS in a browser.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/app/file_store_io.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/ui/home_page.dart';
import 'package:woodshed_player/ui/style.dart';

import 'fakes.dart';

const goldenNew = 'test/golden/library_swift.json';
const goldenLegacy = 'test/golden/library_swift_legacy.json';

/// SHA-256 of «abc» (FIPS 180-2, appendix B.1).
const abcHash =
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

late Directory tmp;

Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

File source(String name, String content) => File('${tmp.path}/quelle/$name')
  ..createSync(recursive: true)
  ..writeAsStringSync(content);

Library ioLibrary(Directory base) => Library(
  IoFileStore(base),
  probe: (_) => 2.5,
  readSource: readLocalFile,
  saveDelay: Duration.zero,
  random: Random(7),
);

/// Library as in the browser: the file picker hands out keys whose bytes are fetched once.
class WebLike {
  WebLike([MemoryFileStore? store]) : store = store ?? MemoryFileStore();
  final MemoryFileStore store;
  final picked = <String, Uint8List>{};
  late final library = Library(
    store,
    probe: (_) => null, // only the core knows the duration, when loading
    readSource: (key) async => picked.remove(key),
    saveDelay: Duration.zero,
    random: Random(5),
  );

  String pick(String name, String content) {
    final key = 'web:${picked.length + 1}/$name';
    picked[key] = bytes(content);
    return key;
  }
}

/// Library folder with library.json from [golden] and audio files for the golden tracks.
Directory swiftFolder(String golden) {
  final d = Directory('${tmp.path}/swift')..createSync();
  File(golden).copySync('${d.path}/library.json');
  final json = jsonDecode(File(golden).readAsStringSync());
  final tracks = json is List ? json : (json as Map)['tracks'] as List;
  for (final t in tracks.cast<Map>()) {
    File('${d.path}/Tracks/${t['fileName']}')
      ..createSync(recursive: true)
      ..writeAsStringSync('inhalt ${t['fileName']}');
  }
  return d;
}

List<Map<String, Object?>> tracksIn(String json) {
  final j = jsonDecode(json);
  return [
    for (final t in (j is List ? j : (j as Map)['tracks'] as List))
      (t as Map).cast<String, Object?>(),
  ];
}

void main() {
  setUp(() => tmp = Directory.systemTemp.createTempSync('wp_store_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('#35/AK1 FileStore for file system and OPFS', () {
    test('file system: write, read, rename, delete, hash', () async {
      final s = IoFileStore(Directory('${tmp.path}/lib'));
      expect(await s.read('Tracks/a.mp3'), isNull);
      await s.write('Tracks/a.mp3', bytes('abc'));
      expect(await s.exists('Tracks/a.mp3'), isTrue);
      expect(utf8.decode((await s.read('Tracks/a.mp3'))!), 'abc');
      expect(await s.sha256('Tracks/a.mp3'), abcHash);
      await s.write('Tracks/a.mp3', bytes('neu'));
      expect(utf8.decode((await s.read('Tracks/a.mp3'))!), 'neu');
      await s.rename('Tracks/a.mp3', 'Tracks/b.mp3');
      expect(await s.exists('Tracks/a.mp3'), isFalse);
      expect((await s.storageInfo()).used, 3);
      await s.delete('Tracks/b.mp3');
      await s.delete('Tracks/b.mp3'); // already gone: no error
      expect(await s.exists('Tracks/b.mp3'), isFalse);
      expect(await s.sha256('Tracks/b.mp3'), isNull);
      expect(
        Directory('${tmp.path}/lib/Tracks').listSync(),
        isEmpty,
        reason: 'no temporary files left',
      );
    });

    test('OPFS implementation for the browser, chosen by platform_web', () {
      final web = File('lib/app/file_store_web.dart').readAsStringSync();
      expect(web, contains('class OpfsFileStore extends FileStore'));
      expect(web, contains('navigator.storage.getDirectory()'));
      expect(web, contains('createWritable()'));
      final platform = File('lib/app/platform_web.dart').readAsStringSync();
      expect(platform, contains('OpfsFileStore.open('));
      final native = File('lib/app/platform_native.dart').readAsStringSync();
      expect(native, contains('IoFileStore('));
      final library = File('lib/library/library.dart').readAsStringSync();
      expect(library, isNot(contains("import 'dart:io'")));
    });

    test('library works with any FileStore', () async {
      final w = WebLike();
      await w.library.load();
      final t = (await w.library.importFiles([w.pick('a.mp3', 'eins')]))
          .imported
          .single;
      expect(w.store.files.keys, contains('Tracks/${t.fileName}'));
      expect(w.store.files.keys, contains('library.json'));
    });
  });

  group('#35/AK2 tracks identified by SHA-256, the same file stored once', () {
    test('import stores the content hash', () async {
      final l = ioLibrary(Directory('${tmp.path}/lib'));
      await l.load();
      final t = (await l.importFiles([source('a.mp3', 'abc').path]))
          .imported
          .single;
      expect(t.contentHash, abcHash);
      expect(l.trackWithHash(abcHash)?.id, t.id);
      final json = tracksIn(
        File('${tmp.path}/lib/library.json').readAsStringSync(),
      );
      expect(json.single['contentHash'], abcHash);
      expect(json.single['id'], t.id, reason: 'UUID stays the internal ID');
      expect(json.single['fileName'], '${t.id}.mp3');
    });

    test('same contents under another name: no second file', () async {
      final base = Directory('${tmp.path}/lib');
      final l = ioLibrary(base);
      await l.load();
      final first = (await l.importFiles([source('a.mp3', 'abc').path]))
          .imported
          .single;
      final r = await l.importFiles([
        source('kopie.mp3', 'abc').path,
        source('anders.mp3', 'xyz').path,
        source('nochmal.mp3', 'xyz').path, // duplicate within the same import
      ]);
      expect(r.imported.map((t) => t.originalFileName), ['anders.mp3']);
      expect(r.duplicates.map((t) => t.id), [first.id, r.imported.single.id]);
      expect(r.failed, isEmpty);
      expect(l.tracks, hasLength(2));
      expect(Directory('${base.path}/Tracks').listSync(), hasLength(2));
    });

    test('old library: hash is computed in the background', () async {
      final store = MemoryFileStore()..hashGate = Completer<void>();
      store.files['library.json'] = File(goldenNew).readAsBytesSync();
      for (final t in tracksIn(File(goldenNew).readAsStringSync())) {
        store.files['Tracks/${t['fileName']}'] = bytes('inhalt ${t['id']}');
      }
      final w = WebLike(store);
      await w.library.load(); // returns although hashing is still blocked
      expect(w.library.tracks, hasLength(2));
      expect(w.library.tracks.every((t) => t.contentHash == null), isTrue);
      var done = false;
      w.library.hashing.then((_) => done = true);
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);
      store.hashGate!.complete();
      await w.library.hashing;
      for (final t in w.library.tracks) {
        expect(
          t.contentHash,
          await store.sha256('Tracks/${t.fileName}'),
          reason: t.title,
        );
      }
      final saved = tracksIn(utf8.decode(store.files['library.json']!));
      expect(
        saved.every((t) => (t['contentHash'] as String).length == 64),
        isTrue,
      );
    });

    test(
      'import waits for hashing and detects old tracks as duplicates',
      () async {
        final store = MemoryFileStore()..hashGate = Completer<void>();
        store.files['library.json'] = File(goldenNew).readAsBytesSync();
        final old = tracksIn(File(goldenNew).readAsStringSync()).first;
        for (final t in tracksIn(File(goldenNew).readAsStringSync())) {
          store.files['Tracks/${t['fileName']}'] = bytes('inhalt ${t['id']}');
        }
        final w = WebLike(store);
        await w.library.load();
        final pending = w.library.importFiles([
          w.pick('wieder.mp3', 'inhalt ${old['id']}'),
        ]);
        store.hashGate!.complete();
        final r = await pending;
        expect(r.imported, isEmpty);
        expect(r.duplicates.single.id, old['id']);
        expect(w.library.tracks, hasLength(2));
      },
    );
  });

  group('#35/AK3 the web file picker adds tracks permanently', () {
    test('import lands in storage and survives a reload', () async {
      final w = WebLike();
      await w.library.load();
      final key = w.pick('Etüde in G.mp3', 'ton');
      final t = (await w.library.importFiles([key])).imported.single;
      expect(t.title, 'Etüde in G');
      expect(t.duration, 0, reason: 'duration known only when loading');
      expect(w.picked, isEmpty, reason: 'picked bytes were taken');
      expect(w.library.filePath(t), 'Tracks/${t.fileName}');
      expect(w.library.localPath(t), isNull, reason: 'no path in the browser');
      expect(w.store.files['Tracks/${t.fileName}'], bytes('ton'));

      // «Reload»: fresh library on the same storage.
      final again = WebLike(w.store);
      await again.library.load();
      await again.library.hashing;
      expect(again.library.tracks.single.id, t.id);
      expect(again.library.tracks.single.contentHash, t.contentHash);
    });

    test('folders, settings and deletion are persisted', () async {
      final w = WebLike();
      await w.library.load();
      final t = (await w.library.importFiles([w.pick('a.mp3', 'a')]))
          .imported
          .single;
      final f = w.library.createFolder('Übungen');
      w.library.moveTracks({t.id}, f.id);
      w.library.updateSettings(t.id, t.settings.copyWith(speed: 0.75));
      final again = WebLike(w.store);
      await again.library.load();
      expect(again.library.track(t.id)!.folderId, f.id);
      expect(again.library.track(t.id)!.settings.speed, 0.75);
      again.library.delete({t.id});
      await Future<void>.delayed(Duration.zero);
      expect(w.store.files.keys, isNot(contains('Tracks/${t.fileName}')));
    });

    test('missing picked file is reported', () async {
      final w = WebLike();
      await w.library.load();
      final r = await w.library.importFiles(['web:9/weg.mp3']);
      expect(r.failed, ['weg.mp3']);
      expect(w.library.tracks, isEmpty);
    });
  });

  group(
    '#35/AK4 desktop: path is device-local, old libraries open unchanged',
    () {
      test('path only as device-local extra information', () async {
        final base = Directory('${tmp.path}/lib');
        final l = ioLibrary(base);
        await l.load();
        final t = (await l.importFiles([source('a.mp3', 'abc').path]))
            .imported
            .single;
        expect(l.localPath(t), '${base.path}/Tracks/${t.fileName}');
        expect(l.filePath(t), l.localPath(t));
        final saved = File('${base.path}/library.json').readAsStringSync();
        expect(saved, isNot(contains(base.path.replaceAll('/', r'\/'))));
        expect(saved, isNot(contains(base.path)));
      });

      for (final golden in [goldenNew, goldenLegacy]) {
        test('library.json in the old format ($golden)', () async {
          final base = swiftFolder(golden);
          final before = tracksIn(File(golden).readAsStringSync());
          final l = ioLibrary(base);
          await l.load();
          await l.hashing;
          expect(l.droppedMissing, 0);
          expect(l.tracks.map((t) => t.id), [
            for (final t in before) (t['id'] as String).toUpperCase(),
          ]);
          final after = tracksIn(
            File('${base.path}/library.json').readAsStringSync(),
          );
          for (var i = 0; i < before.length; i++) {
            final a = {...after[i]}..remove('contentHash');
            final expected = Track.fromJson(before[i]).toJson();
            expect(a, expected, reason: 'all previous fields unchanged');
            expect(
              after[i]['contentHash'],
              await IoFileStore(base).sha256('Tracks/${after[i]['fileName']}'),
            );
          }
          if (golden == goldenNew) {
            final json = jsonDecode(File(golden).readAsStringSync()) as Map;
            expect(l.folders.map((f) => f.id), [
              for (final f in json['folders'] as List) (f as Map)['id'],
            ]);
          }
        });
      }

      test('no library: nothing is created until saving', () async {
        final base = Directory('${tmp.path}/leer');
        final l = ioLibrary(base);
        await l.load();
        expect(l.tracks, isEmpty);
        expect(File('${base.path}/library.json').existsSync(), isFalse);
      });
    },
  );

  group('#35/AK5 persistent storage and storage usage', () {
    test('line for desktop and browser', () {
      expect(const StorageInfo(used: 1234567890).label, '1,2 GB belegt');
      expect(const StorageInfo(used: 512).label, '512 B belegt');
      expect(const StorageInfo(used: 12300).label, '12,3 KB belegt');
      expect(
        const StorageInfo(
          used: 1200000000,
          quota: 59200000000,
          persisted: true,
        ).label,
        '1,2 GB belegt · 58,0 GB frei · dauerhaft gespeichert',
      );
      expect(
        const StorageInfo(used: 0, quota: 1000, persisted: false).label,
        '0 B belegt · 1,0 KB frei · nicht dauerhaft gespeichert',
      );
    });

    test('browser: request persist() once there are tracks', () async {
      final w = WebLike();
      await w.library.load();
      expect(w.store.persistRequests, 0, reason: 'empty library');
      await w.library.importFiles([w.pick('a.mp3', 'a')]);
      await w.library.importFiles([w.pick('b.mp3', 'b')]);
      expect(w.store.persistRequests, 1);
      expect(w.library.storage!.label, contains('dauerhaft gespeichert'));
      expect(w.library.storage!.label, contains('frei'));

      final again = WebLike(w.store);
      await again.library.load();
      expect(w.store.persistRequests, 2, reason: 'on open with tracks');
    });

    test('desktop: no persist(), space used by the library', () async {
      final base = Directory('${tmp.path}/lib');
      final store = IoFileStore(base);
      expect(await store.requestPersistence(), isNull);
      final l = ioLibrary(base);
      await l.load();
      await l.importFiles([source('a.mp3', 'x' * 2000).path]);
      expect(l.storage!.used, greaterThanOrEqualTo(2000));
      expect(l.storage!.quota, isNull);
      expect(l.storage!.label, endsWith('belegt'));
      final used = l.storage!.used;
      l.delete({l.tracks.single.id});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(l.storage!.used, lessThan(used));
    });

    testWidgets('line in the library footer', (tester) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final app = TestApp(Directory('${tmp.path}/ui'));
      await tester.runAsync(() async {
        await app.library.load();
        await app.library.importFiles([source('a.mp3', 'x' * 1500).path]);
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: woodshedTheme(Brightness.light),
          home: HomePage(controller: app.controller),
        ),
      );
      await tester.pump();
      final line = find.byKey(const Key('storageLine'));
      expect(line, findsOneWidget);
      expect(
        find.descendant(of: line, matching: find.textContaining('KB belegt')),
        findsOneWidget,
      );
    });
  });
}
