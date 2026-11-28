// #163: the flow of the smoke test of dropping files (lib/app/drop_smoke.dart) with the fake core and a
// stand-in for the runner's drop code; the built Windows and Linux app runs it with the real runner in
// tools/smoke_app.sh (mode «drop»). Never the real library.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/app/drop_smoke.dart';
import 'package:woodshed_player/app/file_drop.dart';
import 'package:woodshed_player/app/file_platform.dart';

import 'fakes.dart';

const at = Offset(40, 120);
const short = Duration(milliseconds: 300);

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('wp_drop_smoke'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('#163/AK2 uncPath: the drive path over the administrative share', () {
    expect(
      uncPath(r'C:\Users\Jörg\Übungen\Ärger.wav'),
      r'\\localhost\C$\Users\Jörg\Übungen\Ärger.wav',
    );
    expect(uncPath(r'D:\a.wav'), r'\\localhost\D$\a.wav');
  });

  test('#163 dropSmokeFiles: two sine files and two other files in a folder a URI escapes', () {
    final f = dropSmokeFiles(tmp, windows: false);
    final folder = '${tmp.absolute.path}/Übungen Café #1 50% v1.2';
    expect(f.first, '$folder/Ärger öü ß.wav');
    expect(f.second, '$folder/Zweite Datei Ä.WAV');
    expect(f.others, ['$folder/Notiz.txt', '$folder/Liesmich']);
    for (final p in [f.first, f.second]) {
      expect(String.fromCharCodes(File(p).readAsBytesSync().take(4)), 'RIFF');
    }
    // the second sine has its own frequency, so it is a track of its own
    expect(
      File(f.first).readAsBytesSync(),
      isNot(File(f.second).readAsBytesSync()),
    );
    for (final p in f.others) {
      expect(File(p).readAsStringSync(), 'no audio');
    }
  });

  test(
    '#163 pollFor: the value once it is there, null after the guard',
    () async {
      var n = 0;
      expect(
        await pollFor(
          () => ++n == 3 ? 'three' : null,
          guard: const Duration(seconds: 60),
          every: Duration.zero,
        ),
        'three',
      );
      final watch = Stopwatch()..start();
      expect(
        await pollFor<int>(
          () => null,
          guard: const Duration(milliseconds: 30),
          every: const Duration(milliseconds: 1),
        ),
        isNull,
      );
      // the guard is measured with DateTime, the watch with another clock: on Windows the two
      // differ by up to a tick of the system clock (15.6 ms), so only roughly
      expect(
        watch.elapsed,
        greaterThanOrEqualTo(const Duration(milliseconds: 10)),
      );
      expect(await pollFor(() => 1, guard: Duration.zero), 1);
    },
  );

  group('#163 smokeDrop', () {
    late TestApp a;
    late DropSmokeFiles files;
    late List<FileDragEvent> seen;
    late Timer loads;
    FileDropTarget? shown;

    setUp(() async {
      a = TestApp(Directory('${tmp.path}/lib'));
      await a.library.load();
      files = dropSmokeFiles(Directory('${tmp.path}/src'), windows: false);
      seen = [];
      shown = null;
      a.controller.dropTargetAt = (p) => p == at ? shown : null;
      loads = Timer.periodic(
        const Duration(milliseconds: 2),
        (_) => a.finishLoads(),
      );
    });
    tearDown(() => loads.cancel());

    Offset? find(FileDropTarget t) {
      shown = t;
      return at;
    }

    /// The runner's part: audio files only, reported over the window and dropped at [at] + [shift].
    Future<bool> Function(List<String>, Offset) runner({
      Offset shift = Offset.zero,
      bool hover = true,
      bool filter = true,
      bool report = true,
      List<String> Function(List<String> paths)? change,
    }) => (paths, at) async {
      final audio = [
        for (final p in paths)
          if (!filter || p.toLowerCase().endsWith('.wav')) p,
      ];
      if (audio.isEmpty) return false;
      void send(FileDragEvent e) {
        seen.add(e);
        a.files.fileDrag!(e);
      }

      if (hover) send(FileDragOver(at + shift));
      if (report) send(FileDragDrop(change?.call(audio) ?? audio, at + shift));
      return true;
    };

    Future<String?> run(
      Future<bool> Function(List<String>, Offset) drop, {
      Offset? Function(FileDropTarget t)? where,
      // long enough for an import under load; the waits that are to fail get a short one
      Duration guard = const Duration(seconds: 20),
    }) => smokeDrop(
      a.controller,
      files: files,
      seen: seen,
      find: where ?? find,
      drop: drop,
      guard: guard,
    );

    test('#163/AK1 the audio files land in the playlist they are dropped on, the other files stay out', () async {
      expect(await run(runner()), isNull);
      final list = a.library.playlists.single;
      expect(list.name, 'Drop');
      expect(
        a.library.playlistTracks(list.id).map((t) => t.title),
        DropSmokeFiles.titles,
      );
      expect(a.library.tracks, hasLength(2));
      expect(a.controller.fileDropHover.value, isNull);
    });

    test('#163 the playlist must be shown', () async {
      expect(
        await run(runner(), where: (_) => null, guard: short),
        'playlist not shown',
      );
    });

    test('#163 a refused drop fails', () async {
      expect(await run((p, o) async => false), 'drop refused');
    });

    test('#163 a drop that never reaches the app fails', () async {
      expect(
        await run(runner(report: false), guard: short),
        'no drop reported',
      );
    });

    test('#163/AK2 the paths must arrive unchanged and without the other files', () async {
      expect(
        await run(runner(filter: false)),
        'dropped [${files.first}, ${files.second}, ${files.others.join(', ')}]',
      );
      seen.clear();
      a = TestApp(Directory('${tmp.path}/lib2'));
      await a.library.load();
      a.controller.dropTargetAt = (p) => p == at ? shown : null;
      expect(
        await run(runner(change: (p) => [p[1], p[0]])),
        'dropped [${files.second}, ${files.first}]',
      );
    });

    test('#163 the drop must arrive where it was dropped', () async {
      expect(
        await run(runner(shift: const Offset(0, 1.6))),
        'dropped at ${at + const Offset(0, 1.6)}, not at $at',
      );
    });

    test('#163 within 1.5 logical pixels the position counts (rounding to device pixels)', () async {
      a.controller.dropTargetAt = (p) =>
          (p - at).distance <= 1.5 ? shown : null;
      expect(await run(runner(shift: const Offset(0, 1.5))), isNull);
    });

    test('#163 the playlist must light up under the files', () async {
      expect(await run(runner(hover: false)), 'playlist not highlighted');
    });

    test('#163 the tracks must end up in the playlist', () async {
      a.controller.dropTargetAt = (p) => null; // dropped beside the playlist
      final r = await run((paths, at) async {
        a.controller.fileDropHover.value = shown;
        return runner()(paths, at);
      }, guard: short);
      expect(r, 'playlist holds []');
    });

    test('#163 files without audio must not be taken or dropped', () async {
      var n = 0;
      expect(
        await run((paths, at) {
          n++;
          return runner(filter: n == 1)(paths, at);
        }),
        'other files taken',
      );
      n = 0;
      seen.clear();
      a = TestApp(Directory('${tmp.path}/lib3'));
      await a.library.load();
      a.controller.dropTargetAt = (p) => p == at ? shown : null;
      expect(
        await run((paths, at) async {
          n++;
          await runner(filter: n == 1)(paths, at);
          return n == 1;
        }),
        'other files dropped',
      );
    });
  });

  test('#163 the sine of the smoke test is a WAV file', () {
    final f = dropSmokeFiles(tmp, windows: false);
    final b = ByteData.sublistView(File(f.first).readAsBytesSync());
    expect(b.getUint32(24, Endian.little), 44100);
  });
}
