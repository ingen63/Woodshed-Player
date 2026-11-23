// #37, #53: sync engine with merging. Every test runs against the InMemoryProvider (#37/AK7) and libraries in
// in-memory stores, never a real account or the real library.
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/library/stamps.dart';
import 'package:woodshed_player/sync/cloud_provider.dart';
import 'package:woodshed_player/sync/in_memory_provider.dart';
import 'package:woodshed_player/sync/sync_engine.dart';
import 'package:woodshed_player/sync/sync_service.dart';

import 'fakes.dart';

var clock = DateTime.utc(2026, 11, 1);

/// Import sources: name → contents (generated text, no real audio).
final sources = <String, Uint8List>{};

Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

/// One device: its own library in memory, its own device ID, the same cloud.
class Device {
  Device(this.cloud, int seed, {bool eager = true}) {
    library = Library(
      store,
      probe: (_) => 2.5,
      readSource: (s) async => sources[s],
      now: () => clock,
      saveDelay: Duration.zero,
      random: Random(seed),
    );
    sync = CloudSync(
      cloud,
      library,
      eagerDownload: eager,
      now: () => clock,
      changeDelay: const Duration(milliseconds: 20),
    );
  }

  final InMemoryProvider cloud;
  final store = MemoryFileStore();
  late final Library library;
  late final CloudSync sync;

  Future<Track> add(String name, {String? folderId}) async {
    sources.putIfAbsent(name, () => bytes('audio $name'));
    final r = await library.importFiles([name], folderId: folderId);
    return [...r.imported, ...r.duplicates].single;
  }

  Track t(String id) => library.track(id)!;
}

Future<Device> device(
  InMemoryProvider cloud,
  int seed, {
  bool eager = true,
}) async {
  final d = Device(cloud, seed, eager: eager);
  await d.library.load();
  addTearDown(d.sync.dispose);
  return d;
}

/// Shared state in the cloud: every device file merged, as a new device would see it.
SharedState cloudState(InMemoryProvider c) => [
  for (final e in c.files.entries)
    if (CloudSync.parseDeviceName(e.key) != null)
      CloudSync.decodeDevice(e.key, e.value).state,
].fold(SharedState.empty, (a, b) => a.merge(b)).purge(clock);

/// Name of the device file of [d].
String ownName(Device d) => CloudSync.deviceName(d.library.device.deviceId);

/// The device file of [d] as JSON.
Map<String, Object?> ownJson(InMemoryProvider c, Device d) =>
    (jsonDecode(utf8.decode(c.files[ownName(d)]!)) as Map).cast();

int cloudGeneration(InMemoryProvider c, Device d) =>
    ownJson(c, d)['generation']! as int;

/// Writes of device files (with every device on this storage).
int deviceWrites(InMemoryProvider c) =>
    c.requests.where((r) => r.startsWith('put devices/')).length;

void tick([int ms = 1000]) => clock = clock.add(Duration(milliseconds: ms));

void main() {
  setUp(() {
    clock = DateTime.utc(2026, 11, 1);
    sources.clear();
  });

  group('#37/AK7 InMemoryProvider', () {
    test('conditional put: version and absence are checked', () async {
      final c = InMemoryProvider();
      final v1 = await c.put('state.json', bytes('1'), ifAbsent: true);
      await expectLater(
        c.put('state.json', bytes('x'), ifAbsent: true),
        throwsA(isA<VersionConflict>()),
      );
      final v2 = await c.put('state.json', bytes('2'), ifVersion: v1);
      expect(v2, isNot(v1));
      await expectLater(
        c.put('state.json', bytes('3'), ifVersion: v1),
        throwsA(isA<VersionConflict>()),
      );
      expect(utf8.decode((await c.get('state.json'))!.bytes), '2');
      expect((await c.list('state')).single.version, v2);
      await c.delete('state.json');
      expect(await c.get('state.json'), isNull);
      expect((await c.quota()).used, 0);
    });

    test('offline: every request fails with CloudOffline', () async {
      final c = InMemoryProvider()..offline = true;
      await expectLater(c.list(''), throwsA(isA<CloudOffline>()));
      await expectLater(c.get('a'), throwsA(isA<CloudOffline>()));
    });
  });

  group('#37/AK1 merging is independent of order and idempotent', () {
    test(
      'first sync writes the own device file; a second sync writes nothing',
      () async {
        final cloud = InMemoryProvider();
        final a = await device(cloud, 1);
        final t = await a.add('a.mp3');
        await a.sync.sync();
        expect(cloudState(cloud).tracks.keys, [t.id]);
        expect(cloud.files.keys, contains('audio/${t.id}.mp3'));
        final puts = cloud.requests.where((r) => r.startsWith('put')).length;
        await a.sync.sync();
        await a.sync.sync();
        expect(
          cloud.requests.where((r) => r.startsWith('put')).length,
          puts,
          reason: 'idempotent: nothing changed, nothing written',
        );
        expect(a.sync.status, SyncStatus.idle);
      },
    );

    test('two devices: changes of both arrive on both', () async {
      final cloud = InMemoryProvider();
      final a = await device(cloud, 1);
      final b = await device(cloud, 2);
      final t = await a.add('a.mp3');
      await a.sync.sync();
      await b.sync.sync();
      expect(b.library.track(t.id)?.title, 'a');
      expect(b.library.hasFile(t.id), isTrue, reason: 'downloaded (desktop)');
      tick();
      a.library.editMetadata(t.id, title: 'Titel A', artist: null);
      tick();
      b.library.editMetadata(t.id, title: 'a', artist: 'Künstler B');
      await b.sync.sync();
      await a.sync.sync();
      await b.sync.sync();
      for (final d in [a, b]) {
        expect(d.t(t.id).title, 'Titel A');
        expect(d.t(t.id).artist, 'Künstler B');
      }
      expect(
        sameJson(a.library.state.toJson(), b.library.state.toJson()),
        isTrue,
      );
    });

    test('random changes on three devices, synced in random order, converge (random inputs)', () async {
      final stats = [0, 0, 0]; // tracks, tombstones, tracks with loops
      for (var seed = 0; seed < 25; seed++) {
        final r = Random(seed);
        final cloud = InMemoryProvider();
        final devices = [
          for (var i = 0; i < 3; i++) await device(cloud, seed * 10 + i),
        ];
        final names = ['a.mp3', 'b.mp3', 'c.mp3', 'd.mp3'];
        for (var step = 0; step < 30; step++) {
          tick(
            r.nextInt(3) == 0 ? 0 : r.nextInt(2000),
          ); // same millisecond now and then
          final d = devices[r.nextInt(devices.length)];
          final l = d.library;
          final tracks = l.tracks;
          final t = tracks.isEmpty ? null : tracks[r.nextInt(tracks.length)];
          switch (r.nextInt(9)) {
            case 0 || 1:
              await d.add(names[r.nextInt(names.length)]);
            case 2 when t != null:
              l.editMetadata(
                t.id,
                title: 'T${r.nextInt(5)}',
                artist: r.nextBool() ? 'A${r.nextInt(3)}' : null,
              );
            case 3 when t != null:
              final s = r.nextDouble();
              l.updateSettings(
                t.id,
                t.settings.copyWith(
                  loopEnabled: r.nextBool(),
                  loopStart: s,
                  loopEnd: r.nextInt(4) == 0 ? 0 : s + 1,
                ),
              );
            case 4 when t != null:
              l.delete({t.id});
            case 5:
              final f = l.createFolder('F${r.nextInt(3)}');
              if (t != null) l.moveTracks({t.id}, f.id);
            case 6 when l.folders.isNotEmpty:
              final f = l.folders[r.nextInt(l.folders.length)];
              r.nextBool()
                  ? l.setFolderSync(f.id, r.nextBool())
                  : l.deleteFolder(f.id);
            case 7 when t != null:
              l.setNoUpload({t.id}, r.nextBool());
            case _:
              await d.sync.sync();
          }
        }
        // Everyone syncs, twice, in a random order each round.
        for (var round = 0; round < 2; round++) {
          for (final d in [...devices]..shuffle(r)) {
            await d.sync.sync();
          }
        }
        final ref = cloudState(cloud).toJson();
        stats[0] += cloudState(cloud).tracks.length;
        stats[1] += cloudState(cloud).tracks.values
            .where((t) => !t.alive)
            .length;
        stats[2] += cloudState(cloud).tracks.values
            .where((t) => t.values.keys.any((k) => k.startsWith('loops.')))
            .length;
        for (final d in devices) {
          expect(
            sameJson(d.library.state.toJson(), ref),
            isTrue,
            reason: 'seed $seed',
          );
          expect(
            d.library.tracks.map((t) => t.id).toSet(),
            devices.first.library.tracks.map((t) => t.id).toSet(),
            reason: 'seed $seed',
          );
        }
        // Idempotent: another round writes nothing.
        final writes = deviceWrites(cloud);
        for (final d in devices) {
          await d.sync.sync();
        }
        expect(deviceWrites(cloud), writes, reason: 'seed $seed');
      }
      // the random inputs do reach the interesting cases
      expect(stats.every((n) => n > 5), isTrue, reason: '$stats');
    });

    test('pure merge with loop fields: every order gives the same result, merging twice changes nothing', () {
      final r = Random(37);
      Hlc stamp() => Hlc(r.nextInt(4), r.nextInt(2), 'abc'[r.nextInt(3)]);
      SharedState random() => SharedState(
        tracks: {
          for (final id in ['t1', 't2'])
            if (r.nextBool())
              id: () {
                final fields = <String, (Object?, Hlc)>{
                  for (final k in [
                    'title',
                    'activeLoop',
                    'loops.x',
                    'loops.y',
                    'noUpload',
                  ])
                    if (r.nextBool())
                      k: (
                        r.nextInt(3) == 0
                            ? null
                            : {'start': r.nextInt(3), 'end': 5},
                        stamp(),
                      ),
                };
                return StampedRecord(
                  {for (final e in fields.entries) e.key: e.value.$1},
                  {for (final e in fields.entries) e.key: e.value.$2},
                  r.nextInt(4) == 0 ? stamp() : null,
                );
              }(),
        },
      );
      for (var i = 0; i < 200; i++) {
        final states = [random(), random(), random()];
        final ref = states.reduce((x, y) => x.merge(y)).toJson();
        for (var k = 0; k < 6; k++) {
          final order = [...states]..shuffle(r);
          final m = order.reduce((x, y) => x.merge(y));
          expect(sameJson(m.toJson(), ref), isTrue);
          expect(sameJson(m.merge(m).toJson(), ref), isTrue);
          expect(sameJson(m.merge(order.first).toJson(), ref), isTrue);
        }
      }
    });

    test(
      'a device file from a newer app is neither merged nor overwritten',
      () async {
        final cloud = InMemoryProvider();
        cloud.putDirect(
          'devices/00000000000000aa.json',
          bytes(jsonEncode({'formatVersion': 3})),
        );
        final a = await device(cloud, 1);
        await a.add('a.mp3');
        await a.sync.sync();
        expect(a.sync.status, SyncStatus.tooNew);
        expect(deviceWrites(cloud), 0);
        expect(a.library.lastError, isA<CloudStateTooNew>());
      },
    );

    test('#10 regression (found bug 15): a speed of 1e400 in a device file is skipped; saving still works', () async {
      // Found in the former state.json (seed 1819282202, removed from regressions.json with #127 because
      // its property is gone since #53): 1e400 is valid JSON, Dart reads it as infinity; once merged,
      // every later save of the library failed. Today the same holds for a device file.
      final cloud = InMemoryProvider();
      final a = await device(cloud, 1);
      final t = await a.add('a.mp3');
      a.library.updateSettings(t.id, const PlaybackSettings(speed: 0.75));
      await a.sync.sync();
      final name = cloud.files.keys.singleWhere(
        (k) => k.startsWith('devices/'),
      );
      final text = utf8.decode(cloud.files[name]!);
      expect(text, contains('"speed": 0.75'));
      cloud.putDirect(
        name,
        bytes(text.replaceFirst('"speed": 0.75', '"speed": 1e400')),
      );
      final b = await device(cloud, 2);
      final own = await b.add('b.mp3');
      tick();
      await b.sync.sync();
      expect(b.library.track(t.id), isNull, reason: 'the file is skipped');
      b.library.editMetadata(own.id, title: 'Later', artist: null);
      await b.library.save();
      expect(b.library.lastError, isNull);
      final again = Library(
        b.store,
        probe: (_) => 2.5,
        readSource: (_) async => null,
      );
      await again.load();
      expect(again.track(own.id)!.title, 'Later');
    });
  });

  group('#37/AK2 without an account nothing is sent', () {
    test('NoSync does nothing and knows no cloud', () async {
      final s = NoSync();
      await s.start();
      s.resumed();
      s.localChanged();
      await s.syncNow();
      expect(s.status, SyncStatus.off);
      expect(s.inCloud('x'), isFalse);
    });
  });

  group('#37/AK3 offline changes wait in the queue and are retried after an abort', () {
    test(
      'offline: nothing sent, retry planned; online again: everything arrives',
      () async {
        final cloud = InMemoryProvider();
        final a = await device(cloud, 1);
        final t = await a.add('a.mp3');
        cloud.offline = true;
        await a.sync.sync();
        expect(a.sync.status, SyncStatus.offline);
        expect(a.sync.nextRetry, isNotNull);
        tick();
        a.library.editMetadata(t.id, title: 'Offline geändert', artist: null);
        await a.sync.sync();
        expect(
          a.sync.nextRetry! > const Duration(seconds: 2),
          isTrue,
          reason: 'backoff grows',
        );
        expect(cloud.files, isEmpty);
        cloud.offline = false;
        await a.sync.sync();
        expect(a.sync.status, SyncStatus.idle);
        expect(
          cloudState(cloud).tracks[t.id]!.values['title'],
          'Offline geändert',
        );
        expect(cloud.files.keys, contains('audio/${t.id}.mp3'));
      },
    );

    test(
      'aborted upload is retried after the backoff and then stored once',
      () async {
        final cloud = InMemoryProvider();
        final a = await device(cloud, 1);
        final t = await a.add('a.mp3');
        final audio = 'audio/${t.id}.mp3';
        var aborts = 1;
        cloud.abortPut = (name) => name == audio && aborts-- > 0;
        await a.sync.sync();
        expect(cloud.files.containsKey(audio), isFalse);
        expect(a.sync.pending.single.key, 'up:${t.id}');
        expect(a.sync.nextRetry, isNotNull);
        await a.sync.sync(); // too early: the task waits for its backoff
        expect(cloud.countOf('put $audio'), 1);
        tick(3000);
        await a.sync.sync();
        expect(cloud.files[audio], sources['a.mp3']);
        expect(a.sync.pending, isEmpty);
        await a.sync.sync();
        expect(
          cloud.countOf('put $audio'),
          2,
          reason: 'already there: not uploaded again',
        );
      },
    );

    test('a file that keeps failing is given up after maxAttempts (no endless loop)', () async {
      final cloud = InMemoryProvider();
      final a = await device(cloud, 1);
      final t = await a.add('a.mp3');
      final audio = 'audio/${t.id}.mp3';
      cloud.abortPut = (name) => name == audio;
      for (var i = 0; i < 20; i++) {
        await a.sync.sync();
        tick(10 * 60 * 1000);
      }
      expect(cloud.countOf('put $audio'), a.sync.maxAttempts);
      expect(a.sync.status, SyncStatus.failed);
      expect(a.sync.failed.single.key, 'up:${t.id}');
      expect(cloudState(cloud).tracks.keys, [
        t.id,
      ], reason: 'the state still syncs');
      cloud.abortPut = null;
      await a.sync.syncNow();
      expect(cloud.files.containsKey(audio), isTrue);
      expect(a.sync.status, SyncStatus.idle);
    });

    test(
      'another device writes between reading and writing: nothing is lost',
      () async {
        final cloud = InMemoryProvider();
        final a = await device(cloud, 1);
        final b = await device(cloud, 2);
        final t = await a.add('a.mp3');
        await a.sync.sync();
        await b.sync.sync();
        tick();
        b.library.editMetadata(t.id, title: 'von B', artist: null);
        tick();
        a.library.editMetadata(t.id, title: 'a', artist: 'von A');
        var once = true;
        cloud.beforePut = (name) async {
          if (name == ownName(a) && once) {
            once = false;
            await b.sync.sync(); // B writes its own file in between
          }
        };
        await a.sync.sync();
        await a.sync.sync();
        final s = cloudState(cloud).tracks[t.id]!.values;
        expect(s['title'], 'von B');
        expect(s['artist'], 'von A');
        expect(a.t(t.id).title, 'von B');
      },
    );

    test('audio is stored as audio/<hash>.<ext>; the same file twice is uploaded once', () async {
      final cloud = InMemoryProvider();
      final a = await device(cloud, 1);
      final b = await device(cloud, 2);
      sources['x.m4a'] = bytes('same contents');
      sources['y.m4a'] = bytes('same contents');
      final t = await a.add('x.m4a');
      await a.sync.sync();
      await b.add('y.m4a');
      await b.sync.sync();
      expect(cloud.files.keys.where((k) => k.startsWith('audio/')), [
        'audio/${t.id}.m4a',
      ]);
      expect(cloud.countOf('put audio/${t.id}.m4a'), 1);
    });
  });

  group('#37/AK4 loops are merged element by element', () {
    test('a loop set on each device: both remain', () async {
      final cloud = InMemoryProvider();
      final a = await device(cloud, 1);
      final b = await device(cloud, 2);
      final t = await a.add('a.mp3');
      await a.sync.sync();
      await b.sync.sync();
      tick();
      a.library.updateSettings(
        t.id,
        a
            .t(t.id)
            .settings
            .copyWith(loopEnabled: true, loopStart: 1, loopEnd: 2),
      );
      tick();
      b.library.updateSettings(
        t.id,
        b
            .t(t.id)
            .settings
            .copyWith(loopEnabled: true, loopStart: 3, loopEnd: 4),
      );
      final idA = a.t(t.id).loopId!;
      final idB = b.t(t.id).loopId!;
      expect(idA, isNot(idB));
      await a.sync.sync();
      await b.sync.sync();
      await a.sync.sync();
      for (final d in [a, b]) {
        final tr = d.t(t.id);
        expect(tr.loops[idA], const LoopRange(1, 2));
        expect(tr.loops[idB], const LoopRange(3, 4));
        // the later change decides which loop is shown
        expect(tr.loopId, idB);
        expect(tr.settings.loopStart, 3);
      }
    });

    test('changing one loop and deleting another on two devices: both changes remain', () async {
      final cloud = InMemoryProvider();
      final a = await device(cloud, 1);
      final b = await device(cloud, 2);
      final t = await a.add('a.mp3');
      // Two loops: x (active on A) and y, known on both devices.
      tick();
      a.library.updateSettings(
        t.id,
        a.t(t.id).settings.copyWith(loopStart: 1, loopEnd: 2),
      );
      final x = a.t(t.id).loopId!;
      a.library.updateSettings(
        t.id,
        a.t(t.id).settings.copyWith(loopStart: 0, loopEnd: 0),
      );
      tick();
      a.library.updateSettings(
        t.id,
        a.t(t.id).settings.copyWith(loopStart: 5, loopEnd: 6),
      );
      final y = a.t(t.id).loopId!;
      expect(a.t(t.id).loops[x], isNull, reason: 'x was cleared');
      await a.sync.sync();
      await b.sync.sync();
      // A changes y; B clears y (deletes it) and sets a new loop z.
      tick();
      a.library.updateSettings(
        t.id,
        a.t(t.id).settings.copyWith(loopStart: 5, loopEnd: 7),
      );
      tick();
      b.library.updateSettings(
        t.id,
        b.t(t.id).settings.copyWith(loopStart: 0, loopEnd: 0),
      );
      tick();
      b.library.updateSettings(
        t.id,
        b.t(t.id).settings.copyWith(loopStart: 8, loopEnd: 9),
      );
      final z = b.t(t.id).loopId!;
      await b.sync.sync();
      await a.sync.sync();
      await b.sync.sync();
      for (final d in [a, b]) {
        final rec = d.library.state.tracks[t.id]!.values;
        expect(
          rec['loops.$y'],
          isNull,
          reason: 'deleted by B after A changed it',
        );
        expect(rec['loops.$z'], {'start': 8.0, 'end': 9.0});
        expect(d.t(t.id).loopId, z);
      }
    });

    test(
      'loop from format 2 before #37 is taken over with the fixed ID «0»',
      () {
        final t = Track.fromShared('h', {
          'fileName': 'h.mp3',
          'loop': {'enabled': true, 'start': 1.5, 'end': 3},
        });
        expect(t.loopId, '0');
        expect(t.settings.loopEnabled, isTrue);
        expect(t.settings.loopEnd, 3);
        expect(t.toShared()['loops.0'], {'start': 1.5, 'end': 3.0});
      },
    );
  });

  group('#37/AK5 «don\'t upload» per track and «sync» per folder', () {
    test('excluded files stay here, their metadata travel along', () async {
      final cloud = InMemoryProvider();
      final a = await device(cloud, 1);
      final b = await device(cloud, 2);
      final keep = await a.add('keep.mp3');
      final private = await a.add('private.mp3');
      final f = a.library.createFolder('Nur hier');
      final inFolder = await a.add('folder.mp3', folderId: f.id);
      a.library.setNoUpload({private.id}, true);
      a.library.setFolderSync(f.id, false);
      await a.sync.sync();
      final audio = cloud.files.keys
          .where((k) => k.startsWith('audio/'))
          .toList();
      expect(audio, ['audio/${keep.id}.mp3']);
      final s = cloudState(cloud);
      expect(s.tracks[private.id]!.values['noUpload'], isTrue);
      expect(s.tracks[inFolder.id]!.values['folderId'], f.id);
      expect(s.folders[f.id]!.values['sync'], isFalse);

      await b.sync.sync();
      expect(b.library.tracks.map((t) => t.id).toSet(), {
        keep.id,
        private.id,
        inFolder.id,
      });
      expect(b.library.hasFile(keep.id), isTrue);
      for (final id in [private.id, inFolder.id]) {
        expect(b.library.hasFile(id), isFalse);
        expect(
          b.sync.inCloud(id),
          isFalse,
          reason: '«File only on one device»',
        );
      }
      // still visible after a restart of B
      final again = Library(
        b.store,
        probe: (_) => 2.5,
        readSource: (_) async => null,
        now: () => clock,
      );
      await again.load();
      expect(again.track(private.id), isNotNull);
      expect(again.hasFile(private.id), isFalse);
    });

    test(
      'switching on uploads, switching off removes the file from the cloud',
      () async {
        final cloud = InMemoryProvider();
        final a = await device(cloud, 1);
        final t = await a.add('a.mp3');
        final audio = 'audio/${t.id}.mp3';
        a.library.setNoUpload({t.id}, true);
        await a.sync.sync();
        expect(cloud.files.containsKey(audio), isFalse);
        tick();
        a.library.setNoUpload({t.id}, false);
        await a.sync.sync();
        expect(cloud.files.containsKey(audio), isTrue);
        final f = a.library.createFolder('F');
        a.library.moveTracks({t.id}, f.id);
        tick();
        a.library.setFolderSync(f.id, false);
        await a.sync.sync();
        expect(cloud.files.containsKey(audio), isFalse);
      },
    );

    test('deleted track: tombstone in the device files, file gone from the cloud and from other devices', () async {
      final cloud = InMemoryProvider();
      final a = await device(cloud, 1);
      final b = await device(cloud, 2);
      final t = await a.add('a.mp3');
      await a.sync.sync();
      await b.sync.sync();
      expect(b.store.files.keys, contains('Tracks/${t.id}.mp3'));
      tick();
      a.library.delete({t.id});
      await a.sync.sync();
      expect(cloud.files.containsKey('audio/${t.id}.mp3'), isFalse);
      expect(cloudState(cloud).tracks[t.id]!.alive, isFalse);
      await b.sync.sync();
      expect(b.library.track(t.id), isNull);
      expect(b.store.files.keys, isNot(contains('Tracks/${t.id}.mp3')));
    });

    test(
      'on demand (phone, browser): the file is loaded when played',
      () async {
        final cloud = InMemoryProvider();
        final a = await device(cloud, 1);
        final b = await device(cloud, 2, eager: false);
        final t = await a.add('a.mp3');
        await a.sync.sync();
        await b.sync.sync();
        expect(b.library.hasFile(t.id), isFalse);
        expect(b.sync.inCloud(t.id), isTrue);
        expect(await b.sync.fetchAudio(b.t(t.id)), isTrue);
        expect(b.library.hasFile(t.id), isTrue);
        expect(await b.library.readAudio(b.t(t.id)), sources['a.mp3']);
      },
    );
  });

  group(
    '#37/AK6, #53/AK7 the last 5 own states remain under backup/<device-id>/',
    () {
      test('#53/AK7 before every write the previous own file goes to backup/<device-id>/state-<n>.json', () async {
        final cloud = InMemoryProvider();
        final a = await device(cloud, 1);
        final b = await device(cloud, 2);
        final t = await a.add('a.mp3');
        final previous = <Uint8List>[];
        for (var i = 0; i < 8; i++) {
          tick();
          a.library.editMetadata(t.id, title: 'Stand $i', artist: null);
          final before = cloud.files[ownName(a)];
          if (before != null) previous.add(before);
          await a.sync.sync();
          await b.sync.sync();
        }
        final id = a.library.device.deviceId;
        final backups = {
          for (final e in cloud.files.entries)
            if (e.key.startsWith('backup/$id/')) e.key: e.value,
        };
        expect(backups.keys.toSet(), {
          for (var n = 1; n <= 5; n++) CloudSync.backupName(id, n),
        });
        expect(CloudSync.backupName(id, 3), 'backup/$id/state-3.json');
        final kept = backups.values.map(utf8.decode).toSet();
        expect(kept, previous.reversed.take(5).map(utf8.decode).toSet());
        // only own states: b's backups are under its own ID
        expect(
          cloud.files.keys.where(
            (k) => k.startsWith('backup/') && !k.startsWith('backup/$id/'),
          ),
          everyElement(startsWith('backup/${b.library.device.deviceId}/')),
        );
        // the backup is written before the own file each time
        final puts = cloud.requests
            .where(
              (r) =>
                  r.startsWith('put backup/$id/') || r == 'put ${ownName(a)}',
            )
            .toList();
        for (var i = 0; i < puts.length; i++) {
          if (puts[i].startsWith('put backup/')) {
            expect(puts[i + 1], 'put ${ownName(a)}');
          }
        }
      });

      test('no backup when nothing changes', () async {
        final cloud = InMemoryProvider();
        final a = await device(cloud, 1);
        await a.add('a.mp3');
        await a.sync.sync();
        await a.sync.sync();
        expect(cloud.files.keys.where((k) => k.startsWith('backup/')), isEmpty);
      });
    },
  );

  group('#37 triggers: start, change (delayed, combined), foreground', () {
    test(
      '#92/AK1 start and resume sync; several changes are sent together once',
      () async {
        final cloud = InMemoryProvider();
        final a = await device(cloud, 1);
        final t = await a.add('a.mp3');
        a.library.onLocalChange = a.sync.localChanged;
        await a.sync.start();
        expect(cloudState(cloud).tracks.keys, [t.id]);
        final writes = deviceWrites(cloud);
        for (var i = 0; i < 5; i++) {
          tick();
          a.library.editMetadata(t.id, title: 'T$i', artist: null);
        }
        expect(deviceWrites(cloud), writes, reason: 'delayed');
        // #92/AK1: wait for the delayed sync to finish, not for a fixed time
        await eventually(
          () =>
              deviceWrites(cloud) > writes && a.sync.status == SyncStatus.idle,
          'delayed sync after the last change',
        );
        expect(
          deviceWrites(cloud),
          writes + 1,
          reason: 'five changes are sent together once',
        );
        expect(cloudState(cloud).tracks[t.id]!.values['title'], 'T4');
        // another device changed something; coming back to the foreground fetches it
        cloud.putDirect(
          CloudSync.deviceName('ffffffffffffffff'),
          CloudSync.encodeDevice(
            cloudState(cloud).copyWith(
              settings: cloudState(cloud).settings.update(
                {'sortOrder': 'alphabetical'},
                Hlc(clock.millisecondsSinceEpoch + 5000, 0, 'ffffffffffffffff'),
              ),
            ),
            'ffffffffffffffff',
            1,
            clock,
          ),
        );
        a.sync.resumed();
        await eventually(
          () =>
              a.library.sortOrder == TrackSortOrder.alphabetical &&
              a.sync.status == SyncStatus.idle,
          'resumed() fetches the other device\'s state',
        );
        expect(a.library.sortOrder, TrackSortOrder.alphabetical);
      },
    );

    test('a sync requested while one runs follows right after it', () async {
      final cloud = InMemoryProvider();
      final a = await device(cloud, 1);
      final gate = Completer<void>();
      cloud.beforePut = (_) => gate.future;
      await a.add('a.mp3');
      final first = a.sync.sync();
      final second = a.sync.sync();
      expect(identical(first, second), isTrue);
      gate.complete();
      await first;
      expect(a.sync.status, SyncStatus.idle);
    });
  });

  group('#104 the purge horizon applies only after the first sync', () {
    // Example of the issue: A imports X and folder F, syncs, deletes both and purges them 91 days later
    // (the device files then have a horizon). B has its own library with Y and folder G, last changed before the
    // horizon, and syncs for the first time after it.
    Future<(Device, Device, InMemoryProvider, Track, Track)> purgedCloud({
      bool bSyncsEarly = false,
    }) async {
      final cloud = InMemoryProvider();
      final a = await device(cloud, 1);
      final b = await device(cloud, 2);
      final x = await a.add('x.mp3');
      final f = a.library.createFolder('F');
      await a.sync.sync();
      if (bSyncsEarly) await b.sync.sync();
      tick();
      final g = b.library.createFolder('G');
      final y = await b.add('y.mp3', folderId: g.id);
      tick();
      a.library.delete({x.id});
      a.library.deleteFolder(f.id);
      await a.sync.sync();
      clock = clock.add(const Duration(days: 91));
      await a.sync.sync();
      expect(cloudState(cloud).purged, isNotNull);
      expect(cloudState(cloud).tracks[x.id], isNull);
      // without #104 the horizon would kill Y and G on b's first sync
      final horizon = cloudState(cloud).purged!;
      expect(b.library.state.tracks[y.id]!.latest! < horizon, isTrue);
      expect(b.library.state.folders[g.id]!.latest! < horizon, isTrue);
      return (a, b, cloud, x, y);
    }

    test('#104/AK2 a track of a device syncing for the first time stays on both devices, with its audio', () async {
      final (a, b, cloud, _, y) = await purgedCloud();
      expect(b.library.device.synced, isFalse);
      await b.sync.sync();
      await a.sync.sync();
      expect(b.library.device.synced, isTrue);
      for (final d in [a, b]) {
        expect(d.library.track(y.id), isNotNull);
        expect(d.library.hasFile(y.id), isTrue);
      }
      expect(await b.library.readAudio(b.t(y.id)), sources['y.mp3']);
      expect(b.store.files.keys, contains('Tracks/${y.id}.mp3'));
      expect(cloud.files.keys, contains('audio/${y.id}.mp3'));
      expect(cloudState(cloud).tracks[y.id]!.alive, isTrue);
    });

    test('#104/AK3 a folder of a device syncing for the first time stays on both devices, with its tracks', () async {
      final (a, b, _, _, y) = await purgedCloud();
      final g = b.t(y.id).folderId!;
      await b.sync.sync();
      await a.sync.sync();
      for (final d in [a, b]) {
        expect(d.library.folders.map((f) => f.id), contains(g));
        expect(d.t(y.id).folderId, g);
      }
    });

    test('#104/AK4 a device that has synced before still loses what was deleted and purged', () async {
      final (a, b, _, x, y) = await purgedCloud(bSyncsEarly: true);
      expect(b.library.device.synced, isTrue);
      // offline since before the deletion
      expect(b.library.track(x.id), isNotNull);
      await b.sync.sync();
      await a.sync.sync();
      for (final d in [a, b]) {
        expect(d.library.track(x.id), isNull);
        expect(d.library.folders.map((f) => f.name), isNot(contains('F')));
      }
    });

    test('#104 the flag is kept in device.json and read again', () async {
      final (_, b, _, _, _) = await purgedCloud();
      Map<String, Object?> deviceJson() => (jsonDecode(
        utf8.decode(b.store.files[DeviceSettings.fileName]!),
      ) as Map).cast();
      expect(deviceJson().containsKey('synced'), isFalse);
      await b.sync.sync();
      expect(deviceJson()['synced'], isTrue);
      expect((await DeviceSettings.load(b.store)).synced, isTrue);
    });

    test('#104 the first device to sync (empty cloud) counts as synced after its upload', () async {
      final cloud = InMemoryProvider();
      final a = await device(cloud, 1);
      await a.add('a.mp3');
      await a.sync.sync();
      expect(a.library.device.synced, isTrue);
    });

    test('#104 a device.json without the flag: a state with foreign stamps counts as synced', () async {
      final cloud = InMemoryProvider();
      final a = await device(cloud, 1);
      final b = await device(cloud, 2);
      await a.add('a.mp3');
      await a.sync.sync();
      await b.sync.sync();
      b.store.files[DeviceSettings.fileName] = bytes(
        jsonEncode({'deviceId': b.library.device.deviceId}),
      );
      final again = Library(
        b.store,
        probe: (_) => 2.5,
        readSource: (s) async => sources[s],
        now: () => clock,
        saveDelay: Duration.zero,
      );
      await again.load();
      expect(again.device.synced, isTrue);
      final fresh = await device(InMemoryProvider(), 3);
      await fresh.add('b.mp3');
      expect(fresh.library.device.synced, isFalse);
    });

    test('#108/AK1 a library with only its own stamps does not count as synced after a restart', () async {
      final fresh = await device(InMemoryProvider(), 3);
      final b = await fresh.add('b.mp3');
      final again = Library(
        fresh.store,
        probe: (_) => 2.5,
        readSource: (s) async => sources[s],
        now: () => clock,
        saveDelay: Duration.zero,
      );
      await again.load();
      expect(again.track(b.id), isNotNull);
      expect(again.device.synced, isFalse);
    });

    test('#108/AK1 a horizon ahead of the own clock does not kill own tracks on the first merge', () async {
      // the other device's clock runs a day ahead: its horizon lies after everything stamped here
      final b = await device(InMemoryProvider(), 2);
      final y = await b.add('y.mp3');
      final horizon = Hlc(
        clock.add(const Duration(days: 1)).millisecondsSinceEpoch,
        0,
        'a',
      );
      final remote = SharedState.empty.copyWith(purged: horizon);
      expect(remote.latest, isNull); // only the horizon tells the clock
      await b.library.mergeRemote(remote);
      expect(b.library.track(y.id), isNotNull);
      expect(b.library.state.tracks[y.id]!.latest! > horizon, isTrue);
      expect(b.library.device.synced, isTrue);
    });
  });
  group(
    '#107 ask before own tracks and folders are lost to the purge horizon',
    () {
      // Example of the issue: A and B have synced. B stays offline for 91 days and imports Y meanwhile (and
      // creates folder G); A deletes X in that time and purges the tombstone. Y and G were last changed before
      // the horizon.
      Future<(Device, Device, InMemoryProvider, Track, Track)> offline91({
        bool folder = false,
      }) async {
        final cloud = InMemoryProvider();
        final a = await device(cloud, 1);
        final b = await device(cloud, 2);
        final x = await a.add('x.mp3');
        final t = await a.add('t.mp3');
        await a.sync.sync();
        await b.sync.sync();
        expect(b.library.device.synced, isTrue);
        tick();
        final y = await b.add('y.mp3');
        if (folder) {
          // G holds T, a track the other devices know: it stays in any case
          final g = b.library.createFolder('G');
          b.library.moveTracks({t.id}, g.id);
        }
        tick();
        a.library.delete({x.id});
        await a.sync.sync();
        clock = clock.add(const Duration(days: 91));
        await a.sync.sync();
        final horizon = cloudState(cloud).purged!;
        expect(b.library.state.tracks[y.id]!.latest! < horizon, isTrue);
        return (a, b, cloud, x, y);
      }

      void expectHeld(Device b, InMemoryProvider cloud, Track y) {
        expect(b.library.heldNames, contains(y.title));
        expect(b.library.track(y.id), isNotNull);
        expect(b.store.files['Tracks/${y.id}.mp3'], sources['y.mp3']);
        // held back: neither the record nor the audio file goes to the cloud
        expect(cloudState(cloud).tracks[y.id], isNull);
        expect(cloud.files.keys, isNot(contains('audio/${y.id}.mp3')));
      }

      test('#107/AK1 the sync asks before Y is lost; until the answer Y and its file stay unchanged', () async {
        final (a, b, cloud, x, y) = await offline91();
        final before = b.library.state.tracks[y.id]!.toJson();
        await b.sync.sync();
        expect(b.library.heldNames, [y.title]);
        expectHeld(b, cloud, y);
        expect(b.library.device.heldTracks, {y.id});
        // the rest is synced: X's deletion has reached b
        expect(b.library.track(x.id), isNull);
        expect(b.sync.status, SyncStatus.idle);
        // the record is the same as before the sync (no new stamp, no deletion)
        await b.sync.sync();
        expect(
          (await _reload(b)).state.tracks[y.id],
          isNull,
          reason: 'held records are not part of the shared state',
        );
        expect(b.library.heldNames, [y.title]);
        final again = await _reload(b);
        expect(again.track(y.id), isNotNull);
        expect(again.heldNames, [y.title]);
        // the record in library.json is unchanged
        final saved =
            (jsonDecode(utf8.decode(b.store.files['library.json']!))
                    as Map)['tracks']
                as Map;
        expect(saved[y.id], before);
        await a.sync.sync();
        expect(a.library.track(y.id), isNull);
      });

      test('#107/AK2 «Keep»: Y stays on B with its file and reaches A and the cloud; X does not come back', () async {
        final (a, b, cloud, x, y) = await offline91();
        await b.sync.sync();
        await b.library.keepHeld();
        expect(b.library.heldNames, isEmpty);
        expect(b.library.device.heldTracks, isEmpty);
        await b.sync.sync();
        await a.sync.sync();
        for (final d in [a, b]) {
          expect(d.library.track(y.id), isNotNull, reason: 'Y on $d');
          expect(d.library.hasFile(y.id), isTrue);
          expect(d.library.track(x.id), isNull, reason: 'X came back');
          expect(d.library.heldNames, isEmpty);
        }
        expect(await a.library.readAudio(a.t(y.id)), sources['y.mp3']);
        expect(cloudState(cloud).tracks[y.id]!.alive, isTrue);
        expect(cloudState(cloud).tracks[x.id], isNull);
        expect(cloud.files.keys, contains('audio/${y.id}.mp3'));
        // a further sync asks nothing
        await b.sync.sync();
        expect(b.library.heldNames, isEmpty);
      });

      test(
        '#107/AK3 «Remove»: Y is deleted on B with its audio file, as before',
        () async {
          final (a, b, cloud, x, y) = await offline91();
          await b.sync.sync();
          await b.library.removeHeld();
          expect(b.library.track(y.id), isNull);
          expect(b.store.files.keys, isNot(contains('Tracks/${y.id}.mp3')));
          expect(b.library.state.tracks[y.id], isNull);
          expect(b.library.heldNames, isEmpty);
          await b.sync.sync();
          await a.sync.sync();
          for (final d in [a, b]) {
            expect(d.library.track(y.id), isNull);
            expect(d.library.track(x.id), isNull);
            expect(d.library.heldNames, isEmpty);
          }
          expect(cloud.files.keys, isNot(contains('audio/${y.id}.mp3')));
          expect((await _reload(b)).track(y.id), isNull);
        },
      );

      test('#107/AK4 a folder: held, then kept with its tracks', () async {
        final (a, b, _, _, y) = await offline91(folder: true);
        final g = b.library.folders.single;
        await b.sync.sync();
        expect(b.library.heldNames, ['G', y.title]);
        expect(b.library.device.heldFolders, {g.id});
        expect(b.library.state.folders[g.id], isNull);
        await b.library.keepHeld();
        await b.sync.sync();
        await a.sync.sync();
        for (final d in [a, b]) {
          expect(d.library.folders.map((f) => f.id), [g.id]);
          expect(
            d.t(d.library.tracks.firstWhere((t) => t.title == 't').id).folderId,
            g.id,
          );
        }
      });

      test('#107/AK4 a folder: removed, its tracks stay', () async {
        final (a, b, _, _, _) = await offline91(folder: true);
        final t = b.library.tracks.firstWhere((t) => t.title == 't');
        await b.sync.sync();
        await b.library.removeHeld();
        expect(b.library.folders, isEmpty);
        await b.sync.sync();
        await a.sync.sync();
        for (final d in [a, b]) {
          expect(d.library.folders, isEmpty);
          expect(d.library.track(t.id), isNotNull);
          expect(d.t(t.id).folderId, isNull);
          expect(d.library.hasFile(t.id), isTrue);
        }
      });

      test('#107/AK5 unanswered: nothing lost, asked again on the next sync, also after a restart or offline', () async {
        final (a, b, cloud, _, y) = await offline91();
        await b.sync.sync();
        expectHeld(b, cloud, y);
        // offline again
        cloud.offline = true;
        await b.sync.sync();
        cloud.offline = false;
        expectHeld(b, cloud, y);
        // restart: a new library and sync on the same store
        final lib = await _reload(b);
        expect(lib.heldNames, [y.title]);
        expect(lib.track(y.id), isNotNull);
        expect(lib.uploadable(lib.track(y.id)!), isFalse);
        final sync = CloudSync(cloud, lib, now: () => clock);
        addTearDown(sync.dispose);
        tick();
        await sync.sync();
        expect(lib.heldNames, [y.title]);
        expect(lib.track(y.id), isNotNull);
        expect(b.store.files['Tracks/${y.id}.mp3'], sources['y.mp3']);
        expect(cloudState(cloud).tracks[y.id], isNull);
        await a.sync.sync();
        expect(a.library.track(y.id), isNull);
        // answered after the restart
        await lib.keepHeld();
        await sync.sync();
        await a.sync.sync();
        expect(a.library.track(y.id), isNotNull);
      });

      test('#107/AK5 a held track changed here is no longer at risk and syncs without a question', () async {
        final (a, b, _, _, y) = await offline91();
        await b.sync.sync();
        tick();
        b.library.editMetadata(y.id, title: 'Y2');
        await b.sync.sync();
        await a.sync.sync();
        expect(b.library.heldNames, isEmpty);
        expect(a.t(y.id).title, 'Y2');
      });

      test('#107/AK5 a held track deleted here before the answer stays deleted with «Keep» and keeps its tombstone with «Remove»', () async {
        for (final keep in [true, false]) {
          final (a, b, _, _, y) = await offline91();
          await b.sync.sync();
          tick();
          b.library.delete({y.id});
          expect(
            b.library.state.tracks[y.id],
            isNull,
            reason: 'held until the next sync',
          );
          keep ? await b.library.keepHeld() : await b.library.removeHeld();
          expect(b.library.track(y.id), isNull);
          await b.sync.sync();
          await a.sync.sync();
          expect(b.library.state.tracks[y.id]!.alive, isFalse, reason: '$keep');
          expect(a.library.track(y.id), isNull);
          expect(b.library.heldNames, isEmpty);
        }
      });

      test(
        '#107/AK6 an ordinary sync and a first sync (#104) ask nothing',
        () async {
          final cloud = InMemoryProvider();
          final a = await device(cloud, 1);
          final b = await device(cloud, 2);
          await a.add('a.mp3');
          await a.sync.sync();
          await b.add('b.mp3');
          await b.sync.sync();
          await a.sync.sync();
          for (final d in [a, b]) {
            expect(d.library.heldNames, isEmpty);
          }
          // a horizon in the cloud; c syncs for the first time with an own track from before it
          final c = await device(cloud, 3);
          final z = await c.add('z.mp3');
          tick();
          a.library.delete({a.library.tracks.first.id});
          await a.sync.sync();
          clock = clock.add(const Duration(days: 91));
          await a.sync.sync();
          expect(
            cloudState(cloud).purged!,
            greaterThan(c.library.state.tracks[z.id]!.latest!),
          );
          await c.sync.sync();
          expect(c.library.heldNames, isEmpty);
          expect(c.library.device.heldTracks, isEmpty);
          expect(c.library.track(z.id), isNotNull);
          await b.sync.sync();
          expect(b.library.heldNames, isEmpty);
        },
      );
    },
  );

  group('#107 held records in the library itself', () {
    /// A library that has synced, with Y and folder G held back and T known to the other side, whose horizon
    /// lies a day ahead of the clock.
    Future<(Library, MemoryFileStore, Track, Track, String, Hlc)> held({
      Duration saveDelay = Duration.zero,
      MemoryFileStore? store,
    }) async {
      final s = store ?? MemoryFileStore();
      final lib = open(s, saveDelay: saveDelay);
      await lib.load();
      sources['y.mp3'] = bytes('audio y');
      sources['t.mp3'] = bytes('audio t');
      final r = await lib.importFiles(['y.mp3', 't.mp3']);
      final y = r.imported.firstWhere((t) => t.title == 'y');
      final t = r.imported.firstWhere((t) => t.title == 't');
      final g = lib.createFolder('G').id;
      lib.flush();
      await lib.markSynced();
      final horizon = Hlc(
        clock.add(const Duration(days: 1)).millisecondsSinceEpoch,
        0,
        'ffffffffffffffff',
      );
      await lib.mergeRemote(
        SharedState(tracks: {t.id: lib.state.tracks[t.id]!}, purged: horizon),
      );
      expect(lib.device.heldTracks, {y.id});
      expect(lib.device.heldFolders, {g});
      return (lib, s, y, t, g, horizon);
    }

    test('#107 nothing held: «Keep» and «Remove» do nothing', () async {
      final lib = open(MemoryFileStore());
      await lib.load();
      var changes = 0;
      var notes = 0;
      lib.onLocalChange = () => changes++;
      lib.addListener(() => notes++);
      await lib.keepHeld();
      await lib.removeHeld();
      expect((changes, notes), (0, 0));
    });

    test('#107 «Keep» after a restart: stamped after the horizon, saved, a sync is requested', () async {
      final (_, store, y, _, g, horizon) = await held();
      final lib = open(store);
      await lib.load();
      expect(lib.device.heldTracks, {y.id});
      var changes = 0;
      lib.onLocalChange = () => changes++;
      await lib.keepHeld();
      expect(changes, 1);
      for (final l in [lib, open(store)]) {
        if (!identical(l, lib)) await l.load();
        expect(l.state.tracks[y.id]!.latest! > horizon, isTrue);
        expect(l.state.folders[g]!.latest! > horizon, isTrue);
        expect(l.device.heldTracks, isEmpty);
        expect(l.device.heldFolders, isEmpty);
      }
    });

    test('#107 «Remove»: files, cache lists and held lists cleaned up, saved at once, other changes kept', () async {
      final (lib, store, y, t, g, _) = await held(
        saveDelay: const Duration(hours: 1),
      );
      store.files['Tracks/${y.id}.artwork'] = bytes('art');
      await lib.setKeepOffline({y.id}, true);
      // a change of another track not yet saved
      lib.updateSettings(t.id, const PlaybackSettings(speed: 0.5));
      await lib.removeHeld();
      expect(store.files.keys.where((k) => k.contains(y.id)), isEmpty);
      expect(lib.device.keepOffline, isNot(contains(y.id)));
      expect(lib.device.heldTracks, isEmpty);
      expect(lib.device.heldFolders, isEmpty);
      expect(lib.track(t.id)!.settings.speed, 0.5);
      expect(lib.storage!.used, (await store.storageInfo()).used);
      final again = open(store);
      await again.load();
      expect(again.track(y.id), isNull);
      expect(again.state.folders[g], isNull);
      expect(again.device.heldTracks, isEmpty);
      lib.dispose();
    });

    test(
      '#107 «Remove» tells the UI even when the storage cannot be measured',
      () async {
        final (lib, _, y, _, _, _) = await held(store: _NoStorageInfo());
        var notes = 0;
        lib.addListener(() => notes++);
        await lib.removeHeld();
        expect(lib.track(y.id), isNull);
        expect(notes, greaterThan(0));
      },
    );

    test(
      '#107 after a restart only held records still there and alive stay held',
      () async {
        final (lib, store, y, _, g, _) = await held();
        lib.deleteFolder(g);
        final again = open(store);
        await again.load();
        expect(again.device.heldTracks, {y.id});
        expect(again.device.heldFolders, isEmpty);
        // ids without a record (device.json from elsewhere) are dropped
        final d = (jsonDecode(
          utf8.decode(store.files[DeviceSettings.fileName]!),
        ) as Map).cast<String, Object?>();
        d['heldTracks'] = [y.id, 'nope'];
        d['heldFolders'] = ['nope'];
        store.files[DeviceSettings.fileName] = bytes(jsonEncode(d));
        final third = open(store);
        await third.load();
        expect(third.device.heldTracks, {y.id});
        expect(third.device.heldFolders, isEmpty);
      },
    );

    test(
      '#107 a missing or unreadable library.json leaves nothing held',
      () async {
        for (final contents in [null, bytes('{damaged')]) {
          final (_, store, y, _, _, _) = await held();
          if (contents == null) {
            store.files.remove(Library.indexName);
          } else {
            store.files[Library.indexName] = contents;
          }
          final again = open(store);
          await again.load();
          expect(again.device.heldTracks, isEmpty, reason: '$contents');
          expect(again.device.heldFolders, isEmpty);
          expect(again.state.tracks[y.id], isNull);
        }
      },
    );
  });
}

/// A store whose used storage cannot be measured.
class _NoStorageInfo extends MemoryFileStore {
  @override
  Future<StorageInfo> storageInfo() => Future.error(StateError('no info'));
}

/// A library on [store] with the test clock.
Library open(MemoryFileStore store, {Duration saveDelay = Duration.zero}) =>
    Library(
      store,
      probe: (_) => 2.5,
      readSource: (s) async => sources[s],
      now: () => clock,
      saveDelay: saveDelay,
    );

/// The library of [d] opened again on its store, as after a restart.
Future<Library> _reload(Device d) async {
  final lib = Library(
    d.store,
    probe: (_) => 2.5,
    readSource: (s) async => sources[s],
    now: () => clock,
    saveDelay: Duration.zero,
  );
  await lib.load();
  return lib;
}
