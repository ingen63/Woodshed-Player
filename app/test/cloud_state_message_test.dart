// #111: since #53 every device writes only its own file (`devices/<id>.json`), so the repair dialog of #65
// is gone. What stays is the message for a cloud written by a newer app (#10/AK7). Fake sync only, never a
// real account or the real library.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/sync/sync_service.dart';
import 'package:woodshed_player/ui/messages.dart';

import 'home_page_test.dart' show pumpApp;

void main() {
  const removed = [
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

  List<Map<String, dynamic>> arbs() {
    final files = Directory('lib/l10n')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.arb'))
        .toList();
    expect(files.length, greaterThanOrEqualTo(2));
    return [
      for (final f in files)
        jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
    ];
  }

  test('#111/AK2 no ARB file has a key of the repair dialog any more', () {
    for (final j in arbs()) {
      for (final k in removed) {
        expect(j.containsKey(k), isFalse, reason: k);
        expect(j.containsKey('@$k'), isFalse, reason: '@$k');
      }
    }
  });

  test('#111/AK3 cloudStateTooNew stays in every ARB file and language', () {
    for (final j in arbs()) {
      expect(
        j['cloudStateTooNew'],
        isA<String>().having((s) => s.isEmpty, 'empty', false),
      );
    }
    for (final locale in AppLocalizations.supportedLocales) {
      final l = lookupAppLocalizations(locale);
      expect(libraryMessageText(l, const CloudStateTooNew(3)), isNotEmpty);
    }
  });

  testWidgets(
    '#111/AK1, AK3 a cloud from a newer app is shown with a plain OK, no repair',
    (tester) async {
      final app = await pumpApp(tester, sync: NoSync());
      app.library.report(const CloudStateTooNew(3));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('message')), findsOneWidget);
      final l = AppLocalizations.of(
        tester.element(find.byKey(const Key('message'))),
      );
      expect(find.text(l.cloudStateTooNew), findsOneWidget);
      for (final k in ['cloudStateRestoreBackup', 'cloudStateOverwrite']) {
        expect(find.byKey(Key(k)), findsNothing);
      }
      expect(find.widgetWithText(TextButton, l.ok), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, l.ok));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('message')), findsNothing);
      expect(app.controller.message, isNull);
    },
  );
}
