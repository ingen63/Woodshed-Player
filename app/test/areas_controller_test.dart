// #115: the areas and the Spotify-like controls without widgets: «Next», «Previous», repeat and shuffle on a
// folder or a playlist, the area stored per device, the metronome ramp back to its start. The audio core is a
// fake (FakeCore), the library lives in a temporary folder; never the real library.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/app/app_controller.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/metronome/metronome_controller.dart';
import 'package:woodshed_player/player/play_queue.dart';
import 'package:woodshed_player/player/player_service.dart';

import 'fakes.dart';

void main() {
  late Directory dir;
  late TestApp app;
  late List<String> ids; // A, B, C, D in the section without a folder

  AppController c() => app.controller;
  PlayerService p() => app.player;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('wp_areas');
    app = TestApp(Directory('${dir.path}/lib'));
    await app.library.load();
    app.library.sortOrder = TrackSortOrder.alphabetical;
    final src = Directory('${dir.path}/src')..createSync();
    final r = await app.library.importFiles([
      for (final n in ['A', 'B', 'C', 'D'])
        (File('${src.path}/$n.mp3')..writeAsStringSync('audio $n')).path,
    ]);
    ids = [for (final t in r.imported) t.id];
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> load() async {
    app.finishLoads(30);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> choose(int i) async {
    final f = c().selectInFolder(app.library.track(ids[i])!);
    await load();
    expect(await f, isTrue);
  }

  /// The core plays the track to its end and stops by itself.
  Future<void> playToEnd() async {
    app.core.pos = 30;
    app.core.playing = false;
    for (var i = 0; i < 4; i++) {
      app.tick();
    }
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> next() async {
    final f = c().next();
    await load();
    await f;
  }

  Future<void> previous() async {
    final f = c().previous();
    await load();
    await f;
  }

  int playing() => ids.indexOf(p().trackId!);

  group('#115/AK9 next and previous on a folder', () {
    test('a track chosen in the library plays within its folder', () async {
      await choose(1);
      expect(c().queue, const PlayQueue.folder(null, 1));
      expect(p().isPlaying, isFalse); // a tap only loads
      await next();
      expect(playing(), 2);
      expect(p().isPlaying, isFalse);
      p().play();
      await next();
      expect(playing(), 3);
      expect(p().isPlaying, isTrue); // playing goes on playing
    });

    test('after the last track «Next» stops at its end', () async {
      await choose(3);
      p().play();
      await next();
      expect(playing(), 3);
      expect(p().isPlaying, isFalse);
      expect(app.core.calls.last, 'seek 30.0');
    });

    test('«Previous» goes to the start of the track; within its first 3 s to the previous one', () async {
      await choose(2);
      p().play();
      app.core.pos = 12;
      app.tick();
      await previous();
      expect(playing(), 2);
      expect(app.core.calls.last, 'seek 0.0');
      app.core.pos = 2.9;
      app.tick();
      await previous();
      expect(playing(), 1);
      expect(p().isPlaying, isTrue);
      app.core.pos = 3;
      app.tick();
      await previous();
      expect(playing(), 1); // 3 s and more: to the start
    });

    test('«Previous» at the first track goes to its start', () async {
      await choose(0);
      await previous();
      expect(playing(), 0);
      expect(app.core.calls.last, 'seek 0.0');
    });

    test('a folder sorted anew: «Next» follows the new order', () async {
      final f = app.library.createFolder('F');
      app.library.moveTracks({ids[0], ids[2]}, f.id);
      await choose(2);
      expect(c().queue, PlayQueue.folder(f.id, 1));
      await previous();
      expect(playing(), 0);
      app.library.editMetadata(
        ids[0],
        title: 'Z',
        artist: null,
      ); // A → Z: now after C
      await next();
      expect(playing(), 0); // nothing after Z: stays, at its end
      await previous(); // at the end: to its start
      expect(playing(), 0);
      await previous();
      expect(playing(), 2);
    });

    test('without a track «Next» and «Previous» do nothing', () async {
      await c().next();
      await c().previous();
      expect(app.core.calls, isEmpty);
    });

    test('a track on its own: «Next» stops at its end', () async {
      final f = c().select(app.library.track(ids[1])!);
      await load();
      await f;
      await next();
      expect(playing(), 1);
      expect(app.core.calls.last, 'seek 30.0');
      await previous();
      expect(app.core.calls.last, 'seek 0.0');
    });

    test('a playlist: «Next» goes to its next row', () async {
      final pl = app.library.createPlaylist('Band').id;
      app.library.addToPlaylist(pl, [ids[3], ids[0]]);
      final f = c().playPlaylist(pl);
      await load();
      await f;
      await next();
      expect(playing(), 0);
      expect(c().queue, PlayQueue(pl, 1));
      await previous();
      expect(playing(), 3);
    });
  });

  group('#115/AK9 the list changed while a track plays', () {
    late String pl;
    Future<void> start(int row) async {
      final f = c().playPlaylist(pl, index: row, play: false);
      await load();
      await f;
    }

    setUp(() {
      pl = app.library.createPlaylist('Band').id;
      app.library.addToPlaylist(pl, [ids[0], ids[1], ids[2]]);
    });

    test(
      'a row moved: «Next» goes on after the track where it is now',
      () async {
        await start(1); // B
        app.library.movePlaylistEntry(pl, 1, 0); // B, A, C
        await next();
        expect(playing(), 0); // A, the row after B
        expect(c().queue, PlayQueue(pl, 1));
      },
    );

    test(
      'a row above removed: «Next» and «Previous» still find the track',
      () async {
        final f = c().playPlaylist(pl, index: 2, play: false); // C
        await load();
        await f;
        // B, C: the old row 2 is just past the end
        app.library.removeFromPlaylist(pl, 0);
        await previous();
        expect(playing(), 1); // B, the row before C now
        await next();
        expect(playing(), 2);
        // C alone: its old row 1 is just past the end again
        app.library.removeFromPlaylist(pl, 0);
        await next();
        expect(playing(), 2);
        expect(app.core.calls.last, 'seek 30.0'); // the end: nothing after C
        await previous(); // at the end: to the start
        await previous();
        expect(playing(), 2);
        expect(app.core.calls.last, 'seek 0.0');
      },
    );
  });

  group('#115/AK8 repeat', () {
    test('off at the end of the list: playback ends', () async {
      await choose(3);
      p().play();
      await playToEnd();
      await load();
      expect(p().isPlaying, isFalse);
      expect(playing(), 3);
    });

    test('list: after the last track the first follows', () async {
      c().cycleRepeat();
      expect(c().repeat, Repeat.list);
      await choose(3);
      p().play();
      await playToEnd();
      await load();
      expect(playing(), 0);
      expect(p().isPlaying, isTrue);
    });

    test('track: the track starts over at its end', () async {
      c()
        ..cycleRepeat()
        ..cycleRepeat();
      expect(c().repeat, Repeat.track);
      await choose(1);
      p().play();
      final loads = app.core.calls.where((x) => x.startsWith('load')).length;
      await playToEnd();
      expect(playing(), 1);
      expect(p().isPlaying, isTrue);
      expect(app.core.calls.where((x) => x.startsWith('load')).length, loads);
      expect(app.core.calls, containsAllInOrder(['seek 0.0', 'play']));
    });

    test('track: also a track chosen on its own', () async {
      c()
        ..cycleRepeat()
        ..cycleRepeat();
      final f = c().select(app.library.track(ids[2])!);
      await load();
      await f;
      p().play();
      await playToEnd();
      expect(p().isPlaying, isTrue);
      expect(app.core.calls.last, 'play');
    });

    test('a track on its own without repeat ends', () async {
      final f = c().select(app.library.track(ids[2])!);
      await load();
      await f;
      p().play();
      final calls = app.core.calls.length;
      await playToEnd();
      expect(p().isPlaying, isFalse);
      expect(app.core.calls.skip(calls), isEmpty);
    });

    test('track: «Next» by hand still goes to the next track', () async {
      c()
        ..cycleRepeat()
        ..cycleRepeat();
      await choose(1);
      await next();
      expect(playing(), 2);
    });

    test('a third tap switches repeat off; listeners hear of every tap', () {
      var n = 0;
      c().addListener(() => n++);
      for (var i = 0; i < 3; i++) {
        c().cycleRepeat();
      }
      expect(c().repeat, Repeat.off);
      expect(n, 3);
    });
  });

  group('#115/AK10 shuffle', () {
    test(
      'every track of the folder once per pass, then playback ends',
      () async {
        await choose(1);
        c().toggleShuffle();
        expect(c().shuffle, isTrue);
        expect(c().queue!.order.first, 1);
        p().play();
        final played = [playing()];
        for (var i = 0; i < 5; i++) {
          await playToEnd();
          await load();
          if (!p().isPlaying) break;
          played.add(playing());
        }
        expect(played.length, 4);
        expect(played.toSet(), {0, 1, 2, 3});
      },
    );

    test(
      'shuffle on before choosing: the chosen track begins the pass',
      () async {
        c().toggleShuffle();
        await choose(2);
        expect(c().queue!.shuffled, isTrue);
        expect(c().queue!.order.first, 2);
        expect(c().queue!.order.toSet(), {0, 1, 2, 3});
      },
    );

    test(
      'shuffle off: the folder goes on in its order after the track',
      () async {
        await choose(1);
        c().toggleShuffle();
        var n = 0;
        c().addListener(() => n++);
        c().toggleShuffle();
        expect(n, 1);
        expect(c().shuffle, isFalse);
        expect(c().queue, const PlayQueue.folder(null, 1));
        await next();
        expect(playing(), 2);
      },
    );

    test('without a list shuffle only switches', () {
      c().toggleShuffle();
      expect(c().shuffle, isTrue);
      expect(c().queue, isNull);
    });

    test('a playlist kept on this device keeps its shuffled order', () async {
      final pl = app.library.createPlaylist('Band').id;
      app.library.addToPlaylist(pl, [ids[0], ids[1], ids[2]]);
      c().toggleShuffle();
      final f = c().playPlaylist(pl, play: false);
      await load();
      await f;
      final order = c().queue!.order;
      final id = c().setPlaylistShared(pl, false);
      expect(c().queue!.playlistId, id);
      expect(c().queue!.order, order);
    });
  });

  group('#115/AK7 the area chosen last', () {
    test(
      'Player until one is chosen; the choice is stored per device',
      () async {
        expect(c().area, AppArea.player);
        var n = 0;
        c().addListener(() => n++);
        c().setArea(AppArea.metronome);
        c().setArea(AppArea.metronome);
        expect(n, 1);
        expect(c().area, AppArea.metronome);
        final file = File('${dir.path}/lib/${DeviceSettings.fileName}');
        await eventually(
          () =>
              file.existsSync() &&
              file.readAsStringSync().contains('metronome'),
          'area written',
        );
        final again = TestApp(Directory('${dir.path}/lib'));
        await again.library.load();
        expect(again.controller.area, AppArea.metronome);
        expect(again.library.device.toJson()['area'], 'metronome');
      },
    );

    test('an unknown name opens the area Player', () {
      expect(AppArea.named(null), AppArea.player);
      expect(AppArea.named('nope'), AppArea.player);
      expect(AppArea.named('practice'), AppArea.practice);
    });

    test(
      'device.json keeps the area; an empty or wrong value is none',
      () async {
        final store = app.library.store;
        const d = DeviceSettings(
          deviceId: '0123456789abcdef',
          area: 'practice',
        );
        await d.save(store);
        expect((await DeviceSettings.load(store)).area, 'practice');
        expect(d.copyWith().area, 'practice');
        expect(d.copyWith(area: 'player').area, 'player');
        expect(
          const DeviceSettings(deviceId: '0123456789abcdef').toJson(),
          isNot(contains('area')),
        );
        for (final bad in ['""', '3']) {
          await store.write(
            DeviceSettings.fileName,
            Uint8List.fromList(
              '{"deviceId":"0123456789abcdef","area":$bad}'.codeUnits,
            ),
          );
          expect((await DeviceSettings.load(store)).area, isNull);
        }
      },
    );
  });

  test('#115/AK3 switching the area changes nothing in playback', () async {
    await choose(1);
    p().setLoopStart(4);
    p().setLoopEnd(9);
    p().setSpeed(0.75);
    p().play();
    final calls = app.core.calls.length;
    for (final a in [...AppArea.values, AppArea.player]) {
      c().setArea(a);
    }
    expect(app.core.calls.skip(calls), isEmpty);
    expect(p().isPlaying, isTrue);
    expect(app.core.loop, (4.0, 9.0));
  });

  group('#115/AK13 stopping the metronome', () {
    test('sets an active ramp back to its start tempo', () async {
      final backend = FakeMetronome();
      final m = MetronomeController(backend);
      m.setRamp(enabled: true, start: 100, target: 150);
      m.start();
      backend.bpm = 124; // the core ramped up
      m.sync();
      expect(m.settings.bpm, 124);
      m.stop();
      expect(m.settings.bpm, 100);
      expect(backend.bpm, 100);
    });

    test('without a ramp the tempo stays', () {
      final backend = FakeMetronome();
      final m = MetronomeController(backend)..setBpm(133);
      m.start();
      m.stop();
      expect(m.settings.bpm, 133);
      expect(backend.bpm, 133);
    });
  });
}
