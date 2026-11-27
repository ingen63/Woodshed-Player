// #60/AK4: Windows paths in the library and the import: drive letter, backslash, UNC and umlauts.
// The first group runs everywhere with paths as strings (the library takes the file name from either
// separator); the second one works with real files and runs on Windows, where WP_WINDOWS_REQUIRED=1
// (CI job «windows») turns its skip into a failure. The core opens such paths in
// core/tests/capi_tests.cpp («unicodePath»). The tests never touch the real library.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/app/file_store_io.dart';
import 'package:woodshed_player/library/library.dart';

import 'required_resource.dart';

double _probe(String path) => 2.5;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('wp_win_paths'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Library library(Future<Uint8List?> Function(String path) readSource) =>
      Library(
        IoFileStore(Directory('${tmp.path}/lib')),
        probe: _probe,
        readSource: readSource,
        saveDelay: Duration.zero,
        random: Random(1),
      );

  group('#60/AK4 Windows paths as strings', () {
    test(
      'title and failed names come from the file name after \\ or /',
      () async {
        const sources = {
          r'C:\Users\Jörg\Musik\Übungen\Café Ä.mp3': 'a',
          r'\\server\share\Jazz\Ölweg 7.wav': 'b',
          r'D:/Gemischt\Ordner/Straße.flac': 'c',
          r'\\?\C:\Lange Pfade\Ärger.m4a': 'd',
        };
        final l = library(
          (p) async => sources.containsKey(p) ? utf8.encode(sources[p]!) : null,
        );
        await l.load();
        final r = await l.importFiles([
          ...sources.keys,
          r'E:\Fehlt\Nicht da.mp3',
          r'\\server\share\Fehlt\Weg.mp3',
        ]);
        expect(r.imported.map((t) => t.title), [
          'Café Ä',
          'Ölweg 7',
          'Straße',
          'Ärger',
        ]);
        expect(r.imported.map((t) => t.originalFileName), [
          'Café Ä.mp3',
          'Ölweg 7.wav',
          'Straße.flac',
          'Ärger.m4a',
        ]);
        expect(r.imported.map((t) => t.fileName.split('.').last), [
          'mp3',
          'wav',
          'flac',
          'm4a',
        ]);
        expect(r.failed, ['Nicht da.mp3', 'Weg.mp3']);
      },
    );
  });

  group('#60/AK4 Windows paths with real files', () {
    bool onWindows() => needs(
      windowsRequired,
      available: Platform.isWindows,
      reason: 'Windows paths need Windows',
    );

    test('drive letter, backslash, UNC and umlauts import, play and stay after a reload', () async {
      if (!onWindows()) return;
      final folder = Directory('${tmp.path}\\Übungen Café')..createSync();
      final file = File('${folder.path}\\Ärger öü ß.mp3')
        ..writeAsStringSync('audio');
      final drive = file.absolute.path;
      expect(drive, matches(RegExp(r'^[A-Za-z]:\\')));
      // the same file as UNC path over the administrative share of this computer
      final unc = '\\\\localhost\\${drive[0]}\$${drive.substring(2)}'; // \\localhost\C$\...
      final uncFile = File('${folder.path}\\Zweite Datei Ä.wav')
        ..writeAsStringSync('other');
      final uncSecond =
          '\\\\localhost\\${drive[0]}\$${uncFile.absolute.path.substring(2)}';
      expect(
        File(unc).existsSync(),
        isTrue,
        reason: 'UNC path $unc not reachable',
      );
      final l = library(readLocalFile);
      await l.load();
      final r = await l.importFiles([drive, uncSecond]);
      expect(r.failed, isEmpty);
      expect(r.imported.map((t) => t.title), ['Ärger öü ß', 'Zweite Datei Ä']);
      // the same bytes over UNC are the same track
      final again = await l.importFiles([unc]);
      expect(again.duplicates.single.id, r.imported.first.id);
      // the library file lies in the library folder and opens under its Windows path
      for (final t in r.imported) {
        final local = l.localPath(t)!;
        expect(File(local).existsSync(), isTrue, reason: local);
        expect(l.filePath(t), local);
      }
      // reload: titles with umlauts survive library.json
      final reloaded = library(readLocalFile);
      await reloaded.load();
      expect(reloaded.tracks.map((t) => t.title).toSet(), {
        'Ärger öü ß',
        'Zweite Datei Ä',
      });
    });
  });
}
