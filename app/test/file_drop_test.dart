// #121: files dragged in from outside onto a playlist or folder. Library in a temporary folder, the core
// as a fake; never the real library.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/app/app_controller.dart';
import 'package:woodshed_player/app/file_drop.dart';
import 'package:woodshed_player/app/file_platform.dart';
import 'package:woodshed_player/library/library.dart';

import 'fakes.dart';

late Directory tmp;

/// A source file with its own contents (the same text gives the same track, #36).
String src(String name, [String? contents]) =>
    (File('${tmp.path}/src/$name')
          ..createSync(recursive: true)
          ..writeAsStringSync(contents ?? 'audio $name'))
        .path;

void main() {
  setUp(() => tmp = Directory.systemTemp.createTempSync('wp_file_drop'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<TestApp> app() async {
    final a = TestApp(Directory('${tmp.path}/lib'));
    await a.library.load();
    return a;
  }

  /// Runs [work], finishing the load of the first track it may start.
  Future<T> settle<T>(TestApp a, Future<T> work) async {
    T? result;
    var done = false;
    work.then((r) {
      result = r;
      done = true;
    });
    await eventually(() {
      a.finishLoads();
      return done;
    }, 'drop finished');
    return result as T;
  }

  Future<ImportResult> drop(
    TestApp a,
    List<String> paths,
    FileDropTarget? target,
  ) => settle(a, a.controller.dropFiles(paths, target));

  List<String> titles(TestApp a, String playlistId) => [
    for (final t in a.library.playlistTracks(playlistId)) t.title,
  ];

  Future<String> add(TestApp a, String name, {String? folderId}) async =>
      (await settle(
        a,
        a.controller.importFiles([src(name)], folderId: folderId),
      )).tracks.single.id;

  int storedFiles() =>
      Directory('${tmp.path}/lib/Tracks')
          .listSync()
          .where((f) => !f.path.endsWith('.jpg'))
          .length;

  group('#121 files dropped on a playlist', () {
    test('#121/AK1 dropped files are in the library and in the playlist where they were dropped, in their order', () async {
      final a = await app();
      final x = await add(a, 'x.mp3');
      final y = await add(a, 'y.mp3');
      final p = a.library.createPlaylist('Band');
      a.library.addToPlaylist(p.id, [x, y]);

      final r = await drop(a, [
        src('c.mp3'),
        src('a.mp3'),
        src('b.mp3'),
      ], PlaylistDropTarget(p.id, 1));
      expect(r.tracks.map((t) => t.title), ['c', 'a', 'b']);
      expect(a.library.tracks, hasLength(5));
      expect(titles(a, p.id), ['x', 'c', 'a', 'b', 'y']);

      await drop(a, [src('d.mp3')], PlaylistDropTarget(p.id));
      expect(titles(a, p.id), ['x', 'c', 'a', 'b', 'y', 'd']);
      await drop(a, [src('e.mp3')], PlaylistDropTarget(p.id, 0));
      expect(titles(a, p.id).first, 'e');
    });

    test('#121/AK2 a track already in the library is not stored again; the present one goes into the playlist', () async {
      final a = await app();
      final x = await add(a, 'x.mp3');
      final p = a.library.createPlaylist('Band');
      expect(storedFiles(), 1);

      final r = await drop(a, [
        src('copy of x.mp3', 'audio x.mp3'),
        src('n.mp3'),
      ], PlaylistDropTarget(p.id));
      expect(r.duplicates.single.id, x);
      expect(r.tracks.map((t) => t.id).first, x);
      expect(a.library.tracks, hasLength(2));
      expect(storedFiles(), 2);
      expect(titles(a, p.id), ['x', 'n']);
      expect(a.library.playlist(p.id)!.entries.first, x);
    });

    test('#121/AK5 broken files are reported as in a normal import; the others still go into the playlist', () async {
      final a = await app();
      final p = a.library.createPlaylist('Band');
      final r = await drop(a, [
        src('a.mp3'),
        '${tmp.path}/src/missing.mp3',
        src('b.mp3'),
      ], PlaylistDropTarget(p.id));
      expect(r.failed, ['missing.mp3']);
      expect((a.controller.message! as ImportFailed).files, ['missing.mp3']);
      expect(titles(a, p.id), ['a', 'b']);
    });
  });

  group('#121 files dropped on a folder', () {
    test('#121/AK3 dropped files land in the folder, tracks already present move there', () async {
      final a = await app();
      final f = a.library.createFolder('Etüden');
      final g = a.library.createFolder('Songs');
      final x = await add(a, 'x.mp3', folderId: g.id);
      final r = await drop(a, [
        src('a.mp3'),
        src('copy of x.mp3', 'audio x.mp3'),
      ], FolderDropTarget(f.id));
      expect(r.imported.single.folderId, f.id);
      expect(a.library.track(x)!.folderId, f.id);
      expect(a.library.sortedTracksIn(f.id).map((t) => t.title), ['a', 'x']);
      expect(a.library.sortedTracksIn(g.id), isEmpty);

      await drop(a, [src('b.mp3')], const FolderDropTarget(null));
      expect(a.library.sortedTracksIn(null).single.title, 'b');
      expect(a.library.playlists, isEmpty);
    });

    test('#121 without a target the files only come into the library; tracks present stay where they are (#22)', () async {
      final a = await app();
      final g = a.library.createFolder('Songs');
      final x = await add(a, 'x.mp3', folderId: g.id);
      final r = await drop(a, [
        src('a.mp3'),
        src('copy of x.mp3', 'audio x.mp3'),
      ], null);
      expect(r.imported.single.folderId, isNull);
      expect(a.library.track(x)!.folderId, g.id);
    });
  });

  group('#121 dragging over the window', () {
    test('#121/AK4 the target under the files is highlighted while they hover, and gets them when dropped', () async {
      final a = await app();
      final p = a.library.createPlaylist('Band');
      final asked = <Offset>[];
      a.controller.dropTargetAt = (o) {
        asked.add(o);
        return o.dy < 100 ? PlaylistDropTarget(p.id) : null;
      };
      final drag = a.files.fileDrag!;
      expect(a.controller.fileDropHover.value, isNull);

      drag(const FileDragOver(Offset(5, 50)));
      expect(a.controller.fileDropHover.value, PlaylistDropTarget(p.id));
      drag(const FileDragOver(Offset(5, 150)));
      expect(a.controller.fileDropHover.value, isNull);
      drag(const FileDragOver(Offset(5, 60)));
      drag(const FileDragLeave());
      expect(a.controller.fileDropHover.value, isNull);

      drag(const FileDragOver(Offset(5, 70)));
      drag(FileDragDrop([src('a.mp3')], const Offset(5, 80)));
      expect(a.controller.fileDropHover.value, isNull);
      expect(asked.last, const Offset(5, 80));
      await eventually(() {
        a.finishLoads();
        return titles(a, p.id).isNotEmpty;
      }, 'in the playlist');
      expect(titles(a, p.id), ['a']);

      drag(FileDragDrop([src('b.mp3')]));
      await eventually(() {
        a.finishLoads();
        return a.library.tracks.length == 2;
      }, 'in the library');
      expect(asked.last, const Offset(5, 80));
      expect(titles(a, p.id), ['a']);
    });

    test(
      '#121 the window starts without a target and frees the hover when closed',
      () async {
        final a = TestApp(Directory('${tmp.path}/lib2'));
        expect(a.controller.dropTargetAt(Offset.zero), isNull);
        final c = AppController(
          library: a.library,
          player: a.player,
          metronome: a.controller.metronome,
          files: a.files,
        );
        expect(a.files.fileDrag, isNotNull);
        c.dispose();
        expect(a.files.fileDrag, isNull);
        expect(() => c.fileDropHover.addListener(() {}), throwsStateError);
      },
    );

    test('#121 messages of the native part become drag events', () {
      expect(
        fileDragEvent(const MethodCall('dragFiles', {'x': 3, 'y': 4.5})),
        isA<FileDragOver>().having(
          (e) => e.position,
          'position',
          const Offset(3, 4.5),
        ),
      );
      expect(fileDragEvent(const MethodCall('dragFiles')), isNull);
      expect(fileDragEvent(const MethodCall('dragFiles', {'x': 3})), isNull);
      expect(
        fileDragEvent(const MethodCall('dragFiles', {'x': 'a', 'y': 1})),
        isNull,
      );
      expect(fileDragEvent(const MethodCall('dragExit')), isA<FileDragLeave>());
      final dropped =
          fileDragEvent(
                const MethodCall('dropFiles', {
                  'paths': ['a.mp3', 'b.wav'],
                  'x': 1,
                  'y': 2,
                }),
              )!
              as FileDragDrop;
      expect(dropped.paths, ['a.mp3', 'b.wav']);
      expect(dropped.position, const Offset(1, 2));
      final plain =
          fileDragEvent(const MethodCall('dropFiles', ['a.mp3', 3]))!
              as FileDragDrop;
      expect(plain.paths, ['a.mp3']);
      expect(plain.position, isNull);
      final unplaced =
          fileDragEvent(
                const MethodCall('dropFiles', {
                  'paths': ['a.mp3'],
                }),
              )!
              as FileDragDrop;
      expect(unplaced.position, isNull);
      expect(fileDragEvent(const MethodCall('dropFiles', 'a.mp3')), isNull);
      expect(fileDragEvent(const MethodCall('showAbout')), isNull);
    });

    test('#121 drop targets are equal when they are the same place', () {
      expect(
        const PlaylistDropTarget('p', 1),
        const PlaylistDropTarget('p', 1),
      );
      expect(
        const PlaylistDropTarget('p', 1).hashCode,
        const PlaylistDropTarget('p', 1).hashCode,
      );
      expect(
        const PlaylistDropTarget('p', 1) == const PlaylistDropTarget('p', 2),
        isFalse,
      );
      expect(
        const PlaylistDropTarget('p') == const PlaylistDropTarget('q'),
        isFalse,
      );
      expect(const FolderDropTarget('f'), const FolderDropTarget('f'));
      expect(
        const FolderDropTarget('f').hashCode,
        const FolderDropTarget('f').hashCode,
      );
      expect(
        const FolderDropTarget('f') == const FolderDropTarget(null),
        isFalse,
      );
      expect(
        const FolderDropTarget('p') == const PlaylistDropTarget('p'),
        isFalse,
      );
      expect(
        const PlaylistDropTarget('p') == const FolderDropTarget('p'),
        isFalse,
      );
    });
  });
}
