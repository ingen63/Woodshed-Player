// #37: the sync in the app: NoSync without an account (no request, no provider module), the triggers, and
// the switches in the context menus. Temporary folders only, never the real library or a real account.
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/l10n/app_localizations.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/library/stamps.dart'
    show Hlc, SharedState, StampedRecord;
import 'package:woodshed_player/sync/in_memory_provider.dart';
import 'package:woodshed_player/sync/sync_engine.dart';
import 'package:woodshed_player/sync/sync_service.dart';

import 'fakes.dart';
import 'home_page_test.dart' show pumpApp;

/// How long a test watches that no request goes out (#95/AK2).
const _quiet = Duration(milliseconds: 50);

/// Counts what the app asks of the sync.
class CountingSync extends NoSync {
  final calls = <String>[];
  @override
  Future<void> start() async => calls.add('start');
  @override
  void resumed() => calls.add('resumed');
  @override
  void localChanged() => calls.add('changed');
}

/// Fails the test as soon as anything opens an HTTP connection.
class NoNetwork extends HttpOverrides {
  int clients = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    clients++;
    throw StateError('network access without an account');
  }
}

/// Files of lib/ reachable through imports and exports from [entry] (both branches of conditional imports).
Set<String> reachable(String entry) {
  final seen = <String>{};
  final todo = [entry];
  final directive = RegExp(r'^(?:import|export)\s[^;]*;', multiLine: true);
  final uri = RegExp(r"'([^']+)'");
  while (todo.isNotEmpty) {
    final path = todo.removeLast();
    if (!seen.add(path)) continue;
    final text = File(path).readAsStringSync();
    for (final d in directive.allMatches(text)) {
      for (final u in uri.allMatches(d.group(0)!)) {
        final s = u.group(1)!;
        if (s.startsWith('dart:') ||
            s.startsWith('package:') &&
                !s.startsWith('package:woodshed_player/')) {
          continue;
        }
        final target = s.startsWith('package:woodshed_player/')
            ? 'lib/${s.substring('package:woodshed_player/'.length)}'
            : File(path).parent.uri.resolve(s).toFilePath();
        todo.add(Uri.file(target).normalizePath().toFilePath());
      }
    }
  }
  return seen;
}

void main() {
  group('#37/AK2 without an account no request (NoSync)', () {
    test(
      'the app creates NoSync: start, changes and foreground send nothing',
      () async {
        final net = NoNetwork();
        await HttpOverrides.runZoned(() async {
          final dir = Directory.systemTemp.createTempSync('wp_nosync');
          addTearDown(() => dir.deleteSync(recursive: true));
          final app = TestApp(Directory('${dir.path}/lib'));
          expect(app.controller.sync, isA<NoSync>());
          expect(app.controller.sync.status, SyncStatus.off);
          await app.library.load();
          await app.controller.start();
          final src = File('${dir.path}/a.mp3')..writeAsStringSync('audio a');
          await app.library.importFiles([src.path]);
          final t = app.library.tracks.single;
          app.library.editMetadata(t.id, title: 'Neu', artist: null);
          app.library.setNoUpload({t.id}, true);
          app.controller.resumed();
          await Future<void>.delayed(_quiet); // absence: no request
        }, createHttpClient: net.createHttpClient);
        expect(net.clients, 0);
      },
    );

    test('the app does not import the sync engine or any provider', () {
      final files = {
        ...reachable('lib/main.dart'),
        ...reachable('lib/app/platform_native.dart'),
        ...reachable('lib/app/platform_web.dart'),
      };
      expect(files, contains(endsWith('sync/sync_service.dart')));
      for (final module in [
        'sync_engine.dart',
        'cloud_provider.dart',
        'in_memory_provider.dart',
      ]) {
        expect(files.where((f) => f.endsWith(module)), isEmpty, reason: module);
      }
      // no HTTP client anywhere in the app yet (providers come with #38 in app/lib/sync/providers/, #58)
      for (final f in files) {
        final text = File(f).readAsStringSync();
        expect(
          text.contains('HttpClient') || text.contains('package:http/'),
          isFalse,
          reason: f,
        );
      }
    });
  });

  group('#37 triggers are connected', () {
    test('start, change and foreground reach the sync service', () async {
      final dir = Directory.systemTemp.createTempSync('wp_sync_triggers');
      addTearDown(() => dir.deleteSync(recursive: true));
      final sync = CountingSync();
      final app = TestApp(Directory('${dir.path}/lib'), sync: (_) => sync);
      await app.library.load();
      await app.controller.start();
      final src = File('${dir.path}/a.mp3')..writeAsStringSync('audio a');
      await app.library.importFiles([src.path]);
      app.controller.resumed();
      expect(sync.calls, ['start', 'changed', 'resumed']);
    });

    testWidgets('coming back to the foreground calls resumed', (tester) async {
      final sync = CountingSync();
      final app = await pumpApp(tester, sync: sync);
      sync.calls.clear();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(sync.calls, contains('resumed'));
      expect(app.controller.sync, same(sync));
    });

    test(
      'with the InMemoryProvider: the app syncs on start and after a change',
      () async {
        final dir = Directory.systemTemp.createTempSync('wp_sync_app');
        addTearDown(() => dir.deleteSync(recursive: true));
        final cloud = InMemoryProvider();
        final withSync = TestApp(
          Directory('${dir.path}/lib'),
          sync: (l) => CloudSync(
            cloud,
            l,
            changeDelay: const Duration(milliseconds: 20),
          ),
        );
        await withSync.library.load();
        await withSync.controller.start();
        expect(
          cloud.files.keys,
          contains(CloudSync.deviceName(withSync.library.device.deviceId)),
        );
        final src = File('${dir.path}/a.mp3')..writeAsStringSync('audio a');
        await withSync.library.importFiles([src.path]);
        // #95/AK1: wait for the upload (a state, not a time)
        await eventually(
          () => cloud.files.keys.any((k) => k.startsWith('audio/')),
          'audio file uploaded',
        );
        expect(
          cloud.files.keys.where((k) => k.startsWith('audio/')),
          hasLength(1),
        );
        withSync.controller.dispose();
      },
    );
  });

  group('#37/AK5 switches in the context menus', () {
    testWidgets('track: «Nicht hochladen» switches the field', (tester) async {
      final app = await pumpApp(tester);
      await tester.tap(find.byKey(const Key('menu:Bossa')));
      await tester.pumpAndSettle();
      expect(find.text('Nicht hochladen'), findsOneWidget);
      await tester.tap(find.byKey(const Key('dontUpload')).first);
      await tester.pumpAndSettle();
      final t = app.library.tracks.firstWhere((t) => t.title == 'Bossa');
      expect(t.noUpload, isTrue);
      expect(app.library.state.tracks[t.id]!.values['noUpload'], isTrue);
    });

    testWidgets('folder: «Synchronisieren» is on and switches off', (
      tester,
    ) async {
      final app = await pumpApp(tester);
      final f = app.library.createFolder('Etüden');
      await tester.pump();
      await tester.tap(find.byTooltip('Ordner-Aktionen'));
      await tester.pumpAndSettle();
      final item = tester.widget<CheckboxMenuButton>(
        find.byKey(const Key('syncFolder:Etüden')).first,
      );
      expect(item.value, isTrue);
      await tester.tap(find.text('Synchronisieren'));
      await tester.pumpAndSettle();
      expect(app.library.folders.single.sync, isFalse);
      expect(app.library.state.folders[f.id]!.values['sync'], isFalse);
    });

    testWidgets(
      'a track from another device without its file: «Datei nur auf einem Gerät»',
      (tester) async {
        final app = await pumpApp(tester, titles: ['Hier']);
        const id =
            'ab0000000000000000000000000000000000000000000000000000000000cdef';
        final remote = SharedState(
          tracks: {
            id: StampedRecord.create(
              {
                'fileName': '$id.mp3',
                'title': 'Woanders',
                'dateAdded': '2026-11-01T00:00:00.000Z',
              },
              Hlc(
                DateTime.utc(2026, 11, 2).millisecondsSinceEpoch,
                0,
                'ffffffffffffffff',
              ),
            ),
          },
        );
        await tester.runAsync(() => app.library.mergeRemote(remote));
        await tester.pump();
        expect(find.byKey(const Key('onlyElsewhere:Woanders')), findsOneWidget);
        expect(find.text('Datei nur auf einem Gerät'), findsOneWidget);
        expect(find.byKey(const Key('onlyElsewhere:Hier')), findsNothing);
        // playing it explains why it does not load
        await tester.tap(find.byKey(const Key('track:Woanders')));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('nur auf einem anderen Gerät'),
          findsOneWidget,
        );
      },
    );
  });
  group('#107/AK7 the question about held tracks and folders (German, set in the test)', () {
    /// Holds every track of [app] back: a remote state whose horizon lies after all of them.
    Future<void> holdAll(WidgetTester tester, TestApp app) async {
      await tester.runAsync(() async {
        await app.library.markSynced();
        final h = Hlc(
          app.library.state.latest!.millis + 1000,
          0,
          'ffffffffffffffff',
        );
        await app.library.mergeRemote(SharedState.empty.copyWith(purged: h));
      });
      await tester.pump();
    }

    testWidgets(
      'a hint in the library, the dialog names the count and the first 10 names; «Später» keeps the question, «Behalten» keeps the tracks',
      (tester) async {
        final titles = [
          for (var i = 1; i <= 12; i++) 'T${'$i'.padLeft(2, '0')}',
        ];
        final app = await pumpApp(tester, titles: titles);
        expect(find.byKey(const Key('heldHint')), findsNothing);
        await holdAll(tester, app);
        expect(app.library.heldNames, titles);
        expect(find.byKey(const Key('heldHint')), findsOneWidget);
        expect(
          find.text(
            'Abgleich: 12 Titel und Ordner, die nur auf diesem Gerät waren, behalten?',
          ),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('heldDecide')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('heldDialog')), findsOneWidget);
        expect(find.text('Titel und Ordner behalten?'), findsOneWidget);
        expect(
          find.textContaining('Diese 12 Titel und Ordner'),
          findsOneWidget,
        );
        final names = tester
            .widget<Text>(find.byKey(const Key('heldNames')))
            .data!;
        expect(names.split('\n'), [
          for (final t in titles.take(10)) '• $t',
          'und 2 weitere',
        ]);
        await tester.tap(find.byKey(const Key('heldLater')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('heldDialog')), findsNothing);
        expect(find.byKey(const Key('heldHint')), findsOneWidget);
        expect(app.library.heldNames, hasLength(12));
        await tester.tap(find.byKey(const Key('heldDecide')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('heldKeep')));
        await tester.pump();
        await waitUntil(
          tester,
          () => app.library.state.tracks.length == 12,
          'kept tracks back in the shared state',
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('heldHint')), findsNothing);
        expect(app.library.heldNames, isEmpty);
        expect(app.library.tracks, hasLength(12));
        expect(app.library.state.tracks, hasLength(12));
      },
    );

    testWidgets('one entry: singular; «Entfernen» removes it', (tester) async {
      final app = await pumpApp(tester, titles: ['Solo']);
      await holdAll(tester, app);
      expect(
        find.text(
          'Abgleich: 1 Titel oder Ordner, der nur auf diesem Gerät war, behalten?',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('heldDecide')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Dieser Titel oder Ordner'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('heldNames'))).data,
        '• Solo',
      );
      await tester.tap(find.byKey(const Key('heldRemove')));
      await tester.pump();
      await waitUntil(
        tester,
        () => app.library.tracks.isEmpty && app.library.heldNames.isEmpty,
        'held track removed',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('heldHint')), findsNothing);
      expect(app.library.tracks, isEmpty);
    });

    test('the texts in English and German, with plurals', () {
      final en = lookupAppLocalizations(const Locale('en'));
      expect(en.heldMore(1), 'and 1 more');
      expect(en.heldMore(5), 'and 5 more');
      expect(de.heldMore(1), 'und 1 weiterer');
      expect(de.heldMore(5), 'und 5 weitere');
      expect(en.heldHint(1), contains('1 track or folder'));
      expect(en.heldHint(3), contains('3 tracks and folders'));
      expect(en.heldText(3), contains('These 3 tracks and folders'));
      for (final l in [en, de]) {
        for (final t in [
          l.heldTitle,
          l.heldDecide,
          l.heldExplain,
          l.heldKeep,
          l.heldRemove,
          l.heldLater,
        ]) {
          expect(t, isNotEmpty);
        }
      }
    });
  });
}
