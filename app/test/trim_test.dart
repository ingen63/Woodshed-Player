// #116: trimming a track in the library and across devices. The library gets a fake trimmer that marks the
// bytes with the range (the real cut is tested in core/tests/trim_tests.cpp and wp_trim_ffi_test.dart);
// libraries live in memory, syncs go through the InMemoryProvider.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/app/app_controller.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/metronome/metronome_controller.dart';
import 'package:woodshed_player/player/player_service.dart';
import 'package:woodshed_player/sync/in_memory_provider.dart';
import 'package:woodshed_player/sync/sync_engine.dart';
import 'package:wp_core/wp_types.dart';

import 'fakes.dart';
import 'metadata_test.dart' show apic, id3;

var clock = DateTime.utc(2026, 11, 1);
final sources = <String, Uint8List>{};

Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));
String sha(Uint8List b) => crypto.sha256.convert(b).toString();

/// Cuts nothing but marks the bytes with the range, so every range gives a new file (and ID).
Future<WpTrimmed> fakeTrim(Uint8List b, double start, double end) async =>
    WpTrimmed(
      Uint8List.fromList([...b, ...utf8.encode('|$start-$end')]),
      start,
      end,
    );

/// A trimmer that fails with [code] (as the core does).
AudioTrimmer failing(int code) =>
    (b, s, e) async => WpTrimmed.failed(code);

class Device {
  Device(this.cloud, int seed) {
    library = Library(
      store,
      probe: (_) => 10,
      readSource: (s) async => sources[s],
      now: () => clock,
      saveDelay: Duration.zero,
      random: Random(seed),
    );
    sync = CloudSync(
      cloud,
      library,
      now: () => clock,
      changeDelay: const Duration(milliseconds: 20),
    );
  }

  final InMemoryProvider cloud;
  final store = MemoryFileStore();
  late final Library library;
  late final CloudSync sync;

  Future<Track> add(String name) async {
    sources.putIfAbsent(name, () => bytes('audio $name'));
    final r = await library.importFiles([name]);
    return [...r.imported, ...r.duplicates].single;
  }
}

Future<Device> device(InMemoryProvider cloud, int seed) async {
  final d = Device(cloud, seed);
  await d.library.load();
  addTearDown(d.sync.dispose);
  return d;
}

void tick([int ms = 1000]) => clock = clock.add(Duration(milliseconds: ms));

void main() {
  setUp(() {
    clock = DateTime.utc(2026, 11, 1);
    sources.clear();
  });

  group('#116/AK6 loops in the trimmed file', () {
    test('a loop moves by the part cut off at the start', () {
      // cut [2, 8]: the loop 3–5 s now lies at 1–3 s
      expect(const LoopRange(3, 5).trimmed(2, 6), const LoopRange(1, 3));
    });
    test('a loop reaching outside is clamped to the new range', () {
      // 1–4 s with the start cut at 2 s: 0–2 s; 5–9 s with the end at 8 s (length 6): 3–6 s
      expect(const LoopRange(1, 4).trimmed(2, 6), const LoopRange(0, 2));
      expect(const LoopRange(5, 9).trimmed(2, 6), const LoopRange(3, 6));
      expect(const LoopRange(1, 9).trimmed(2, 6), const LoopRange(0, 6));
    });
    test(
      'a loop entirely outside is dropped, touching a bound counts as outside',
      () {
        expect(const LoopRange(0, 1.5).trimmed(2, 6), isNull);
        expect(const LoopRange(0, 2).trimmed(2, 6), isNull);
        expect(const LoopRange(8, 9).trimmed(2, 6), isNull);
        expect(const LoopRange(8.5, 9).trimmed(2, 6), isNull);
      },
    );
  });

  group('#116 trimming in the library', () {
    test('#116/AK5 #116/AK6 new ID from the new file; title, artist, folder, playlists, tempo and loops stay', () async {
      final d = await device(InMemoryProvider(), 1);
      final lib = d.library;
      var t = await d.add('song.mp3');
      final folder = lib.createFolder('Gig');
      lib.moveTracks({t.id}, folder.id);
      lib.editMetadata(t.id, title: 'Intro', artist: 'Band');
      final p = lib.createPlaylist('Set');
      lib.addToPlaylist(p.id, [t.id, t.id]);
      // three loops: 3–5 s (active), 0.5–1.5 s (before the cut), 7–9.5 s (over the end)
      lib.updateSettings(
        t.id,
        const PlaybackSettings(
          speedEnabled: true,
          speed: 0.75,
          loopEnabled: true,
          loopStart: 3,
          loopEnd: 5,
        ),
      );
      t = lib.track(t.id)!;
      final loops = {
        ...t.loops,
        'aaaaaaaa': const LoopRange(0.5, 1.5),
        'bbbbbbbb': const LoopRange(7, 9.5),
      };
      final old = t.id;
      final withLoops = t.copyWith(loops: loops);
      expect(withLoops.loops.length, 3);
      // the extra loops go through the shared record, as a sync would bring them
      final state = lib.state;
      await lib.mergeRemote(
        state.copyWith(
          tracks: {
            ...state.tracks,
            old: state.tracks[old]!.update(
              withLoops.toShared(),
              Hlc(clock.millisecondsSinceEpoch + 1, 0, 'ffff'),
            ),
          },
        ),
      );
      expect(lib.track(old)!.loops.length, 3);

      final next = await lib.trimTrack(old, 2, 8, fakeTrim);
      final file = Uint8List.fromList([
        ...sources['song.mp3']!,
        ...utf8.encode('|2.0-8.0'),
      ]);
      expect(next, sha(file), reason: 'the ID is the SHA-256 of the new file');
      expect(lib.track(old), isNull);
      final n = lib.track(next!)!;
      expect(n.fileName, '$next.mp3');
      expect(await d.store.read(Library.trackName(n.fileName)), file);
      expect(
        await d.store.exists(Library.trackName('$old.mp3')),
        isFalse,
        reason: 'the original is not kept',
      );
      // AK5
      expect(n.title, 'Intro');
      expect(n.artist, 'Band');
      expect(n.folderId, folder.id);
      expect(lib.playlist(p.id)!.entries, [next, next]);
      expect(lib.playlistTracks(p.id).map((x) => x.id), [next, next]);
      expect(n.settings.speedEnabled, isTrue);
      expect(n.settings.speed, 0.75);
      expect(n.duration, 6);
      expect(n.hasArtwork, isFalse);
      // AK6: 3–5 s → 1–3 s (active), 0.5–1.5 s dropped, 7–9.5 s → 5–6 s
      expect(n.settings.loopEnabled, isTrue);
      expect((n.settings.loopStart, n.settings.loopEnd), (1.0, 3.0));
      expect(n.loops.values.toSet(), {
        const LoopRange(1, 3),
        const LoopRange(5, 6),
      });
      // the old record is a tombstone naming the new track
      final rec = lib.state.tracks[old]!;
      expect(rec.alive, isFalse);
      expect(rec.values[Library.replacedByField], next);
      // saved: a restart shows the same
      final again = Library(
        d.store,
        probe: (_) => 10,
        readSource: (s) async => null,
        now: () => clock,
      );
      await again.load();
      expect(again.tracks.map((x) => x.id), [next]);
      expect(again.track(next)!.title, 'Intro');
    });

    test(
      '#116/AK6 an active loop outside the kept part is switched off',
      () async {
        final d = await device(InMemoryProvider(), 2);
        final t = await d.add('a.mp3');
        d.library.updateSettings(
          t.id,
          const PlaybackSettings(loopEnabled: true, loopStart: 0, loopEnd: 1.5),
        );
        final next = await d.library.trimTrack(t.id, 2, 9, fakeTrim);
        final n = d.library.track(next!)!;
        expect(n.loopId, isNull);
        expect(n.loops, isEmpty);
        expect(n.settings.loopEnabled, isFalse);
        expect(n.settings.loopEnd, 0);
      },
    );

    test(
      '#116/AK7 less than 1 s, or the end before the start: nothing changes',
      () async {
        final d = await device(InMemoryProvider(), 3);
        final t = await d.add('a.mp3');
        var calls = 0;
        Future<WpTrimmed> counting(Uint8List b, double s, double e) {
          calls++;
          return fakeTrim(b, s, e);
        }

        expect(await d.library.trimTrack(t.id, 2, 2.9, counting), isNull);
        expect(await d.library.trimTrack(t.id, 5, 2, counting), isNull);
        expect(calls, 0);
        expect(
          (d.library.lastError! as TrimFailed).problem,
          TrimProblem.tooShort,
        );
        // the core refuses a range too short after clamping
        expect(
          await d.library.trimTrack(
            t.id,
            9,
            12,
            failing(WpCode.invalidArgument),
          ),
          isNull,
        );
        expect(
          (d.library.lastError! as TrimFailed).problem,
          TrimProblem.tooShort,
        );
        expect(d.library.tracks.map((x) => x.id), [t.id]);
      },
    );

    test('#116/AK9 a failed cut or write leaves the track unchanged and names the reason', () async {
      final d = await device(InMemoryProvider(), 4);
      final t = await d.add('a.mp3');
      final before = jsonEncode(d.library.state.toJson());
      final files = {...d.store.files.keys};
      Future<TrimProblem> problem(AudioTrimmer trim) async {
        expect(await d.library.trimTrack(t.id, 1, 5, trim), isNull);
        final m = d.library.lastError! as TrimFailed;
        expect(m.title, t.title);
        d.library.lastError = null;
        return m.problem;
      }

      expect(
        await problem(failing(WpCode.unsupportedFormat)),
        TrimProblem.format,
      );
      expect(await problem(failing(WpCode.outOfMemory)), TrimProblem.memory);
      expect(await problem(failing(-99)), TrimProblem.failed);
      expect(
        await problem((b, s, e) async => throw StateError('worker gone')),
        TrimProblem.failed,
      );
      // no space for the new file (file system: ENOSPC, browser: QuotaExceededError)
      d.store.failWrites = 'FileSystemException: Cannot write, OS Error: No space left on device, errno = 28';
      expect(await problem(fakeTrim), TrimProblem.noSpace);
      d.store.failWrites = 'QuotaExceededError: The quota has been exceeded.';
      expect(await problem(fakeTrim), TrimProblem.noSpace);
      d.store.failWrites = 'IO error';
      expect(await problem(fakeTrim), TrimProblem.failed);
      // a write that left part of the new file behind: it is removed
      d.store.partialWrites = true;
      d.store.failWrites = 'No space left on device, errno = 28';
      expect(await problem(fakeTrim), TrimProblem.noSpace);
      d.store.partialWrites = false;
      d.store.failWrites = null;
      expect(jsonEncode(d.library.state.toJson()), before);
      expect({...d.store.files.keys}, files, reason: 'no new file left behind');
      expect(d.library.tracks.single.id, t.id);
    });

    test(
      '#116 M4A is not trimmed; nor a file only on another device',
      () async {
        final d = await device(InMemoryProvider(), 5);
        sources['b.m4a'] = bytes('aac');
        final t = (await d.library.importFiles(['b.m4a'])).imported.single;
        expect(Library.trimmable(t), isFalse);
        for (final ext in ['mp3', 'MP3', 'wav', 'flac', 'aac']) {
          expect(Library.trimmable(t.copyWith(fileName: 'x.$ext')), isTrue);
        }
        expect(Library.trimmable(t.copyWith(fileName: 'x.mp4')), isFalse);
        expect(await d.library.trimTrack(t.id, 1, 5, fakeTrim), isNull);
        expect(
          (d.library.lastError! as TrimFailed).problem,
          TrimProblem.format,
        );
        // a file missing on this device
        final m = await d.add('c.mp3');
        await d.store.delete(Library.trackName(m.fileName));
        expect(await d.library.trimTrack(m.id, 1, 5, fakeTrim), isNull);
        expect(
          (d.library.lastError! as TrimFailed).problem,
          TrimProblem.notOnDevice,
        );
        expect(d.library.track(m.id), isNotNull);
      },
    );
  });

  group('#116 trimming, details', () {
    test(
      '#116/AK5 the cover picture moves to the new ID; the old one is removed',
      () async {
        final d = await device(InMemoryProvider(), 20);
        final cover = Uint8List.fromList([0xFF, 0xD8, 1, 2, 3, 0xFF, 0xD9]);
        sources['c.mp3'] = Uint8List.fromList([
          ...id3(3, [('APIC', apic(3, cover))]),
          ...utf8.encode('audio'),
        ]);
        final t = (await d.library.importFiles(['c.mp3'])).imported.single;
        expect(t.hasArtwork, isTrue);
        final next = await d.library.trimTrack(t.id, 1, 5, fakeTrim);
        final n = d.library.track(next!)!;
        expect(n.hasArtwork, isTrue);
        expect(d.store.files[Library.artworkNameFor(next)], cover);
        expect(
          d.store.files.containsKey(Library.artworkNameFor(t.id)),
          isFalse,
        );
      },
    );

    test(
      '#116 a track deleted while it is cut leaves no new file behind',
      () async {
        final d = await device(InMemoryProvider(), 21);
        final cover = Uint8List.fromList([0xFF, 0xD8, 9, 0xFF, 0xD9]);
        sources['c.mp3'] = Uint8List.fromList([
          ...id3(3, [('APIC', apic(3, cover))]),
          ...utf8.encode('audio'),
        ]);
        final t = (await d.library.importFiles(['c.mp3'])).imported.single;
        final files = {...d.store.files.keys}
          ..removeAll([
            Library.trackName(t.fileName),
            Library.artworkNameFor(t.id),
          ]);
        Future<WpTrimmed> deleting(Uint8List b, double s, double e) async {
          d.library.delete({t.id});
          await pumpEventQueue();
          // the old picture is still there while the cut runs (deleted only afterwards)
          d.store.files[Library.artworkNameFor(t.id)] = cover;
          return fakeTrim(b, s, e);
        }

        expect(await d.library.trimTrack(t.id, 1, 5, deleting), isNull);
        expect(d.library.tracks, isEmpty);
        expect(
          {...d.store.files.keys}
              .where((k) => k != Library.indexName)
              .where((k) => k != Library.artworkNameFor(t.id))
              .toSet(),
          files.where((k) => k != Library.indexName).toSet(),
          reason: 'neither the new audio file nor its picture stay',
        );
      },
    );

    test(
      '#116 the trimmed file already in the library: it stays one track',
      () async {
        final d = await device(InMemoryProvider(), 22);
        final t = await d.add('a.mp3');
        sources['same.mp3'] = Uint8List.fromList([
          ...sources['a.mp3']!,
          ...utf8.encode('|1.0-5.0'),
        ]);
        final dup = await d.add('same.mp3');
        final next = await d.library.trimTrack(t.id, 1, 5, fakeTrim);
        expect(next, dup.id);
        expect(d.library.tracks.map((x) => x.id), [dup.id]);
        expect(d.library.track(dup.id)!.title, t.title);
      },
    );

    test('#116 device lists and the loaded track follow the new ID; listeners hear of it', () async {
      final d = await device(InMemoryProvider(), 23);
      final t = await d.add('a.mp3');
      await d.library.markUsed(t.id);
      await d.library.setKeepOffline({t.id}, true);
      d.library.inUse = t.id;
      var notified = 0;
      d.library.addListener(() => notified++);
      final next = await d.library.trimTrack(t.id, 1, 5, fakeTrim);
      expect(notified, greaterThan(0));
      expect(d.library.inUse, next);
      expect(d.library.keptOffline(next!), isTrue);
      expect(d.library.device.keepOffline, {next});
      expect(d.library.device.lastUsed.keys, [next]);
      // the measured storage follows (old file gone, new one there)
      await pumpEventQueue();
      expect(
        d.library.storage!.used,
        d.store.files.values.fold<int>(0, (s, b) => s + b.length),
      );
    });

    test(
      '#116 importing the old file again on the same device brings it back',
      () async {
        final d = await device(InMemoryProvider(), 24);
        final t = await d.add('a.mp3');
        final next = await d.library.trimTrack(t.id, 1, 5, fakeTrim);
        tick();
        await d.library.importFiles(['a.mp3']);
        tick();
        d.library.editMetadata(next!, title: 'saved again');
        await d.library.save();
        expect(d.library.tracks.map((x) => x.id).toSet(), {t.id, next});
        expect(d.library.state.tracks[t.id]!.alive, isTrue);
        // deleted again it is an ordinary deletion, not a replacement any more
        d.library.delete({t.id});
        await d.library.save();
        final rec = d.library.state.tracks[t.id]!;
        expect(rec.alive, isFalse);
        expect(rec.values.containsKey(Library.replacedByField), isFalse);
      },
    );

    test('#116 replacements are followed, also over several trims; a damaged cycle ends', () async {
      final d = await device(InMemoryProvider(), 25);
      final t = await d.add('a.mp3');
      final p = d.library.createPlaylist('Set');
      final first = await d.library.trimTrack(t.id, 1, 9, fakeTrim);
      final second = await d.library.trimTrack(first!, 1, 5, fakeTrim);
      expect(d.library.current(t.id), second);
      expect(d.library.current(first), second);
      expect(d.library.current('unknown'), 'unknown');
      // an entry made elsewhere for the very first ID finds the latest track
      final s = d.library.state;
      await d.library.mergeRemote(
        s.copyWith(
          playlists: {
            p.id: s.playlists[p.id]!.update({
              'name': 'Set',
              'shared': true,
              'entries': [t.id],
            }, Hlc(clock.millisecondsSinceEpoch + 5, 0, 'ffff')),
          },
        ),
      );
      expect(d.library.playlistTracks(p.id).map((x) => x.id), [second]);
      // two tombstones naming each other (a damaged file): no endless loop
      final stamp = Hlc(clock.millisecondsSinceEpoch + 9, 0, 'ffff');
      StampedRecord loop(String to) =>
          StampedRecord({'replacedBy': to}, {'replacedBy': stamp}, stamp);
      await d.library.mergeRemote(
        d.library.state.copyWith(
          tracks: {...d.library.state.tracks, 'x': loop('y'), 'y': loop('x')},
        ),
      );
      expect(['x', 'y'], contains(d.library.current('x')));
    });

    test('#116 a file name starting with its dot is judged by that ending', () {
      final t = Track(
        id: 'a',
        fileName: '.mp3',
        originalFileName: '.mp3',
        title: 't',
        duration: 9,
        hasArtwork: false,
        dateAdded: DateTime.utc(2026),
        customOrder: 0,
      );
      expect(Library.trimmable(t), isTrue);
      expect(Library.trimmable(t.copyWith(fileName: 'mp3')), isFalse);
    });

    test('#116/AK6 the active loop outside follows its settings even if the loop list says otherwise', () {
      final t = Track(
        id: 'a',
        fileName: 'a.mp3',
        originalFileName: 'a.mp3',
        title: 't',
        duration: 10,
        hasArtwork: false,
        dateAdded: DateTime.utc(2026),
        customOrder: 0,
        loopId: 'l1',
        loops: const {'l1': LoopRange(3, 5)},
        settings: const PlaybackSettings(
          loopEnabled: true,
          loopStart: 0,
          loopEnd: 1,
        ),
      );
      final n = t.trimmed(
        id: 'b',
        fileName: 'b.mp3',
        start: 2,
        duration: 6,
        hasArtwork: false,
      );
      expect(n.loops, isEmpty);
      expect(n.loopId, isNull);
    });
  });

  group('#116/AK8 sync', () {
    test('another device shows the trimmed track instead of the old one, the old file leaves the cloud', () async {
      final cloud = InMemoryProvider();
      final a = await device(cloud, 10);
      final b = await device(cloud, 11);
      final t = await a.add('song.mp3');
      final p = a.library.createPlaylist('Set');
      a.library.addToPlaylist(p.id, [t.id]);
      await a.sync.sync();
      tick();
      await b.sync.sync();
      expect(b.library.tracks.map((x) => x.id), [t.id]);
      expect(cloud.files.keys, contains(startsWith('audio/${t.id}')));
      tick();
      final next = await a.library.trimTrack(t.id, 1, 6, fakeTrim);
      tick();
      await a.sync.sync();
      tick();
      await b.sync.sync();
      expect(b.library.tracks.map((x) => x.id), [
        next,
      ], reason: 'no second track');
      expect(b.library.playlistTracks(p.id).map((x) => x.id), [next]);
      expect(b.library.track(next!)!.title, t.title);
      expect(cloud.files.keys.where((k) => k.startsWith('audio/')), [
        startsWith('audio/$next'),
      ], reason: 'the old audio file is gone from the cloud');
      expect(await b.store.exists(Library.trackName('${t.id}.mp3')), isFalse);
    });

    test('a change made elsewhere meanwhile revives no second track; an entry added there finds the new one', () async {
      final cloud = InMemoryProvider();
      final a = await device(cloud, 12);
      final b = await device(cloud, 13);
      final t = await a.add('song.mp3');
      await a.sync.sync();
      tick();
      await b.sync.sync();
      tick();
      final next = await a.library.trimTrack(t.id, 1, 6, fakeTrim);
      tick();
      // b, not yet synced: renames the old track and puts it in a new playlist
      b.library.editMetadata(t.id, title: 'Renamed');
      final p = b.library.createPlaylist('Later');
      b.library.addToPlaylist(p.id, [t.id]);
      tick();
      await a.sync.sync();
      tick();
      await b.sync.sync();
      tick();
      await a.sync.sync();
      for (final d in [a, b]) {
        expect(d.library.tracks.map((x) => x.id), [next]);
        expect(d.library.playlistTracks(p.id).map((x) => x.id), [next]);
      }
      expect(
        jsonEncode(a.library.state.toJson()),
        jsonEncode(b.library.state.toJson()),
      );
    });

    test(
      'importing the old file again later brings it back as a track of its own',
      () async {
        final cloud = InMemoryProvider();
        final a = await device(cloud, 14);
        final b = await device(cloud, 15);
        final t = await a.add('song.mp3');
        await a.sync.sync();
        tick();
        await b.sync.sync();
        tick();
        final next = await a.library.trimTrack(t.id, 1, 6, fakeTrim);
        tick();
        await a.sync.sync();
        tick();
        await b.sync.sync();
        tick();
        await b.add('song.mp3');
        tick();
        await b.sync.sync();
        tick();
        await a.sync.sync();
        for (final d in [a, b]) {
          expect(d.library.tracks.map((x) => x.id).toSet(), {next, t.id});
        }
      },
    );
  });

  group('#116 controller', () {
    test('#116/AK2 listening plays the range once without the loop, then stops at its start', () {
      final core = FakeCore();
      final timers = <FakeTimer>[];
      final player = PlayerService(
        core,
        timerFactory: (d, f) {
          final t = FakeTimer(d, f);
          timers.add(t);
          return t;
        },
      );
      player.load(
        't.mp3',
        settings: const PlaybackSettings(
          loopEnabled: true,
          loopStart: 2,
          loopEnd: 4,
        ),
      );
      core.finishLoad(10);
      void tickAll() {
        for (final t in timers.where((t) => t.active).toList()) {
          t.onTick(t);
        }
      }

      tickAll();
      expect(core.loop, (2.0, 4.0));
      var ended = 0;
      player.onEnded = () => ended++;
      player.previewRange(1, 9);
      expect(player.preview, (1.0, 9.0));
      expect(core.loop, isNull, reason: 'the loop would jump back');
      expect(core.playing, isTrue);
      tickAll(); // the core reports the seek to 1 s
      expect(player.preview, (1.0, 9.0));
      core.pos = 9.05;
      tickAll();
      expect(player.preview, isNull);
      expect(core.playing, isFalse);
      expect(player.position, 1.0, reason: 'back at the start of the range');
      expect(core.loop, (2.0, 4.0), reason: 'the loop applies again');
      expect(ended, 0, reason: 'a playlist does not go on');
      // the range ends exactly at its end
      core.calls.clear();
      player.previewRange(1.5, 9);
      expect(core.calls, ['seek 1.5', 'play']);
      tickAll();
      core.pos = 9.0;
      tickAll();
      expect(player.preview, isNull);
      // while it plays in the range it goes on, also after the grace ticks
      player.previewRange(1, 9);
      for (var i = 0; i < 5; i++) {
        core.pos = 2 + i * 0.1;
        tickAll();
      }
      expect(player.preview, (1.0, 9.0));
      // playback stopped elsewhere (the core paused): listening ends
      core.playing = false;
      tickAll();
      expect(player.preview, isNull);
      // stopping by hand
      player.previewRange(3, 5);
      player.stopPreview();
      expect(player.preview, isNull);
      expect(core.playing, isFalse);
    });

    test('#116 the loaded track is loaded again with its new file; failures are shown', () async {
      final store = MemoryFileStore();
      sources['song.mp3'] = bytes('audio song');
      final library = Library(
        store,
        probe: (_) => 10,
        readSource: (s) async => sources[s],
        saveDelay: Duration.zero,
        random: Random(1),
      );
      await library.load();
      final core = FakeCore();
      final player = PlayerService(core, timerFactory: FakeTimer.new);
      final c = AppController(
        library: library,
        player: player,
        metronome: MetronomeController(FakeMetronome()),
        files: FakeFiles(),
        trimmer: fakeTrim,
      );
      final t = (await library.importFiles(['song.mp3'])).imported.single;
      final loading = c.openForTrim(t);
      core.finishLoad(10);
      player.tick();
      expect(await loading, isTrue);
      player.play();
      final trimming = c.trimTrack(t.id, 2, 7);
      expect(c.trimming, t.id);
      expect(player.isPlaying, isFalse);
      // the new file loads
      await eventually(
        () => core.calls.where((x) => x.startsWith('load')).length >= 2,
        'the trimmed track loads',
      );
      core.finishLoad(5);
      player.tick();
      final next = await trimming;
      expect(c.trimming, isNull);
      expect(player.trackId, next);
      expect(player.path, Library.trackName('$next.mp3'));
      c.dispose();
      // a failure: the library's message reaches the controller
      final failed = AppController(
        library: library,
        player: player,
        metronome: MetronomeController(FakeMetronome()),
        files: FakeFiles(),
        trimmer: failing(WpCode.unsupportedFormat),
      );
      addTearDown(failed.dispose);
      expect(await failed.trimTrack(next!, 1, 3), isNull);
      expect(failed.message, isA<TrimFailed>());
      expect(library.track(next), isNotNull);
    });
  });
}
