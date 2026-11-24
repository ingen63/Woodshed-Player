// #54: details of the Google Drive sync found by the mutation tests: what the provider remembers (fewer
// requests, never a stale ID), the upload sessions, the account and backend notifications, the backups,
// the device list of the engine and the restore of the library. Simulated Drive only (AK13).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/sync/cloud_account.dart';
import 'package:woodshed_player/sync/cloud_provider.dart';
import 'package:woodshed_player/sync/google_sync.dart';
import 'package:woodshed_player/sync/providers/google_auth.dart';
import 'package:woodshed_player/sync/providers/google_auth_desktop.dart';
import 'package:woodshed_player/sync/providers/google_drive_provider.dart';
import 'package:woodshed_player/sync/providers/google_platform_io.dart';
import 'package:woodshed_player/sync/providers/http_transport.dart';
import 'package:woodshed_player/sync/secret_store.dart';
import 'package:woodshed_player/sync/sync_engine.dart';
import 'package:woodshed_player/sync/sync_service.dart';

import 'fakes.dart';
import 'google_fakes.dart';
import 'sync_test.dart' show bytes, sources;

const kib = 1024;
Uint8List big(int n, [int seed = 7]) =>
    Uint8List.fromList(List.generate(n, (i) => i * seed % 251));

GoogleDriveProvider provider(
  FakeDrive drive, {
  GoogleAuth? auth,
  int resumableAbove = 100 * kib,
}) => GoogleDriveProvider(
  transport: drive.transport(),
  auth: auth ?? FixedAuth(),
  resumableAbove: resumableAbove,
  chunkSize: 256 * kib,
);

Future<Library> library() async {
  final lib = Library(
    MemoryFileStore(),
    probe: (_) => 2.5,
    readSource: (s) async => sources[s],
    saveDelay: Duration.zero,
  );
  await lib.load();
  return lib;
}

/// Counts notifications of [n].
int Function() counter(Listenable n) {
  var count = 0;
  n.addListener(() => count++);
  return () => count;
}

void main() {
  group('#54/AK3 the provider remembers IDs and never uses a stale one', () {
    test('a known file costs one request; the root is searched once', () async {
      final drive = FakeDrive();
      final p = provider(drive);
      await p.put('devices/a.json', bytes('a'));
      var n = drive.calls.length;
      expect((await p.get('devices/a.json'))!.bytes, bytes('a'));
      expect(drive.calls.length - n, 1, reason: 'media only');
      final fresh = provider(drive);
      final from = drive.calls.length;
      await fresh.list('devices/');
      await fresh.list('audio/');
      await p.list('devices/');
      final rootSearches = drive.calls
          .skip(from)
          .where(
            (c) =>
                c.url.queryParameters['q']?.contains("'root' in parents") ??
                false,
          );
      expect(rootSearches, hasLength(1));
      // deleted: the next get lists the folder once instead of asking for the old ID
      n = drive.calls.length;
      await p.put('devices/a.json', bytes('b'));
      expect(
        drive.calls.length - n,
        1,
        reason: 'write a known file: one request',
      );
      n = drive.calls.length;
      await p.delete('devices/a.json');
      expect(
        drive.calls.length - n,
        1,
        reason: 'delete a known file: one request',
      );
      n = drive.calls.length;
      expect(await p.get('devices/a.json'), isNull);
      expect(drive.calls.length - n, 1);
    });

    test('a listing forgets files and folders that are gone', () async {
      final drive = FakeDrive();
      final p = provider(drive);
      await p.put('devices/a.json', bytes('a'));
      await p.put('audio/x.mp3', bytes('x'));
      final file = drive.files.values.firstWhere((f) => f.name == 'a.json');
      final audio = drive.files.values.firstWhere((f) => f.name == 'audio');
      drive.files
        ..remove(file.id)
        ..remove(audio.id); // removed in Drive by another device or by hand
      await p.list('devices/');
      await p.list('');
      final n = drive.calls.length;
      expect(await p.get('devices/a.json'), isNull);
      expect(drive.calls.length - n, 1, reason: 'no request for the old ID');
      await p.put('audio/y.mp3', bytes('y'));
      expect(drive.paths, contains('WoodshedPlayer/audio/y.mp3'));
    });

    test('a new device reads a file of a folder it never listed', () async {
      final drive = FakeDrive();
      await provider(drive).put('devices/a.json', bytes('a'));
      final fresh = provider(drive);
      expect((await fresh.get('devices/a.json'))!.bytes, bytes('a'));
      expect(drive.roots, hasLength(1));
    });

    test('reading creates no folder', () async {
      final drive = FakeDrive();
      final p = provider(drive);
      await p.put('format.json', bytes('1'));
      expect(await p.get('nothing/a.json'), isNull);
      expect(await p.list('nothing/'), isEmpty);
      await p.delete('nothing/a.json');
      expect(drive.files.values.where((f) => f.name == 'nothing'), isEmpty);
    });

    test('names with «/» or empty are left out; a hidden name gets its number at the end', () async {
      final drive = FakeDrive();
      final p = provider(drive);
      await p.put('devices/x.json', bytes('x'));
      final devices = drive.files.values.firstWhere((f) => f.name == 'devices');
      drive.addFile('a/b.json', devices.id, bytes('1'));
      drive.addFile('', devices.id, bytes('2'));
      drive.addFile('.hidden', devices.id, bytes('3'));
      drive.addFile('.hidden', devices.id, bytes('4'));
      expect((await p.list('devices/')).map((e) => e.name).toList(), [
        'devices/x.json',
        'devices/.hidden',
        'devices/.hidden (1)',
      ]);
    });

    test('a file already gone when deleting is no error', () async {
      final drive = FakeDrive();
      final p = provider(drive);
      await p.put('devices/a.json', bytes('a'));
      drive.files.removeWhere((_, f) => f.name == 'a.json');
      await p.delete('devices/a.json');
      drive.respond = (c) => c.method == 'DELETE'
          ? HttpReply.json(500, {
              'error': {'message': 'backend'},
            })
          : null;
      await p.put('devices/b.json', bytes('b'));
      await expectLater(p.delete('devices/b.json'), throwsA(isA<CloudError>()));
    });

    test('an error without details names its message', () async {
      final drive = FakeDrive()
        ..respond = (_) => HttpReply.json(400, {
          'error': {'errors': <Object>[], 'message': 'bad request'},
        });
      await expectLater(
        provider(drive).list('devices/'),
        throwsA(
          isA<CloudError>().having(
            (e) => e.detail,
            'detail',
            contains('bad request'),
          ),
        ),
      );
    });

    test('blocks must be multiples of 256 KiB', () {
      expect(
        () => GoogleDriveProvider(
          transport: FakeDrive().transport(),
          auth: FixedAuth(),
          chunkSize: 1000,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('#54/AK4 upload sessions', () {
    test('exactly at the limit one request, above it in blocks', () async {
      final drive = FakeDrive();
      final p = provider(drive);
      await p.put('audio/a.mp3', big(100 * kib));
      expect(p.sentBytes, 0);
      await p.put('audio/b.mp3', big(100 * kib + 1));
      expect(p.sentBytes, 100 * kib + 1);
    });

    test(
      'a finished session is never used for the next file of that name',
      () async {
        final drive = FakeDrive();
        final p = provider(drive);
        // the answer of the last block is lost: the status query finishes it
        var lose = true;
        drive.cut = (c) {
          if (lose &&
              c.url.queryParameters.containsKey('upload_id') &&
              (c.headers['Content-Range']?.startsWith('bytes ${256 * kib}') ??
                  false)) {
            lose = false;
            drive.answer(c);
            return true;
          }
          return false;
        };
        await expectLater(
          p.put('audio/a.mp3', big(300 * kib)),
          throwsA(isA<CloudOffline>()),
        );
        await p.put('audio/a.mp3', big(300 * kib));
        // the same name and size with other contents goes up anew, once by status query, once after blocks
        final other = big(300 * kib, 11);
        await p.put('audio/a.mp3', other);
        expect((await p.get('audio/a.mp3'))!.bytes, other);
        final third = big(300 * kib, 13);
        await p.put('audio/a.mp3', third);
        expect((await p.get('audio/a.mp3'))!.bytes, third);
        expect(
          drive.files.values.where((f) => f.name == 'a.mp3'),
          hasLength(1),
        );
      },
    );

    test(
      'a server error in a block keeps the session: the next try goes on',
      () async {
        final drive = FakeDrive();
        final p = provider(drive);
        var blocks = 0;
        drive.respond = (c) =>
            c.url.queryParameters.containsKey('upload_id') &&
                c.body != null &&
                ++blocks == 2
            ? HttpReply.json(503, {'error': 'busy'})
            : null;
        final data = big(600 * kib);
        await expectLater(
          p.put('audio/a.mp3', data),
          throwsA(isA<CloudError>()),
        );
        final sent = p.sentBytes;
        await p.put('audio/a.mp3', data);
        expect(p.sentBytes - sent, 600 * kib - 256 * kib);
        expect((await p.get('audio/a.mp3'))!.bytes, data);
      },
    );

    test(
      'an expired session in the middle starts again on the next try',
      () async {
        final drive = FakeDrive();
        final p = provider(drive);
        var blocks = 0;
        drive.respond = (c) {
          if (c.url.queryParameters.containsKey('upload_id') &&
              c.body != null &&
              ++blocks == 2) {
            drive.sessions.clear();
            return HttpReply.json(404, {'error': 'gone'});
          }
          return null;
        };
        final data = big(600 * kib);
        await expectLater(
          p.put('audio/a.mp3', data),
          throwsA(isA<CloudError>()),
        );
        await p.put('audio/a.mp3', data);
        expect((await p.get('audio/a.mp3'))!.bytes, data);
      },
    );
  });

  group('#54/AK11 a closed provider sends nothing', () {
    test('no token is asked for and no request goes out', () async {
      final drive = FakeDrive();
      final auth = _CountingAuth();
      final p = provider(drive, auth: auth);
      p.close();
      await expectLater(p.list(''), throwsA(isA<CloudSignInRequired>()));
      expect(auth.asked, 0);
      expect(drive.calls, isEmpty);
    });
  });

  group('#54/AK1 desktop sign-in details', () {
    test('the token of the exchange is used, no refresh right after', () async {
      final drive = FakeDrive();
      final auth = DesktopGoogleAuth(
        transport: drive.transport(),
        secrets: MemorySecretStore(),
        openBrowser: _answer,
      );
      final notified = counter(auth);
      expect(await auth.signIn(), SignInResult.signedIn);
      expect(notified(), 1);
      await auth.token();
      expect(drive.log.where((l) => l.endsWith('/token')), hasLength(1));
    });

    test(
      'a browser that keeps its connection open does not hold up the end',
      () async {
        final drive = FakeDrive();
        final clients = <HttpClient>[];
        addTearDown(() {
          for (final c in clients) {
            c.close(force: true);
          }
        });
        final auth = DesktopGoogleAuth(
          transport: drive.transport(),
          secrets: MemorySecretStore(),
          openBrowser: (url) => _answer(url, keep: clients),
        );
        expect(
          await auth.signIn().timeout(const Duration(seconds: 20)),
          SignInResult.signedIn,
        );
      },
    );

    test(
      'a second sign-in ends the first; sign-out ends a waiting one',
      () async {
        final drive = FakeDrive();
        final secrets = MemorySecretStore();
        var calls = 0;
        final auth = DesktopGoogleAuth(
          transport: drive.transport(),
          secrets: secrets,
          openBrowser: (url) async {
            if (++calls == 2) await _answer(url);
          },
          waitForBrowser: const Duration(minutes: 10),
        );
        final first = auth.signIn();
        await eventually(() => calls == 1, 'first browser');
        final second = auth.signIn();
        expect(
          await first.timeout(const Duration(seconds: 20)),
          SignInResult.failed,
        );
        expect(await second, SignInResult.signedIn);
        final third = auth.signIn();
        await eventually(() => calls == 3, 'third browser');
        await auth.signOut();
        expect(
          await third.timeout(const Duration(seconds: 20)),
          SignInResult.failed,
        );
      },
    );

    test(
      'a new sign-in and the sign-out clear «sign in again»; both are notified',
      () async {
        final drive = FakeDrive();
        final secrets = MemorySecretStore();
        await secrets.write(DesktopGoogleAuth.refreshKey, 'revoked');
        final auth = DesktopGoogleAuth(
          transport: drive.transport(),
          secrets: secrets,
          openBrowser: _answer,
        );
        final notified = counter(auth);
        await auth.load();
        expect(notified(), 1);
        await expectLater(auth.token(), throwsA(isA<CloudSignInRequired>()));
        expect(auth.needsSignIn, isTrue);
        expect(notified(), 2);
        await auth.signIn();
        expect(auth.needsSignIn, isFalse);
        await secrets.write(DesktopGoogleAuth.refreshKey, 'revoked');
        final again = DesktopGoogleAuth(
          transport: drive.transport(),
          secrets: secrets,
          openBrowser: _answer,
        );
        await again.load();
        await expectLater(again.token(), throwsA(isA<CloudSignInRequired>()));
        final before = counter(again);
        await again.signOut();
        expect(again.needsSignIn, isFalse);
        expect(before(), 1);
      },
    );
  });

  group('#54/AK7 account and backend', () {
    test(
      'the switch follows only the service in use and forgets it when disposed',
      () {
        final a = _Notifying();
        final b = _Notifying();
        final s = SyncSwitch();
        final n = counter(s);
        s.use(a);
        expect(n(), 1);
        s.use(b);
        a.ping();
        expect(n(), 2, reason: 'the previous one is no longer followed');
        b.ping();
        expect(n(), 3);
        s.dispose();
        b.ping(); // no call into the disposed switch
        expect(() => s.addListener(() {}), throwsStateError);
      },
    );

    test('choose, sign in twice at once, sign-out and dispose', () async {
      final lib = await library();
      await lib.setSyncProvider('google');
      final b = _Backend();
      final account = CloudAccount(library: lib, loadGoogle: () async => b);
      final n = counter(account);
      expect(
        await CloudAccount(
          library: await library(),
          loadGoogle: () async => b,
        ).signIn(),
        isFalse,
        reason: 'nothing chosen',
      );
      expect(b.signIns, 0);
      final seen = <bool>[];
      account.addListener(() => seen.add(account.signingIn));
      final gate = Completer<bool?>();
      b.answer = gate.future;
      final first = account.signIn();
      await eventually(() => account.signingIn, 'signing in');
      final shown = n();
      expect(shown, greaterThan(0));
      expect(await account.signIn(), isFalse, reason: 'one sign-in at a time');
      gate.complete(true);
      expect(await first, isTrue);
      expect(account.signingIn, isFalse);
      expect(n(), greaterThan(shown));
      expect(seen.last, isFalse, reason: 'the end of the sign-in is shown');
      final signedIn = <bool>[];
      account.addListener(() => signedIn.add(account.signedIn));
      // the backend's changes reach the settings
      final m = n();
      b.ping();
      expect(n(), m + 1);
      // «Off» signs out
      await account.signOut();
      expect(b.signOuts, 1);
      expect(signedIn.last, isFalse, reason: 'the sign-out is shown');
      await account.choose(CloudChoice.none);
      expect(account.choice, CloudChoice.none);
      expect(account.sync.inner, isA<NoSync>());
      expect(b.disposed, isTrue);
      account.dispose();
      account.sync.notifyListeners();
      expect(() => account.addListener(() {}), throwsStateError);
    });

    test(
      'folder choice: no sync before it, cleared by confirming or signing out',
      () async {
        final lib = await library();
        await lib.setSyncProvider('google');
        late _Backend b;
        final account = CloudAccount(
          library: lib,
          loadGoogle: () async => b = _Backend(),
          chooseFolders: true,
        );
        addTearDown(account.dispose);
        await account.signIn();
        expect(account.needsFolderChoice, isTrue);
        await account.syncNow();
        expect(b.sync.now, 0);
        final n = counter(account);
        await account.confirmFolders({});
        expect(account.needsFolderChoice, isFalse);
        expect(n(), greaterThan(0));
        expect(b.sync.now, 1);
        await account.syncNow();
        expect(b.sync.now, 2);
        await account.signOut();
        await account.signIn();
        expect(account.needsFolderChoice, isTrue);
        // confirmed while the backend lost its sign-in: no sync, but the choice is closed and shown
        b.signedInValue = false;
        final choice = <bool>[];
        account.addListener(() => choice.add(account.needsFolderChoice));
        await account.confirmFolders({});
        expect(choice, [false]);
        b.signedInValue = true;
        await account.signOut();
        await account.signIn();
        final m = counter(account);
        await account.signOut();
        expect(account.needsFolderChoice, isFalse);
        expect(m(), greaterThan(0));
      },
    );

    test('#138/AK2 choosing «None» while signed in signs out first', () async {
      final lib = await library();
      await lib.setSyncProvider('google');
      final b = _Backend()..signedInValue = true;
      final account = CloudAccount(library: lib, loadGoogle: () async => b);
      await account.open();
      expect(account.signedIn, isTrue);
      await account.choose(CloudChoice.none);
      expect(b.signOuts, 1);
      expect(b.disposed, isTrue);
      expect(account.signedIn, isFalse);
      expect(lib.device.syncProvider, isNull);
      account.dispose();
    });

    test('disposing the account disposes the backend', () async {
      final lib = await library();
      await lib.setSyncProvider('google');
      final b = _Backend()..signedInValue = true;
      final account = CloudAccount(library: lib, loadGoogle: () async => b);
      await account.open();
      account.dispose();
      expect(b.disposed, isTrue);
    });

    test('backend: notifications, failed sign-in, the engine ends with sign-out and dispose', () async {
      final drive = FakeDrive();
      final lib = await library();
      final auth = _CountingAuth();
      final backend = GoogleBackend(
        auth: auth,
        transport: drive.transport(),
        library: lib,
        eagerDownload: true,
      );
      final n = counter(backend);
      auth.ping();
      expect(n(), 1);
      backend.engine.notifyListeners();
      expect(n(), 2);
      auth.result = SignInResult.failed;
      expect(await backend.signIn(), isFalse);
      auth.result = SignInResult.redirected;
      expect(await backend.signIn(), isNull);
      await backend.signOut();
      expect(() => backend.engine.addListener(() {}), throwsStateError);
      final other = GoogleBackend(
        auth: _CountingAuth(),
        transport: drive.transport(),
        library: lib,
        eagerDownload: false,
      );
      final otherAuth = other.auth as _CountingAuth;
      other.dispose();
      expect(() => other.engine.addListener(() {}), throwsStateError);
      otherAuth.ping(); // no call into the disposed backend
      expect(() => other.addListener(() {}), throwsStateError);
    });

    test('the desktop module downloads every file right away', () {
      final b = openGoogle(
        library: Library(
          MemoryFileStore(),
          probe: (_) => 1,
          readSource: (_) async => null,
        ),
        secrets: MemorySecretStore(),
        openUrl: (_) async {},
        playing: () => false,
      ) as GoogleBackend;
      addTearDown(b.dispose);
      expect(b.engine.eagerDownload, isTrue);
      expect(b.auth, isA<DesktopGoogleAuth>());
    });
  });

  group('#54/AK8 last sync per device', () {
    test(
      'the own device after its first write; a file without time is listed too',
      () async {
        final drive = FakeDrive();
        final lib = await library();
        final now = DateTime.utc(2026, 11, 22, 12);
        final sync = CloudSync(provider(drive), lib, now: () => now);
        addTearDown(sync.dispose);
        await sync.syncNow();
        expect(sync.devices, {lib.device.deviceId: now});
        // another device whose file has no time, and a newer and an older time of a known one
        final other = CloudSync.encodeDevice(
          lib.state,
          'aaaaaaaaaaaaaaaa',
          1,
          now,
        );
        final j = jsonDecode(utf8.decode(other)) as Map..remove('written');
        final p = provider(drive);
        await p.put(
          'devices/aaaaaaaaaaaaaaaa.json',
          Uint8List.fromList(utf8.encode(jsonEncode(j))),
        );
        await sync.syncNow();
        expect(sync.devices.containsKey('aaaaaaaaaaaaaaaa'), isTrue);
        expect(sync.devices['aaaaaaaaaaaaaaaa'], isNull);
        await p.put(
          'devices/aaaaaaaaaaaaaaaa.json',
          CloudSync.encodeDevice(
            lib.state,
            'aaaaaaaaaaaaaaaa',
            2,
            now.subtract(const Duration(days: 1)),
          ),
        );
        await sync.syncNow();
        expect(
          sync.devices['aaaaaaaaaaaaaaaa'],
          now.subtract(const Duration(days: 1)),
        );
      },
    );
  });

  group('#54/AK9 backups and restore', () {
    test(
      'the backend lists the backups of this device with time and state',
      () async {
        final drive = FakeDrive();
        final lib = await library();
        var now = DateTime.utc(2026, 11, 20, 10);
        final backend = GoogleBackend(
          auth: FixedAuth(),
          transport: drive.transport(),
          library: lib,
          eagerDownload: true,
        );
        addTearDown(backend.dispose);
        final sync = CloudSync(backend.provider, lib, now: () => now);
        addTearDown(sync.dispose);
        sources['r.mp3'] = bytes('audio r');
        await lib.importFiles(['r.mp3']);
        await sync.syncNow();
        expect(await backend.backups(), isEmpty);
        now = now.add(const Duration(days: 1));
        lib.editMetadata(lib.tracks.single.id, title: 'Neu', artist: null);
        await sync.syncNow();
        // a damaged backup is not offered
        await backend.provider.put(
          'backup/${lib.device.deviceId}/state-5.json',
          bytes('{'),
        );
        final list = await backend.backups();
        expect(list, hasLength(1));
        expect(list.single.name, 'backup/${lib.device.deviceId}/state-2.json');
        expect(list.single.written, DateTime.utc(2026, 11, 20, 10));
        expect(list.single.state.tracks.values.single.values['title'], 'r');
        expect((await backend.space())!.used, greaterThan(0));
      },
    );

    test('restore on a read-only library changes nothing', () async {
      final store = MemoryFileStore();
      store.files[Library.indexName] = Uint8List.fromList(
        utf8.encode(jsonEncode({'formatVersion': 999})),
      );
      final lib = Library(
        store,
        probe: (_) => 1,
        readSource: (_) async => null,
      );
      await lib.load();
      expect(lib.readOnly, isTrue);
      expect(await lib.restore(lib.state), isFalse);
    });

    test('restore removes what came later with its file, keeps files that are missing missing', () async {
      final a = await library();
      final b = await library();
      sources['k.mp3'] = bytes('audio k');
      sources['l.mp3'] = bytes('audio l');
      sources['m.mp3'] = bytes('audio m');
      await b.importFiles(['m.mp3']);
      await a.importFiles(['k.mp3']);
      await a.mergeRemote(b.state); // m arrives without its file
      final m = a.tracks.firstWhere((t) => t.title == 'm');
      expect(a.hasFile(m.id), isFalse);
      final backup = a.state;
      await a.importFiles(['l.mp3']);
      final l = a.tracks.firstWhere((t) => t.title == 'l');
      final store = a.store as MemoryFileStore;
      expect(store.files.keys, contains(Library.trackName(l.fileName)));
      store.files[Library.artworkNameFor(l.id)] = bytes('cover');
      final n = counter(a);
      expect(await a.restore(backup), isTrue);
      expect(n(), greaterThan(0));
      expect(a.tracks.map((t) => t.title).toSet(), {'k', 'm'});
      expect(store.files.keys, isNot(contains(Library.trackName(l.fileName))));
      expect(store.files.keys, isNot(contains(Library.artworkNameFor(l.id))));
      expect(
        a.hasFile(m.id),
        isFalse,
        reason: 'still to be loaded from the cloud',
      );
    });
  });
}

/// The browser: opens the redirect with a code; [keep] leaves its connection open.
Future<void> _answer(String url, {List<HttpClient>? keep}) async {
  final u = Uri.parse(url);
  final redirect = Uri.parse(u.queryParameters['redirect_uri']!);
  final client = HttpClient();
  final req = await client.getUrl(
    redirect.replace(
      queryParameters: {'state': u.queryParameters['state']!, 'code': 'c'},
    ),
  );
  final res = await req.close();
  await res.drain<void>();
  if (keep != null) {
    keep.add(client);
  } else {
    client.close();
  }
}

class _Notifying extends NoSync {
  void ping() => notifyListeners();
}

class _CountingAuth extends FixedAuth {
  int asked = 0;
  SignInResult result = SignInResult.signedIn;
  void ping() => notifyListeners();
  @override
  Future<String> token() {
    asked++;
    return super.token();
  }

  @override
  Future<SignInResult> signIn({String doneText = ''}) async => result;
}

class _CountingSync extends NoSync {
  int now = 0;
  @override
  Future<void> syncNow() async => now++;
}

class _Backend extends ChangeNotifier implements CloudBackend {
  @override
  final _CountingSync sync = _CountingSync();
  bool signedInValue = false;
  int signIns = 0;
  int signOuts = 0;
  bool disposed = false;
  Future<bool?>? answer;

  void ping() => notifyListeners();

  @override
  Future<void> load() async {}
  @override
  bool get signedIn => signedInValue;
  @override
  bool get needsSignIn => false;
  @override
  Future<bool?> signIn({String doneText = ''}) async {
    signIns++;
    final ok = await (answer ?? Future.value(true));
    answer = null;
    if (ok == true) signedInValue = true;
    return ok;
  }

  @override
  void cancelSignIn() {}
  @override
  Future<void> signOut() async {
    signOuts++;
    signedInValue = false;
  }

  @override
  DateTime? get lastSync => null;
  @override
  Map<String, DateTime?> get devices => const {};
  @override
  List<String> get errors => const [];
  @override
  Future<CloudSpace?> space() async => null;
  @override
  Future<List<CloudBackup>> backups() async => const [];
  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}
