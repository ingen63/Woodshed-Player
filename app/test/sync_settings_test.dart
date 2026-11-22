// #54: settings «Sync» and the hints around it (AK5, AK7–AK10, AK12). The provider part is a fake backend;
// the library is a temporary folder. Language fixed to German (fakes.dart), checks by key where possible.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/sync/cloud_account.dart';
import 'package:woodshed_player/sync/sync_service.dart';

import 'fakes.dart';
import 'home_page_test.dart' show pumpApp;

class FakeSync extends NoSync {
  SyncStatus value = SyncStatus.idle;
  int now = 0;
  int started = 0;
  int resumes = 0;
  @override
  SyncStatus get status => value;
  @override
  void resumed() => resumes++;
  @override
  Future<void> syncNow() async => now++;
  @override
  Future<void> start() async => started++;
}

class FakeBackend extends ChangeNotifier implements CloudBackend {
  @override
  final FakeSync sync = FakeSync();
  bool signedInValue = false;
  bool needs = false;
  bool? signInAnswer = true;
  int signOuts = 0;
  int loads = 0;
  bool disposed = false;
  CloudSpace? spaceValue = const CloudSpace(4000000000, 15000000000);
  List<CloudBackup> backupList = const [];
  @override
  DateTime? lastSync;
  @override
  Map<String, DateTime?> devices = {};
  @override
  List<String> errors = [];

  void expire() {
    needs = true;
    notifyListeners();
  }

  @override
  Future<void> load() async => loads++;
  @override
  bool get signedIn => signedInValue;
  @override
  bool get needsSignIn => needs;
  @override
  Future<bool?> signIn({String doneText = ''}) async {
    if (signInAnswer == true) {
      signedInValue = true;
      needs = false;
    }
    return signInAnswer;
  }

  @override
  void cancelSignIn() {}
  @override
  Future<void> signOut() async {
    signOuts++;
    signedInValue = false;
  }

  @override
  Future<CloudSpace?> space() async => spaceValue;
  @override
  Future<List<CloudBackup>> backups() async => backupList;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

/// Account with a fake backend; [google] false: as on the native iPhone/iPad app.
CloudAccount Function(Library) account(
  FakeBackend b, {
  bool google = true,
  bool folders = false,
}) =>
    (lib) => CloudAccount(
      library: lib,
      loadGoogle: google ? () async => b : null,
      chooseFolders: folders,
    );

Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('syncButton')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('syncSettings')), findsOneWidget);
}

/// Pumps until [done] holds; the library's real file work runs in between. Bounded by [hangGuard] (#95).
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() done,
  String what, {
  Duration hangGuard = const Duration(seconds: 60),
}) async {
  final watch = Stopwatch()..start();
  while (!done() && watch.elapsed < hangGuard) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  expect(done(), isTrue, reason: 'hang: «$what» not reached');
  await tester.pumpAndSettle();
}

bool shown(Finder f) => f.evaluate().isNotEmpty;

/// Taps [key] and waits until [done].
Future<void> tapAsync(
  WidgetTester tester,
  Key key,
  bool Function() done,
  String what,
) async {
  await tester.tap(find.byKey(key));
  await pumpUntil(tester, done, what);
}

void main() {
  group('#54/AK7 settings: choose Google Drive, sign in, sign out', () {
    testWidgets('choose, sign in and sign out; the choice stays per device', (
      tester,
    ) async {
      final b = FakeBackend();
      final app = await pumpApp(tester, cloud: account(b));
      expect(find.text(de.syncLine(de.syncStatusOff)), findsOneWidget);
      await openSettings(tester);
      expect(find.byKey(const Key('syncSignIn')), findsNothing);
      await tapAsync(
        tester,
        const Key('syncChoice-google'),
        () => app.library.device.syncProvider == 'google',
        'Google chosen',
      );
      expect(app.library.device.syncProvider, 'google');
      expect(b.loads, 0, reason: 'nothing loaded before signing in');
      await tapAsync(
        tester,
        const Key('syncSignIn'),
        () => b.sync.now == 1,
        'signed in and synced',
      );
      expect(b.signedInValue, isTrue);
      expect(app.controller.cloud.sync.inner, same(b.sync));
      expect(b.sync.now, 1, reason: 'the first sync starts');
      expect(find.byKey(const Key('syncSignOut')), findsOneWidget);
      await tester.tap(find.byKey(const Key('syncSignOut')));
      await tester.pumpAndSettle();
      await tapAsync(
        tester,
        const Key('syncSignOutConfirm'),
        () => b.disposed,
        'signed out',
      );
      expect(b.signOuts, 1);
      expect(b.disposed, isTrue);
      expect(app.controller.cloud.sync.inner, isA<NoSync>());
      expect(find.byKey(const Key('syncSignIn')), findsOneWidget);
      expect(find.text(de.syncNotSignedIn), findsWidgets);
      await tapAsync(
        tester,
        const Key('syncChoice-none'),
        () => app.library.device.syncProvider == null,
        'off',
      );
      expect(app.library.device.syncProvider, isNull);
      expect(find.byKey(const Key('syncSignIn')), findsNothing);
    });

    testWidgets('a failed sign-in says so and leaves the sync off', (
      tester,
    ) async {
      final b = FakeBackend()..signInAnswer = false;
      final app = await pumpApp(tester, cloud: account(b));
      await tester.runAsync(() => app.library.setSyncProvider('google'));
      await openSettings(tester);
      await tapAsync(
        tester,
        const Key('syncSignIn'),
        () => shown(find.text(de.syncSignInFailed)),
        'failure shown',
      );
      expect(find.text(de.syncSignInFailed), findsOneWidget);
      expect(app.controller.cloud.sync.inner, isA<NoSync>());
    });

    testWidgets(
      'web: the page goes to Google (no answer yet), nothing else happens',
      (tester) async {
        final b = FakeBackend()..signInAnswer = null;
        final app = await pumpApp(tester, cloud: account(b));
        await tester.runAsync(() => app.library.setSyncProvider('google'));
        await openSettings(tester);
        await tapAsync(
          tester,
          const Key('syncSignIn'),
          () => b.loads == 1 && !app.controller.cloud.signingIn,
          'redirected',
        );
        expect(app.controller.cloud.sync.inner, isA<NoSync>());
        expect(find.text(de.syncSignInFailed), findsNothing);
      },
    );

    testWidgets(
      'iPhone/iPad app: Google Drive is not offered, with a hint to the web app',
      (tester) async {
        final b = FakeBackend();
        final app = await pumpApp(tester, cloud: account(b, google: false));
        await tester.runAsync(() => app.library.setSyncProvider('google'));
        await openSettings(tester);
        expect(find.byKey(const Key('syncChoice-google')), findsNothing);
        expect(find.byKey(const Key('syncWebOnly')), findsOneWidget);
        expect(find.text(de.syncGoogleWebOnly), findsOneWidget);
        expect(app.controller.cloud.choice, CloudChoice.none);
        await tester.runAsync(() => app.controller.cloud.open());
        expect(b.loads, 0);
      },
    );

    testWidgets('at start the chosen and signed-in sync runs', (tester) async {
      final b = FakeBackend()..signedInValue = true;
      final app = await pumpApp(tester, cloud: account(b));
      await tester.runAsync(() async {
        await app.library.setSyncProvider('google');
        await app.controller.start();
      });
      expect(app.controller.cloud.sync.inner, same(b.sync));
      expect(b.sync.started, 1);
    });
  });

  group('#54/AK8 status, last sync per device, errors, «Sync now»', () {
    testWidgets('the settings show it all; the button syncs', (tester) async {
      final b = FakeBackend()
        ..signedInValue = true
        ..lastSync = DateTime(2026, 11, 22, 9, 30)
        ..errors = ['up:abc: CloudError(write: 500)', 'down:def: x'];
      final app = await pumpApp(tester, cloud: account(b));
      await tester.runAsync(() async {
        await app.library.setSyncProvider('google');
        await app.controller.cloud.open();
      });
      final me = app.library.device.deviceId;
      b.devices = {
        'aaaaaaaaaaaaaaaa': DateTime(2026, 11, 20, 8, 15),
        me: DateTime(2026, 11, 22, 9, 30),
        'bbbbbbbbbbbbbbbb': null,
      };
      await tester.pump();
      expect(find.text(de.syncLine(de.syncStatusIdle)), findsOneWidget);
      await openSettings(tester);
      expect(find.text(de.syncStatusIdle), findsOneWidget);
      expect(find.text(de.syncLastSync('22.11.2026 09:30')), findsOneWidget);
      expect(find.text(de.syncErrors(2)), findsOneWidget);
      expect(find.text(de.syncThisDevice), findsOneWidget);
      expect(find.text(de.syncDevice('aaaaaa')), findsOneWidget);
      expect(find.text('20.11.2026 08:15'), findsOneWidget);
      expect(find.text(de.syncUnknown), findsOneWidget);
      // own device first
      final rows = tester
          .widgetList<Row>(
            find.byWidgetPredicate(
              (w) => w is Row && '${w.key}'.contains('syncDevice-'),
            ),
          )
          .map((r) => '${r.key}')
          .toList();
      expect(rows.first, contains(me));
      await tapAsync(
        tester,
        const Key('syncNow'),
        () => b.sync.now == 1,
        'synced',
      );
      expect(b.sync.now, 1);
      for (final (s, text) in [
        (SyncStatus.syncing, de.syncStatusSyncing),
        (SyncStatus.offline, de.syncStatusOffline),
        (SyncStatus.failed, de.syncStatusFailed),
        (SyncStatus.tooNew, de.syncStatusTooNew),
        (SyncStatus.foreignLibrary, de.syncStatusForeign),
        (SyncStatus.off, de.syncStatusWaiting),
      ]) {
        b.sync.value = s;
        b.sync.notifyListeners();
        await tester.pump();
        expect(find.text(text), findsWidgets, reason: '$s');
      }
    });

    testWidgets('never synced yet', (tester) async {
      final b = FakeBackend()..signedInValue = true;
      final app = await pumpApp(tester, cloud: account(b));
      await tester.runAsync(() async {
        await app.library.setSyncProvider('google');
        await app.controller.cloud.open();
      });
      await openSettings(tester);
      expect(find.text(de.syncNever), findsOneWidget);
      expect(find.byKey(const Key('syncErrors')), findsNothing);
    });
  });

  group('#54/AK5 hint to sign in again, never during playback', () {
    testWidgets('expired while playing: the hint waits until playback stops', (
      tester,
    ) async {
      final b = FakeBackend()..signedInValue = true;
      final app = await pumpApp(tester, cloud: account(b));
      await tester.runAsync(() async {
        await app.library.setSyncProvider('google');
        await app.controller.cloud.open();
      });
      final t = app.library.sortedTracks.first;
      await tester.tap(find.byKey(Key('track:${t.title}')));
      await tester.pump();
      app.finishLoads(30);
      await tester.pump();
      app.player.play();
      await tester.pump();
      expect(app.player.isPlaying, isTrue);
      b.expire();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('signInHint')), findsNothing);
      app.player.pause();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('signInHint')), findsOneWidget);
      expect(find.text(de.syncSignInAgain), findsOneWidget);
      await tester.tap(find.byKey(const Key('signInHintSettings')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('syncSettings')), findsOneWidget);
      expect(find.byKey(const Key('syncSignIn')), findsOneWidget);
      // only once
      b.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('signInHint')), findsNothing);
    });

    testWidgets('a sync that waited for playback goes on when it stops', (
      tester,
    ) async {
      final b = FakeBackend()..signedInValue = true;
      final app = await pumpApp(tester, cloud: account(b));
      await tester.runAsync(() async {
        await app.library.setSyncProvider('google');
        await app.controller.cloud.open();
      });
      final t = app.library.sortedTracks.first;
      await tester.tap(find.byKey(Key('track:${t.title}')));
      await tester.pump();
      app.finishLoads(30);
      await tester.pump();
      app.player.play();
      app.player.pause();
      expect(b.sync.resumes, 0, reason: 'not waiting: nothing to do');
      b.sync.value = SyncStatus.offline;
      app.player.play();
      expect(b.sync.resumes, 0, reason: 'never while playing');
      app.player.pause();
      expect(b.sync.resumes, 1);
      await tester.pump();
    });
  });

  group('#54/AK9 a backup can be restored', () {
    testWidgets(
      'the list of backups, newest first; the chosen one comes back',
      (tester) async {
        final b = FakeBackend()..signedInValue = true;
        final app = await pumpApp(tester, cloud: account(b));
        await tester.runAsync(() async {
          await app.library.setSyncProvider('google');
          await app.controller.cloud.open();
        });
        final before = app.library.state;
        final first = app.library.sortedTracks.first;
        app.library.editMetadata(first.id, title: 'Geändert', artist: null);
        app.library.delete({app.library.sortedTracks.last.id});
        await tester.pump();
        b.backupList = [
          CloudBackup(
            'backup/x/state-1.json',
            DateTime(2026, 11, 11, 10),
            before,
          ),
          CloudBackup(
            'backup/x/state-2.json',
            DateTime(2026, 11, 12, 10),
            before,
          ),
        ];
        await openSettings(tester);
        await tester.tap(find.byKey(const Key('syncRestore')));
        await pumpUntil(
          tester,
          () => shown(find.byKey(const Key('syncBackup-0'))),
          'backups listed',
        );
        expect(find.text(de.syncBackupOf('12.11.2026 10:00')), findsOneWidget);
        final tiles = tester
            .widgetList<ListTile>(
              find.descendant(
                of: find.byKey(const Key('syncRestoreDialog')),
                matching: find.byType(ListTile),
              ),
            )
            .toList();
        expect(
          (tiles.first.title! as Text).data,
          de.syncBackupOf('12.11.2026 10:00'),
        );
        await tester.tap(find.byKey(const Key('syncBackup-0')));
        await pumpUntil(
          tester,
          () => shown(find.text(de.syncRestoreDone)),
          'restored',
        );
        expect(find.text(de.syncRestoreDone), findsOneWidget);
        expect(app.library.tracks.length, 3);
        expect(app.library.track(first.id)!.title, first.title);
        expect(
          b.sync.now,
          greaterThanOrEqualTo(1),
          reason: 'the restored state goes out',
        );
      },
    );

    testWidgets('no backups yet', (tester) async {
      final b = FakeBackend()..signedInValue = true;
      final app = await pumpApp(tester, cloud: account(b));
      await tester.runAsync(() async {
        await app.library.setSyncProvider('google');
        await app.controller.cloud.open();
      });
      await openSettings(tester);
      await tester.tap(find.byKey(const Key('syncRestore')));
      await pumpUntil(
        tester,
        () => shown(find.byKey(const Key('syncRestoreNone'))),
        'empty list',
      );
      expect(find.byKey(const Key('syncRestoreNone')), findsOneWidget);
    });

    test(
      'Library.restore: values, deletions and revivals as new changes',
      () async {
        final dir = Directory.systemTemp.createTempSync('wp_restore');
        addTearDown(() => dir.deleteSync(recursive: true));
        final app = TestApp(Directory('${dir.path}/lib'));
        await app.library.load();
        final src = Directory('${dir.path}/src')..createSync();
        await app.library.importFiles([
          for (final n in ['a', 'b'])
            (File('${src.path}/$n.mp3')..writeAsStringSync('audio $n')).path,
        ]);
        final f = app.library.createFolder('Ordner');
        app.library.sortOrder = TrackSortOrder.alphabetical;
        await app.library.save();
        final backup = app.library.state;
        final a = app.library.tracks.firstWhere((t) => t.title == 'a');
        final b = app.library.tracks.firstWhere((t) => t.title == 'b');
        app.library.editMetadata(a.id, title: 'A2', artist: null);
        app.library.delete({b.id});
        app.library.deleteFolder(f.id);
        app.library.createFolder('Neu');
        app.library.sortOrder = TrackSortOrder.dateAdded;
        final held = app.library.createPlaylist('Nur hier');
        app.library.setPlaylistShared(held.id, false);
        await app.library.save();
        final stampBefore = app.library.state.latest!;
        var changes = 0;
        app.library.onLocalChange = () => changes++;
        expect(await app.library.restore(backup), isTrue);
        expect(app.library.tracks.map((t) => t.title).toSet(), {'a', 'b'});
        expect(app.library.folders.map((x) => x.name), ['Ordner']);
        expect(app.library.sortOrder, TrackSortOrder.alphabetical);
        expect(app.library.playlists.map((p) => p.name), [
          'Nur hier',
        ], reason: 'only on this device: kept');
        expect(changes, 1);
        expect(
          app.library.state.latest! > stampBefore,
          isTrue,
          reason: 'new stamps win the merge',
        );
        // b came back without its file (deleted with the track): loaded from the cloud
        expect(app.library.hasFile(b.id), isFalse);
        expect(app.library.hasFile(a.id), isTrue);
        final saved = jsonDecode(
          await File('${dir.path}/lib/library.json').readAsString(),
        ) as Map;
        expect((saved['tracks'] as Map).length, 2);
      },
    );
  });

  group(
    '#54/AK10 first sign-in on the desktop: folders with size and free space',
    () {
      testWidgets(
        'the choice comes before the first sync and sets «sync» per folder',
        (tester) async {
          final b = FakeBackend();
          final app = await pumpApp(tester, cloud: account(b, folders: true));
          final lib = app.library;
          late TrackFolder keep, skip;
          await tester.runAsync(() async {
            await lib.setSyncProvider('google');
            keep = lib.createFolder('Üben');
            skip = lib.createFolder('Aufnahmen');
            final ts = lib.sortedTracks;
            lib.moveTracks({ts[0].id}, keep.id);
            lib.moveTracks({ts[1].id, ts[2].id}, skip.id);
            await lib.save();
          });
          await tester.pump();
          await openSettings(tester);
          await tester.tap(find.byKey(const Key('syncSignIn')));
          await pumpUntil(
            tester,
            () => shown(find.byKey(Key('syncFolderSize-${keep.id}'))),
            'folder sizes',
          );
          expect(find.byKey(const Key('syncFolders')), findsOneWidget);
          expect(b.sync.now, 0, reason: 'no sync before the choice');
          expect(app.controller.cloud.sync.inner, isA<NoSync>());
          expect(
            find.text(de.syncFree(formatBytesDe(11000000000))),
            findsOneWidget,
          );
          final size = 'audio Ärger'.length; // bytes of the file in «Üben»
          expect(
            tester
                .widget<Text>(find.byKey(Key('syncFolderSize-${keep.id}')))
                .data,
            '$size B',
          );
          await tester.tap(find.byKey(Key('syncFolder-${skip.id}')));
          await tester.pump();
          await tapAsync(
            tester,
            const Key('syncFoldersStart'),
            () => b.sync.now == 1,
            'first sync',
          );
          expect(lib.folders.firstWhere((f) => f.id == skip.id).sync, isFalse);
          expect(lib.folders.firstWhere((f) => f.id == keep.id).sync, isTrue);
          expect(app.controller.cloud.sync.inner, same(b.sync));
          expect(b.sync.now, 1);
        },
      );

      testWidgets('free space unknown; no folders', (tester) async {
        final b = FakeBackend()..spaceValue = null;
        final app = await pumpApp(tester, cloud: account(b, folders: true));
        await tester.runAsync(() => app.library.setSyncProvider('google'));
        await openSettings(tester);
        await tapAsync(
          tester,
          const Key('syncSignIn'),
          () => shown(find.text(de.syncNoFolders)),
          'folder choice',
        );
        expect(find.text(de.syncFreeUnknown), findsOneWidget);
        expect(find.text(de.syncNoFolders), findsOneWidget);
      });

      testWidgets('a device that synced before is not asked again', (
        tester,
      ) async {
        final b = FakeBackend();
        final app = await pumpApp(tester, cloud: account(b, folders: true));
        await tester.runAsync(() async {
          await app.library.setSyncProvider('google');
          await app.library.markSynced();
        });
        await openSettings(tester);
        await tapAsync(
          tester,
          const Key('syncSignIn'),
          () => b.sync.now == 1,
          'synced',
        );
        expect(find.byKey(const Key('syncFolders')), findsNothing);
        expect(b.sync.now, 1);
      });

      test('CloudSpace.free never below zero; unlimited is unknown', () {
        expect(const CloudSpace(5, 10).free, 5);
        expect(const CloudSpace(15, 10).free, 0);
        expect(const CloudSpace(5, null).free, isNull);
      });
    },
  );

  group('#54/AK12 every new text in every ARB file', () {
    test(
      'the sync texts exist in English and German with the same placeholders',
      () {
        final en =
            jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync()) as Map;
        final de =
            jsonDecode(File('lib/l10n/app_de.arb').readAsStringSync()) as Map;
        final keys = [
          for (final k in en.keys)
            if (k is String && (k.startsWith('sync') || k == 'settings')) k,
        ];
        expect(keys.length, greaterThan(40));
        final ph = RegExp(r'\{(\w+)');
        for (final k in keys) {
          expect(de[k], isA<String>(), reason: k);
          expect(de[k], isNot(isEmpty), reason: k);
          expect(
            ph.allMatches(de[k] as String).map((m) => m[1]).toSet(),
            ph.allMatches(en[k] as String).map((m) => m[1]).toSet(),
            reason: k,
          );
        }
      },
    );
  });
}

String formatBytesDe(int b) =>
    '${(b / 1e9).toStringAsFixed(1).replaceAll('.', ',')} GB';
