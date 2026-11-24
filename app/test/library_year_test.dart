// #141/AK1–AK3, #140/AK12a: the year in the library: from the tag on import, set by the command line, read
// once for the tracks already there. Works on temporary folders, never on the real library.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/app/file_store_io.dart';
import 'package:woodshed_player/library/library.dart';

import 'library_test.dart' as lt show IoLibrary, dir, loaded, source, tmp;
import 'library_test.dart' show IoLibrary;
import 'metadata_test.dart' show id3, text;

Uint8List tagged(String year, [String title = 'Getaggt']) =>
    id3(3, [('TIT2', text(0, title)), ('TYER', text(0, year))]);

File taggedSource(String name, String year) =>
    File('${lt.dir('quelle').path}/$name')
      ..writeAsBytesSync([...tagged(year, name), ...name.codeUnits]);

/// Counts the audio files read and can hold the next read back until [gate] completes.
class CountingStore extends IoFileStore {
  CountingStore(super.base);
  final reads = <String>[];
  Completer<void>? gate;
  void Function()? onRead;

  @override
  Future<Uint8List?> read(String name) async {
    if (name.startsWith('Tracks/')) {
      reads.add(name);
      onRead?.call();
      if (gate case final g?) await g.future;
    }
    return super.read(name);
  }
}

void main() {
  setUp(() => lt.tmp = Directory.systemTemp.createTempSync('wp_year'));
  tearDown(() => lt.tmp.deleteSync(recursive: true));

  test('#141/AK2 an imported MP3 takes the year from its tag', () async {
    final l = await lt.loaded(lt.dir('lib'));
    final r = await l.importFiles([taggedSource('a.mp3', '1937').path]);
    expect(r.imported.single.year, 1937);
    final again = await lt.loaded(l.base);
    expect(again.tracks.single.year, 1937);
  });

  test('#141/AK2 without a year in the tag it stays empty', () async {
    final l = await lt.loaded(lt.dir('lib'));
    final r = await l.importFiles([lt.source('b.mp3').path]);
    expect(r.imported.single.year, isNull);
  });

  group('#140/AK12a editYear', () {
    test('sets, keeps and clears the year', () async {
      final l = await lt.loaded(lt.dir('lib'));
      final t = (await l.importFiles([lt.source('c.mp3').path]))
          .imported
          .single;
      expect(l.editYear(t.id, 1937), isTrue);
      expect(l.track(t.id)!.year, 1937);
      expect((await lt.loaded(l.base)).track(t.id)!.year, 1937);
      expect(l.editYear(t.id, 1937), isTrue);
      expect(l.editYear(t.id, null), isTrue);
      expect(l.track(t.id)!.year, isNull);
    });
    test(
      'refuses an unknown track and a year that is not four digits',
      () async {
        final l = await lt.loaded(lt.dir('lib'));
        final t = (await l.importFiles([lt.source('d.mp3').path]))
            .imported
            .single;
        expect(l.editYear('f' * 64, 1937), isFalse);
        expect(l.editYear(t.id, 0), isFalse);
        expect(l.editYear(t.id, 10000), isFalse);
        expect(l.editYear(t.id, 1), isTrue);
        expect(l.editYear(t.id, 9999), isTrue);
        expect(l.track(t.id)!.year, 9999);
      },
    );
    test('notifies listeners only on a change', () async {
      final l = await lt.loaded(lt.dir('lib'));
      final t = (await l.importFiles([lt.source('e.mp3').path]))
          .imported
          .single;
      var calls = 0;
      l.addListener(() => calls++);
      l.editYear(t.id, 1937);
      expect(calls, 1);
      l.editYear(t.id, 1937);
      expect(calls, 1);
    });
  });

  group('#141/AK3 fillYears', () {
    /// A library whose tracks were imported before the year existed: the stored files carry a tag now.
    Future<(Library, String, String)> older() async {
      final l = await lt.loaded(lt.dir('lib'));
      final a = (await l.importFiles([lt.source('a.mp3').path]))
          .imported
          .single;
      final b = (await l.importFiles([lt.source('b.mp3').path]))
          .imported
          .single;
      File('${l.tracksDir.path}/${a.fileName}')
          .writeAsBytesSync(tagged('1937'));
      File('${l.tracksDir.path}/${b.fileName}')
          .writeAsBytesSync(tagged('1941'));
      return (l, a.id, b.id);
    }

    test('reads the year of tracks without one, once per device', () async {
      final (l, a, b) = await older();
      expect(await l.fillYears(), 2);
      expect(l.track(a)!.year, 1937);
      expect(l.track(b)!.year, 1941);
      final again = await lt.loaded(l.base);
      expect(again.track(a)!.year, 1937);
      // the second start reads nothing
      File('${l.tracksDir.path}/${again.track(a)!.fileName}')
          .writeAsBytesSync(tagged('1999'));
      again.editYear(a, null);
      expect(await again.fillYears(), 0);
      expect(again.track(a)!.year, isNull);
    });

    test('a year set already stays', () async {
      final (l, a, b) = await older();
      l.editYear(a, 1950);
      expect(await l.fillYears(), 1);
      expect(l.track(a)!.year, 1950);
      expect(l.track(b)!.year, 1941);
    });

    test('skips tracks whose file is not on this device', () async {
      final (l, a, b) = await older();
      // the file of a was removed from the cache (#39): the track stays, its file is not here
      await l.setKeepOffline({b}, true);
      await l.setCacheLimit(1);
      expect(await l.trimCache(inCloud: (_) => true), [a]);
      expect(l.hasFile(a), isFalse);
      expect(await l.fillYears(), 1);
      expect(l.track(a)!.year, isNull);
      expect(l.track(b)!.year, 1941);
    });

    /// [older] with a store that counts reads, loaded anew.
    Future<(Library, CountingStore, String, String)> counted() async {
      final (l, a, b) = await older();
      final store = CountingStore(l.base);
      final again = Library(
        store,
        probe: (_) => 2.5,
        readSource: readLocalFile,
        saveDelay: Duration.zero,
      );
      await again.load();
      store.reads.clear();
      return (again, store, a, b);
    }

    test(
      'a track with a year is not read, and listeners hear of the change once',
      () async {
        final (l, store, a, b) = await counted();
        l.editYear(a, 1950);
        var calls = 0;
        l.addListener(() => calls++);
        expect(await l.fillYears(), 1);
        expect(store.reads, ['Tracks/${l.track(b)!.fileName}']);
        expect(calls, 1);
      },
    );

    test('a year set while the file is read stays', () async {
      final (l, store, a, b) = await counted();
      store.gate = Completer();
      store.onRead = () {
        // the user sets the year of a while its file is read
        if (store.reads.length == 1) l.editYear(a, 1950);
      };
      final running = l.fillYears();
      await Future<void>.delayed(Duration.zero);
      store.gate!.complete();
      expect(await running, 1);
      expect(l.track(a)!.year, 1950);
      expect(l.track(b)!.year, 1941);
    });

    test('nothing to read still marks the device and does not save', () async {
      final l = await lt.loaded(lt.dir('lib'));
      await l.importFiles([lt.source('x.mp3').path]);
      var calls = 0;
      l.addListener(() => calls++);
      expect(await l.fillYears(), 0);
      expect(calls, 0);
      final f = File('${l.base.path}/device.json').readAsStringSync();
      expect(f, contains('"yearsRead":true'));
    });
  });
}
