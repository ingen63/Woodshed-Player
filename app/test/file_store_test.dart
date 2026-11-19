// #35: Speicher-Schicht (FileStore) und Titel über den SHA-256 ihres Inhalts. Dateisystem nur in temporären
// Ordnern, nie in der echten Bibliothek; der Browser wird mit MemoryFileStore nachgebildet (keine Pfade,
// wie OPFS). Das echte OPFS im Browser prüft tool/web_store_check.dart.
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

/// SHA-256 von «abc» (FIPS 180-2, Anhang B.1).
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

/// Bibliothek wie im Browser: Dateiauswahl liefert Schlüssel, deren Bytes einmal abgeholt werden.
class WebLike {
  WebLike([MemoryFileStore? store]) : store = store ?? MemoryFileStore();
  final MemoryFileStore store;
  final picked = <String, Uint8List>{};
  late final library = Library(
    store,
    probe: (_) => null, // Dauer kennt erst der Kern beim Laden
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

/// Bibliotheksordner mit library.json aus [golden] und den Audiodateien der Golden-Titel.
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

  group('#35/AK1 FileStore für Dateisystem und OPFS', () {
    test('Dateisystem: schreiben, lesen, umbenennen, löschen, Hash', () async {
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
      await s.delete('Tracks/b.mp3'); // fehlt schon: kein Fehler
      expect(await s.exists('Tracks/b.mp3'), isFalse);
      expect(await s.sha256('Tracks/b.mp3'), isNull);
      expect(
        Directory('${tmp.path}/lib/Tracks').listSync(),
        isEmpty,
        reason: 'keine Zwischendateien',
      );
    });

    test('OPFS-Implementierung im Browser, gewählt von platform_web', () {
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

    test('Bibliothek arbeitet mit jedem FileStore', () async {
      final w = WebLike();
      await w.library.load();
      final t = (await w.library.importFiles([w.pick('a.mp3', 'eins')]))
          .imported
          .single;
      expect(w.store.files.keys, contains('Tracks/${t.fileName}'));
      expect(w.store.files.keys, contains('library.json'));
    });
  });

  group('#35/AK2 Titel über SHA-256, dieselbe Datei nur einmal', () {
    test('Import speichert den Hash des Inhalts', () async {
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
      expect(json.single['id'], t.id, reason: 'UUID bleibt interne ID');
      expect(json.single['fileName'], '${t.id}.mp3');
    });

    test('gleicher Inhalt unter anderem Namen: keine zweite Datei', () async {
      final base = Directory('${tmp.path}/lib');
      final l = ioLibrary(base);
      await l.load();
      final first = (await l.importFiles([source('a.mp3', 'abc').path]))
          .imported
          .single;
      final r = await l.importFiles([
        source('kopie.mp3', 'abc').path,
        source('anders.mp3', 'xyz').path,
        source('nochmal.mp3', 'xyz').path, // Doppel im selben Import
      ]);
      expect(r.imported.map((t) => t.originalFileName), ['anders.mp3']);
      expect(r.duplicates.map((t) => t.id), [first.id, r.imported.single.id]);
      expect(r.failed, isEmpty);
      expect(l.tracks, hasLength(2));
      expect(Directory('${base.path}/Tracks').listSync(), hasLength(2));
    });

    test('alte Bibliothek: Hash wird im Hintergrund nachgerechnet', () async {
      final store = MemoryFileStore()..hashGate = Completer<void>();
      store.files['library.json'] = File(goldenNew).readAsBytesSync();
      for (final t in tracksIn(File(goldenNew).readAsStringSync())) {
        store.files['Tracks/${t['fileName']}'] = bytes('inhalt ${t['id']}');
      }
      final w = WebLike(store);
      await w.library.load(); // kehrt zurück, obwohl das Rechnen noch hängt
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
      'Import wartet auf das Nachrechnen und erkennt alte Titel als Doppel',
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

  group('#35/AK3 Im Web fügt die Dateiauswahl Titel dauerhaft hinzu', () {
    test('Import landet im Speicher und ist nach dem Neuladen da', () async {
      final w = WebLike();
      await w.library.load();
      final key = w.pick('Etüde in G.mp3', 'ton');
      final t = (await w.library.importFiles([key])).imported.single;
      expect(t.title, 'Etüde in G');
      expect(t.duration, 0, reason: 'Dauer erst beim Laden bekannt');
      expect(w.picked, isEmpty, reason: 'Bytes der Auswahl abgeholt');
      expect(w.library.filePath(t), 'Tracks/${t.fileName}');
      expect(w.library.localPath(t), isNull, reason: 'im Browser kein Pfad');
      expect(w.store.files['Tracks/${t.fileName}'], bytes('ton'));

      // «Neu laden»: frische Bibliothek auf demselben Speicher.
      final again = WebLike(w.store);
      await again.library.load();
      await again.library.hashing;
      expect(again.library.tracks.single.id, t.id);
      expect(again.library.tracks.single.contentHash, t.contentHash);
    });

    test('Ordner, Einstellungen und Löschen bleiben gespeichert', () async {
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

    test('fehlende Auswahl wird gemeldet', () async {
      final w = WebLike();
      await w.library.load();
      final r = await w.library.importFiles(['web:9/weg.mp3']);
      expect(r.failed, ['weg.mp3']);
      expect(w.library.tracks, isEmpty);
    });
  });

  group(
    '#35/AK4 Desktop: Pfad gerätelokal, alte Bibliotheken öffnen unverändert',
    () {
      test('Pfad nur als gerätelokale Zusatzinfo', () async {
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
        test('library.json im alten Format ($golden)', () async {
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
            expect(a, expected, reason: 'alle bisherigen Felder unverändert');
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

      test(
        'ohne Bibliothek: nichts wird angelegt ausser beim Speichern',
        () async {
          final base = Directory('${tmp.path}/leer');
          final l = ioLibrary(base);
          await l.load();
          expect(l.tracks, isEmpty);
          expect(File('${base.path}/library.json').existsSync(), isFalse);
        },
      );
    },
  );

  group('#35/AK5 dauerhafter Speicher und Speicherverbrauch', () {
    test('Zeile für Desktop und Browser', () {
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

    test('Browser: persist() einmal anfragen, sobald es Titel gibt', () async {
      final w = WebLike();
      await w.library.load();
      expect(w.store.persistRequests, 0, reason: 'leere Bibliothek');
      await w.library.importFiles([w.pick('a.mp3', 'a')]);
      await w.library.importFiles([w.pick('b.mp3', 'b')]);
      expect(w.store.persistRequests, 1);
      expect(w.library.storage!.label, contains('dauerhaft gespeichert'));
      expect(w.library.storage!.label, contains('frei'));

      final again = WebLike(w.store);
      await again.library.load();
      expect(w.store.persistRequests, 2, reason: 'beim Öffnen mit Titeln');
    });

    test('Desktop: kein persist(), belegter Platz der Bibliothek', () async {
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

    testWidgets('Zeile im Fuss der Bibliothek', (tester) async {
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
