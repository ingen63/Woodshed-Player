// #109: the screen stays on in the web app while a track plays (Screen Wake Lock API). The logic runs
// against a fake [WakeLockApi]; the browser side (wake_lock_web.dart) is checked in test/web/ and by its
// sources. Libraries in temporary folders, never the real library.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/app/media_session.dart';
import 'package:woodshed_player/app/wake_lock.dart';

import 'fakes.dart';
import 'pwa_test.dart' show FakeMediaSession;

class FakeLock implements WakeLockHandle {
  @override
  bool released = false;
  int releases = 0;

  @override
  void release() {
    releases++;
    released = true;
  }
}

/// Records what the app asks of `navigator.wakeLock`. [grant] false: the browser refuses (or has no API
/// behind it). [hold] keeps requests open until the test completes them.
class FakeWakeLock implements WakeLockApi {
  bool grant = true;
  bool hold = false;
  final locks = <FakeLock>[];
  final open = <Completer<WakeLockHandle?>>[];
  void Function()? visible;
  int requests = 0;

  @override
  Future<WakeLockHandle?> request() {
    requests++;
    final c = Completer<WakeLockHandle?>();
    if (hold) {
      open.add(c);
    } else {
      c.complete(_answer());
    }
    return c.future;
  }

  FakeLock? _answer() {
    if (!grant) return null;
    final l = FakeLock();
    locks.add(l);
    return l;
  }

  /// Answers the oldest open request.
  void complete() => open.removeAt(0).complete(_answer());

  @override
  void onVisible(void Function() handler) => visible = handler;
}

/// A loaded track in [app], paused at 0.
Future<TestApp> loaded() async {
  final dir = Directory.systemTemp.createTempSync('wp_wake_lock');
  addTearDown(() => dir.deleteSync(recursive: true));
  final app = TestApp(Directory('${dir.path}/lib'));
  await app.library.load();
  final src = File('${dir.path}/Etude.mp3')..writeAsStringSync('audio');
  await app.library.importFiles([src.path]);
  final loading = app.controller.select(app.library.tracks.single);
  await eventually(() => app.player.isLoading, 'load started');
  app.finishLoads(30);
  expect(await loading, isTrue);
  return app;
}

/// Lets pending requests come back.
Future<void> settle() => pumpEventQueue();

WakeLockLink link(FakeWakeLock api, TestApp app) {
  final l = WakeLockLink(api, app.player);
  addTearDown(l.dispose);
  return l;
}

void main() {
  test('#109/AK1 while a track plays, the screen lock is held', () async {
    final app = await loaded();
    final api = FakeWakeLock();
    final l = link(api, app);
    await settle();
    expect(api.requests, 0, reason: 'paused: the device timeout applies');
    app.player.play();
    await settle();
    expect(api.requests, 1);
    expect(l.lock, same(api.locks.single));
    app.tick(); // ticks while playing ask for nothing new
    app.tick();
    await settle();
    expect(api.requests, 1);
    expect(api.locks.single.released, isFalse);
  });

  test(
    '#109/AK1 a link made while a track plays takes the lock at once',
    () async {
      final app = await loaded();
      app.player.play();
      final api = FakeWakeLock();
      final l = link(api, app);
      await settle();
      expect(l.lock, same(api.locks.single));
    },
  );

  group('#109/AK2 pause, stop and the end of the track release the lock', () {
    test('pause', () async {
      final app = await loaded();
      final api = FakeWakeLock();
      final l = link(api, app);
      app.player.play();
      await settle();
      app.player.pause();
      expect(api.locks.single.releases, 1);
      expect(l.lock, isNull);
      app.tick();
      expect(api.locks.single.releases, 1, reason: 'released once');
      app.player.play(); // a new lock for the next take
      await settle();
      expect(api.requests, 2);
      expect(l.lock, same(api.locks.last));
    });

    test('stop from the lock screen', () async {
      final app = await loaded();
      final api = FakeWakeLock();
      final l = link(api, app);
      final media = MediaSessionLink(FakeMediaSession(), app.controller);
      addTearDown(media.dispose);
      app.player.play();
      await settle();
      media.handle(MediaAction.stop, null);
      expect(api.locks.single.released, isTrue);
      expect(l.lock, isNull);
    });

    test('unloading the track', () async {
      final app = await loaded();
      final api = FakeWakeLock();
      final l = link(api, app);
      app.player.play();
      await settle();
      app.player.unload(); // track removed
      expect(app.player.hasTrack, isFalse);
      expect(api.locks.single.released, isTrue);
      expect(l.lock, isNull);
    });

    test('end of the track', () async {
      final app = await loaded();
      final api = FakeWakeLock();
      final l = link(api, app);
      app.player.play();
      await settle();
      app.core.playing = false; // the core reached the end
      for (var i = 0; i < 5 && app.player.isPlaying; i++) {
        app.tick();
      }
      expect(app.player.isPlaying, isFalse);
      expect(api.locks.single.released, isTrue);
      expect(l.lock, isNull);
    });

    test('paused while the request is on its way', () async {
      final app = await loaded();
      final api = FakeWakeLock()..hold = true;
      final l = link(api, app);
      app.player.play();
      app.player.pause();
      api.complete();
      await settle();
      expect(api.locks.single.released, isTrue);
      expect(l.lock, isNull);
    });

    test('dispose releases the lock', () async {
      final app = await loaded();
      final api = FakeWakeLock();
      final l = WakeLockLink(api, app.player);
      app.player.play();
      await settle();
      l.dispose();
      expect(api.locks.single.released, isTrue);
      app.player.pause();
      app.player.play();
      await settle();
      expect(api.requests, 1, reason: 'no longer listening');
    });
  });

  group('#109/AK3 back from the background the lock is requested again', () {
    test(
      'playing: a new lock after the browser released the old one',
      () async {
        final app = await loaded();
        final api = FakeWakeLock();
        final l = link(api, app);
        app.player.play();
        await settle();
        api.locks.single.released = true; // page hidden: the browser drops it
        api.visible!();
        await settle();
        expect(api.requests, 2);
        expect(l.lock, same(api.locks.last));
        expect(l.lock!.released, isFalse);
      },
    );

    test('a lock still held is kept', () async {
      final app = await loaded();
      final api = FakeWakeLock();
      link(api, app);
      app.player.play();
      await settle();
      api.visible!();
      await settle();
      expect(api.requests, 1);
    });

    test('paused: nothing is requested', () async {
      final app = await loaded();
      final api = FakeWakeLock();
      link(api, app);
      app.player.play();
      await settle();
      app.player.pause();
      api.visible!();
      await settle();
      expect(api.requests, 1);
    });

    test('a request refused while hidden is repeated once visible', () async {
      final app = await loaded();
      final api = FakeWakeLock()..hold = true;
      final l = link(api, app);
      app.player.play(); // request from the hidden page ...
      api.visible!(); // ... the page is visible before the answer
      api.grant = false;
      api.complete(); // refused: the page was hidden
      await settle();
      expect(api.requests, 2);
      api.grant = true;
      api.complete();
      await settle();
      expect(l.lock, same(api.locks.single));
      expect(api.requests, 2);
    });

    test('a request granted while visible is not repeated', () async {
      final app = await loaded();
      final api = FakeWakeLock()..hold = true;
      final l = link(api, app);
      app.player.play();
      api.visible!();
      api.complete();
      await settle();
      expect(api.requests, 1);
      expect(l.lock, same(api.locks.single));
    });
  });

  test('#109/AK4 a refused lock changes nothing in playback', () async {
    final app = await loaded();
    final api = FakeWakeLock()..grant = false;
    final l = link(api, app);
    app.player.play();
    await settle();
    expect(app.player.isPlaying, isTrue);
    expect(l.lock, isNull);
    api.visible!(); // tried again on return, still without error
    await settle();
    expect(api.requests, 2);
    app.player.pause();
    expect(app.player.isPlaying, isFalse);
  });

  group('#109 browser side', () {
    String read(String p) => File(p).readAsStringSync();

    test('AK4: without the API no link and no error', () {
      final web = read('lib/app/wake_lock_web.dart');
      expect(web, contains("@JS('navigator.wakeLock')"));
      expect(web, contains('_wakeLockOrNull == null ? null'));
      expect(web, contains("request('screen')"));
      expect(web, contains('return null;')); // refused request
      expect(
        read('lib/app/platform_web.dart'),
        contains('WebWakeLock.create() case final api?'),
      );
    });

    test('AK3: the page reports its return through visibilitychange', () {
      final web = read('lib/app/wake_lock_web.dart');
      expect(web, contains("'visibilitychange'"));
      expect(web, contains("visibilityState == 'visible'"));
    });

    test('AK5: the native apps do not use the wake lock', () {
      expect(
        read('lib/app/platform_native.dart'),
        isNot(contains('wake_lock')),
      );
      final users = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => f.readAsStringSync().contains('wake_lock'))
          .map((f) => f.path.replaceAll(r'\', '/'))
          .toList();
      expect(
        users,
        unorderedEquals([
          'lib/app/platform_web.dart',
          'lib/app/wake_lock.dart', // names the web file in its header
          'lib/app/wake_lock_web.dart',
        ]),
      );
    });

    test('AK6: README describes it', () {
      // #145: the feature table moved from README.md to docs/FUNKTIONEN.md.
      final readme = read('../docs/FUNKTIONEN.md');
      expect(readme, contains('**Bildschirm bleibt an** (#109'));
    });
  });
}
