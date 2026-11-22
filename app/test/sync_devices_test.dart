// #53: sync with one file per device and several sources (docs/KONZEPT-SYNC.md, M1). Every test runs
// against InMemoryProviders and libraries in memory, never a real account or the real library. Random
// tests use fixed seeds and can be repeated.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/library/stamps.dart' show sameJson;
import 'package:woodshed_player/sync/cloud_provider.dart';
import 'package:woodshed_player/sync/in_memory_provider.dart';
import 'package:woodshed_player/sync/sync_engine.dart';
import 'package:woodshed_player/sync/sync_service.dart';
import 'package:woodshed_player/ui/messages.dart';

import 'fakes.dart';
import 'sync_test.dart' show bytes, sources, tick;
import 'sync_test.dart' as base show clock;

/// One storage as one device sees it: records the requests of this device only.
class Tap implements CloudProvider {
  Tap(this.inner);
  final CloudProvider inner;
  final requests = <String>[];

  @override
  Future<List<CloudEntry>> list(String prefix) {
    requests.add('list $prefix');
    return inner.list(prefix);
  }

  @override
  Future<CloudFile?> get(String name) {
    requests.add('get $name');
    return inner.get(name);
  }

  @override
  Future<String> put(
    String name,
    Uint8List bytes, {
    String? ifVersion,
    bool ifAbsent = false,
  }) {
    requests.add('put $name');
    return inner.put(name, bytes, ifVersion: ifVersion, ifAbsent: ifAbsent);
  }

  @override
  Future<void> delete(String name) {
    requests.add('delete $name');
    return inner.delete(name);
  }

  @override
  Future<CloudQuota> quota() => inner.quota();
}

/// Another device writes `format.json` right after every write of it through this view.
class Racing extends Tap {
  Racing(InMemoryProvider super.inner, this.winner);
  final String winner;

  @override
  Future<String> put(
    String name,
    Uint8List bytes, {
    String? ifVersion,
    bool ifAbsent = false,
  }) async {
    final v = await super.put(name, bytes);
    if (name == CloudSync.formatName) {
      (inner as InMemoryProvider).putDirect(
        name,
        CloudSync.encodeFormat(winner),
      );
    }
    return v;
  }
}

/// A device with its own library and one or more sources.
class Node {
  Node(List<CloudProvider> storages, int seed, {bool eager = true}) {
    library = Library(
      store,
      probe: (_) => 2.5,
      readSource: (s) async => sources[s],
      now: () => base.clock,
      saveDelay: Duration.zero,
      random: Random(seed),
    );
    taps = [for (final s in storages) Tap(s)];
    sync = CloudSync(
      taps.first,
      library,
      more: taps.skip(1).toList(),
      eagerDownload: eager,
      now: () => base.clock,
      changeDelay: const Duration(days: 1),
      random: Random(seed + 1000),
    );
  }

  final store = MemoryFileStore();
  late final Library library;
  late final List<Tap> taps;
  late final CloudSync sync;

  String get id => library.device.deviceId;
  String get file => CloudSync.deviceName(id);

  Future<Track> add(String name) async {
    sources.putIfAbsent(name, () => bytes('audio $name'));
    final r = await library.importFiles([name]);
    return [...r.imported, ...r.duplicates].single;
  }

  Track t(String id) => library.track(id)!;
}

Future<Node> node(
  List<CloudProvider> storages,
  int seed, {
  bool eager = true,
}) async {
  final n = Node(storages, seed, eager: eager);
  await n.library.load();
  addTearDown(n.sync.dispose);
  return n;
}

/// A storage without conditional writes (#53/AK3), as the engine must expect.
InMemoryProvider plain() => InMemoryProvider(conditional: false);

/// One random change on [n] (tracks, metadata, loops, folders, deletions, exclusions).
Future<void> randomChange(Random r, Node n) async {
  final l = n.library;
  final tracks = l.tracks;
  final t = tracks.isEmpty ? null : tracks[r.nextInt(tracks.length)];
  switch (r.nextInt(8)) {
    case 0 || 1:
      await n.add(['a.mp3', 'b.mp3', 'c.mp3', 'd.mp3'][r.nextInt(4)]);
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
          loopEnd: s + 1,
        ),
      );
    case 4 when t != null:
      l.delete({t.id});
    case 5:
      final f = l.createFolder('F${r.nextInt(3)}');
      if (t != null) l.moveTracks({t.id}, f.id);
    case 6 when l.folders.isNotEmpty:
      l.deleteFolder(l.folders[r.nextInt(l.folders.length)].id);
    case _ when t != null:
      l.setNoUpload({t.id}, r.nextBool());
  }
}

/// Every device has the same state and the same tracks.
void expectConverged(List<Node> nodes, String reason) {
  final ref = nodes.first.library.state.toJson();
  for (final n in nodes) {
    expect(sameJson(n.library.state.toJson(), ref), isTrue, reason: reason);
    expect(
      n.library.tracks.map((t) => t.id).toSet(),
      nodes.first.library.tracks.map((t) => t.id).toSet(),
      reason: reason,
    );
  }
}

int devicePuts(InMemoryProvider c) =>
    c.requests.where((r) => r.startsWith('put devices/')).length;

void main() {
  setUp(() {
    base.clock = DateTime.utc(2026, 11, 1);
    sources.clear();
  });

  group('#53/AK1 a device writes only its own file', () {
    test('random changes on three devices: every write under devices/ is the own file', () async {
      final r = Random(5301);
      final cloud = plain();
      final nodes = [
        for (var i = 0; i < 3; i++) await node([cloud], 10 + i),
      ];
      for (var step = 0; step < 60; step++) {
        tick(r.nextInt(2000));
        final n = nodes[r.nextInt(3)];
        r.nextInt(3) == 0 ? await n.sync.sync() : await randomChange(r, n);
      }
      for (final n in nodes) {
        await n.sync.sync();
      }
      for (final n in nodes) {
        final writes = n.taps.single.requests.where(
          (q) =>
              q.startsWith('put devices/') || q.startsWith('delete devices/'),
        );
        expect(writes, isNotEmpty);
        expect(writes, everyElement('put ${n.file}'));
        expect(
          n.taps.single.requests.where((q) => q.startsWith('put backup/')),
          everyElement(startsWith('put backup/${n.id}/')),
        );
      }
      expect(cloud.files.keys.where((k) => k.startsWith('devices/')).toSet(), {
        for (final n in nodes) n.file,
      });
    });

    test('the device file holds the state, the device, a generation and the time of writing', () async {
      final cloud = plain();
      final a = await node([cloud], 1);
      final t = await a.add('a.mp3');
      await a.sync.sync();
      final j = jsonDecode(utf8.decode(cloud.files[a.file]!)) as Map;
      expect(j['deviceId'], a.id);
      expect(j['generation'], 1);
      expect(j['written'], base.clock.millisecondsSinceEpoch);
      expect(j['formatVersion'], SharedState.formatVersion);
      expect((j['tracks'] as Map).keys, [t.id]);
      expect(a.file, 'devices/${a.id}.json');
    });
  });

  group('#53/AK2 devices changing at the same time converge in any order (random, fixed seeds)', () {
    for (final count in [2, 3]) {
      test(
        '$count devices, writes interleaved, synced in random order',
        () async {
          final stats = [0, 0]; // tracks, interleaved writes
          for (var seed = 0; seed < 20; seed++) {
            final r = Random(5302 + seed * 7 + count);
            final cloud = plain();
            final nodes = [
              for (var i = 0; i < count; i++)
                await node([cloud], seed * 10 + i),
            ];
            // while one device writes its file, another one syncs (at the same time)
            var inside = false;
            cloud.beforePut = (name) async {
              if (inside || !name.startsWith('devices/') || r.nextInt(3) > 0) {
                return;
              }
              inside = true;
              stats[1]++;
              // another device than the one writing (its own sync would wait for itself)
              final others = [
                for (final n in nodes)
                  if (n.file != name) n,
              ];
              final other = others[r.nextInt(others.length)];
              await randomChange(r, other);
              await other.sync.sync();
              inside = false;
            };
            for (var step = 0; step < 25; step++) {
              tick(r.nextInt(3) == 0 ? 0 : r.nextInt(2000));
              final n = nodes[r.nextInt(count)];
              r.nextInt(3) == 0
                  ? await n.sync.sync()
                  : await randomChange(r, n);
            }
            cloud.beforePut = null;
            for (var round = 0; round < 2; round++) {
              for (final n in [...nodes]..shuffle(r)) {
                await n.sync.sync();
              }
            }
            expectConverged(nodes, 'seed $seed');
            stats[0] += nodes.first.library.tracks.length;
            for (final n in nodes) {
              expect(n.sync.status, SyncStatus.idle, reason: 'seed $seed');
            }
            // idempotent: another round writes nothing
            final writes = devicePuts(cloud);
            for (final n in nodes) {
              await n.sync.sync();
            }
            expect(devicePuts(cloud), writes, reason: 'seed $seed');
          }
          expect(stats.every((s) => s > 5), isTrue, reason: '$stats');
        },
      );
    }

    test('the order of the files does not matter: merging them in every order gives one state', () async {
      final cloud = plain();
      final nodes = [
        for (var i = 0; i < 3; i++) await node([cloud], 20 + i),
      ];
      final r = Random(5322);
      for (var step = 0; step < 30; step++) {
        tick(r.nextInt(1500));
        final n = nodes[r.nextInt(3)];
        r.nextInt(4) == 0 ? await n.sync.sync() : await randomChange(r, n);
      }
      for (final n in nodes) {
        await n.sync.sync();
      }
      final files = [
        for (final e in cloud.files.entries)
          if (e.key.startsWith('devices/'))
            CloudSync.decodeDevice(e.key, e.value).state,
      ];
      expect(files, hasLength(3));
      final ref = files.reduce((a, b) => a.merge(b)).toJson();
      for (var k = 0; k < 6; k++) {
        final order = [...files]..shuffle(r);
        expect(
          sameJson(order.reduce((a, b) => a.merge(b)).toJson(), ref),
          isTrue,
        );
      }
    });
  });

  group('#53/AK3 a storage without conditional writes', () {
    test(
      'the in-memory storage without versions refuses conditional writes',
      () async {
        final c = plain();
        expect(await c.put('x', bytes('1')), '');
        expect((await c.get('x'))!.version, '');
        expect((await c.list('x')).single.version, '');
        await expectLater(
          c.put('x', bytes('2'), ifAbsent: true),
          throwsA(isA<UnsupportedError>()),
        );
        await expectLater(
          c.put('x', bytes('2'), ifVersion: ''),
          throwsA(isA<UnsupportedError>()),
        );
        c.putDirect('y', bytes('3'));
        expect(c.versionOf('y'), '');
      },
    );

    test('two devices sync everything, audio included, without a single conditional write', () async {
      final cloud = plain();
      final a = await node([cloud], 1);
      final b = await node([cloud], 2);
      final t = await a.add('a.mp3');
      final u = await b.add('b.mp3');
      for (final n in [a, b, a]) {
        await n.sync.sync();
      }
      for (final n in [a, b]) {
        expect(n.sync.status, SyncStatus.idle);
        expect(n.sync.pending, isEmpty);
        expect(n.library.hasFile(t.id) && n.library.hasFile(u.id), isTrue);
      }
      expectConverged([a, b], 'two devices');
      tick();
      b.library.editMetadata(t.id, title: 'von B', artist: null);
      await b.sync.sync();
      await a.sync.sync();
      expect(a.t(t.id).title, 'von B');
    });
  });

  group('#53/AK4 several sources and a bridge', () {
    test('A only with X, C only with B, B with both: a change on C arrives at A and back', () async {
      final x = plain(); // the cloud
      final y = plain(); // what B answers to its paired device C (#56)
      final a = await node([x], 1);
      final b = await node([x, y], 2);
      final c = await node([y], 3);
      expect(b.sync.sources, hasLength(2));
      await b.sync.sync(); // B sets up both storages with one library ID
      final t = await c.add('c.mp3');
      for (final n in [c, b, a]) {
        await n.sync.sync();
      }
      expect(a.library.track(t.id), isNotNull);
      expect(
        a.library.hasFile(t.id),
        isTrue,
        reason: 'the audio file travels along',
      );
      expect(
        x.files.keys,
        isNot(contains(c.file)),
        reason: 'C never wrote to X',
      );
      tick();
      a.library.editMetadata(t.id, title: 'von A', artist: null);
      for (final n in [a, b, c]) {
        await n.sync.sync();
      }
      expect(c.t(t.id).title, 'von A');
      expect(a.library.device.libraryId, c.library.device.libraryId);
      expectConverged([a, b, c], 'bridge');
    });

    test(
      'one source offline: the others still sync, a retry is planned',
      () async {
        final x = plain();
        final y = plain();
        final a = await node([x], 1);
        final b = await node([x, y], 2);
        final t = await a.add('a.mp3');
        await a.sync.sync();
        y.offline = true;
        await b.sync.sync();
        expect(b.library.track(t.id), isNotNull);
        expect(b.sync.status, SyncStatus.idle);
        expect(b.sync.nextRetry, isNotNull);
        y.offline = false;
        await b.sync.sync();
        expect(y.files.keys, contains(b.file));
        expect(y.files.keys, contains('audio/${t.id}.mp3'));
        x.offline = true;
        y.offline = true;
        await b.sync.sync();
        expect(b.sync.status, SyncStatus.offline);
      },
    );

    test('sources come and go (a paired device connects and leaves)', () async {
      final x = plain();
      final y = plain();
      final b = await node([x], 2);
      final t = await b.add('b.mp3');
      final peer = Tap(y);
      b.sync.addSource(peer);
      b.sync.addSource(peer); // once only
      expect(b.sync.sources, hasLength(2));
      expect(b.sync.provider, b.taps.first);
      await b.sync.sync();
      expect(y.files.keys, containsAll([b.file, 'audio/${t.id}.mp3']));
      b.sync.removeSource(peer);
      expect(b.sync.sources, [b.taps.first]);
      tick();
      b.library.editMetadata(t.id, title: 'neu', artist: null);
      await b.sync.sync();
      expect(peer.requests.where((q) => q.startsWith('put')).length, 3);
    });

    test('fetchAudio tries the next source when the first one fails', () async {
      final x = plain();
      final y = plain();
      final a = await node([y], 1);
      final t = await a.add('a.mp3');
      await a.sync.sync();
      final b = await node([x, y], 2, eager: false);
      await b.sync.sync();
      expect(b.library.hasFile(t.id), isFalse);
      expect(b.sync.inCloud(t.id), isTrue);
      x.offline = true;
      expect(await b.sync.fetchAudio(t), isTrue);
      expect(b.library.hasFile(t.id), isTrue);
    });
  });

  group('#53/AK5 an unreadable device file or a damaged audio file', () {
    test('an unreadable device file: no error, the rest is merged, read again later', () async {
      final cloud = plain();
      final a = await node([cloud], 1);
      final b = await node([cloud], 2);
      final c = await node([cloud], 3);
      final ta = await a.add('a.mp3');
      final tb = await b.add('b.mp3');
      await a.sync.sync();
      await b.sync.sync();
      final good = cloud.files[a.file]!;
      cloud.putDirect(a.file, good.sublist(0, good.length ~/ 2));
      await c.sync.sync();
      expect(c.sync.status, SyncStatus.idle);
      expect(c.sync.failed, isEmpty);
      expect(c.library.lastError, isNull);
      expect(c.library.track(tb.id), isNotNull, reason: 'B\'s file is merged');
      // A's track still reaches C: B merged it before the damage
      expect(c.library.track(ta.id), isNotNull);
      expect(
        cloud.files[a.file],
        hasLength(good.length ~/ 2),
        reason: 'left as it is',
      );
      // later: the file is readable again and is read again
      tick();
      a.library.editMetadata(ta.id, title: 'nur in A', artist: null);
      await a.sync.sync(); // A writes its file anew
      await c.sync.sync();
      expect(c.t(ta.id).title, 'nur in A');
    });

    test('an audio file with the wrong hash: no error status, tried again, stored once it is right', () async {
      final cloud = plain();
      final a = await node([cloud], 1);
      final t = await a.add('a.mp3');
      await a.sync.sync();
      final good = cloud.files['audio/${t.id}.mp3']!;
      cloud.putDirect('audio/${t.id}.mp3', bytes('wrong contents'));
      final b = await node([cloud], 2);
      await b.sync.sync();
      expect(
        b.library.track(t.id),
        isNotNull,
        reason: 'the state is merged anyway',
      );
      expect(b.library.hasFile(t.id), isFalse);
      expect(b.sync.status, SyncStatus.idle);
      expect(b.sync.pending.single.key, 'down:${t.id}');
      expect(b.sync.nextRetry, isNotNull);
      cloud.putDirect('audio/${t.id}.mp3', good);
      tick(10 * 1000);
      await b.sync.sync();
      expect(b.library.hasFile(t.id), isTrue);
      expect(b.sync.pending, isEmpty);
    });
  });

  group('#53/AK6 conflict copies of device files', () {
    // name patterns of the storages (sync_engine.dart, parseDeviceName)
    const id = '0123456789abcdef';
    const copies = {
      'Google Drive for desktop': 'devices/$id (1).json',
      'OneDrive API (rename)': 'devices/$id 1.json',
      'OneDrive client (device name)': 'devices/$id-Laptop.json',
      'iCloud': 'devices/$id 2.json',
      'conflicted copy':
          "devices/$id (Laptop's conflicted copy 2026-11-22).json",
      'Syncthing': 'devices/$id.sync-conflict-20261122-101010-ABCDEFG.json',
    };

    test('every name pattern is recognised as a copy of the device; other names are not', () {
      for (final e in copies.entries) {
        final k = CloudSync.parseDeviceName(e.value);
        expect(k, isNotNull, reason: e.key);
        expect(k!.deviceId, id, reason: e.key);
        expect(k.copy, isTrue, reason: e.key);
      }
      expect(CloudSync.parseDeviceName('devices/$id.json'), (
        deviceId: id,
        copy: false,
      ));
      for (final other in [
        'devices/${id}0.json', // 17 hex digits: not a device
        'devices/0123.json',
        'devices/$id.json.tmp',
        'devices/sub/$id.json',
        'format.json',
        'backup/$id/state-1.json',
        'devices/${id.toUpperCase()}.json',
      ]) {
        expect(CloudSync.parseDeviceName(other), isNull, reason: other);
      }
    });

    for (final e in copies.entries) {
      test('${e.key}: the copy is read, merged and removed', () async {
        final cloud = plain();
        final a = await node([cloud], 1);
        final other = await node([plain()], 9);
        final t = await other.add('x.mp3');
        // the storage kept the other version of a device file under a new name
        final name = e.value.replaceFirst(id, a.id);
        cloud.putDirect(
          name,
          CloudSync.encodeDevice(other.library.state, a.id, 3, base.clock),
        );
        await a.sync.sync();
        expect(a.library.track(t.id), isNotNull, reason: e.key);
        expect(cloud.files.keys, isNot(contains(name)), reason: e.key);
        expect(cloud.files.keys, contains(a.file));
        final own = CloudSync.decodeDevice(a.file, cloud.files[a.file]!);
        expect(
          own.state.tracks.keys,
          contains(t.id),
          reason: 'kept in the own file',
        );
      });
    }

    test('a copy of another device\'s file is merged and removed too; that file stays', () async {
      final cloud = plain();
      final a = await node([cloud], 1);
      final b = await node([cloud], 2);
      final tb = await b.add('b.mp3');
      await b.sync.sync();
      final other = await node([plain()], 9);
      final tc = await other.add('c.mp3');
      final copy = 'devices/${b.id} (1).json';
      cloud.putDirect(
        copy,
        CloudSync.encodeDevice(other.library.state, b.id, 1, base.clock),
      );
      await a.sync.sync();
      expect(a.library.track(tb.id), isNotNull);
      expect(a.library.track(tc.id), isNotNull);
      expect(cloud.files.keys, isNot(contains(copy)));
      expect(cloud.files.keys, contains(b.file));
    });

    test(
      'an unreadable copy or one that changed since reading stays',
      () async {
        final cloud = plain();
        final a = await node([cloud], 1);
        final damaged = 'devices/${a.id} (1).json';
        cloud.putDirect(damaged, bytes('{"formatVersion": 2'));
        final other = await node([plain()], 9);
        await other.add('x.mp3');
        final changing = 'devices/${a.id} 2.json';
        cloud.putDirect(
          changing,
          CloudSync.encodeDevice(other.library.state, a.id, 1, base.clock),
        );
        cloud.beforePut = (name) async {
          if (name == a.file) {
            // the storage writes the copy anew before it would be removed
            // (same length, other content: compared byte by byte)
            cloud.putDirect(
              changing,
              CloudSync.encodeDevice(other.library.state, a.id, 2, base.clock),
            );
          }
        };
        await a.sync.sync();
        expect(cloud.files.keys, containsAll([damaged, changing]));
        cloud.beforePut = null;
        await a.sync.sync();
        expect(cloud.files.keys, isNot(contains(changing)));
        expect(cloud.files.keys, contains(damaged));
        expect(a.sync.status, SyncStatus.idle);
      },
    );
  });

  group('#53/AK8 a device file not written for 180 days is removed without data loss', () {
    test(
      'after 180 days: merged, removed, its tracks stay (with audio)',
      () async {
        final cloud = plain();
        final a = await node([cloud], 1);
        final gone = await node([cloud], 2);
        final t = await gone.add('g.mp3');
        await gone.sync.sync(); // the device is never seen again
        base.clock = base.clock.add(const Duration(days: 179));
        await a.sync.sync();
        expect(cloud.files.keys, contains(gone.file), reason: 'not yet');
        expect(a.library.track(t.id), isNotNull);
        base.clock = base.clock.add(const Duration(days: 1));
        await a.sync.sync();
        expect(cloud.files.keys, isNot(contains(gone.file)));
        expect(a.library.track(t.id), isNotNull);
        expect(a.library.hasFile(t.id), isTrue);
        expect(
          CloudSync.decodeDevice(
            a.file,
            cloud.files[a.file]!,
          ).state.tracks[t.id]?.alive,
          isTrue,
        );
        // a new device still gets everything
        final c = await node([cloud], 3);
        await c.sync.sync();
        expect(c.library.track(t.id), isNotNull);
        expect(c.library.hasFile(t.id), isTrue);
      },
    );

    test('a device that only had nothing to say writes its file again before it looks gone', () async {
      final cloud = plain();
      final a = await node([cloud], 1);
      final b = await node([cloud], 2);
      final t = await b.add('b.mp3');
      await b.sync.sync();
      await a.sync.sync();
      for (var day = 0; day < 200; day += 20) {
        base.clock = base.clock.add(const Duration(days: 20));
        await b.sync.sync(); // nothing changes on b
        await a.sync.sync();
        expect(cloud.files.keys, contains(b.file), reason: 'day $day');
      }
      expect(a.library.track(t.id), isNotNull);
      final writes = b.taps.single.requests.where((q) => q == 'put ${b.file}');
      expect(writes.length, lessThan(10), reason: 'not on every sync');
    });

    test('an unreadable old file is not removed; a file without time of writing neither', () async {
      final cloud = plain();
      final a = await node([cloud], 1);
      const damaged = 'devices/00000000000000aa.json';
      const timeless = 'devices/00000000000000bb.json';
      cloud.putDirect(damaged, bytes('{'));
      final j = (jsonDecode(
        utf8.decode(
          CloudSync.encodeDevice(
            SharedState.empty,
            '00000000000000bb',
            1,
            base.clock,
          ),
        ),
      ) as Map)..remove('written');
      cloud.putDirect(timeless, bytes(jsonEncode(j)));
      base.clock = base.clock.add(const Duration(days: 400));
      await a.sync.sync();
      expect(cloud.files.keys, containsAll([damaged, timeless]));
    });
  });

  group('#53/AK9 format.json', () {
    test(
      'the first device creates it with a library ID; the others take it over',
      () async {
        final cloud = plain();
        final a = await node([cloud], 1);
        expect(a.library.device.libraryId, isNull);
        await a.sync.sync();
        final f =
            jsonDecode(utf8.decode(cloud.files[CloudSync.formatName]!)) as Map;
        expect(f['formatVersion'], SharedState.formatVersion);
        expect(f['libraryId'], matches(RegExp(r'^[0-9a-f]{32}$')));
        expect(a.library.device.libraryId, f['libraryId']);
        final b = await node([cloud], 2);
        await b.sync.sync();
        expect(b.library.device.libraryId, f['libraryId']);
        // kept in device.json
        expect((await DeviceSettings.load(b.store)).libraryId, f['libraryId']);
        final puts = cloud.countOf('put ${CloudSync.formatName}');
        await a.sync.sync();
        await b.sync.sync();
        expect(cloud.countOf('put ${CloudSync.formatName}'), puts);
      },
    );

    test('a higher version: nothing is written, the message asks to update the app', () async {
      final cloud = plain();
      final a = await node([cloud], 1);
      await a.add('a.mp3');
      cloud.putDirect(
        CloudSync.formatName,
        bytes(
          jsonEncode({
            'formatVersion': SharedState.formatVersion + 1,
            'libraryId': 'x',
          }),
        ),
      );
      await a.sync.sync();
      expect(a.sync.status, SyncStatus.tooNew);
      expect(
        cloud.requests.where(
          (q) => q.startsWith('put') || q.startsWith('delete'),
        ),
        isEmpty,
      );
      final m = a.library.lastError;
      expect(m, isA<CloudStateTooNew>());
      for (final loc in AppLocalizations.supportedLocales) {
        expect(libraryMessageText(lookupAppLocalizations(loc), m!), isNotEmpty);
      }
      expect(
        libraryMessageText(lookupAppLocalizations(const Locale('en')), m!),
        contains('update the app'),
      );
      expect(
        libraryMessageText(lookupAppLocalizations(const Locale('de')), m),
        contains('App'),
      );
    });

    test('another library ID: nothing is merged or written', () async {
      final cloud = plain();
      final a = await node([cloud], 1);
      await a.add('a.mp3');
      await a.sync.sync();
      // another library took the storage over
      final other = plain();
      final b = await node([other], 2);
      final tb = await b.add('b.mp3');
      await b.sync.sync();
      for (final e in other.files.entries) {
        cloud.putDirect(e.key, e.value);
      }
      tick();
      await a.add('neu.mp3'); // not uploaded to a storage of another library
      final before = a.library.state.toJson();
      final requests = cloud.requests.length;
      await a.sync.sync();
      expect(a.sync.status, SyncStatus.foreignLibrary);
      expect(a.library.track(tb.id), isNull);
      expect(sameJson(a.library.state.toJson(), before), isTrue);
      expect(
        cloud.requests
            .skip(requests)
            .where((q) => q.startsWith('put') || q.startsWith('delete')),
        isEmpty,
      );
      // with a second source of its own library the rest still syncs
      final mine = plain();
      a.sync.addSource(mine);
      await a.sync.sync();
      expect(mine.files.keys, contains(a.file));
      expect(a.sync.status, SyncStatus.foreignLibrary);
    });

    test(
      'a damaged or older format.json is written again with the own library ID',
      () async {
        final cloud = plain();
        final a = await node([cloud], 1);
        await a.sync.sync();
        final id = a.library.device.libraryId;
        for (final f in [
          bytes('{damaged'),
          bytes('[]'),
          bytes(jsonEncode({'formatVersion': 1, 'libraryId': id})),
          bytes(jsonEncode({'formatVersion': SharedState.formatVersion})),
          bytes(
            jsonEncode({
              'formatVersion': SharedState.formatVersion,
              'libraryId': '',
            }),
          ),
        ]) {
          cloud.putDirect(CloudSync.formatName, f);
          await a.sync.sync();
          expect(a.sync.status, SyncStatus.idle, reason: utf8.decode(f));
          final j = jsonDecode(
            utf8.decode(cloud.files[CloudSync.formatName]!),
          ) as Map;
          expect(j['libraryId'], id, reason: utf8.decode(f));
          expect(j['formatVersion'], SharedState.formatVersion);
        }
      },
    );

    test('two devices create it at once: the one stored wins before anything is merged', () async {
      final cloud = plain();
      final a = await node([Racing(cloud, 'b' * 32)], 1);
      await a.sync.sync();
      expect(
        a.library.device.libraryId,
        'b' * 32,
        reason: 'read back after writing',
      );
      expect(a.sync.status, SyncStatus.idle);
      // a device that already belongs to a library does not take another one over
      final c = await node([plain()], 3);
      await c.library.setLibraryId('d' * 32);
      final fresh = plain();
      c.sync.addSource(Racing(fresh, 'e' * 32));
      await c.sync.sync();
      expect(c.sync.status, SyncStatus.foreignLibrary);
      expect(c.library.device.libraryId, 'd' * 32);
      expect(fresh.files.keys, isNot(contains(c.file)));
    });
  });

  group('#53 rules of the engine (found by mutation testing)', () {
    test('audio waits until the state of that source got through', () async {
      final cloud = plain();
      final a = await node([cloud], 1);
      final t = await a.add('a.mp3');
      cloud.abortPut = (name) => name == a.file;
      await a.sync.sync();
      expect(cloud.files.keys, isNot(contains('audio/${t.id}.mp3')));
      expect(a.sync.pending.map((x) => x.key), ['state']);
      expect(a.sync.pending.single.attempts, 1);
      expect(a.sync.pending.single.lastError, isA<CloudError>());
    });

    test('a state that keeps failing is given up after maxAttempts', () async {
      final cloud = plain();
      final a = await node([cloud], 1);
      await a.add('a.mp3');
      cloud.abortPut = (name) => name == a.file;
      for (var i = 0; i < 12; i++) {
        await a.sync.sync();
        tick(10 * 60 * 1000);
      }
      expect(cloud.countOf('put ${a.file}'), a.sync.maxAttempts);
      expect(a.sync.status, SyncStatus.failed);
      expect(a.sync.failed.single.key, 'state');
    });

    test('connection lost after the state: offline, retry planned', () async {
      final cloud = plain();
      final a = await node([cloud], 1);
      await a.add('a.mp3');
      cloud.beforePut = (name) async {
        if (name == a.file) cloud.offline = true; // the put still lands
      };
      await a.sync.sync();
      expect(cloud.files.keys, contains(a.file));
      expect(a.sync.status, SyncStatus.offline);
      expect(a.sync.nextRetry, isNotNull);
    });

    test(
      'a source offline again and again: retries with growing delay, then stop',
      () async {
        final x = plain();
        final y = plain()..offline = true;
        final n = Node([x, y], 2);
        await n.library.load();
        final s = CloudSync(
          n.taps.first,
          n.library,
          more: [n.taps.last],
          maxOfflineRetries: 2,
          now: () => base.clock,
        );
        addTearDown(s.dispose);
        addTearDown(n.sync.dispose);
        await s.sync();
        expect(s.nextRetry, s.backoffBase);
        await s.sync();
        expect(
          s.nextRetry,
          s.backoffBase * 2,
          reason: 'the second retry is the last',
        );
        await s.sync();
        expect(s.nextRetry, isNull);
        expect(s.status, SyncStatus.idle, reason: 'x got through');
      },
    );

    test('an unreadable own file is kept as backup and written anew; others are not', () async {
      final cloud = plain();
      final a = await node([cloud], 1);
      await a.add('a.mp3');
      final damaged = bytes('{"formatVersion": 2, "tracks": 7');
      cloud.putDirect(a.file, damaged);
      cloud.putDirect('devices/00000000000000aa.json', bytes('{"other": 1'));
      await a.sync.sync();
      expect(cloud.files[CloudSync.backupName(a.id, 1)], damaged);
      expect(
        CloudSync.decodeDevice(a.file, cloud.files[a.file]!).generation,
        1,
      );
    });

    test('the own file is written again exactly after refreshAfter', () async {
      final cloud = plain();
      final a = await node([cloud], 1);
      await a.sync.sync();
      final writes = cloud.countOf('put ${a.file}');
      base.clock = base.clock.add(
        CloudSync.refreshAfter - const Duration(milliseconds: 1),
      );
      await a.sync.sync();
      expect(cloud.countOf('put ${a.file}'), writes);
      base.clock = base.clock.add(const Duration(milliseconds: 1));
      await a.sync.sync();
      expect(cloud.countOf('put ${a.file}'), writes + 1);
    });

    test('a time of writing of 0 is the epoch', () {
      final j = (jsonDecode(
        utf8.decode(
          CloudSync.encodeDevice(
            SharedState.empty,
            '00000000000000aa',
            1,
            base.clock,
          ),
        ),
      ) as Map)..['written'] = 0;
      final f = CloudSync.decodeDevice(
        'devices/00000000000000aa.json',
        bytes(jsonEncode(j)),
      );
      expect(f.written, DateTime.utc(1970));
    });
  });

  group('#53/AK10 without a chosen sync it stays NoSync', () {
    test(
      'NoSync sends nothing and knows no storage (the tests of #37 stay green)',
      () async {
        final s = NoSync();
        await s.start();
        s.resumed();
        s.localChanged();
        await s.syncNow();
        expect(s.status, SyncStatus.off);
        expect(s.inCloud('x'), isFalse);
      },
    );
  });
}
