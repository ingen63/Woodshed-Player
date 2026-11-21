// #10/AK6, AK7: random tests of the sync engine (#37) on 2 to 4 devices with the InMemoryProvider. Libraries
// in memory with generated audio bytes, never a real account or the real library.
// - AK6: any sequence of imports, edits, deletions, folder moves and syncs (some offline) converges: after
//   syncing every device all have the same state, whatever the order; merging the states in any order
//   gives that state; a second sync changes nothing; no track that was never deleted is lost.
// - #98/AK5: the clock sometimes jumps by more than the 90 days of a tombstone, so devices stay offline that
//   long; no deleted track or folder comes back, and only tracks last changed before the purge horizon may be
//   lost (decision in #98).
// - #104/AK5: some devices sync for the first time only late, often after such a jump; their first sync
//   loses none of their own tracks (with audio), the purge horizon applies only once a device has synced.
// - AK7, #53/AK5: a damaged device file in the cloud (foreign version number, missing stamps, changed
//   types, extreme values, truncated) never crashes the sync and never loses local data; it is skipped
//   without an error (a newer format gets an understandable message in every language) and read again
//   once its device wrote it anew, so the devices come together again. (Before #53 a damaged shared
//   `state.json` stopped the sync until a repair, #65.)
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/library/stamps.dart' show sameJson;
import 'package:woodshed_player/sync/in_memory_provider.dart';
import 'package:woodshed_player/sync/sync_engine.dart';
import 'package:woodshed_player/sync/sync_service.dart';
import 'package:woodshed_player/ui/messages.dart';

import '../fakes.dart';
import 'corrupt.dart';
import 'library_property_test.dart' show randomSettings, randomText;
import 'property.dart';

final en = lookupAppLocalizations(const Locale('en'));

/// Shared test clock of all devices (each case starts it anew).
var clock = DateTime.utc(2026, 11, 1);

class Device {
  Device(this.name, this.cloud, this.random, this.sources) {
    library = open();
    sync = CloudSync(
      cloud,
      library,
      now: () => clock,
      changeDelay: const Duration(hours: 1),
      backoffBase: const Duration(hours: 1),
    );
  }

  final String name;
  final InMemoryProvider cloud;
  final Random random;
  final Map<String, Uint8List> sources;
  final store = MemoryFileStore();
  late final Library library;
  late final CloudSync sync;

  Library open() => Library(
    store,
    probe: (_) => 30,
    readSource: (s) async => sources[s],
    now: () => clock,
    saveDelay: Duration.zero,
    random: Random(random.nextInt(1 << 31)),
  );
}

Map<String, Object?> stateJson(Library l) => l.state.toJson();

/// Name of the device file of [d].
String fileOf(Device d) => CloudSync.deviceName(d.library.device.deviceId);

/// The same contents in every device's pool: the same file gives the same track ID everywhere.
Map<String, Uint8List> pool(int n) => {
  for (var i = 0; i < n; i++)
    'p$i.mp3': Uint8List.fromList(utf8.encode('audio p$i')),
};

void main() {
  group('#10/AK6 sync on 2 to 4 devices', () {
    property('random edits, deletions and syncs on 2 to 4 devices converge', (
      r,
    ) async {
      clock = DateTime.utc(2026, 11, 1);
      final cloud = InMemoryProvider();
      final sources = pool(8);
      final devices = [
        for (var i = 0, n = 2 + r.nextInt(3); i < n; i++)
          Device('d$i', cloud, r, sources),
      ];
      for (final d in devices) {
        await d.library.load();
      }
      final imported = <String>{};
      final deleted = <String>{};
      // #98/AK5: stamp of every deletion of a track or folder
      final deletions = <(String, Hlc)>[];
      // #98/AK5: newest change of each track seen on any device
      final lastChange = <String, Hlc>{};
      final log = <String>[];
      final steps = 10 + r.nextInt(30);
      // #104/AK5: step from which a device syncs; before that it works on its own library only
      final joinAt = {
        for (final d in devices)
          d: d == devices.first || r.nextBool() ? 0 : r.nextInt(steps),
      };
      for (var step = 0; step < steps; step++) {
        final d = pick(r, devices);
        final lib = d.library;
        final ids = lib.tracks.map((t) => t.id).toList();
        final folders = [null, ...lib.folders.map((f) => f.id)];
        clock = clock.add(Duration(milliseconds: r.nextInt(3) * 700));
        if (r.nextInt(8) == 0) {
          // #98/AK5: devices not syncing now stay offline beyond the tombstones
          clock = clock.add(Duration(days: 85 + r.nextInt(20)));
          log.add('+days');
        }
        switch (r.nextInt(9)) {
          case 0 || 1:
            final names = [
              for (final s in sources.keys)
                if (r.nextInt(4) == 0) s,
            ];
            final res = await lib.importFiles(names);
            imported.addAll([
              ...res.imported.map((t) => t.id),
              ...res.duplicates.map((t) => t.id),
            ]);
            log.add('${d.name} import ${names.length}');
          case 2:
            if (ids.isNotEmpty) {
              final id = pick(r, ids);
              lib.delete({id});
              deleted.add(id);
              deletions.add(('t$id', lib.state.tracks[id]!.deleted!));
              log.add('${d.name} delete');
            }
          case 3:
            if (ids.isNotEmpty) {
              lib.editMetadata(pick(r, ids), title: randomText(r));
              log.add('${d.name} edit');
            }
          case 4:
            if (r.nextBool() || folders.length == 1) {
              lib.createFolder(randomText(r));
            } else {
              final f = pick(r, folders.whereType<String>().toList());
              lib.deleteFolder(f);
              deletions.add(('f$f', lib.state.folders[f]!.deleted!));
            }
            log.add('${d.name} folder');
          case 5:
            if (ids.isNotEmpty) {
              lib.moveTracks({pick(r, ids)}, pick(r, folders));
              log.add('${d.name} move');
            }
          case 6:
            if (ids.isNotEmpty) {
              lib.updateSettings(pick(r, ids), randomSettings(r));
              log.add('${d.name} settings');
            }
          default:
            if (step < joinAt[d]!) {
              log.add('${d.name} not yet');
              break;
            }
            final first = !lib.device.synced;
            final own = {for (final t in lib.tracks) t.id};
            cloud.offline = r.nextInt(5) == 0;
            await d.sync.sync();
            cloud.offline = false;
            log.add('${d.name} sync');
            if (first && lib.device.synced) {
              // #104/AK5: nothing of its own lost on the first sync, unless deleted elsewhere
              for (final id in own.difference(deleted)) {
                expect(
                  lib.track(id),
                  isNotNull,
                  reason: '$id lost on the first sync: ${log.join(', ')}',
                );
                expect(lib.hasFile(id), isTrue, reason: log.join(', '));
              }
            }
        }
        for (final e in devices.expand((d) => d.library.state.tracks.entries)) {
          final l = Hlc.maxOf([lastChange[e.key], e.value.latest]);
          if (l != null) lastChange[e.key] = l;
        }
      }
      final reason = log.join(', ');

      // Merging the states in any order gives the same state (commutative, associative).
      final states = [for (final d in devices) d.library.state];
      SharedState fold(List<SharedState> s) =>
          s.skip(1).fold(s.first, (a, b) => a.merge(b));
      final shuffled = [...states]..shuffle(r);
      expect(
        fold(shuffled).toJson(),
        fold(states.reversed.toList()).toJson(),
        reason: 'merge depends on the order: $reason',
      );

      // Converge: every device syncs, in a random order, until a round changes nothing (at least twice).
      // #98/AK5: a purged tombstone may have held field values that a device offline since then brings back
      // once the track was revived by a newer change; that takes another round.
      for (var round = 0, changed = true; changed; round++) {
        expect(round, lessThan(5), reason: 'no end state: $reason');
        final before = [for (final d in devices) stateJson(d.library)];
        for (final d in [...devices]..shuffle(r)) {
          await d.sync.sync();
        }
        changed =
            round == 0 ||
            [for (final d in devices) stateJson(d.library)].indexed
                .any((e) => !sameJson(e.$2, before[e.$1]));
      }
      // compared as maps: the order of keys carries no meaning
      final first = stateJson(devices.first.library);
      for (final d in devices) {
        expect(
          stateJson(d.library),
          first,
          reason: '${d.name} differs after syncing: $reason',
        );
        expect(d.sync.failed, isEmpty, reason: reason);
      }

      // A second sync changes nothing: no write, the same state.
      final puts = cloud.requests.where((q) => q.startsWith('put')).length;
      for (final d in [...devices]..shuffle(r)) {
        await d.sync.sync();
        expect(stateJson(d.library), first, reason: reason);
      }
      expect(
        cloud.requests.where((q) => q.startsWith('put')).length,
        puts,
        reason: 'a second sync wrote: $reason',
      );

      // #98/AK5: no deleted track or folder comes back unless changed after its deletion (a new import).
      final end = devices.first.library.state;
      for (final (key, stamp) in deletions) {
        final id = key.substring(1);
        final rec = key.startsWith('t') ? end.tracks[id] : end.folders[id];
        if (rec != null && rec.alive) {
          expect(
            rec.latest! > stamp,
            isTrue,
            reason: '$key came back: $reason',
          );
        }
      }

      // No track lost that was never deleted, with its audio on every device and in the cloud; #98/AK5:
      // except one last changed before the purge horizon.
      for (final id in imported.difference(deleted)) {
        final horizon = end.purged;
        if (horizon != null && lastChange[id]! < horizon) continue;
        for (final d in devices) {
          expect(d.library.track(id), isNotNull, reason: '$id lost: $reason');
          expect(d.library.hasFile(id), isTrue, reason: 'audio: $reason');
        }
        expect(
          cloud.files.keys.any((k) => k.startsWith('audio/$id')),
          isTrue,
          reason: 'audio not in the cloud: $reason',
        );
      }

      // What each device saved loads again as the same state.
      for (final d in devices) {
        final again = d.open();
        await again.load();
        expect(again.lastError, isNull);
        expect(stateJson(again), first, reason: reason);
        d.sync.dispose();
      }
    }, scale: 0.3);
  });

  test(
    '#10/AK6 a new device does not reset the settings chosen on the others',
    () async {
      clock = DateTime.utc(2026, 11, 1);
      final cloud = InMemoryProvider();
      final sources = pool(2);
      final a = Device('a', cloud, Random(1), sources);
      final b = Device('b', cloud, Random(2), sources);
      await a.library.load();
      await b.library.load();
      a.library.sortOrder = TrackSortOrder.alphabetical;
      a.library.appearance = Appearance.dark;
      await a.sync.sync();
      clock = clock.add(const Duration(hours: 1));
      await b.library.importFiles([
        'p1.mp3',
      ]); // first save of b, with its defaults, an hour later
      await b.sync.sync();
      await a.sync.sync();
      for (final d in [a, b]) {
        expect(
          (d.library.sortOrder, d.library.appearance),
          (TrackSortOrder.alphabetical, Appearance.dark),
        );
      }
      a.sync.dispose();
      b.sync.dispose();
    },
  );

  test('#98/AK2, AK3, AK4 a device offline beyond the tombstones does not revive deleted tracks and folders', () async {
    clock = DateTime.utc(2026, 1, 1);
    final cloud = InMemoryProvider();
    final sources = pool(1);
    final a = Device('a', cloud, Random(1), sources);
    final b = Device('b', cloud, Random(2), sources);
    await a.library.load();
    await b.library.load();
    final x = (await a.library.importFiles(['p0.mp3'])).imported.single.id;
    final f = a.library.createFolder('Etüden').id;
    await a.sync.sync();
    await b.sync.sync();
    expect(b.library.track(x), isNotNull);
    clock = DateTime.utc(2026, 1, 2); // a deletes, b stays offline from now on
    a.library.delete({x});
    a.library.deleteFolder(f);
    await a.sync.sync();
    // horizon 2026-01-03: a's sync purges the tombstones
    clock = DateTime.utc(2026, 4, 3);
    await a.sync.sync();
    expect(a.library.state.tracks, isEmpty);
    expect(a.library.state.purged, isNotNull);
    // b comes back (both directions of the merge itself: stamps_test.dart)
    await b.sync.sync();
    await a.sync.sync();
    for (final d in [a, b]) {
      expect(d.library.track(x), isNull, reason: d.name);
      expect(d.library.folders, isEmpty, reason: d.name);
    }
    // #98/AK4: importing the same audio file again after the horizon revives the track everywhere
    clock = DateTime.utc(2026, 4, 4);
    await b.library.importFiles(['p0.mp3']);
    await b.sync.sync();
    await a.sync.sync();
    for (final d in [a, b]) {
      expect(d.library.track(x), isNotNull);
      expect(d.library.hasFile(x), isTrue);
    }
    // the horizon survives saving and loading
    final again = a.open();
    await again.load();
    expect(again.state.purged, a.library.state.purged);
    a.sync.dispose();
    b.sync.dispose();
  });

  group('#10/AK7, #53/AK5 damaged device file', () {
    final outcomes = <String, int>{};
    property('a damaged device file never crashes and never loses local data', (
      r,
    ) async {
      clock = DateTime.utc(2026, 11, 1);
      final cloud = InMemoryProvider();
      final sources = pool(6);
      final a = Device('a', cloud, r, sources);
      final b = Device('b', cloud, r, sources);
      await a.library.load();
      await b.library.load();
      // a: tracks p0–p2 in the cloud; b: its own tracks p3–p5, never synced
      await a.library.importFiles(['p0.mp3', 'p1.mp3', 'p2.mp3']);
      final f = a.library.createFolder('Etüden');
      a.library.moveTracks({a.library.tracks.first.id}, f.id);
      a.library.updateSettings(a.library.tracks.last.id, randomSettings(r));
      await a.sync.sync();
      clock = clock.add(const Duration(minutes: 1));
      await b.library.importFiles(['p3.mp3', 'p4.mp3', 'p5.mp3']);
      b.library.editMetadata(b.library.tracks.first.id, title: 'Eigene');
      final mine = {for (final t in b.library.tracks) t.id: t.toShared()};

      final state = jsonDecode(utf8.decode(cloud.files[fileOf(a)]!));
      final (bytes, damage) = corrupt(
        r,
        state,
        ids: [...a.library.tracks.map((t) => t.id), ...mine.keys, f.id],
      );
      cloud.putDirect(fileOf(a), bytes);
      final what = '$damage: ${utf8.decode(bytes, allowMalformed: true)}';

      await b.sync.sync(); // must not throw
      b.library.flush();
      // b's own tracks are all there, unchanged
      for (final e in mine.entries) {
        expect(
          b.library.track(e.key)?.toShared(),
          e.value,
          reason: 'local track changed or lost: $what',
        );
      }
      // what b saved loads again without a message and with the same tracks
      final again = b.open();
      await again.load();
      expect(again.lastError, isNull, reason: 'library.json damaged: $what');
      expect(
        {for (final t in again.tracks) t.id: t.toShared()},
        {for (final t in b.library.tracks) t.id: t.toShared()},
        reason: what,
      );
      final msg = b.library.lastError;
      final key = msg != null
          ? msg.runtimeType.toString()
          : b.library.tracks.length > mine.length
          ? 'used'
          : 'skipped';
      outcomes[key] = (outcomes[key] ?? 0) + 1;
      if (msg != null) {
        for (final loc in [de, en]) {
          expect(libraryMessageText(loc, msg), isNotEmpty);
        }
      } else {
        // #53/AK5: used or skipped, the sync went through without an error
        expect(b.sync.failed, isEmpty, reason: what);
        expect(b.sync.status, SyncStatus.idle, reason: what);
        expect(cloud.files.keys, contains(fileOf(b)), reason: what);
      }
      if (msg is! CloudStateTooNew) {
        // a writes its file anew (its own file is unreadable or differs); b reads it on the next sync
        final mineA = {for (final t in a.library.tracks) t.id: t.toShared()};
        clock = clock.add(const Duration(minutes: 1));
        await a.sync.sync();
        await b.sync.sync();
        await a.sync.sync();
        expect(stateJson(a.library), stateJson(b.library), reason: what);
        for (final id in [...mineA.keys, ...mine.keys]) {
          expect(b.library.track(id), isNotNull, reason: 'lost $id: $what');
          expect(a.library.track(id), isNotNull, reason: 'lost $id: $what');
        }
      }
      a.sync.dispose();
      b.sync.dispose();
    }, scale: 0.5);

    test('#53/AK5 a damaged device file: no message, left as it is, merged once readable; newer format: one message', () async {
      clock = DateTime.utc(2026, 11, 1);
      final cloud = InMemoryProvider();
      final b = Device('b', cloud, Random(3), pool(2));
      await b.library.load();
      await b.library.importFiles(['p0.mp3']);
      final before = b.library.state.toJson();
      const other = 'devices/00000000000000aa.json';
      cloud.putDirect(
        other,
        Uint8List.fromList(utf8.encode('{"formatVersion": 2, "tracks": 7}')),
      );
      await b.sync.sync();
      expect(b.library.lastError, isNull);
      expect(b.library.state.toJson(), before);
      expect(b.sync.pending, isEmpty);
      expect(b.sync.status, SyncStatus.idle);
      // the file is left as it is, for its device to write anew
      expect(utf8.decode(cloud.files[other]!), contains('"tracks": 7'));
      cloud.putDirect(
        other,
        Uint8List.fromList(utf8.encode('{"formatVersion": 3}')),
      );
      await b.sync.syncNow();
      expect(b.library.lastError, isA<CloudStateTooNew>());
      expect((b.library.lastError! as CloudStateTooNew).version, 3);
      expect(libraryMessageText(en, b.library.lastError!), contains('update'));
      b.library.lastError = null;
      await b.sync.syncNow(); // the same version: no second message
      expect(b.library.lastError, isNull);
      expect(b.sync.status, SyncStatus.tooNew);
      b.sync.dispose();
    });

    tearDownAll(() {
      // ignore: avoid_print
      print('damaged device file: $outcomes');
    });
  });
}
