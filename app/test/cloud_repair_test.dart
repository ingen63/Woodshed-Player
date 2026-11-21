// #65: the dialog for a damaged `state.json` in the cloud. Since #53 every device writes only its own file
// (`devices/<id>.json`), so the engine never reports a damaged library any more; the dialog and its texts
// stay until the UI of the sync is reworked (M5). Every test runs against the InMemoryProvider and
// libraries in memory, never a real account or the real library.
import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/sync/in_memory_provider.dart';
import 'package:woodshed_player/sync/sync_service.dart';
import 'package:woodshed_player/ui/messages.dart';

import 'home_page_test.dart' show pumpApp;
import 'sync_test.dart' show bytes, device;

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
  group('#65/AK1 the dialog offers both ways', () {
    test(
      '#53: a damaged device file is skipped, so a repair only syncs',
      () async {
        final cloud = InMemoryProvider()
          ..putDirect(
            'devices/00000000000000aa.json',
            bytes('{"formatVersion": 2, "tracks": 7'),
          );
        final d = await device(cloud, 1);
        await d.add('a.mp3');
        for (final how in CloudStateRepair.values) {
          expect(
            await d.sync.repairCloudState(how),
            CloudRepairResult.notDamaged,
          );
        }
        expect(d.sync.status, SyncStatus.idle);
        expect(
          cloud.files.keys,
          contains('devices/${d.library.device.deviceId}.json'),
        );
        expect(d.library.lastError, isNull);
      },
    );

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
