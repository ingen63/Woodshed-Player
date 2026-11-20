// #16: Bibliothek und Datenmodell. Alle Tests arbeiten in einem temporären Ordner, nie in der echten Bibliothek.
// Since #36 the golden files are the former format 1 and are migrated on load (see migration_test.dart).
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/app/file_store_io.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/library/natural_compare.dart';

const goldenNew = 'test/golden/library_swift.json';
const goldenLegacy = 'test/golden/library_swift_legacy.json';

/// Former UUIDs of the golden tracks.
const id1 = '0F0E0D0C-0B0A-0908-0706-050403020100';
const id2 = '99999999-8888-7777-6666-555555555555';

/// Their IDs after the migration (#36): SHA-256 of the audio files written by [swiftFolder].
final hash1 = crypto.sha256.convert(utf8.encode('mp3')).toString();
final hash2 = crypto.sha256.convert(utf8.encode('flac')).toString();
const etueden = '11111111-2222-3333-4444-555555555555';

late Directory tmp;

Directory dir(String name) =>
    Directory('${tmp.path}/$name')..createSync(recursive: true);

/// Bibliotheksordner mit library.json aus [golden] und leeren Audiodateien.
Directory swiftFolder(String name, String golden, {bool withFiles = true}) {
  final d = dir(name);
  File(golden).copySync('${d.path}/library.json');
  Directory('${d.path}/Tracks').createSync();
  if (withFiles) {
    File('${d.path}/Tracks/$id1.mp3').writeAsStringSync('mp3');
    File('${d.path}/Tracks/$id1.artwork').writeAsStringSync('jpg');
    File('${d.path}/Tracks/$id2.flac').writeAsStringSync('flac');
  }
  return d;
}

/// Dauer-Attrappe: Dateien mit «kaputt» im Namen sind kein Audio.
double fakeProbe(String path) =>
    latin1.decode(File(path).readAsBytesSync()).contains('kaputt') ? -3 : 2.5;

var clock = DateTime.utc(2026, 1, 1);
Library lib(Directory base) => Library(
  IoFileStore(base),
  probe: fakeProbe,
  readSource: readLocalFile,
  now: () => clock = clock.add(const Duration(minutes: 1)),
  saveDelay: Duration.zero,
  random: Random(1),
);

Future<Library> loaded(Directory base) async {
  final l = lib(base);
  await l.load();
  return l;
}

/// Library folders and files in the file system (tests only).
extension IoLibrary on Library {
  Directory get base => (store as IoFileStore).base;
  Directory get tracksDir => Directory('${base.path}/Tracks');
  File get indexFile => File('${base.path}/library.json');
}

/// Source file; without [content] it gets contents unique to its name (equal contents are a duplicate, #35).
File source(String name, [String? content]) =>
    File('${dir('quelle').path}/$name')
      ..writeAsStringSync(content ?? 'audio $name');

void main() {
  setUp(() => tmp = Directory.systemTemp.createTempSync('wp_library_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('#16/AK1 Datenmodell', () {
    test('Track mit allen Feldern aus der Swift-JSON (migriert)', () async {
      final l = await loaded(swiftFolder('lib', goldenNew));
      final t = l.track(hash1)!;
      expect(t.fileName, '$hash1.mp3');
      expect(t.originalFileName, 'Übung in C.mp3');
      expect(t.title, 'Übung in C');
      expect(t.artist, 'Testband');
      expect(t.album, 'Testalbum');
      expect(t.duration, 183.456);
      expect(t.hasArtwork, isTrue);
      expect(t.customOrder, 2);
      expect(t.folderId, etueden);
      expect(
        t.dateAdded,
        DateTime.utc(2001).add(const Duration(microseconds: 784123456789000)),
      );
      expect(
        t.settings,
        const PlaybackSettings(
          speedEnabled: true,
          speed: 0.75,
          loopEnabled: true,
          loopStart: 12.5,
          loopEnd: 47,
        ),
      );
      final t2 = l.track(hash2)!;
      expect(t2.artist, isNull);
      expect(t2.folderId, isNull);
      expect(t2.settings, const PlaybackSettings());
      expect(l.folders.map((f) => f.name), ['Etüden', 'Swing 2']);
    });

    test('Swift-Datum: Sekunden seit 2001-01-01', () {
      expect(dateToSwift(DateTime.utc(2001)), 0);
      expect(dateFromSwift(0), DateTime.utc(2001));
      expect(dateToSwift(dateFromSwift(784123456.789)), 784123456.789);
    });

    test('neue UUIDs wie in Swift: Version 4, Grossbuchstaben', () {
      final u = newUuid(Random(7));
      expect(
        u,
        matches(
          RegExp(
            r'^[0-9A-F]{8}-[0-9A-F]{4}-4[0-9A-F]{3}-[89AB][0-9A-F]{3}-[0-9A-F]{12}$',
          ),
        ),
      );
    });
  });

  group('#16/AK2 library.json', () {
    test(
      'altes Format [Track] wird gelesen und im neuen Format gespeichert',
      () async {
        final base = swiftFolder('lib', goldenLegacy);
        final l = await loaded(base);
        expect(l.tracks.length, 2);
        expect(l.folders, isEmpty);
        l.save();
        final json = jsonDecode(
          File('${base.path}/library.json').readAsStringSync(),
        ) as Map;
        expect(json['formatVersion'], SharedState.formatVersion);
        expect((json['tracks'] as Map).length, 2);
      },
    );

    test('#21/AK4 bestehende library.json und preferences.json mit altem Schlüssel werden gelesen', () async {
      final base = swiftFolder('lib', goldenNew);
      File(
        '${base.path}/preferences.json',
      ).writeAsStringSync('{"sortOrder":"alphabetical","legacyImported":true}');
      final l = await loaded(base);
      expect(l.tracks.map((t) => t.id), containsAll([hash1, hash2]));
      expect(l.folders.length, 2);
      expect(l.sortOrder, TrackSortOrder.alphabetical);
      expect((await loaded(base)).sortOrder, TrackSortOrder.alphabetical);
    });

    test('fehlende Dateien: Einträge fallen weg und werden gezählt', () async {
      final base = swiftFolder('lib', goldenNew);
      File('${base.path}/Tracks/$id2.flac').deleteSync();
      final l = await loaded(base);
      expect(l.tracks.map((t) => t.id), [hash1]);
      expect(l.droppedMissing, 1);
    });

    test('no library.json: empty library, Tracks/ appears with the first import (#35)', () async {
      final base = dir('neu');
      final l = await loaded(base);
      expect(l.tracks, isEmpty);
      await l.importFiles([source('a.mp3').path]);
      expect(Directory('${base.path}/Tracks').listSync(), hasLength(1));
    });

    test(
      'beschädigte library.json wird aufgehoben, nicht überschrieben',
      () async {
        final base = dir('kaputt');
        File('${base.path}/library.json')
            .writeAsStringSync('{ "tracks": [ kaputt');
        final l = await loaded(base);
        expect(l.tracks, isEmpty);
        expect(l.lastError, isA<LibraryCorrupt>());
        expect(
          (l.lastError! as LibraryCorrupt).backupName,
          startsWith('library.json.defekt-'),
        );
        final kept = base.listSync().whereType<File>().where(
          (f) => f.path.contains('library.json.defekt-'),
        );
        expect(kept.length, 1);
        expect(kept.first.readAsStringSync(), '{ "tracks": [ kaputt');
      },
    );

    test('Einstellungen pro Titel werden gespeichert', () async {
      final base = swiftFolder('lib', goldenNew);
      final l = await loaded(base);
      l.updateSettings(
        hash2,
        const PlaybackSettings(
          loopEnabled: true,
          loopStart: 0.25,
          loopEnd: 0.75,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      l.flush();
      final again = await loaded(base);
      expect(again.track(hash2)!.settings.loopStart, 0.25);
      expect(again.track(hash2)!.settings.loopEnabled, isTrue);
    });

    test('#29/AK7 Steigerung pro Titel wird gespeichert', () async {
      final base = swiftFolder('lib', goldenNew);
      final l = await loaded(base);
      final ramp = const PlaybackSettings().copyWith(
        rampEnabled: true,
        rampStart: 55,
        rampTarget: 95,
        rampStep: 2,
        rampPasses: 6,
      );
      l.updateSettings(hash2, ramp);
      await Future<void>.delayed(Duration.zero);
      l.flush();
      final again = await loaded(base);
      expect(again.track(hash2)!.settings, ramp);
    });
  });

  group('#16/AK4 Import', () {
    test('kopiert in den App-Ordner und liest Metadaten und Cover', () async {
      final l = await loaded(dir('neu'));
      final wav = File('${dir('quelle').path}/Aufnahme.wav')
        ..writeAsBytesSync(wavWithInfo('Etüde 3', 'Testband'));
      final r = await l.importFiles([wav.path]);
      expect(r.failed, isEmpty);
      final t = r.imported.single;
      expect(t.title, 'Etüde 3');
      expect(t.artist, 'Testband');
      expect(t.originalFileName, 'Aufnahme.wav');
      expect(t.fileName, '${t.id}.wav');
      expect(t.duration, 2.5);
      expect(File(l.filePath(t)).existsSync(), isTrue);
      expect(wav.existsSync(), isTrue, reason: 'original stays');
      expect(
        jsonDecode(l.indexFile.readAsStringSync())['tracks'],
        hasLength(1),
      );
    });

    test('ohne Titel im Tag: Dateiname ohne Endung', () async {
      final l = await loaded(dir('neu'));
      final r = await l.importFiles([source('Mein Stück.MP3').path]);
      expect(r.imported.single.title, 'Mein Stück');
      expect(r.imported.single.fileName, endsWith('.mp3'));
    });

    test(
      'unlesbare und fehlende Dateien werden gemeldet, nichts bleibt liegen',
      () async {
        final l = await loaded(dir('neu'));
        final r = await l.importFiles([
          source('gut.mp3').path,
          source('kaputt.mp3', 'kaputt').path,
          '${tmp.path}/gibts-nicht.mp3',
        ]);
        expect(r.imported.length, 1);
        expect(r.failed, ['kaputt.mp3', 'gibts-nicht.mp3']);
        expect((l.lastError! as ImportFailed).files, [
          'kaputt.mp3',
          'gibts-nicht.mp3',
        ]);
        expect(l.tracksDir.listSync().length, 1);
      },
    );

    test(
      'in einen Ordner importieren, Löschen entfernt Datei und Cover',
      () async {
        final l = await loaded(dir('neu'));
        final f = l.createFolder('Übungen');
        final r = await l.importFiles([source('a.mp3').path], folderId: f.id);
        final t = r.imported.single;
        expect(t.folderId, f.id);
        File('${l.tracksDir.path}/${t.id}.artwork').writeAsStringSync('x');
        l.delete({t.id});
        expect(l.tracks, isEmpty);
        expect(l.tracksDir.listSync(), isEmpty);
      },
    );
  });

  group('#16/AK5 Sortierung und Ordner', () {
    late Library l;
    late Map<String, String> ids;
    setUp(() async {
      l = await loaded(dir('neu'));
      final r = await l.importFiles([
        for (final n in ['Track 10', 'track 2', 'Ärger', 'Bossa', 'Zebra'])
          source('$n.mp3').path,
      ]);
      ids = {for (final t in r.imported) t.title: t.id};
    });

    List<String> titles([String? folder]) =>
        l.sortedTracksIn(folder).map((t) => t.title).toList();

    test('Standard: zuletzt hinzugefügte zuerst', () {
      expect(l.sortOrder, TrackSortOrder.dateAdded);
      expect(titles(), ['Zebra', 'Bossa', 'Ärger', 'track 2', 'Track 10']);
    });

    test(
      'alphabetisch natürlich, Umlaute beim Grundbuchstaben, Zahlen nach Wert',
      () {
        l.sortOrder = TrackSortOrder.alphabetical;
        expect(titles(), ['Ärger', 'Bossa', 'track 2', 'Track 10', 'Zebra']);
      },
    );

    test('eigene Reihenfolge durch Verschieben, ausgehend von der Anzeige', () {
      l.sortOrder = TrackSortOrder.alphabetical;
      l.move(null, 4, 0); // Zebra nach oben
      expect(l.sortOrder, TrackSortOrder.custom);
      expect(titles(), ['Zebra', 'Ärger', 'Bossa', 'track 2', 'Track 10']);
      l.move(null, 0, 5); // ans Ende (Index vor dem Entfernen)
      expect(titles(), ['Ärger', 'Bossa', 'track 2', 'Track 10', 'Zebra']);
    });

    test('Sortierung bleibt nach Neustart', () async {
      l.sortOrder = TrackSortOrder.alphabetical;
      expect((await loaded(l.base)).sortOrder, TrackSortOrder.alphabetical);
    });

    test(
      'Ordner anlegen, umbenennen, löschen: Titel bleiben erhalten',
      () async {
        final f = l.createFolder('  Swing ');
        expect(f.name, 'Swing');
        expect(
          l.createFolder('   ', fallback: 'Neuer Ordner').name,
          'Neuer Ordner',
        );
        l.moveTracks({ids['Bossa']!, ids['Zebra']!}, f.id);
        expect(titles(f.id), ['Zebra', 'Bossa']);
        expect(titles().length, 3);
        l.renameFolder(f.id, '  ');
        expect(l.folders.firstWhere((x) => x.id == f.id).name, 'Swing');
        l.renameFolder(f.id, 'Jazz');
        expect(l.folders.firstWhere((x) => x.id == f.id).name, 'Jazz');
        l.deleteFolder(f.id);
        expect(l.folders.where((x) => x.id == f.id), isEmpty);
        expect(l.tracks.length, 5);
        expect(titles().length, 5);
        final again = await loaded(l.base);
        expect(again.tracks.where((t) => t.folderId != null), isEmpty);
      },
    );

    test('in Ordner an eine Stelle verschieben und wieder heraus', () {
      final f = l.createFolder('A');
      l.sortOrder = TrackSortOrder.custom;
      l.moveTracks({ids['Bossa']!}, f.id, at: 0);
      l.moveTracks({ids['Zebra']!}, f.id, at: 0);
      expect(titles(f.id), ['Zebra', 'Bossa']);
      l.moveTracks({ids['Zebra']!}, null, at: 0);
      expect(titles(f.id), ['Bossa']);
      expect(titles().first, 'Zebra');
    });

    test('Ordner alphabetisch', () {
      l.createFolder('b');
      l.createFolder('Ä');
      l.createFolder('C 10');
      l.createFolder('C 9');
      expect(l.sortedFolders.map((f) => f.name), ['Ä', 'b', 'C 9', 'C 10']);
    });
  });

  test('naturalCompare', () {
    expect(naturalCompare('a2', 'a10'), lessThan(0));
    expect(naturalCompare('Öl', 'Ofen'), greaterThan(0)); // «ol» nach «ofen»
    expect(naturalCompare('abc', 'ABD'), lessThan(0));
    expect(naturalCompare('Straße', 'Strasse'), isNot(0));
  });

  test('#59 sortedNaturally (one key per item) sorts like naturalCompare', () {
    final r = Random(59);
    const pieces = [
      'a',
      'B',
      'ä',
      'Ö',
      'o',
      ' ',
      '2',
      '10',
      '007',
      'ß',
      'ss',
      'x-1',
    ];
    final texts = [
      for (var i = 0; i < 500; i++)
        [
          for (var j = r.nextInt(5); j >= 0; j--)
            pieces[r.nextInt(pieces.length)],
        ].join(),
    ];
    expect(sortedNaturally(texts, (t) => t), [...texts]..sort(naturalCompare));
  });
}

/// WAV mit LIST/INFO-Block (Titel, Künstler).
List<int> wavWithInfo(String title, String artist) {
  List<int> le32(int v) => [
    v & 255,
    v >> 8 & 255,
    v >> 16 & 255,
    v >> 24 & 255,
  ];
  List<int> sub(String id, String text) {
    final b = [...utf8.encode(text), 0];
    return [...id.codeUnits, ...le32(b.length), ...b, if (b.length.isOdd) 0];
  }

  final info = [
    ...'INFO'.codeUnits,
    ...sub('INAM', title),
    ...sub('IART', artist),
  ];
  final list = [...'LIST'.codeUnits, ...le32(info.length), ...info];
  final fmt = [
    ...'fmt '.codeUnits,
    ...le32(16),
    1,
    0,
    1,
    0,
    ...le32(8000),
    ...le32(16000),
    2,
    0,
    16,
    0,
  ];
  final data = [...'data'.codeUnits, ...le32(4), 0, 0, 0, 0];
  final body = [...'WAVE'.codeUnits, ...fmt, ...list, ...data];
  return [...'RIFF'.codeUnits, ...le32(body.length), ...body];
}
