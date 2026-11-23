// #114/AK5, AK6: playing a playlist from start to end. The audio core is a fake (FakeCore), the library lives
// in a temporary folder; never the real library.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/app/app_controller.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/player/play_queue.dart';
import 'package:woodshed_player/player/player_service.dart';

import 'fakes.dart';

void main() {
  group('#114 playing a playlist', () {
    late Directory dir;
    late TestApp app;
    late List<String> ids;
    late String playlist;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('wp_playlist');
      app = TestApp(Directory('${dir.path}/lib'));
      await app.library.load();
      final src = Directory('${dir.path}/src')..createSync();
      final r = await app.library.importFiles([
        for (final n in ['A', 'B', 'C'])
          (File('${src.path}/$n.mp3')..writeAsStringSync('audio $n')).path,
      ]);
      ids = [for (final t in r.imported) t.id];
      playlist = app.library.createPlaylist('Band').id;
      app.library.addToPlaylist(playlist, [ids[0], ids[1], ids[0]]);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    /// Completes the load and lets the track play to its end, as the core does.
    Future<void> load() async {
      app.finishLoads(30);
      await Future<void>.delayed(Duration.zero);
    }

    Future<void> playToEnd() async {
      app.core.pos = 30;
      app.core.playing = false;
      // the player waits a few ticks for the core to take a play command over
      for (var i = 0; i < 4; i++) {
        app.tick();
      }
      await Future<void>.delayed(Duration.zero);
    }

    test('#114/AK5 at the end of a track the next one follows; after the last one playback ends', () async {
      final started = app.controller.playPlaylist(playlist);
      await load();
      expect(await started, isTrue);
      expect(app.player.trackId, ids[0]);
      expect(app.player.isPlaying, isTrue);

      await playToEnd();
      await load();
      expect(app.player.trackId, ids[1]);
      expect(app.player.isPlaying, isTrue);
      expect(app.controller.queue, PlayQueue(playlist, 1));

      await playToEnd();
      await load();
      expect(app.player.trackId, ids[0]); // the same track a second time
      expect(app.controller.queue, PlayQueue(playlist, 2));

      final loads = app.core.calls.where((c) => c.startsWith('load')).length;
      await playToEnd();
      await load();
      expect(app.player.isPlaying, isFalse);
      expect(app.core.calls.where((c) => c.startsWith('load')).length, loads);
    });

    test('#114/AK5 a pause is no end: nothing follows', () async {
      final started = app.controller.playPlaylist(playlist);
      await load();
      await started;
      final loads = app.core.calls.where((c) => c.startsWith('load')).length;
      app.core.pos = 29.9;
      app.player.pause();
      app.tick();
      await Future<void>.delayed(Duration.zero);
      expect(app.core.calls.where((c) => c.startsWith('load')).length, loads);
      expect(app.player.trackId, ids[0]);
      expect(app.controller.queue, PlayQueue(playlist, 0));
    });

    test('#114/AK6 with an active loop the track repeats the loop instead of going on', () async {
      final started = app.controller.playPlaylist(playlist);
      await load();
      await started;
      app.player.updateSettings(
        (s) => s.copyWith(loopEnabled: true, loopStart: 0, loopEnd: 30),
      );
      expect(app.player.activeLoop, isNotNull);
      // the core loops and keeps playing; even a stop at the end does not advance
      await playToEnd();
      await load();
      expect(app.player.trackId, ids[0]);
      expect(app.controller.queue, PlayQueue(playlist, 0));
    });

    test('#114 a track chosen on its own ends the playlist', () async {
      final started = app.controller.playPlaylist(playlist, play: false);
      await load();
      await started;
      expect(app.player.isPlaying, isFalse);
      final chosen = app.controller.select(app.library.track(ids[2])!);
      await load();
      await chosen;
      expect(app.controller.queue, isNull);
      app.player.play();
      app.tick();
      await playToEnd();
      await load();
      expect(app.player.trackId, ids[2]);
    });

    test('#114 deleting the track playing ends the playlist', () async {
      final started = app.controller.playPlaylist(playlist, index: 1);
      await load();
      await started;
      app.controller.deleteTracks({ids[1]});
      expect(app.controller.queue, isNull);
      expect(await app.controller.playPlaylist(playlist, index: 5), isFalse);
    });

    test('#114/AK5 the queue goes to the next row and ends after the last', () {
      const q = PlayQueue('p', 0);
      expect(q.next(3), const PlayQueue('p', 1));
      expect(const PlayQueue('p', 2).next(3), isNull);
      expect(q.next(0), isNull);
      expect(q.toString(), contains('p'));
      expect(q.hashCode, const PlayQueue('p', 0).hashCode);
      expect(q == const PlayQueue('q', 0), isFalse);
    });

    test('#114 a stored loop that is off does not stop the playlist', () async {
      app.library.updateSettings(
        ids[0],
        const PlaybackSettings(loopEnabled: false, loopStart: 2, loopEnd: 5),
      );
      final started = app.controller.playPlaylist(playlist);
      await load();
      await started;
      await playToEnd();
      await load();
      expect(app.player.trackId, ids[1]);
    });

    test('#114/AK5 «Play» is the default; an index outside the playlist loads nothing', () async {
      var notified = 0;
      app.controller.addListener(() => notified++);
      expect(await app.controller.playPlaylist(playlist, index: -1), isFalse);
      expect(await app.controller.playPlaylist(playlist, index: 3), isFalse);
      expect(app.controller.queue, isNull);
      expect(notified, 0);
      final started = app.controller.playPlaylist(playlist, index: 2);
      expect(notified, greaterThan(0)); // the queue shows at once
      expect(app.controller.queue, PlayQueue(playlist, 2));
      await load();
      expect(await started, isTrue);
      expect(app.player.isPlaying, isTrue);
    });

    test(
      '#114/AK5 a load that fails or was overtaken does not start playing',
      () async {
        final first = app.controller.playPlaylist(playlist);
        final second = app.controller.playPlaylist(
          playlist,
          index: 1,
          play: false,
        );
        await load();
        expect(await first, isFalse); // overtaken
        expect(await second, isTrue);
        expect(app.player.isPlaying, isFalse);
        expect(app.controller.queue, PlayQueue(playlist, 1));

        // the queue changed while loading: the old load does not play
        final third = app.controller.playPlaylist(playlist, index: 2);
        app.controller.select(app.library.track(ids[2])!);
        await load();
        await third;
        expect(app.player.isPlaying, isFalse);
      },
    );

    test('#114/AK5 choosing a track on its own tells the listeners the playlist ended', () async {
      final started = app.controller.playPlaylist(playlist, play: false);
      await load();
      await started;
      var notified = 0;
      app.controller.addListener(() => notified++);
      final chosen = app.controller.select(app.library.track(ids[2])!);
      expect(notified, 1);
      await load();
      await chosen;
      notified = 0;
      final again = app.controller.select(app.library.track(ids[1])!);
      expect(notified, 0); // no playlist, nothing to tell
      await load();
      await again;
    });

    test('#114/AK9 a playlist being played goes on under its new ID once kept on this device', () async {
      final started = app.controller.playPlaylist(playlist);
      await load();
      await started;
      var notified = 0;
      app.controller.addListener(() => notified++);
      final local = app.controller.setPlaylistShared(playlist, false);
      expect(local, isNot(playlist));
      expect(app.controller.queue, PlayQueue(local, 0));
      expect(notified, 1);
      // another playlist does not touch the queue
      final other = app.library.createPlaylist('Solo').id;
      final otherLocal = app.controller.setPlaylistShared(other, false);
      expect(otherLocal, isNot(other));
      expect(app.controller.queue, PlayQueue(local, 0));
      // shared again: the same ID, the queue stays
      expect(app.controller.setPlaylistShared(local, true), local);
      expect(app.controller.queue, PlayQueue(local, 0));
      expect(notified, 1);
      await playToEnd();
      await load();
      expect(app.controller.queue, PlayQueue(local, 1));
    });

    test('#114/AK5 the end of a track counts only when the core stops by itself at the end', () async {
      var ended = 0;
      final player = app.player;
      final wired = player.onEnded;
      player.onEnded = () => ended++;
      player.tick(); // no track loaded: a tick ends nothing
      expect(ended, 0);
      player.onEnded = wired;
      final started = app.controller.playPlaylist(playlist, index: 2);
      await load();
      await started;
      player.onEnded = () => ended++;

      void ticks(int n) {
        for (var i = 0; i < n; i++) {
          app.tick();
        }
      }

      void resume() {
        player.play();
        ticks(4); // the core has taken the play command over
        expect(player.isPlaying, isTrue);
      }

      // the core has not taken the play command over yet (grace ticks): no end
      app.core.pos = 30;
      app.core.playing = false;
      ticks(1);
      expect(ended, 0);
      // a seek on its way to the core: no end either
      app.core.applySeekImmediately = false;
      player.seek(10);
      ticks(4);
      expect(ended, 0);
      expect(player.isPlaying, isFalse);
      app.core.applySeekImmediately = true;
      player.seek(10);
      ticks(1);

      // stopped clearly before the end (e.g. the device went away): no end
      resume();
      app.core.playing = false;
      app.core.pos = 20;
      ticks(1);
      expect(ended, 0);

      // stopped right at the end (within the tolerance): the end
      resume();
      app.core.playing = false;
      app.core.pos = 30 - PlayerService.endTolerance;
      ticks(1);
      expect(ended, 1);
    });
  });

  group('#124 sorting a playlist being played', () {
    late Directory dir;
    late TestApp app;
    late List<String> ids; // A, B, C
    late String playlist;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('wp_playlist_sort');
      app = TestApp(Directory('${dir.path}/lib'));
      await app.library.load();
      final src = Directory('${dir.path}/src')..createSync();
      final r = await app.library.importFiles([
        for (final n in ['A', 'B', 'C'])
          (File('${src.path}/$n.mp3')..writeAsStringSync('audio $n')).path,
      ]);
      ids = [for (final t in r.imported) t.id];
      playlist = app.library.createPlaylist('Band').id;
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Future<void> load() async {
      app.finishLoads(30);
      await Future<void>.delayed(Duration.zero);
    }

    Future<void> playToEnd() async {
      app.core.pos = 30;
      app.core.playing = false;
      for (var i = 0; i < 4; i++) {
        app.tick();
      }
      await Future<void>.delayed(Duration.zero);
    }

    int loads() => app.core.calls.where((c) => c.startsWith('load')).length;

    test('#124/AK5 the track goes on playing; then the next one of the new order follows', () async {
      app.library.addToPlaylist(playlist, ids); // A, B, C
      final started = app.controller.playPlaylist(playlist, index: 1);
      await load();
      await started;
      expect(app.player.trackId, ids[1]);
      final before = loads();
      var told = 0;
      app.controller.addListener(() => told++);

      app.controller.sortPlaylist(
        playlist,
        PlaylistSortKey.title,
        descending: true,
      ); // C, B, A
      expect(told, greaterThan(0));
      expect(loads(), before);
      expect(app.player.trackId, ids[1]);
      expect(app.player.isPlaying, isTrue);
      expect(app.controller.queue, PlayQueue(playlist, 1));

      await playToEnd();
      await load();
      expect(app.player.trackId, ids[0]); // A, not C as before
      expect(app.controller.queue, PlayQueue(playlist, 2));
    });

    test('#124/AK5 a track twice in the playlist: the row being played moves with it', () async {
      app.library.addToPlaylist(playlist, [ids[0], ids[1], ids[0]]);
      final started = app.controller.playPlaylist(playlist, index: 2);
      await load();
      await started;
      app.controller.sortPlaylist(playlist, PlaylistSortKey.title); // A, A, B
      expect(app.controller.queue, PlayQueue(playlist, 1));
      await playToEnd();
      await load();
      expect(app.player.trackId, ids[1]);
      expect(app.controller.queue, PlayQueue(playlist, 2));
    });

    test(
      '#124/AK5 with shuffle the rows still to come keep their tracks',
      () async {
        app.library.addToPlaylist(playlist, ids); // A, B, C
        app.controller.toggleShuffle();
        final started = app.controller.playPlaylist(playlist);
        await load();
        await started;
        final q = app.controller.queue!;
        final tracks = [for (final i in q.order) ids[i]];
        app.controller.sortPlaylist(
          playlist,
          PlaylistSortKey.title,
          descending: true,
        ); // C, B, A
        final sorted = app.controller.queue!;
        final rows = app.library.playlistTracks(playlist);
        expect([for (final i in sorted.order) rows[i].id], tracks);
        expect(rows[sorted.index].id, app.player.trackId);
      },
    );

    test(
      '#124/AK5 another playlist or a row gone meanwhile leave the queue alone',
      () async {
        app.library.addToPlaylist(playlist, ids);
        final other = app.library.createPlaylist('Solo').id;
        app.library.addToPlaylist(other, [ids[2], ids[0]]);
        final started = app.controller.playPlaylist(playlist, index: 2);
        await load();
        await started;
        app.controller.sortPlaylist(other, PlaylistSortKey.title);
        expect(app.controller.queue, PlayQueue(playlist, 2));
        expect(app.library.playlistTracks(other).first.id, ids[0]);

        app.library.removeFromPlaylist(playlist, 0); // B, C; row 2 is no more
        app.controller.sortPlaylist(
          playlist,
          PlaylistSortKey.title,
          descending: true,
        );
        expect(app.controller.queue, PlayQueue(playlist, 2));
        expect(app.player.trackId, ids[2]);
      },
    );

    test(
      '#124/AK5 without a playlist being played, sorting changes no queue',
      () async {
        app.library.addToPlaylist(playlist, ids);
        app.controller.sortPlaylist(playlist, PlaylistSortKey.dateAdded);
        expect(app.controller.queue, isNull);
        app.controller.sortPlaylist('nope', PlaylistSortKey.title);
        expect(app.controller.queue, isNull);
      },
    );
  });

  test('#114 the controller and the player are the ones the app wires', () {
    final dir = Directory.systemTemp.createTempSync('wp_playlist_wire');
    addTearDown(() => dir.deleteSync(recursive: true));
    final app = TestApp(Directory('${dir.path}/lib'));
    expect(app.controller, isA<AppController>());
    expect(app.player.onEnded, isNotNull);
  });
}
