// #141/AK4–AK14: export of tracks as MP3 files. File names, ID3 tag and the order per track with a
// fake encoder; the real encoder is tested in the core (mp3_export_tests) and in mp3_ffi_test.dart.
// Temporary folders only, never the real library.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/app/track_export.dart';
import 'package:woodshed_player/library/export_name.dart';
import 'package:woodshed_player/library/id3_tag.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/library/metadata.dart';
import 'package:wp_core/wp_types.dart';

import 'fakes.dart' show eventually;
import 'library_test.dart' as lt show dir, loaded, tmp;
import 'metadata_test.dart' show id3, text;

/// Two MPEG frame headers with some bytes: what an MP3 file holds besides its tags.
final frames = Uint8List.fromList([
  0xff, 0xfb, 0x90, 0x00, ...List.filled(20, 7), //
  0xff, 0xfb, 0x90, 0x00, ...List.filled(20, 9),
]);

List<int> id3v1() => [
  ...'TAG'.codeUnits,
  ...List.filled(125, 0x41),
]; // 128 bytes

List<int> ape({bool header = true}) {
  final items = List.filled(40, 0x55);
  List<int> block(bool isHeader) => [
    ...'APETAGEX'.codeUnits,
    0xd0, 0x07, 0, 0, // version 2000
    ...[(items.length + 32) & 0xff, 0, 0, 0], // size: items + footer
    1, 0, 0, 0, // one item
    0, 0, 0, isHeader ? 0xa0 : (header ? 0x80 : 0), // flags
    ...List.filled(8, 0),
  ];
  return [if (header) ...block(true), ...items, ...block(false)];
}

void main() {
  group('#141/AK5, AK6 exportBaseName', () {
    test('title, artist and year', () {
      expect(
        exportBaseName('Minor Swing', 'Trio', 1937),
        'Minor Swing - Trio - 1937',
      );
    });
    test('a missing part drops out with its dash', () {
      expect(exportBaseName('Minor Swing', null, 1937), 'Minor Swing - 1937');
      expect(exportBaseName('Minor Swing', 'Trio', null), 'Minor Swing - Trio');
      expect(exportBaseName('Minor Swing', null, null), 'Minor Swing');
      expect(exportBaseName('Minor Swing', '  ', null), 'Minor Swing');
    });
    test('characters a file name may not hold become a dash, spaces go', () {
      expect(
        exportBaseName(' AC/DC: Live ', 'A\\B', null),
        'AC-DC- Live - A-B',
      );
      expect(
        exportBaseName('Tab\there', 'Line\nbreak', 7),
        'Tab-here - Line-break - 0007',
      );
    });
  });

  group('#141/AK7 uniqueExportName', () {
    test('free name, then (2), (3)', () {
      expect(uniqueExportName('A', (_) => false), 'A.mp3');
      final taken = {'A.mp3', 'A (2).mp3'};
      expect(uniqueExportName('A', taken.contains), 'A (3).mp3');
      expect(uniqueExportName('A', {'A.mp3'}.contains), 'A (2).mp3');
      expect(uniqueExportName('A', (_) => false, ext: 'wav'), 'A.wav');
    });
  });

  group('#141/AK8 id3v2Tag', () {
    test('is read back with title, artist, album and year', () {
      final tag = id3v2Tag(
        title: 'Minor Swing',
        artist: 'Trío',
        album: 'Live',
        year: 1937,
      );
      expect(tag.sublist(0, 5), [0x49, 0x44, 0x33, 3, 0]);
      final m = readMetadata(Uint8List.fromList([...tag, ...frames]));
      expect(m.title, 'Minor Swing');
      expect(m.artist, 'Trío');
      expect(m.album, 'Live');
      expect(m.year, 1937);
    });
    test('fields that are not set are left out', () {
      final tag = id3v2Tag(title: 'T', artist: ' ', year: null);
      final m = readMetadata(Uint8List.fromList([...tag, ...frames]));
      expect(m.title, 'T');
      expect(m.artist, isNull);
      expect(m.album, isNull);
      expect(m.year, isNull);
      expect(String.fromCharCodes(tag).contains('TPE1'), isFalse);
      expect(id3v2Tag().length, 10);
    });
    test('the size in the header is the size of the frames', () {
      final tag = id3v2Tag(title: 'Title');
      final size = tag[6] << 21 | tag[7] << 14 | tag[8] << 7 | tag[9];
      expect(size, tag.length - 10);
    });
  });

  group('#141/AK9 mp3Frames', () {
    test('without tags the file stays', () {
      expect(mp3Frames(frames), frames);
    });
    test('takes off ID3v2, ID3v1 and APEv2', () {
      final tagged = Uint8List.fromList([
        ...id3(3, [('TIT2', text(0, 'Old'))]).sublist(0, 10 + 20 + 11),
        ...frames,
        ...ape(),
        ...id3v1(),
      ]);
      final withTag = Uint8List.fromList([
        ...id3v2Tag(title: 'Old'),
        ...frames,
        ...ape(),
        ...id3v1(),
      ]);
      expect(mp3Frames(withTag), frames);
      expect(
        mp3Frames(
          Uint8List.fromList([
            ...id3v2Tag(title: 'X'),
            ...frames,
            ...id3v1(),
            ...ape(header: false),
          ]),
        ),
        frames,
      );
      expect(tagged.length, greaterThan(frames.length));
    });
    test('several ID3v2 tags and a v2.4 footer', () {
      final v24 = [
        ...'ID3'.codeUnits, 4, 0, 0x10, 0, 0, 0, 2, 0, 0, //
        ...'3DI'.codeUnits, 4, 0, 0x10, 0, 0, 0, 2,
      ];
      final b = Uint8List.fromList([
        ...id3v2Tag(title: 'A'),
        ...v24,
        ...frames,
      ]);
      expect(mp3Frames(b), frames);
    });
    test('a tag claiming more than the file is left as it is', () {
      final b = Uint8List.fromList([
        ...'ID3'.codeUnits,
        3,
        0,
        0,
        0x7f,
        0x7f,
        0x7f,
        0x7f,
        ...frames,
      ]);
      expect(mp3Frames(b), b);
    });
    test('a tag exactly at the bounds', () {
      // only an empty ID3v2 header, only ID3v1, only an APE footer: nothing remains
      expect(mp3Frames(id3v2Tag()), isEmpty);
      expect(mp3Frames(Uint8List.fromList(id3v1())), isEmpty);
      final apeFooterOnly = ape(header: false).sublist(40); // no items: size 32
      apeFooterOnly[12] = 32;
      expect(mp3Frames(Uint8List.fromList(apeFooterOnly)), isEmpty);
      // a file shorter than any tag at the end stays
      final short = Uint8List.fromList([0xff, 0xfb, 0x90, 0]);
      expect(mp3Frames(short), short);
    });
    test('ID3v2.4 without a footer, v2.3 with the footer bit', () {
      for (final version in [3, 4]) {
        final noFooter = [
          ...'ID3'.codeUnits,
          version,
          0,
          version == 3 ? 0x10 : 0,
          0,
          0,
          0,
          2,
          0,
          0, //
        ];
        expect(
          mp3Frames(Uint8List.fromList([...noFooter, ...frames])),
          frames,
          reason: 'v2.$version',
        );
      }
    });
    test(
      'an APE tag claiming more than the file, or less than its footer, stays',
      () {
        final big = ape(header: false);
        big[big.length - 32 + 13] = 0x10; // size 4096 + …
        final b = Uint8List.fromList([...frames, ...big]);
        expect(mp3Frames(b), b);
        final tiny = ape(header: false);
        tiny[tiny.length - 32 + 12] = 0; // size 0
        final t = Uint8List.fromList([...frames, ...tiny]);
        expect(mp3Frames(t), t);
      },
    );
    test('only tags give nothing', () {
      expect(
        mp3Frames(Uint8List.fromList([...id3v2Tag(title: 'A'), ...id3v1()])),
        isEmpty,
      );
    });
  });

  group('#141 TrackExporter', () {
    late Library lib;
    late Directory out;
    late List<(String, String)> encoded;
    var encodeCode = WpCode.ok;
    Completer<void>? encodeGate;
    var fetchOk = true;
    final fetched = <String>[];

    TrackExporter exporter() => TrackExporter(
      library: lib,
      fetchAudio: (t) async {
        fetched.add(t.id);
        return fetchOk;
      },
      encode: (input, output, {cancel, onProgress}) async {
        encoded.add((input, output));
        onProgress?.call(0.5);
        if (encodeGate != null) {
          await Future.any([encodeGate!.future, ?cancel]);
          if (!encodeGate!.isCompleted) {
            File(output).writeAsBytesSync([1, 2, 3]); // half written
            return WpCode.cancelled;
          }
        }
        if (encodeCode == WpCode.ok) File(output).writeAsBytesSync(frames);
        return encodeCode;
      },
    );

    Future<Track> add(String name, List<int> bytes) async {
      final f = File('${lt.dir('quelle').path}/$name')..writeAsBytesSync(bytes);
      return (await lib.importFiles([f.path])).imported.single;
    }

    Uint8List file(String name) => File('${out.path}/$name').readAsBytesSync();

    setUp(() async {
      lt.tmp = Directory.systemTemp.createTempSync('wp_export');
      lib = await lt.loaded(lt.dir('lib'));
      out = lt.dir('out');
      encoded = [];
      encodeCode = WpCode.ok;
      encodeGate = null;
      fetchOk = true;
      fetched.clear();
    });
    tearDown(() => lt.tmp.deleteSync(recursive: true));

    test(
      '#141/AK9: an MP3 keeps its frames, the tag comes from the library',
      () async {
        final t = await add('a.mp3', [
          ...id3v2Tag(title: 'Old', year: 1999),
          ...frames,
          ...id3v1(),
        ]);
        lib.editMetadata(t.id, title: 'Minor Swing', artist: 'Trio');
        lib.editYear(t.id, 1937);
        final r = await exporter().run([lib.track(t.id)!], out.path);
        expect(r.exported, ['Minor Swing - Trio - 1937.mp3']);
        expect(r.failures, isEmpty);
        expect(r.cancelled, isFalse);
        expect(encoded, isEmpty); // not encoded again
        final b = file('Minor Swing - Trio - 1937.mp3');
        expect(mp3Frames(b), frames);
        final m = readMetadata(b);
        expect(m.title, 'Minor Swing');
        expect(m.artist, 'Trio');
        expect(m.year, 1937);
      },
    );

    test('#141/AK10: other formats are encoded, the tag goes in front, no part file stays', () async {
      final t = await add('b.wav', 'RIFF....WAVE'.codeUnits);
      final r = await exporter().run([t], out.path);
      expect(r.exported, ['b.mp3']);
      expect(encoded.single.$1, lib.filePath(t));
      expect(encoded.single.$2, '${out.path}/b.mp3.part');
      final b = file('b.mp3');
      expect(mp3Frames(b), frames);
      expect(readMetadata(b).title, 'b');
      expect(out.listSync().map((e) => e.uri.pathSegments.last), ['b.mp3']);
    });

    test(
      '#141/AK7: names taken in the folder or in the same export get a number',
      () async {
        final a = await add('x1.mp3', [...frames, 1]);
        final b = await add('x2.mp3', [...frames, 2]);
        final c = await add('x3.mp3', [...frames, 3]);
        for (final t in [a, b, c]) {
          lib.editMetadata(t.id, title: 'Same', artist: null);
        }
        File('${out.path}/same.MP3').writeAsBytesSync([
          0,
        ]); // another case: the same name on macOS and Windows (#60)
        final r = await exporter().run(
          [a, b, c].map((t) => lib.track(t.id)!).toList(),
          out.path,
        );
        final names = Platform.isMacOS || Platform.isWindows
            ? ['Same (2).mp3', 'Same (3).mp3', 'Same (4).mp3']
            : ['Same.mp3', 'Same (2).mp3', 'Same (3).mp3'];
        expect(r.exported, names);
        expect(File('${out.path}/same.MP3').readAsBytesSync(), [
          0,
        ]); // nothing overwritten
      },
    );

    test(
      '#141/AK11: tempo, loop and the other settings do not change the file',
      () async {
        final t = await add('c.mp3', frames);
        lib.updateSettings(
          t.id,
          const PlaybackSettings(
            speedEnabled: true,
            speed: 0.5,
            loopEnabled: true,
            loopStart: 0,
            loopEnd: 1,
          ),
        );
        await exporter().run([lib.track(t.id)!], out.path);
        expect(mp3Frames(file('c.mp3')), frames);
      },
    );

    test('#141/AK12: cancel stops; files written before stay, a half-written one goes', () async {
      final a = await add('d1.mp3', [...frames, 1]);
      final b = await add('d2.wav', 'RIFF1'.codeUnits);
      final c = await add('d3.wav', 'RIFF2'.codeUnits);
      encodeGate = Completer();
      final cancel = Completer<void>();
      final steps = <(int, int, double)>[];
      final running = exporter().run(
        [a, b, c],
        out.path,
        cancel: cancel.future,
        progress: (i, n, f) => steps.add((i, n, f)),
      );
      await eventually(() => encoded.isNotEmpty, 'the second track is encoded');
      cancel.complete();
      final r = await running;
      expect(r.cancelled, isTrue);
      expect(r.exported, ['d1.mp3']);
      expect(r.failures, isEmpty);
      expect(encoded.length, 1); // d3 not started
      expect(out.listSync().map((e) => e.uri.pathSegments.last), ['d1.mp3']);
      expect(steps.first, (0, 3, 0.0));
      expect(steps, contains((1, 3, 0.5)));
      expect(steps.last.$1, 1);
    });

    test(
      '#141/AK12: cancelled before the start, nothing is exported',
      () async {
        final a = await add('k1.mp3', [...frames, 1]);
        final b = await add('k2.mp3', [...frames, 2]);
        final r = await exporter().run(
          [a, b],
          out.path,
          cancel: Future.value(),
        );
        expect(r.cancelled, isTrue);
        expect(r.exported, isEmpty);
        expect(out.listSync(), isEmpty);
      },
    );

    test('#141/AK12: progress per track and at the end', () async {
      final a = await add('p1.mp3', [...frames, 1]);
      final b = await add('p2.wav', 'RIFF3'.codeUnits);
      final steps = <(int, int, double)>[];
      await exporter().run(
        [a, b],
        out.path,
        progress: (i, n, f) => steps.add((i, n, f)),
      );
      expect(steps, [(0, 2, 0.0), (1, 2, 0.0), (1, 2, 0.5), (2, 2, 0.0)]);
    });

    test(
      '#141/AK13: a failing track is named, the others are exported',
      () async {
        final a = await add('e1.wav', 'RIFF4'.codeUnits);
        final b = await add('e2.mp3', [...frames, 5]);
        for (final (code, problem) in [
          (WpCode.unsupportedFormat, ExportProblem.format),
          (WpCode.fileNotFound, ExportProblem.format),
          (WpCode.unsupportedSampleRate, ExportProblem.format),
          (WpCode.fileUnreadable, ExportProblem.format),
          (WpCode.encoderUnavailable, ExportProblem.encoderMissing),
          (WpCode.fileUnwritable, ExportProblem.write),
          (WpCode.outOfMemory, ExportProblem.failed),
        ]) {
          encodeCode = code;
          for (final f in out.listSync()) {
            f.deleteSync();
          }
          final r = await exporter().run([a, b], out.path);
          expect(r.failures.single.track.id, a.id, reason: '$code');
          expect(r.failures.single.problem, problem, reason: '$code');
          expect(r.exported, ['e2.mp3'], reason: '$code');
          expect(r.cancelled, isFalse);
          expect(File('${out.path}/e1.mp3.part').existsSync(), isFalse);
        }
      },
    );

    test('#141/AK13: an encoder that throws, an MP3 without frames, an unwritable folder', () async {
      final a = await add('f1.wav', 'RIFF6'.codeUnits);
      final b = await add('f2.mp3', id3v2Tag(title: 'only a tag'));
      final throwing = TrackExporter(
        library: lib,
        fetchAudio: (_) async => true,
        encode: (i, o, {cancel, onProgress}) async {
          File(o).writeAsBytesSync([1, 2]); // half written, then a failure
          throw StateError('x');
        },
      );
      final r = await throwing.run([a, b], out.path);
      expect(r.failures.map((f) => f.problem), [
        ExportProblem.failed,
        ExportProblem.format,
      ]);
      expect(out.listSync(), isEmpty); // no part file stays
      final r2 = await exporter().run([
        lib.track(b.id)!,
      ], '${out.path}/missing');
      expect(r2.failures.single.problem, ExportProblem.format);
      final c = await add('f3.mp3', [...frames, 8]);
      final r3 = await exporter().run([c], '${out.path}/missing');
      expect(r3.failures.single.problem, ExportProblem.write);
    });

    test('#141/AK14: a track only in the cloud is loaded first; failing that, it fails', () async {
      final a = await add('g1.mp3', [...frames, 9]);
      await lib.setKeepOffline({}, true);
      await lib.setCacheLimit(1);
      expect(await lib.trimCache(inCloud: (_) => true), [a.id]);
      fetchOk = false;
      final r = await exporter().run([a], out.path);
      expect(fetched, [a.id]);
      expect(r.failures.single.problem, ExportProblem.notLoaded);
      expect(out.listSync(), isEmpty);
      // loaded: the file is back and exported
      fetchOk = true;
      final ok = TrackExporter(
        library: lib,
        fetchAudio: (t) async =>
            lib.addAudio(t.id, Uint8List.fromList([...frames, 9])),
        encode: (i, o, {cancel, onProgress}) async => WpCode.ok,
      );
      final r2 = await ok.run([a], out.path);
      expect(r2.exported, ['g1.mp3']);
    });

    test('a track on this device is not loaded again', () async {
      final a = await add('h.mp3', frames);
      await exporter().run([a], out.path);
      expect(fetched, isEmpty);
    });
  });
}
