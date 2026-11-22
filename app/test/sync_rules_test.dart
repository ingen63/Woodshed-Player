// #61: rules of the sync engine (sync_engine.dart, #37, #53 and #65), one per test; found by mutation testing
// (make mutants). Every test runs against the InMemoryProvider and libraries in memory, never a real
// account or the real library. Tests about timers run on the fake clock of testWidgets: a timer fires
// exactly when the test moves the clock, never because the machine is slow.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/sync/in_memory_provider.dart';
import 'package:woodshed_player/sync/sync_engine.dart';
import 'package:woodshed_player/sync/sync_service.dart';

import 'fakes.dart';
import 'sync_test.dart'
    show Device, bytes, cloudGeneration, device, ownJson, ownName, tick;

/// How often the device files were listed (once per sync that reads the state).
int _stateReads(InMemoryProvider c) =>
    c.countOf('list ${CloudSync.devicesPrefix}');

/// The device file of [d] with this generation counter.
Uint8List _withGeneration(Device d, Object? generation) {
  final j = (jsonDecode(
    utf8.decode(
      CloudSync.encodeDevice(
        d.library.state,
        d.library.device.deviceId,
        1,
        DateTime.utc(2026),
      ),
    ),
  ) as Map)..['generation'] = generation;
  return bytes(jsonEncode(j));
}

/// The device file of a library outside a [Device].
Map<String, Object?> _fileOf(InMemoryProvider c, Library l) => (jsonDecode(
  utf8.decode(c.files[CloudSync.deviceName(l.device.deviceId)]!),
) as Map).cast();

/// A device whose engine the test disposes itself (no tear-down of [device]).
Future<Device> _ownDevice(InMemoryProvider cloud, int seed) async {
  final d = Device(cloud, seed);
  await d.library.load();
  return d;
}

void main() {
  group('#37/AK3 timers: changes, retries and dispose (fake clock)', () {
    testWidgets('several changes within the delay give one sync', (
      tester,
    ) async {
      final cloud = InMemoryProvider();
      final a = await _ownDevice(cloud, 1);
      await a.sync.sync();
      final reads = _stateReads(cloud);
      // changes at 0, 10 and 15 ms, delay 20 ms: one sync, 20 ms after the last one
      a.sync.localChanged();
      await tester.pump(const Duration(milliseconds: 10));
      a.sync.localChanged();
      await tester.pump(const Duration(milliseconds: 5));
      a.sync.localChanged();
      await tester.pump(const Duration(milliseconds: 19));
      expect(_stateReads(cloud), reads);
      await tester.pump(const Duration(milliseconds: 100));
      expect(_stateReads(cloud), reads + 1);
      a.sync.dispose();
    });

    testWidgets('a direct sync takes the place of a waiting change', (
      tester,
    ) async {
      final cloud = InMemoryProvider();
      final a = await _ownDevice(cloud, 1);
      a.sync.localChanged();
      await a.sync.sync();
      final reads = _stateReads(cloud);
      await tester.pump(const Duration(milliseconds: 100));
      expect(_stateReads(cloud), reads);
      a.sync.dispose();
    });

    testWidgets('a sync cancels the retry planned before', (tester) async {
      final cloud = InMemoryProvider()..offline = true;
      final a = await _ownDevice(cloud, 1);
      await a.sync.sync();
      expect(a.sync.nextRetry, isNotNull);
      cloud.offline = false;
      await a.sync.sync();
      final reads = _stateReads(cloud);
      await tester.pump(const Duration(minutes: 10));
      expect(_stateReads(cloud), reads);
      a.sync.dispose();
    });

    testWidgets('a new retry replaces the planned one', (tester) async {
      final cloud = InMemoryProvider()..offline = true;
      final a = await _ownDevice(cloud, 1);
      await a.sync.sync(); // retry in 2 s
      await a.sync.sync(); // retry in 4 s instead
      final requests = cloud.requests.length;
      await tester.pump(const Duration(seconds: 3));
      expect(cloud.requests.length, requests);
      await tester.pump(const Duration(seconds: 2));
      expect(cloud.requests.length, greaterThan(requests));
      a.sync.dispose();
    });

    testWidgets('dispose ends the waiting change and the planned retry', (
      tester,
    ) async {
      final cloud = InMemoryProvider()..offline = true;
      final a = await _ownDevice(cloud, 1);
      await a.sync.sync(); // plans a retry
      a.sync.localChanged(); // and a sync after the change
      a.sync.dispose();
      // testWidgets fails if a timer is still pending at the end
    });

    testWidgets('a sync runs at once and ends a waiting change', (
      tester,
    ) async {
      final cloud = InMemoryProvider();
      final a = await _ownDevice(cloud, 1);
      a.sync.localChanged();
      await a.sync.sync();
      final reads = _stateReads(cloud);
      expect(reads, 1);
      await tester.pump(const Duration(milliseconds: 100));
      expect(_stateReads(cloud), reads);
      a.sync.dispose();
    });
  });

  group('#37/AK3 offline retries', () {
    test('automatic retries stop after maxOfflineRetries', () async {
      final cloud = InMemoryProvider()..offline = true;
      final d = Device(cloud, 1);
      await d.library.load();
      final s = CloudSync(cloud, d.library, maxOfflineRetries: 2);
      addTearDown(s.dispose);
      await s.sync();
      expect(s.nextRetry, isNotNull);
      await s.sync();
      expect(s.nextRetry, isNotNull, reason: 'the second retry is the last');
      await s.sync();
      expect(s.nextRetry, isNull);
      expect(s.status, SyncStatus.offline);
    });
  });

  group('#37 a sync requested while one runs', () {
    test('follows right after it and sends the later change', () async {
      final cloud = InMemoryProvider();
      final a = await device(cloud, 1);
      final t = await a.add('a.mp3');
      final gate = Completer<void>();
      // the first sync waits while writing its device file, after it read the state
      cloud.beforePut = (name) =>
          name.startsWith('devices/') ? gate.future : Future.value();
      final first = a.sync.sync();
      await eventually(
        () => cloud.requests.any((r) => r.startsWith('put devices/')),
        'the first sync writes its device file',
      );
      tick();
      a.library.editMetadata(t.id, title: 'Später', artist: null);
      final second = a.sync.sync();
      cloud.beforePut = null;
      gate.complete();
      await first;
      await second;
      final state = ownJson(cloud, a);
      expect(
        (((state['tracks']! as Map)[t.id] as Map)['values'] as Map)['title'],
        'Später',
      );
      expect(a.sync.status, SyncStatus.idle);
    });
  });

  group('#37 status for the UI', () {
    test(
      'a library from a newer app gives «too new» without a request',
      () async {
        final cloud = InMemoryProvider();
        final store = MemoryFileStore()
          ..files[Library.indexName] = bytes('{"formatVersion": 99}');
        final library = Library(
          store,
          probe: (_) => 2.5,
          readSource: (_) async => null,
          saveDelay: Duration.zero,
        );
        await library.load();
        final s = CloudSync(cloud, library);
        addTearDown(s.dispose);
        await s.sync();
        expect(s.status, SyncStatus.tooNew);
        expect(cloud.requests, isEmpty);
      },
    );

    test(
      'listeners see «syncing», the files in the cloud, then «idle»',
      () async {
        final cloud = InMemoryProvider();
        final a = await device(cloud, 1);
        final t = await a.add('a.mp3');
        await a.sync.sync();
        final b = await device(cloud, 2, eager: false);
        final seen = <(SyncStatus, bool)>[];
        b.sync.addListener(
          () => seen.add((b.sync.status, b.sync.inCloud(t.id))),
        );
        await b.sync.sync();
        expect(seen.first, (SyncStatus.syncing, false));
        expect(
          seen,
          contains((SyncStatus.syncing, true)),
        ); // after listing audio/
        expect(seen.last, (SyncStatus.idle, true));
      },
    );

    test('a waiting local change is saved before the sync reads it', () async {
      final cloud = InMemoryProvider();
      final store = MemoryFileStore();
      final library = Library(
        store,
        probe: (_) => 2.5,
        readSource: (_) async => bytes('audio'),
        saveDelay: const Duration(hours: 1),
      );
      await library.load();
      final s = CloudSync(cloud, library);
      addTearDown(s.dispose);
      addTearDown(library.dispose);
      await library.importFiles(['x.mp3']);
      library.sortOrder = TrackSortOrder.alphabetical;
      library.metronomePreset = {'bpm': 99};
      await s.sync();
      final state = _fileOf(cloud, library);
      expect(
        ((state['settings']! as Map)['values'] as Map)['metronome.bpm'],
        99,
      );
    });
  });

  group('#37/AK5 audio files', () {
    test(
      'an uploaded or deleted file shows in the cloud state at once',
      () async {
        final cloud = InMemoryProvider();
        final a = await device(cloud, 1);
        final t = await a.add('a.mp3');
        await a.sync.sync();
        expect(a.sync.inCloud(t.id), isTrue);
        tick();
        a.library.delete({t.id});
        await a.sync.sync();
        expect(a.sync.inCloud(t.id), isFalse);
      },
    );

    test('a track excluded after a failed upload is not uploaded', () async {
      final cloud = InMemoryProvider();
      final a = await device(cloud, 1);
      final t = await a.add('a.mp3');
      cloud.abortPut = (name) => name.startsWith('audio/');
      await a.sync.sync();
      expect(a.sync.pending.map((x) => x.key), contains('up:${t.id}'));
      cloud.abortPut = null;
      a.library.setNoUpload({t.id}, true);
      await a.sync.syncNow();
      expect(cloud.files.keys.where((k) => k.startsWith('audio/')), isEmpty);
    });

    test('a good download leaves no task; a damaged one is retried', () async {
      final cloud = InMemoryProvider();
      final a = await device(cloud, 1);
      final t = await a.add('a.mp3');
      await a.sync.sync();
      final b = await device(cloud, 2);
      await b.sync.sync();
      expect(b.library.hasFile(t.id), isTrue);
      expect(b.sync.pending, isEmpty);

      final c = await device(cloud, 3);
      cloud.putDirect(Library.cloudAudioName(t), bytes('damaged'));
      await c.sync.sync();
      expect(c.library.hasFile(t.id), isFalse);
      expect(c.sync.pending.map((x) => x.key), ['down:${t.id}']);
    });

    test('fetchAudio: here already, missing in the cloud, offline', () async {
      final cloud = InMemoryProvider();
      final a = await device(cloud, 1);
      final t = await a.add('a.mp3');
      expect(await a.sync.fetchAudio(t), isTrue); // here already
      await a.sync.sync();
      final b = await device(cloud, 2, eager: false);
      await b.sync.sync();
      cloud.offline = true;
      expect(await b.sync.fetchAudio(t), isFalse);
      cloud.offline = false;
      await cloud.delete(Library.cloudAudioName(t));
      expect(await b.sync.fetchAudio(t), isFalse);
      expect(b.library.hasFile(t.id), isFalse);
    });
  });

  group('#10/AK7, #53/AK5 contents of a device file', () {
    test('a track or folder the app cannot show makes the file unreadable: skipped, the rest is merged', () async {
      final cloud = InMemoryProvider();
      final a = await device(cloud, 1);
      final t = await a.add('a.mp3');
      final f = a.library.createFolder('F');
      await a.sync.sync();
      final good = cloud.files[ownName(a)]!;
      for (final (kind, id, field) in [
        ('tracks', t.id, 'fileName'),
        ('folders', f.id, 'name'),
      ]) {
        final j = jsonDecode(utf8.decode(good)) as Map;
        (((j[kind] as Map)[id] as Map)['values'] as Map)[field] = 7;
        cloud.putDirect(ownName(a), bytes(jsonEncode(j)));
        final b = await device(cloud, 2);
        final own = await b.add('b.mp3');
        await b.sync.sync();
        expect(b.sync.status, SyncStatus.idle, reason: kind);
        expect(b.library.tracks.map((x) => x.id), [own.id], reason: kind);
        expect(b.library.lastError, isNull, reason: kind);
      }
    });

    test('a generation that is not a counter counts as 0', () async {
      for (final g in ['x', -5]) {
        final cloud = InMemoryProvider();
        final a = await device(cloud, 1);
        await a.add('a.mp3');
        cloud.putDirect(ownName(a), _withGeneration(a, g));
        tick();
        await a.add('b.mp3');
        await a.sync.sync();
        expect(a.sync.status, SyncStatus.idle, reason: '$g');
        expect(cloudGeneration(cloud, a), 1, reason: '$g');
        expect(
          cloud.files.keys,
          contains(CloudSync.backupName(a.library.device.deviceId, 1)),
        );
      }
    });

    test('a time of writing that is not a time counts as unknown', () async {
      for (final w in ['x', -5]) {
        final j = (jsonDecode(
          utf8.decode(
            CloudSync.encodeDevice(
              SharedState.empty,
              '00000000000000aa',
              1,
              DateTime.utc(2026),
            ),
          ),
        ) as Map)..['written'] = w;
        final f = CloudSync.decodeDevice(
          'devices/00000000000000aa.json',
          bytes(jsonEncode(j)),
        );
        expect(f.written, isNull, reason: '$w');
      }
      final f = CloudSync.decodeDevice(
        'devices/00000000000000aa.json',
        CloudSync.encodeDevice(
          SharedState.empty,
          '00000000000000aa',
          4,
          DateTime.utc(2026, 3, 4),
        ),
      );
      expect(f.written, DateTime.utc(2026, 3, 4));
      expect(f.generation, 4);
      expect(f.deviceId, '00000000000000aa');
      expect(f.copy, isFalse);
      expect(
        () => CloudSync.decodeDevice('format.json', f.bytes),
        throwsFormatException,
      );
    });
  });

  group('#37 sync() (without the repair of #65, #111)', () {
    test('a disposed engine or a read-only library sends nothing', () async {
      final cloud = InMemoryProvider();
      final d = Device(cloud, 1);
      await d.library.load();
      d.sync.dispose();
      await d.sync.sync();
      expect(cloud.requests, isEmpty);

      final store = MemoryFileStore()
        ..files[Library.indexName] = bytes('{"formatVersion": 99}');
      final library = Library(
        store,
        probe: (_) => 2.5,
        readSource: (_) async => null,
        saveDelay: Duration.zero,
      );
      await library.load();
      final s = CloudSync(cloud, library);
      addTearDown(s.dispose);
      await s.sync();
      expect(s.status, SyncStatus.tooNew);
      expect(cloud.requests, isEmpty);
    });

    test('a sync writes the latest local state, also a change still waiting to be saved', () async {
      final cloud = InMemoryProvider();
      final library = Library(
        MemoryFileStore(),
        probe: (_) => 2.5,
        readSource: (_) async => null,
        saveDelay: const Duration(hours: 1),
      );
      await library.load();
      final s = CloudSync(cloud, library);
      addTearDown(s.dispose);
      addTearDown(library.dispose);
      library.metronomePreset = {'bpm': 66};
      await s.sync();
      expect(
        ((_fileOf(cloud, library)['settings']! as Map)['values']
            as Map)['metronome.bpm'],
        66,
      );
    });
  });

  group('#37 dispose', () {
    test('a disposed engine sends nothing and is ended', () async {
      final cloud = InMemoryProvider();
      final d = Device(cloud, 1);
      await d.library.load();
      d.sync.dispose();
      await d.sync.sync();
      expect(cloud.requests, isEmpty);
      expect(() => d.sync.addListener(() {}), throwsA(isA<Error>()));
    });
  });
}
