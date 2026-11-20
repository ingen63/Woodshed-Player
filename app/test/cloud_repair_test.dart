// #65: repairing a damaged `state.json` in the cloud. Way 1 (suggested) restores the last valid backup from
// `backup/` and merges it with this device, way 2 replaces it with the state of this device. Every test runs
// against the InMemoryProvider and libraries in memory, never a real account or the real library.
import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/sync/in_memory_provider.dart';
import 'package:woodshed_player/sync/sync_engine.dart';
import 'package:woodshed_player/sync/sync_service.dart';
import 'package:woodshed_player/ui/messages.dart';

import 'home_page_test.dart' show pumpApp;
import 'sync_test.dart' show Device, bytes, cloudState, device, tick;

final damaged = bytes('{"formatVersion": 2, "tracks": 7');

/// Tracks of [d] as the cloud sees them (id → record values).
Map<String, Map<String, Object?>> shared(Device d) => {
  for (final t in d.library.tracks) t.id: t.toShared(),
};

/// Titles of the live tracks in [s].
Set<Object?> titles(SharedState s) => {
  for (final r in s.tracks.values)
    if (r.alive) r.values['title'],
};

/// Device a with three tracks, synced several times (so `backup/` has states); device b with its own
/// tracks that never reached the cloud; then `state.json` is damaged and b's sync stops.
Future<(InMemoryProvider, Device, Device)> damagedCloud() async {
  final cloud = InMemoryProvider();
  final a = await device(cloud, 1);
  for (final n in ['a1.mp3', 'a2.mp3', 'a3.mp3']) {
    await a.add(n);
    tick();
    await a.sync.sync();
  }
  final b = await device(cloud, 2);
  await b.add('b1.mp3');
  await b.add('b2.mp3');
  final own = b.library.tracks.first;
  b.library.editMetadata(own.id, title: own.title, artist: 'Eigene');
  cloud.putDirect(CloudSync.stateName, damaged);
  tick();
  await b.sync.sync();
  return (cloud, a, b);
}

/// What b saved loads again without a message and with the same tracks.
Future<void> expectSavedLocally(Device d) async {
  d.library.flush();
  final again = Library(
    d.store,
    probe: (_) => 2.5,
    readSource: (_) async => null,
    saveDelay: Duration.zero,
  );
  await again.load();
  expect(again.lastError, isNull);
  expect({for (final t in again.tracks) t.id: t.toShared()}, shared(d));
}

/// Fake sync for the dialog: records the chosen way and answers with [result].
class RepairSync extends NoSync {
  RepairSync(this.result);
  final CloudRepairResult result;
  final chosen = <CloudStateRepair>[];
  @override
  Future<CloudRepairResult> repairCloudState(CloudStateRepair how) async {
    chosen.add(how);
    return result;
  }
}

void main() {
  group('#65/AK1 a damaged state.json offers both ways', () {
    test(
      'the sync stops with status damaged and waits for the choice',
      () async {
        final (cloud, _, b) = await damagedCloud();
        expect(b.library.lastError, isA<CloudStateUnreadable>());
        expect(b.sync.status, SyncStatus.damaged);
        expect(b.sync.nextRetry, isNull, reason: 'no endless automatic retry');
        expect(cloud.files[CloudSync.stateName], damaged);
      },
    );

    test(
      'way 1: restores the last valid backup and merges it with this device',
      () async {
        final (cloud, a, b) = await damagedCloud();
        final mine = shared(b);
        final result = await b.sync.repairCloudState(
          CloudStateRepair.restoreBackup,
        );
        expect(result, CloudRepairResult.restored);
        // the last valid backup held a1 and a2 (a3's write went straight to state.json, now damaged)
        final restored = cloudState(cloud);
        expect(titles(restored), containsAll(['a1', 'a2', 'b1', 'b2']));
        for (final id in mine.keys) {
          expect(b.library.track(id)?.toShared(), mine[id]);
        }
        expect(cloud.files[CloudSync.damagedName], damaged);
        expect(b.sync.status, SyncStatus.idle);
        // a syncs again: a3 is back in the cloud, b's tracks reach a
        await a.sync.sync();
        await b.sync.sync();
        expect(shared(a), shared(b));
        expect(shared(a).keys.length, 5);
      },
    );

    test(
      'way 1 takes the newest backup it can read and skips damaged ones',
      () async {
        final (cloud, _, b) = await damagedCloud();
        // the newest backup (highest generation) is damaged too: the one before it is used
        final gens = {
          for (var n = 1; n <= CloudSync.backupCount; n++)
            if (cloud.files[CloudSync.backupName(n)] case final f?)
              n: (jsonDecode(utf8.decode(f)) as Map)['generation'] as int,
        };
        final newest = gens.entries.reduce((x, y) => x.value > y.value ? x : y);
        cloud.putDirect(CloudSync.backupName(newest.key), damaged);
        final result = await b.sync.repairCloudState(
          CloudStateRepair.restoreBackup,
        );
        expect(result, CloudRepairResult.restored);
        final names = titles(cloudState(cloud));
        expect(names, containsAll(['a1', 'b1', 'b2']));
        expect(names, isNot(contains('a2')));
      },
    );

    test('way 2: replaces state.json with the state of this device', () async {
      final (cloud, a, b) = await damagedCloud();
      final mine = shared(b);
      final result = await b.sync.repairCloudState(
        CloudStateRepair.overwriteWithLocal,
      );
      expect(result, CloudRepairResult.overwritten);
      expect(cloudState(cloud).tracks.keys.toSet(), mine.keys.toSet());
      expect(shared(b), mine);
      expect(cloud.files[CloudSync.damagedName], damaged);
      expect(b.sync.status, SyncStatus.idle);
      // a keeps its tracks and brings them back to the cloud
      final aTracks = shared(a);
      await a.sync.sync();
      for (final e in aTracks.entries) {
        expect(a.library.track(e.key)?.toShared(), e.value);
      }
      await b.sync.sync();
      expect(shared(a), shared(b));
    });

    test('without a valid backup way 1 says so and leaves everything; way 2 still works', () async {
      final cloud = InMemoryProvider();
      final b = await device(cloud, 2);
      await b.add('b1.mp3');
      cloud.putDirect(CloudSync.stateName, damaged);
      cloud.putDirect(CloudSync.backupName(1), bytes('nonsense'));
      await b.sync.sync();
      final mine = shared(b);
      expect(
        await b.sync.repairCloudState(CloudStateRepair.restoreBackup),
        CloudRepairResult.noBackup,
      );
      expect(cloud.files[CloudSync.stateName], damaged);
      expect(shared(b), mine);
      expect(b.sync.status, SyncStatus.damaged);
      expect(
        await b.sync.repairCloudState(CloudStateRepair.overwriteWithLocal),
        CloudRepairResult.overwritten,
      );
      expect(cloudState(cloud).tracks.keys, mine.keys);
    });

    test(
      'readable again in the meantime: nothing is replaced, the sync goes on',
      () async {
        final (cloud, a, b) = await damagedCloud();
        // a repairs it first
        await a.sync.repairCloudState(CloudStateRepair.overwriteWithLocal);
        final version = cloud.versionOf(CloudSync.stateName);
        final result = await b.sync.repairCloudState(
          CloudStateRepair.overwriteWithLocal,
        );
        expect(result, CloudRepairResult.notDamaged);
        expect(b.sync.status, SyncStatus.idle);
        // b merged instead of replacing: a's tracks are still in the cloud
        expect(cloud.versionOf(CloudSync.stateName), isNot(version));
        expect(cloudState(cloud).tracks.keys.toSet(), {
          ...shared(a).keys,
          ...shared(b).keys,
        });
      },
    );

    test(
      'another device writes during the repair: its write is not overwritten',
      () async {
        final (cloud, a, b) = await damagedCloud();
        final good = await () async {
          await a.sync.repairCloudState(CloudStateRepair.overwriteWithLocal);
          return cloud.files[CloudSync.stateName]!;
        }();
        cloud.putDirect(CloudSync.stateName, damaged);
        var once = true;
        cloud.beforePut = (name) async {
          if (name == CloudSync.stateName && once) {
            once = false;
            cloud.putDirect(CloudSync.stateName, good);
          }
        };
        final result = await b.sync.repairCloudState(
          CloudStateRepair.overwriteWithLocal,
        );
        expect(result, CloudRepairResult.notDamaged);
        expect(cloudState(cloud).tracks.keys.toSet(), {
          ...shared(a).keys,
          ...shared(b).keys,
        });
      },
    );

    test('offline: the repair fails, nothing is lost or replaced', () async {
      final (cloud, _, b) = await damagedCloud();
      final mine = shared(b);
      cloud.offline = true;
      for (final how in CloudStateRepair.values) {
        expect(await b.sync.repairCloudState(how), CloudRepairResult.failed);
      }
      cloud.offline = false;
      expect(cloud.files[CloudSync.stateName], damaged);
      expect(shared(b), mine);
    });

    for (final (button, how) in [
      ('cloudStateRestoreBackup', CloudStateRepair.restoreBackup),
      ('cloudStateOverwrite', CloudStateRepair.overwriteWithLocal),
    ]) {
      testWidgets(
        'the dialog offers restoring first and overwriting second: $button',
        (tester) async {
          final sync = RepairSync(CloudRepairResult.restored);
          final app = await pumpApp(tester, sync: sync);
          app.library.report(const CloudStateUnreadable());
          await tester.pumpAndSettle();
          final restore = find.byKey(const Key('cloudStateRestoreBackup'));
          final overwrite = find.byKey(const Key('cloudStateOverwrite'));
          expect(restore, findsOneWidget);
          expect(overwrite, findsOneWidget);
          expect(find.byKey(const Key('cloudStateLater')), findsOneWidget);
          // the suggested way comes last (primary button)
          expect(
            tester.getTopLeft(restore).dx,
            greaterThan(tester.getTopLeft(overwrite).dx),
          );
          await tester.tap(find.byKey(Key(button)));
          await tester.pumpAndSettle();
          expect(sync.chosen, [how]);
          // the outcome is shown with a plain OK
          expect(find.byKey(const Key('message')), findsOneWidget);
          expect(restore, findsNothing);
          expect(overwrite, findsNothing);
        },
      );
    }

    testWidgets('without a backup only overwriting is offered', (tester) async {
      final sync = RepairSync(CloudRepairResult.noBackup);
      final app = await pumpApp(tester, sync: sync);
      app.library.report(const CloudStateUnreadable());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cloudStateRestoreBackup')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cloudStateRestoreBackup')), findsNothing);
      expect(find.byKey(const Key('cloudStateOverwrite')), findsOneWidget);
    });
  });

  group('#65/AK2 local data are never lost', () {
    test(
      'both ways keep every local track and what was saved loads again',
      () async {
        for (final how in CloudStateRepair.values) {
          final (_, _, b) = await damagedCloud();
          final mine = shared(b);
          await b.sync.repairCloudState(how);
          for (final e in mine.entries) {
            expect(b.library.track(e.key)?.toShared(), e.value, reason: '$how');
          }
          await expectSavedLocally(b);
          for (final t in b.library.tracks) {
            expect(b.library.hasFile(t.id), isTrue, reason: '$how');
          }
        }
      },
    );
  });

  group('#65/AK3 the message and the choice are in every ARB file', () {
    const keys = [
      'cloudStateUnreadable',
      'cloudStateRestoreBackup',
      'cloudStateOverwrite',
      'cloudStateLater',
      'cloudStateRestored',
      'cloudStateOverwritten',
      'cloudStateReadableAgain',
      'cloudStateNoBackup',
      'cloudStateRepairFailed',
    ];

    test('every ARB file has every key with a text', () {
      final arbs = Directory('lib/l10n')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.arb'))
          .toList();
      expect(arbs.length, greaterThanOrEqualTo(2));
      for (final f in arbs) {
        final j = jsonDecode(f.readAsStringSync()) as Map;
        for (final k in keys) {
          expect(
            j[k],
            isA<String>().having((s) => s.isEmpty, 'empty', false),
            reason: '$k in ${f.path}',
          );
        }
      }
    });

    test('every outcome has a text in every language', () {
      const messages = <LibraryMessage>[
        CloudStateUnreadable(),
        CloudStateRestored(),
        CloudStateOverwritten(),
        CloudStateReadableAgain(),
        CloudStateNoBackup(),
        CloudStateRepairFailed(),
      ];
      for (final locale in AppLocalizations.supportedLocales) {
        final l = lookupAppLocalizations(locale);
        for (final m in messages) {
          expect(libraryMessageText(l, m), isNotEmpty);
        }
        expect(l.cloudStateRestoreBackup, isNotEmpty);
        expect(l.cloudStateOverwrite, isNotEmpty);
        expect(l.cloudStateLater, isNotEmpty);
      }
      final de = lookupAppLocalizations(const Locale('de'));
      expect(de.cloudStateRestoreBackup, 'Sicherung wiederherstellen');
    });
  });
}
