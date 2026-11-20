// #10/AK6, AK7: random tests of the sync engine (#37) on 2 to 4 devices with the InMemoryProvider. Libraries
// in memory with generated audio bytes, never a real account or the real library.
// - AK6: any sequence of imports, edits, deletions, folder moves and syncs (some offline) converges: after
//   syncing every device all have the same state, whatever the order; merging the states in any order
//   gives that state; a second sync changes nothing; no track that was never deleted is lost.
// - AK7: a damaged `state.json` in the cloud (foreign version number, missing stamps, changed types,
//   extreme values, truncated) never crashes the sync and never loses local data; the user gets an
//   understandable message (in every language) when it cannot be used.
// - #65/AK4: both repairs of a damaged `state.json` (restore the last valid backup, overwrite with this
//   device), with damaged backups and dropped connections, never lose local data and bring the devices
//   together again.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/library/library.dart';
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

/// A device with an empty library can use this `state.json` (scratch cloud, nothing else touched).
Future<bool> usable(Uint8List bytes) async {
  final cloud = InMemoryProvider()..putDirect(CloudSync.stateName, bytes);
  final d = Device('scratch', cloud, Random(0), const {});
  await d.library.load();
  await d.sync.sync();
  d.sync.dispose();
  return d.sync.status != SyncStatus.damaged;
}

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
      final log = <String>[];
      for (var step = 0, n = 10 + r.nextInt(30); step < n; step++) {
        final d = pick(r, devices);
        final lib = d.library;
        final ids = lib.tracks.map((t) => t.id).toList();
        final folders = [null, ...lib.folders.map((f) => f.id)];
        clock = clock.add(Duration(milliseconds: r.nextInt(3) * 700));
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
              lib.deleteFolder(pick(r, folders.whereType<String>().toList()));
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
            cloud.offline = r.nextInt(5) == 0;
            await d.sync.sync();
            cloud.offline = false;
            log.add('${d.name} sync');
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

      // Converge: every device syncs, twice, in a random order.
      for (var round = 0; round < 2; round++) {
        for (final d in [...devices]..shuffle(r)) {
          await d.sync.sync();
        }
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

      // No track lost that was never deleted, with its audio on every device and in the cloud.
      for (final id in imported.difference(deleted)) {
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

  group('#10/AK7 damaged state.json', () {
    final outcomes = <String, int>{};
    property('damaged state.json never crashes and never loses local data', (
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

      final state = jsonDecode(utf8.decode(cloud.files[CloudSync.stateName]!));
      final (bytes, damage) = corrupt(
        r,
        state,
        ids: [...a.library.tracks.map((t) => t.id), ...mine.keys, f.id],
      );
      cloud.putDirect(CloudSync.stateName, bytes);
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
      final key = msg == null ? 'used' : msg.runtimeType.toString();
      outcomes[key] = (outcomes[key] ?? 0) + 1;
      if (msg != null) {
        for (final loc in [de, en]) {
          expect(libraryMessageText(loc, msg), isNotEmpty);
        }
      } else {
        // used: the damaged file was still valid; the sync went through
        expect(b.sync.failed, isEmpty, reason: what);
      }
      a.sync.dispose();
      b.sync.dispose();
    }, scale: 0.5);

    test(
      'one message per damaged version, local data unchanged, sync waits',
      () async {
        clock = DateTime.utc(2026, 11, 1);
        final cloud = InMemoryProvider();
        final b = Device('b', cloud, Random(3), pool(2));
        await b.library.load();
        await b.library.importFiles(['p0.mp3']);
        final before = b.library.state.toJson();
        cloud.putDirect(
          CloudSync.stateName,
          Uint8List.fromList(utf8.encode('{"formatVersion": 2, "tracks": 7}')),
        );
        await b.sync.sync();
        expect(b.library.lastError, isA<CloudStateUnreadable>());
        expect(b.library.state.toJson(), before);
        expect(b.sync.pending.map((t) => t.key), contains('state'));
        expect(libraryMessageText(en, b.library.lastError!), contains('cloud'));
        expect(libraryMessageText(de, b.library.lastError!), contains('Cloud'));
        b.library.lastError = null;
        await b.sync.syncNow(); // the same damaged version: no second message
        expect(b.library.lastError, isNull);
        // the cloud file is left as it is, for the user or another device to repair
        expect(
          utf8.decode(cloud.files[CloudSync.stateName]!),
          contains('"tracks": 7'),
        );
        cloud.putDirect(
          CloudSync.stateName,
          Uint8List.fromList(utf8.encode('{"formatVersion": 3}')),
        );
        await b.sync.syncNow();
        expect(b.library.lastError, isA<CloudStateTooNew>());
        expect((b.library.lastError! as CloudStateTooNew).version, 3);
        b.sync.dispose();
      },
    );

    tearDownAll(() {
      // ignore: avoid_print
      print('damaged state.json: $outcomes');
    });
  });

  group('#65/AK4 repairing a damaged state.json', () {
    final outcomes = <String, int>{};
    property('both ways never lose local data and the devices converge again', (
      r,
    ) async {
      clock = DateTime.utc(2026, 11, 1);
      final cloud = InMemoryProvider();
      final sources = pool(8);
      final a = Device('a', cloud, r, sources);
      final b = Device('b', cloud, r, sources);
      await a.library.load();
      await b.library.load();
      // a: several syncs, so backup/ holds states; b: its own tracks, never synced
      for (final p in ['p0.mp3', 'p1.mp3', 'p2.mp3', 'p3.mp3']) {
        if (r.nextBool() || a.library.tracks.isEmpty) {
          await a.library.importFiles([p]);
        }
        if (r.nextBool() && a.library.tracks.isNotEmpty) {
          a.library.editMetadata(
            pick(r, a.library.tracks).id,
            title: randomText(r),
          );
        }
        clock = clock.add(const Duration(seconds: 1));
        await a.sync.sync();
      }
      await b.library.importFiles([
        for (final p in ['p4.mp3', 'p5.mp3', 'p6.mp3', 'p7.mp3'])
          if (r.nextBool()) p,
        'p4.mp3',
      ]);
      if (r.nextBool()) {
        b.library.updateSettings(b.library.tracks.first.id, randomSettings(r));
      }
      final ids = [
        ...a.library.tracks.map((t) => t.id),
        ...b.library.tracks.map((t) => t.id),
      ];
      // damage state.json so that it is unusable (checked on a scratch device, so nothing usable is
      // merged on the way), and sometimes some or all backups too
      final state = jsonDecode(utf8.decode(cloud.files[CloudSync.stateName]!));
      Uint8List? bad;
      var damage = '';
      for (var i = 0; i < 20 && bad == null; i++) {
        final (bytes, d) = corrupt(r, state, ids: ids);
        if (!await usable(bytes)) {
          bad = bytes;
          damage = '$d';
        }
      }
      if (bad == null) return; // every damage was still usable (#10/AK7)
      cloud.putDirect(CloudSync.stateName, bad);
      clock = clock.add(const Duration(seconds: 1));
      await b.sync.sync();
      expect(b.sync.status, SyncStatus.damaged, reason: damage);
      for (var n = 1; n <= CloudSync.backupCount; n++) {
        if (cloud.files[CloudSync.backupName(n)] case final f?
            when r.nextInt(3) == 0) {
          // unusable for sure: the damaged state itself or the backup cut short
          cloud.putDirect(
            CloudSync.backupName(n),
            r.nextBool() ? bad : f.sublist(0, r.nextInt(f.length)),
          );
        }
      }
      final mineB = {for (final t in b.library.tracks) t.id: t.toShared()};
      final mineA = {for (final t in a.library.tracks) t.id: t.toShared()};
      final what = 'damage $damage';

      // sometimes the connection drops first: nothing changes, the user tries again
      if (r.nextInt(4) == 0) {
        cloud.offline = true;
        final how = pick(r, CloudStateRepair.values);
        expect(
          await b.sync.repairCloudState(how),
          CloudRepairResult.failed,
          reason: what,
        );
        cloud.offline = false;
      }
      final how = pick(r, CloudStateRepair.values);
      var result = await b.sync.repairCloudState(how);
      final key = '${how.name}: ${result.name}';
      outcomes[key] = (outcomes[key] ?? 0) + 1;
      if (result == CloudRepairResult.noBackup) {
        result = await b.sync.repairCloudState(
          CloudStateRepair.overwriteWithLocal,
        );
      }
      expect(result, isNot(CloudRepairResult.failed), reason: what);
      expect(b.sync.status, isNot(SyncStatus.damaged), reason: what);

      // b keeps every own track unchanged (a backup only adds what b has not seen)
      for (final e in mineB.entries) {
        expect(
          b.library.track(e.key)?.toShared(),
          e.value,
          reason: 'local track changed or lost ($how): $what',
        );
      }
      final again = b.open();
      await again.load();
      expect(again.lastError, isNull, reason: what);
      expect(
        {for (final t in again.tracks) t.id: t.toShared()},
        {for (final t in b.library.tracks) t.id: t.toShared()},
        reason: what,
      );
      // the cloud is readable again; a and b converge and keep all their tracks
      clock = clock.add(const Duration(seconds: 1));
      await a.sync.sync();
      await b.sync.sync();
      await a.sync.sync();
      expect(a.sync.status, SyncStatus.idle, reason: what);
      expect(b.sync.status, SyncStatus.idle, reason: what);
      expect(stateJson(a.library), stateJson(b.library), reason: what);
      for (final e in mineA.entries) {
        expect(a.library.track(e.key)?.toShared(), e.value, reason: what);
      }
      for (final id in [...mineA.keys, ...mineB.keys]) {
        expect(b.library.track(id), isNotNull, reason: 'lost $id: $what');
        expect(b.library.hasFile(id), isTrue, reason: 'audio of $id: $what');
      }
      a.sync.dispose();
      b.sync.dispose();
    }, scale: 0.3);

    tearDownAll(() {
      // ignore: avoid_print
      print('repairs: $outcomes');
    });
  });
}
