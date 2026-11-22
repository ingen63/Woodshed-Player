// #61: rules of the app controller (app_controller.dart), one per test; found by mutation testing
// (make mutants). Libraries in temporary folders, never the real library.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/app/app_controller.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/sync/sync_service.dart';

import 'fakes.dart';

late Directory tmp;

String _src(String name) =>
    (File('${tmp.path}/source/$name')
          ..createSync(recursive: true)
          ..writeAsStringSync('audio $name'))
        .path;

/// Sync without an account that records whether it was disposed.
class _RecordingSync extends NoSync {
  var disposed = false;
  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

void main() {
  setUp(() => tmp = Directory.systemTemp.createTempSync('wp_app_rules'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<TestApp> app(
    String name, {
    SyncService Function(Library)? sync,
  }) async {
    final a = TestApp(Directory('${tmp.path}/$name'), sync: sync);
    await a.library.load();
    return a;
  }

  group('#17 messages for the UI', () {
    test('showing and clearing a message notify', () async {
      final a = await app('a');
      var n = 0;
      a.controller.addListener(() => n++);
      a.library.report(const CloudStateTooNew(3));
      expect(a.controller.message, isA<CloudStateTooNew>());
      expect(n, 1);
      a.controller.clearMessage();
      expect(a.controller.message, isNull);
      expect(n, 2);
    });
  });

  group('#37/AK5 a track whose file is on another device only', () {
    test('cannot be loaded without the cloud and says so', () async {
      final other = await app('other');
      await other.library.importFiles([_src('a.mp3')]);
      final a = await app('a');
      await a.library.mergeRemote(other.library.state);
      final t = a.library.tracks.single;
      expect(a.library.hasFile(t.id), isFalse);
      expect(await a.controller.select(t), isFalse);
      expect(a.controller.message, isA<TrackNotOnDevice>());
      expect(a.player.hasTrack, isFalse);
    });
  });

  group('#17 dispose', () {
    test('ends the sync and no longer listens to the library', () async {
      final sync = _RecordingSync();
      final a = await app('a', sync: (_) => sync);
      expect(a.controller, isA<AppController>());
      a.controller.dispose();
      expect(sync.disposed, isTrue);
      a.library.report(const CloudStateTooNew(3));
      expect(a.controller.message, isNull);
      expect(() => a.controller.addListener(() {}), throwsA(isA<Error>()));
    });
  });
}
