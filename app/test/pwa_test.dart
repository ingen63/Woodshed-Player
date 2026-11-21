// #39: PWA and phone use. Offline start (manifest, service worker, build stamp), Media Session, the audio
// cache with its limit and «Keep offline», tracks only in the cloud, no recording button and the hint «Add to
// Home Screen». Cloud tests run against the InMemoryProvider (#37), libraries in memory or temporary
// folders, never a real account or the real library.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/app/install_hint.dart';
import 'package:woodshed_player/app/media_session.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/sync/in_memory_provider.dart';
import 'package:woodshed_player/sync/sync_engine.dart';
import 'package:woodshed_player/ui/home_page.dart';
import 'package:woodshed_player/ui/library_view.dart';
import 'package:woodshed_player/ui/style.dart';

import '../tool/stamp_sw.dart' as stamp;
import 'fakes.dart';
import 'home_page_test.dart' show phone, pumpApp;

String read(String path) => File(path).readAsStringSync();

Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

var clock = DateTime.utc(2026, 11, 1);

/// Library in memory whose files go to [cloud] (no eager download, as in the browser).
class WebDevice {
  WebDevice(this.cloud, {this.limit = 100}) {
    library = Library(
      store,
      probe: (_) => 2.5,
      readSource: (s) async => sources[s],
      now: () => clock,
      saveDelay: Duration.zero,
      random: Random(7),
    );
    sync = CloudSync(
      cloud,
      library,
      eagerDownload: false,
      now: () => clock,
      changeDelay: const Duration(days: 1), // syncs only when the test asks
    );
  }

  final InMemoryProvider cloud;
  final store = MemoryFileStore();
  final sources = <String, Uint8List>{};
  late final Library library;
  late final CloudSync sync;
  final int limit;

  Future<void> load() async {
    await library.load();
    await library.setCacheLimit(limit);
  }

  /// Imports a track of [size] bytes, one second after the previous one.
  Future<Track> add(String name, int size) async {
    clock = clock.add(const Duration(seconds: 1));
    sources[name] = Uint8List.fromList(
      utf8.encode(name.padRight(size, '.')).sublist(0, size),
    );
    return (await library.importFiles([name])).imported.single;
  }

  bool here(Track t) => library.hasFile(t.id);
}

Future<WebDevice> webDevice(InMemoryProvider cloud, {int limit = 100}) async {
  final d = WebDevice(cloud, limit: limit);
  await d.load();
  addTearDown(d.sync.dispose);
  return d;
}

/// Records what the app sends to `navigator.mediaSession`.
class FakeMediaSession implements MediaSessionApi {
  final handlers = <String, void Function(double?)>{};
  (String?, String?)? metadata;
  String? state;
  final positions = <(double, double, double)>[];

  @override
  void setActionHandler(String action, void Function(double? time) handler) =>
      handlers[action] = handler;
  @override
  void setMetadata(String? title, String? artist) => metadata = (title, artist);
  @override
  void setPlaybackState(String state) => this.state = state;
  @override
  void setPositionState(double duration, double position, double rate) =>
      positions.add((duration, position, rate));
}

void main() {
  setUp(() => clock = DateTime.utc(2026, 11, 1));

  group('#39/AK1 manifest, icons and service worker (offline start)', () {
    test('the manifest makes the app installable from /app/', () {
      final m = jsonDecode(read('web/manifest.json')) as Map;
      expect(m['display'], 'standalone');
      expect(
        m['start_url'],
        '.',
      ); // relative: works under /Woodshed-Player/app/
      expect(m['name'], 'Woodshed Player');
      final icons = (m['icons'] as List).cast<Map<String, Object?>>();
      expect(icons.map((i) => i['sizes']), containsAll(['192x192', '512x512']));
      expect(icons.where((i) => i['purpose'] == 'maskable'), isNotEmpty);
      for (final i in icons) {
        expect(
          File('web/${i['src']}').existsSync(),
          isTrue,
          reason: '${i['src']}',
        );
      }
      final index = read('web/index.html');
      expect(index, contains('<link rel="manifest" href="manifest.json">'));
      expect(index, contains('rel="apple-touch-icon"'));
    });

    test(
      'there is one service worker, it caches the shell and drops old caches',
      () {
        final sw = read('web/sw.js');
        // still the worker of #41 (COOP/COEP), no second one
        expect(sw, contains("'Cross-Origin-Embedder-Policy', 'require-corp'"));
        expect(
          Directory('web')
              .listSync()
              .whereType<File>()
              .where((f) => f.path.contains('sw'))
              .length,
          1,
        );
        expect(sw, contains(stamp.marker));
        expect(sw, contains("addEventListener('install'"));
        expect(sw, contains('cache.put('));
        // activate: caches of other versions go
        expect(sw, contains('caches.delete(name)'));
        // offline: the cache answers when the network fails
        expect(
          sw,
          matches(RegExp(r'catch \(err\) \{\s*const hit = await cache\.match')),
        );
      },
    );

    test('the build stamp lists the shell without symbols, maps and renderer variants', () {
      final files = stamp.shellFiles([
        'index.html',
        'main.dart.js',
        'flutter_bootstrap.js',
        'sw.js',
        'flutter_service_worker.js',
        'flutter.js.map',
        'canvaskit/canvaskit.wasm',
        'canvaskit/chromium/canvaskit.js',
        'canvaskit/canvaskit.js.symbols',
        'wp_core/wp_core_web.wasm',
        'assets/NOTICES',
        'icons/Icon-192.png',
        'manifest.json',
        '.last_build_id',
      ]);
      expect(files, [
        'assets/NOTICES',
        'flutter_bootstrap.js',
        'icons/Icon-192.png',
        'index.html',
        'main.dart.js',
        'manifest.json',
        'wp_core/wp_core_web.wasm',
      ]);
    });

    test(
      'a new build gets a new version; the stamp replaces the marked line',
      () {
        final a = {
          'index.html': utf8.encode('a'),
          'main.dart.js': utf8.encode('1'),
        };
        final b = {
          'index.html': utf8.encode('a'),
          'main.dart.js': utf8.encode('2'),
        };
        expect(stamp.buildVersion(a), hasLength(16));
        expect(stamp.buildVersion(a), stamp.buildVersion({...a}));
        expect(stamp.buildVersion(a), isNot(stamp.buildVersion(b)));
        final out = stamp.stamp(read('web/sw.js'), 'abc', ['index.html'])!;
        expect(
          out,
          contains(
            'const SHELL = {"version":"abc","files":["index.html"]}; // @shell',
          ),
        );
        expect(out, isNot(contains("version: 'dev'")));
        expect(stamp.stamp('// no marker', 'abc', []), isNull);
      },
    );

    test('Makefile and the Pages workflow stamp the build', () {
      expect(
        read('../Makefile'),
        contains('dart run tool/stamp_sw.dart build/web'),
      );
      final pages = read('../.github/workflows/pages.yml');
      final build = pages.indexOf('flutter build web');
      final st = pages.indexOf('tool/stamp_sw.dart build/web');
      expect(build, greaterThan(0));
      expect(st, greaterThan(build));
    });
  });

  group('#39/AK2 Media Session', () {
    test(
      'title, state and position follow the player; the handlers control it',
      () async {
        final dir = Directory.systemTemp.createTempSync('wp_media_session');
        addTearDown(() => dir.deleteSync(recursive: true));
        final app = TestApp(Directory('${dir.path}/lib'));
        await app.library.load();
        final src = File('${dir.path}/Etude.mp3')..writeAsStringSync('audio');
        await app.library.importFiles([src.path]);
        final api = FakeMediaSession();
        final link = MediaSessionLink(api, app.controller);
        addTearDown(link.dispose);
        expect(
          api.handlers.keys,
          containsAll([
            'play',
            'pause',
            'seekto',
            'seekbackward',
            'seekforward',
          ]),
        );
        expect(api.state, 'none');
        expect(api.metadata, (null, null));

        final loading = app.controller.select(app.library.tracks.single);
        await eventually(() => app.player.isLoading, 'load started');
        app.finishLoads(30);
        expect(await loading, isTrue);
        expect(api.metadata!.$1, 'Etude');
        expect(api.state, 'paused');

        api.handlers['play']!(null); // lock screen / headphone button
        expect(app.player.isPlaying, isTrue);
        app.tick();
        expect(api.state, 'playing');
        expect(api.positions.last.$1, 30);

        api.handlers['seekto']!(12.5);
        app.tick();
        expect(app.player.position, closeTo(12.5, 0.01));
        expect(api.positions.last.$2, closeTo(12.5, 0.01));

        api.handlers['seekforward']!(null);
        expect(
          app.player.position,
          closeTo(12.5 + MediaSessionLink.skipSeconds, 0.01),
        );
        api.handlers['seekbackward']!(null);
        expect(app.player.position, closeTo(12.5, 0.01));

        api.handlers['pause']!(null);
        app.tick();
        expect(app.player.isPlaying, isFalse);
        expect(api.state, 'paused');

        // the metronome stops when the title starts (#3/AK20), also from the lock screen
        app.controller.metronome.start();
        api.handlers['play']!(null);
        expect(app.controller.metronome.running, isFalse);
      },
    );

    test('without a track the buttons do nothing', () async {
      final dir = Directory.systemTemp.createTempSync('wp_media_session');
      addTearDown(() => dir.deleteSync(recursive: true));
      final app = TestApp(Directory('${dir.path}/lib'));
      await app.library.load();
      final api = FakeMediaSession();
      MediaSessionLink(api, app.controller);
      api.handlers['play']!(null);
      expect(app.player.isPlaying, isFalse);
    });

    test(
      'the position is sent again only for a new state, tempo or a jump',
      () async {
        final dir = Directory.systemTemp.createTempSync('wp_media_session');
        addTearDown(() => dir.deleteSync(recursive: true));
        final app = TestApp(Directory('${dir.path}/lib'));
        await app.library.load();
        final src = File('${dir.path}/Etude.mp3')..writeAsStringSync('audio');
        await app.library.importFiles([src.path]);
        final api = FakeMediaSession();
        final link = MediaSessionLink(api, app.controller);
        addTearDown(link.dispose);
        final loading = app.controller.select(app.library.tracks.single);
        await eventually(() => app.player.isLoading, 'load started');
        app.finishLoads(30);
        await loading;
        api.handlers['seekto']!(10);
        app.tick();
        final paused = api.positions.length;
        api.handlers['play']!(null);
        app.tick();
        final sent = api.positions.length;
        expect(sent, paused + 1, reason: 'play: the system moves it on now');

        // playback moves the position on by itself: nothing to send
        app.core.pos = 10.5;
        app.tick();
        app.core.pos = 11.5; // exactly 1 s since the last tick
        app.tick();
        expect(api.positions.length, sent, reason: 'normal playback');

        app.core.pos = 20; // a jump (loop, seek in the core)
        app.tick();
        expect(api.positions.length, sent + 1);
        expect(api.positions.last.$2, 20);

        app.player.setSpeedEnabled(true);
        app.player.setSpeed(0.5);
        app.tick();
        expect(api.positions.last.$3, 0.5);
      },
    );

    test('title changes in the library reach the lock screen', () async {
      final dir = Directory.systemTemp.createTempSync('wp_media_session');
      addTearDown(() => dir.deleteSync(recursive: true));
      final app = TestApp(Directory('${dir.path}/lib'));
      await app.library.load();
      final src = File('${dir.path}/Etude.mp3')..writeAsStringSync('audio');
      await app.library.importFiles([src.path]);
      final api = FakeMediaSession();
      final link = MediaSessionLink(api, app.controller);
      final t = app.library.tracks.single;
      final loading = app.controller.select(t);
      await eventually(() => app.player.isLoading, 'load started');
      app.finishLoads(30);
      await loading;
      app.library.editMetadata(t.id, title: 'Etude Nr. 2', artist: 'Band');
      expect(api.metadata, ('Etude Nr. 2', 'Band'));

      link.dispose();
      app.library.editMetadata(t.id, title: 'Etude Nr. 3');
      api.handlers['play']!(null); // a handler still runs; updates stop
      app.tick();
      expect(api.metadata, ('Etude Nr. 2', 'Band'));
      expect(api.state, 'paused');
    });

    test('a track without a duration sends no position', () async {
      final dir = Directory.systemTemp.createTempSync('wp_media_session');
      addTearDown(() => dir.deleteSync(recursive: true));
      final app = TestApp(Directory('${dir.path}/lib'), duration: null);
      await app.library.load();
      final src = File('${dir.path}/Etude.mp3')..writeAsStringSync('audio');
      await app.library.importFiles([src.path]);
      final api = FakeMediaSession();
      MediaSessionLink(api, app.controller);
      final loading = app.controller.select(app.library.tracks.single);
      await eventually(() => app.player.isLoading, 'load started');
      app.finishLoads(0);
      await loading;
      expect(app.player.hasTrack, isTrue);
      expect(api.state, 'paused');
      expect(api.positions, isEmpty);
    });

    test('the web app connects it', () {
      final web = read('lib/app/platform_web.dart');
      expect(web, contains('MediaSessionLink(api, controller)'));
      expect(
        read('lib/app/media_session_web.dart'),
        contains('navigator.mediaSession'),
      );
    });
  });

  group('#39/AK3 cache limit, oldest first, «Keep offline»', () {
    test('the default is 2 GB and the limit is device-local', () async {
      final store = MemoryFileStore();
      final lib = Library(
        store,
        probe: (_) => 1,
        readSource: (_) async => null,
        saveDelay: Duration.zero,
      );
      await lib.load();
      expect(lib.cacheLimit, 2000000000);
      await lib.setCacheLimit(5000000000);
      await lib.save();
      final device =
          jsonDecode(utf8.decode(store.files['device.json']!)) as Map;
      expect(device['cacheLimit'], 5000000000);
      expect(
        utf8.decode(store.files['library.json']!),
        isNot(contains('cacheLimit')),
      );
      expect(lib.state.settings.values.keys, isNot(contains('cacheLimit')));
      final again = Library(
        store,
        probe: (_) => 1,
        readSource: (_) async => null,
      );
      await again.load();
      expect(again.cacheLimit, 5000000000);
    });

    test(
      'above the limit the oldest tracks in the cloud lose their file first',
      () async {
        final cloud = InMemoryProvider();
        final d = await webDevice(cloud, limit: 100);
        final a = await d.add('a', 40);
        final b = await d.add('b', 40);
        final c = await d.add('c', 40); // 120 bytes > 100
        await d.sync.syncNow(); // uploads, then trims
        expect(d.here(a), isFalse);
        expect(d.here(b), isTrue);
        expect(d.here(c), isTrue);
        expect(await d.library.cacheSize(), 80);
        // the track stays in the library and in the cloud
        expect(d.library.track(a.id), isNotNull);
        expect(cloud.files.keys, contains(Library.cloudAudioName(a)));
      },
    );

    test(
      'played tracks count as new; «Keep offline» and the loaded track stay',
      () async {
        final cloud = InMemoryProvider();
        final d = await webDevice(cloud, limit: 100);
        final a = await d.add('a', 30);
        final b = await d.add('b', 30);
        final c = await d.add('c', 30);
        await d.sync.syncNow();
        clock = clock.add(const Duration(minutes: 1));
        await d.library.markUsed(a.id); // a is now the newest
        await d.library.setKeepOffline({b.id}, true);
        d.library.inUse = c.id;
        await d.add(
          'e',
          30,
        ); // 120 > 100, but b and c are protected, a was played
        await d.sync.syncNow();
        expect(d.here(a), isFalse, reason: 'only a may go');
        expect(d.here(b), isTrue);
        expect(d.here(c), isTrue);
        expect(d.library.keptOffline(b.id), isTrue);
        final device =
            jsonDecode(utf8.decode(d.store.files['device.json']!)) as Map;
        expect(device['keepOffline'], [b.id]);
      },
    );

    test('a file not yet in the cloud is never removed', () async {
      final cloud = InMemoryProvider()..offline = true;
      final d = await webDevice(cloud, limit: 10);
      final a = await d.add('a', 40);
      await d.library.trimCache(inCloud: d.sync.inCloud);
      expect(d.here(a), isTrue);
      final b = await d.add('b', 40);
      d.library.setNoUpload({b.id}, true);
      cloud.offline = false;
      await d.sync.syncNow();
      expect(d.here(b), isTrue, reason: '«Don\'t upload»: never in the cloud');
    });

    test('a removed track survives a restart and loads again', () async {
      final cloud = InMemoryProvider();
      final d = await webDevice(cloud, limit: 50);
      final a = await d.add('a', 40);
      await d.add('b', 40);
      await d.sync.syncNow();
      expect(d.here(a), isFalse);
      final again = Library(
        d.store,
        probe: (_) => 1,
        readSource: (_) async => null,
        now: () => clock,
      );
      await again.load();
      expect(again.track(a.id), isNotNull);
      expect(again.hasFile(a.id), isFalse);
      expect(again.droppedMissing, 0);
    });

    test('desktop (eager download) keeps every file', () async {
      final cloud = InMemoryProvider();
      final store = MemoryFileStore();
      final sources = {'a': bytes('a' * 40), 'b': bytes('b' * 40)};
      final lib = Library(
        store,
        probe: (_) => 1,
        readSource: (s) async => sources[s],
        saveDelay: Duration.zero,
      );
      await lib.load();
      await lib.setCacheLimit(10);
      final sync = CloudSync(cloud, lib, changeDelay: const Duration(days: 1));
      addTearDown(sync.dispose);
      await lib.importFiles(['a', 'b']);
      await sync.syncNow();
      expect(lib.tracks.every((t) => lib.hasFile(t.id)), isTrue);
    });

    test(
      'device.json with an unusable limit or entry keeps the rest',
      () async {
        Future<Library> loaded(Map<String, Object?> device) async {
          final store = MemoryFileStore()
            ..files['device.json'] = bytes(jsonEncode(device));
          final lib = Library(
            store,
            probe: (_) => 1,
            readSource: (_) async => null,
          );
          await lib.load();
          return lib;
        }

        const id = '0123456789abcdef';
        expect(
          (await loaded({'deviceId': id, 'cacheLimit': 0})).cacheLimit,
          2000000000,
        );
        final lib = await loaded({
          'deviceId': id,
          'cacheLimit': 5000000000,
          'lastUsed': {'a': 'yesterday', 'b': 5},
        });
        expect(lib.cacheLimit, 5000000000, reason: 'a bad entry is skipped');
      },
    );

    test('a limit below 1 byte is ignored', () async {
      final d = await webDevice(InMemoryProvider(), limit: 100);
      await d.library.setCacheLimit(0);
      expect(d.library.cacheLimit, 100);
      await d.library.setCacheLimit(-5);
      expect(d.library.cacheLimit, 100);
      await d.library.setCacheLimit(1);
      expect(d.library.cacheLimit, 1);
    });

    test('exactly at the limit nothing more is removed', () async {
      final cloud = InMemoryProvider();
      final d = await webDevice(cloud, limit: 100);
      final a = await d.add('a', 50);
      final b = await d.add('b', 50);
      await d.sync.syncNow();
      expect(d.here(a) && d.here(b), isTrue, reason: '100 bytes fit');
      final c = await d.add('c', 50);
      await d.sync.syncNow();
      expect(d.here(a), isFalse);
      expect(d.here(b), isTrue, reason: 'back at 100 bytes after one');
      expect(d.here(c), isTrue);
    });

    test('«Keep offline» updates the list at once', () async {
      final d = await webDevice(InMemoryProvider());
      final a = await d.add('a', 10);
      var heard = 0;
      d.library.addListener(() => heard++);
      await d.library.setKeepOffline({a.id}, true);
      expect(heard, 1);
      await d.library.setKeepOffline({a.id}, true); // no change
      expect(heard, 1);
    });

    test(
      'removing files updates the list, also without a storage figure',
      () async {
        final cloud = InMemoryProvider();
        final store = _NoStorageInfo();
        final sources = {'a': bytes('a' * 40), 'b': bytes('b' * 40)};
        final lib = Library(
          store,
          probe: (_) => 1,
          readSource: (s) async => sources[s],
          now: () => clock,
          saveDelay: Duration.zero,
        );
        await lib.load();
        final sync = CloudSync(
          cloud,
          lib,
          eagerDownload: false,
          changeDelay: const Duration(days: 1),
        );
        addTearDown(sync.dispose);
        await lib.importFiles(['a', 'b']);
        lib.inUse = null;
        await sync.syncNow(); // uploads; 80 bytes are below the default limit
        await lib.setCacheLimit(50);
        var heard = 0;
        lib.addListener(() => heard++);
        expect(await lib.trimCache(inCloud: sync.inCloud), hasLength(1));
        expect(heard, greaterThan(0));
      },
    );

    test('the storage figure is measured again after removing', () async {
      final cloud = InMemoryProvider();
      final d = await webDevice(cloud, limit: 1000);
      await d.add('a', 40);
      await d.add('b', 40);
      d.library.inUse = null;
      await d.sync.syncNow();
      await d.library.setCacheLimit(50);
      expect(await d.library.trimCache(inCloud: d.sync.inCloud), hasLength(1));
      final now = (await d.store.storageInfo()).used;
      expect(d.library.storage!.used, now);
    });

    test('deleting a track forgets it in device.json', () async {
      final d = await webDevice(InMemoryProvider());
      final a = await d.add('a', 10);
      final b = await d.add('b', 10);
      await d.library.setKeepOffline({a.id, b.id}, true);
      await d.library.markUsed(a.id);
      d.library.delete({a.id});
      await eventually(() {
        final device =
            jsonDecode(utf8.decode(d.store.files['device.json']!)) as Map;
        return !jsonEncode(device).contains(a.id);
      }, 'a forgotten');
      expect(d.library.keptOffline(a.id), isFalse);
      expect(d.library.keptOffline(b.id), isTrue);
    });

    testWidgets(
      'the storage line opens the limit; «Keep offline» in the track menu',
      (tester) async {
        final dir = Directory.systemTemp.createTempSync('wp_cache_ui');
        addTearDown(() => dir.deleteSync(recursive: true));
        final app = TestApp(Directory('${dir.path}/lib'));
        await tester.runAsync(() async {
          await app.library.load();
          final src = File('${dir.path}/Etude.mp3')..writeAsStringSync('audio');
          await app.library.importFiles([src.path]);
        });
        await tester.pumpWidget(
          MaterialApp(
            locale: testLocale,
            localizationsDelegates: testDelegates,
            supportedLocales: testLocales,
            theme: woodshedTheme(Brightness.light),
            home: Scaffold(
              body: LibraryView(
                controller: app.controller,
                cacheControls: true,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.textContaining('Grenze 2,0 GB'), findsOneWidget);
        await tester.tap(find.byKey(const Key('storageLine')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('cacheLimitDialog')), findsOneWidget);
        expect(find.text('Offline-Speicher für Audio'), findsOneWidget);
        await tester.tap(find.byKey(const Key('cacheLimit:5000000000')));
        await tester.pumpAndSettle();
        expect(app.library.cacheLimit, 5000000000);
        expect(find.textContaining('Grenze 5,0 GB'), findsOneWidget);

        await tester.tap(find.byKey(const Key('menu:Etude')));
        await tester.pumpAndSettle();
        expect(find.text('Offline halten'), findsOneWidget);
        await tester.tap(find.byKey(const Key('keepOffline')).first);
        await tester.pumpAndSettle();
        expect(app.library.keptOffline(app.library.tracks.single.id), isTrue);
      },
    );

    testWidgets('desktop and mobile: no limit, no «Keep offline»', (
      tester,
    ) async {
      await pumpApp(tester);
      expect(find.textContaining('Grenze'), findsNothing);
      await tester.tap(find.byKey(const Key('menu:Bossa')));
      await tester.pumpAndSettle();
      expect(find.text('Offline halten'), findsNothing);
    });
  });

  group('#39/AK4 tracks only in the cloud', () {
    test('a removed track is loaded from the cloud when played', () async {
      final cloud = InMemoryProvider();
      final d = await webDevice(cloud, limit: 50);
      final a = await d.add('a', 40);
      await d.add('b', 40);
      await d.sync.syncNow();
      expect(d.here(a), isFalse);
      expect(d.sync.inCloud(a.id), isTrue);
      final gets = cloud.countOf('get ${Library.cloudAudioName(a)}');
      expect(await d.sync.fetchAudio(a), isTrue);
      expect(cloud.countOf('get ${Library.cloudAudioName(a)}'), gets + 1);
      expect(d.here(a), isTrue);
      final device =
          jsonDecode(utf8.decode(d.store.files['device.json']!)) as Map;
      expect((device['evicted'] as List?) ?? [], isNot(contains(a.id)));
    });

    testWidgets('the row says «Nur in der Cloud»; tapping loads and plays it', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('wp_only_cloud');
      addTearDown(() => dir.deleteSync(recursive: true));
      final cloud = InMemoryProvider();
      late CloudSync sync;
      final app = TestApp(
        Directory('${dir.path}/lib'),
        sync: (l) => sync = CloudSync(
          cloud,
          l,
          eagerDownload: false,
          changeDelay: const Duration(days: 1),
        ),
      );
      addTearDown(sync.dispose);
      tester.view.physicalSize = phone;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late Track a;
      await tester.runAsync(() async {
        await app.library.load();
        await app.library.setCacheLimit(10);
        final src = File('${dir.path}/Etude.mp3')
          ..writeAsStringSync('audio etude');
        a = (await app.library.importFiles([src.path])).imported.single;
        app.library.inUse = null;
        await sync.syncNow();
      });
      expect(app.library.hasFile(a.id), isFalse);
      await tester.pumpWidget(
        MaterialApp(
          locale: testLocale,
          localizationsDelegates: testDelegates,
          supportedLocales: testLocales,
          theme: woodshedTheme(Brightness.light),
          home: Scaffold(
            body: LibraryView(controller: app.controller, cacheControls: true),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('onlyInCloud:Etude')), findsOneWidget);
      expect(find.text('Nur in der Cloud'), findsOneWidget);
      expect(find.byKey(const Key('onlyElsewhere:Etude')), findsNothing);
      await tester.tap(find.byKey(const Key('track:Etude')));
      await waitUntil(
        tester,
        () => app.library.hasFile(a.id),
        'file loaded from the cloud',
      );
      await tester.pump();
      expect(find.byKey(const Key('onlyInCloud:Etude')), findsNothing);
      expect(app.controller.fetching, isNull);
      expect(app.core.loadState, isNot(0));
    });
  });

  group('#39/AK5 no recording button in the browser', () {
    test('the web platform never creates one', () {
      final web = read('lib/app/platform_web.dart');
      expect(
        web,
        contains(
          'Widget? recordingButtonFor(AppController controller) => null;',
        ),
      );
      expect(web, isNot(contains('recording_button.dart')));
    });

    testWidgets('without a button the phone and desktop layouts show none', (
      tester,
    ) async {
      await pumpApp(tester, size: phone);
      expect(find.byTooltip(de.recordingTooltip), findsNothing);
      await pumpApp(tester);
      expect(find.byTooltip(de.recordingTooltip), findsNothing);
    });
  });

  group('#39/AK6 hint «Add to Home Screen» on iOS', () {
    const iphone =
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1';
    const ipad =
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15';
    const android =
        'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36';

    test('iPhone and iPad in the browser, not when installed or elsewhere', () {
      expect(
        wantsInstallHint(
          userAgent: iphone,
          maxTouchPoints: 5,
          standalone: false,
        ),
        isTrue,
      );
      expect(
        wantsInstallHint(userAgent: ipad, maxTouchPoints: 5, standalone: false),
        isTrue,
      );
      expect(
        wantsInstallHint(
          userAgent: iphone,
          maxTouchPoints: 5,
          standalone: true,
        ),
        isFalse,
      );
      expect(
        wantsInstallHint(userAgent: ipad, maxTouchPoints: 0, standalone: false),
        isFalse,
        reason: 'a Mac',
      );
      expect(
        wantsInstallHint(userAgent: ipad, maxTouchPoints: 1, standalone: false),
        isFalse,
        reason: 'a Mac with one touch point (pen tablet), iPads report 5',
      );
      expect(
        wantsInstallHint(
          userAgent: android,
          maxTouchPoints: 5,
          standalone: false,
        ),
        isFalse,
      );
    });

    testWidgets('the hint shows on top and can be closed', (tester) async {
      tester.view.physicalSize = phone;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final dir = Directory.systemTemp.createTempSync('wp_install_hint');
      addTearDown(() => dir.deleteSync(recursive: true));
      final app = TestApp(Directory('${dir.path}/lib'));
      await tester.runAsync(app.library.load);
      Future<void> pump({required bool hint}) => tester.pumpWidget(
        MaterialApp(
          locale: testLocale,
          localizationsDelegates: testDelegates,
          supportedLocales: testLocales,
          theme: woodshedTheme(Brightness.light),
          home: HomePage(controller: app.controller, installHint: hint),
        ),
      );
      await pump(hint: false);
      expect(find.byKey(const Key('installHint')), findsNothing);
      await pump(hint: true);
      await tester.pump();
      expect(find.byKey(const Key('installHint')), findsOneWidget);
      expect(find.textContaining('Zum Home-Bildschirm'), findsOneWidget);
      expect(find.byKey(const Key('layout:phone')), findsOneWidget);
      await tester.tap(find.byKey(const Key('installHintClose')));
      await tester.pump();
      expect(find.byKey(const Key('installHint')), findsNothing);
    });

    test('the web app asks the browser (navigator.standalone)', () {
      final web = read('lib/app/platform_web.dart');
      expect(web, contains("@JS('navigator.standalone')"));
      expect(web, contains('(display-mode: standalone)'));
      expect(read('lib/main.dart'), contains('installHint: installHintWanted'));
    });
  });
}

/// A store that cannot tell how much it uses (a browser without a storage estimate).
class _NoStorageInfo extends MemoryFileStore {
  @override
  Future<StorageInfo> storageInfo() async =>
      throw UnsupportedError('no estimate');
}
