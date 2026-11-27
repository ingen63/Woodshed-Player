// #54: sync over Google Drive. Sign-in on the desktop (PKCE, receiver on 127.0.0.1) and in the browser
// (redirect, token in IndexedDB), the GoogleDriveProvider with the layout of #53, uploads in blocks, silent
// renewal, sign-out. Every request goes to the simulated Drive of google_fakes.dart (AK13), never to a real
// account; the only real connection is the local receiver of the desktop sign-in on 127.0.0.1.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/sync/cloud_account.dart';
import 'package:woodshed_player/sync/cloud_provider.dart';
import 'package:woodshed_player/sync/google_sync.dart';
import 'package:woodshed_player/sync/providers/google_auth.dart';
import 'package:woodshed_player/sync/providers/google_auth_desktop.dart';
import 'package:woodshed_player/sync/providers/google_auth_web.dart';
import 'package:woodshed_player/sync/providers/google_drive_provider.dart';
import 'package:woodshed_player/sync/providers/http_transport.dart';
import 'package:woodshed_player/sync/secret_store.dart';
import 'package:woodshed_player/sync/sync_engine.dart';
import 'package:woodshed_player/sync/sync_service.dart';

import 'fakes.dart';
import 'google_fakes.dart';
import 'sync_test.dart' show bytes, sources;
import 'sync_test.dart' as base show clock;

/// A device with its own library, syncing over the simulated Drive.
class Device {
  Device(this.drive, int seed, {GoogleAuth? auth, this.eager = true}) {
    library = Library(
      store,
      probe: (_) => 2.5,
      readSource: (s) async => sources[s],
      now: () => base.clock,
      saveDelay: Duration.zero,
      random: Random(seed),
    );
    transport = drive.transport();
    provider = GoogleDriveProvider(
      transport: transport,
      auth: auth ?? FixedAuth(),
    );
    sync = CloudSync(
      provider,
      library,
      eagerDownload: eager,
      now: () => base.clock,
      changeDelay: const Duration(days: 1),
      random: Random(seed + 1000),
    );
  }

  final FakeDrive drive;
  final bool eager;
  final store = MemoryFileStore();
  late final Library library;
  late final HttpTransport transport;
  late final GoogleDriveProvider provider;
  late final CloudSync sync;

  String get id => library.device.deviceId;

  Future<Track> add(String name) async {
    sources.putIfAbsent(name, () => bytes('audio $name'));
    final r = await library.importFiles([name]);
    return [...r.imported, ...r.duplicates].single;
  }
}

Future<Device> device(FakeDrive drive, int seed, {GoogleAuth? auth}) async {
  final d = Device(drive, seed, auth: auth);
  await d.library.load();
  addTearDown(() {
    d.sync.dispose();
    d.library.dispose();
  });
  return d;
}

/// Simulates the browser: follows the sign-in page's redirect to the receiver with [code].
Future<void> Function(String) browser(
  List<Uri> opened, {
  String? code = 'code-1',
  bool wrongStateFirst = false,
}) => (url) async {
  final u = Uri.parse(url);
  opened.add(u);
  final redirect = Uri.parse(u.queryParameters['redirect_uri']!);
  final client = HttpClient();
  try {
    Future<void> hit(Map<String, String> q) async {
      final req = await client.getUrl(redirect.replace(queryParameters: q));
      await (await req.close()).drain<void>();
    }

    if (wrongStateFirst) await hit({'code': 'forged', 'state': 'other'});
    await hit({
      'state': u.queryParameters['state']!,
      'code': ?code,
      if (code == null) 'error': 'access_denied',
    });
  } finally {
    client.close();
  }
};

void main() {
  group('#54/AK1 sign-in with PKCE, only drive.file', () {
    test('desktop: system browser, PKCE S256, receiver on 127.0.0.1, refresh token in the keychain', () async {
      final drive = FakeDrive();
      final secrets = MemorySecretStore();
      final opened = <Uri>[];
      final auth = DesktopGoogleAuth(
        transport: drive.transport(),
        secrets: secrets,
        openBrowser: browser(opened, wrongStateFirst: true),
      );
      await auth.load();
      expect(auth.signedIn, isFalse);
      expect(await auth.signIn(doneText: 'done'), SignInResult.signedIn);
      final q = opened.single.queryParameters;
      expect(opened.single.host, 'accounts.google.com');
      expect(q['scope'], googleScope, reason: 'only drive.file');
      expect(q['response_type'], 'code');
      expect(q['code_challenge_method'], 'S256');
      expect(q['client_id'], googleDesktopClientId);
      expect(q['access_type'], 'offline');
      final redirect = Uri.parse(q['redirect_uri']!);
      expect(redirect.host, '127.0.0.1');
      expect(redirect.port, greaterThan(0));
      // the verifier sent in the exchange belongs to the challenge in the browser
      final ex = drive.lastExchange!;
      expect(ex['code'], 'code-1', reason: 'the forged answer was ignored');
      expect(pkceChallenge(ex['code_verifier']!), q['code_challenge']);
      expect(ex['redirect_uri'], q['redirect_uri']);
      expect(ex.containsKey('client_secret'), isFalse);
      // the refresh token is the only thing stored, in the keychain
      expect(secrets.values.keys, [DesktopGoogleAuth.refreshKey]);
      expect(auth.signedIn, isTrue);
      expect(await auth.token(), startsWith('token-'));
      // the receiver is closed again
      await expectLater(
        HttpClient().getUrl(redirect).then((r) => r.close()),
        throwsA(isA<SocketException>()),
      );
      // the next start finds the sign-in in the keychain
      final again = DesktopGoogleAuth(
        transport: drive.transport(),
        secrets: secrets,
        openBrowser: (_) async {},
      );
      await again.load();
      expect(again.signedIn, isTrue);
    });

    test(
      'desktop: refused, cancelled or without drive.file stores nothing',
      () async {
        final drive = FakeDrive();
        final secrets = MemorySecretStore();
        final refused = DesktopGoogleAuth(
          transport: drive.transport(),
          secrets: secrets,
          openBrowser: browser([], code: null),
        );
        expect(await refused.signIn(), SignInResult.failed);
        drive.grantedScope = 'openid';
        final narrow = DesktopGoogleAuth(
          transport: drive.transport(),
          secrets: secrets,
          openBrowser: browser([]),
        );
        expect(await narrow.signIn(), SignInResult.failed);
        late DesktopGoogleAuth cancelled;
        cancelled = DesktopGoogleAuth(
          transport: drive.transport(),
          secrets: secrets,
          openBrowser: (_) async => cancelled.cancelSignIn(),
        );
        expect(await cancelled.signIn(), SignInResult.failed);
        final timeout = DesktopGoogleAuth(
          transport: drive.transport(),
          secrets: secrets,
          openBrowser: (_) async {},
          waitForBrowser: const Duration(milliseconds: 20),
        );
        expect(await timeout.signIn(), SignInResult.failed);
        expect(secrets.values, isEmpty);
        expect(
          refused.signedIn || narrow.signedIn || cancelled.signedIn,
          isFalse,
        );
      },
    );

    test(
      'desktop: a client secret given at build time goes into the exchange',
      () async {
        final drive = FakeDrive();
        final auth = DesktopGoogleAuth(
          transport: drive.transport(),
          secrets: MemorySecretStore(),
          openBrowser: browser([]),
          clientSecret: 'not-really-secret',
        );
        expect(await auth.signIn(), SignInResult.signedIn);
        expect(drive.lastExchange!['client_secret'], 'not-really-secret');
      },
    );

    test('web: redirect with response_type=token, token in the store (IndexedDB)', () async {
      final drive = FakeDrive();
      final store = MemorySecretStore();
      final went = <Uri>[];
      final redirect = Uri.parse('https://example.test/app/');
      final auth = WebGoogleAuth(
        transport: drive.transport(),
        store: store,
        redirectUri: redirect,
        navigate: (u) => went.add(Uri.parse(u)),
        playing: () => false,
        random: Random(1),
      );
      await auth.load();
      expect(auth.signedIn, isFalse);
      expect(await auth.signIn(), SignInResult.redirected);
      final q = went.single.queryParameters;
      expect(went.single.host, 'accounts.google.com');
      expect(q['scope'], googleScope);
      expect(q['response_type'], 'token');
      expect(q['client_id'], googleWebClientId);
      expect(q['redirect_uri'], redirect.toString());
      expect(q.containsKey('prompt'), isFalse);
      // back from Google: a new page reads the fragment
      final back = WebGoogleAuth(
        transport: drive.transport(),
        store: store,
        redirectUri: redirect,
        navigate: (_) => fail('no redirect'),
        playing: () => false,
        fragment:
            'state=${q['state']}&access_token=token-1&expires_in=3599&scope=${Uri.encodeComponent(googleScope)}',
      );
      await back.load();
      expect(back.signedIn, isTrue);
      expect(await back.token(), 'token-1');
      expect(
        jsonDecode((await store.read(WebGoogleAuth.tokenKey))!),
        containsPair('accessToken', 'token-1'),
      );
      expect(await store.read(WebGoogleAuth.pendingKey), isNull);
    });

    test('web: an answer with another state is ignored', () async {
      final store = MemorySecretStore();
      final auth = WebGoogleAuth(
        transport: FakeDrive().transport(),
        store: store,
        redirectUri: Uri.parse('https://example.test/'),
        navigate: (_) {},
        playing: () => false,
        fragment: 'state=forged&access_token=evil&expires_in=3599',
      );
      await auth.load();
      expect(auth.signedIn, isFalse);
      expect(store.values, isEmpty);
    });

    test('web: the redirect address is the app page without file, query and fragment', () {
      expect(
        redirectUriOf('https://example.test', '/Woodshed-Player/app/'),
        Uri.parse('https://example.test/Woodshed-Player/app/'),
      );
      expect(
        redirectUriOf('https://example.test', '/app/index.html'),
        Uri.parse('https://example.test/app/'),
      );
      expect(WebGoogleAuth.isAnswer('access_token=a&state=b'), isTrue);
      expect(WebGoogleAuth.isAnswer('error=access_denied'), isTrue);
      expect(WebGoogleAuth.isAnswer('/'), isFalse);
      expect(WebGoogleAuth.isAnswer(''), isFalse);
    });

    test(
      'PKCE helpers: verifier of 64 unreserved characters, RFC 7636 example',
      () {
        final v = pkceVerifier(Random(1));
        expect(v, matches(RegExp(r'^[A-Za-z0-9\-._~]{64}$')));
        expect(
          pkceChallenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
          'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
        );
        expect(randomState(Random(2)), matches(RegExp(r'^[0-9a-f]{32}$')));
        expect(grantsDrive('openid $googleScope'), isTrue);
        expect(grantsDrive('openid'), isFalse);
        expect(grantsDrive(null), isTrue);
      },
    );
  });

  group('#54/AK2 the folder WoodshedPlayer', () {
    test(
      'the first device creates it, a second one finds it without a choice',
      () async {
        final drive = FakeDrive();
        final a = await device(drive, 1);
        final b = await device(drive, 2);
        // reading creates nothing
        expect(await b.provider.list('devices/'), isEmpty);
        expect(drive.roots, isEmpty);
        await a.add('a.mp3');
        await a.sync.syncNow();
        expect(drive.roots, hasLength(1));
        await b.sync.syncNow();
        expect(drive.roots, hasLength(1), reason: 'no second folder');
        expect(b.library.tracks.single.title, 'a');
        expect(b.library.device.libraryId, a.library.device.libraryId);
      },
    );

    test('created at the same moment: the oldest folder wins, the own empty one goes', () async {
      final drive = FakeDrive();
      final racing = _Racing(drive);
      final p = GoogleDriveProvider(transport: racing, auth: FixedAuth());
      await p.put('format.json', bytes('{}'));
      expect(drive.roots.single.id, racing.other!.id);
      expect(drive.paths, {'WoodshedPlayer/format.json'});
    });

    test(
      'a folder of the same name elsewhere or in the bin is not taken',
      () async {
        final drive = FakeDrive();
        final elsewhere = drive.addFolder('Music', 'root');
        drive.addFolder('WoodshedPlayer', elsewhere.id);
        final p = GoogleDriveProvider(
          transport: drive.transport(),
          auth: FixedAuth(),
        );
        await p.put('format.json', bytes('{}'));
        expect(drive.roots, hasLength(1));
        final q = drive.calls.first.url.queryParameters['q']!;
        expect(q, contains("'root' in parents"));
        expect(q, contains('trashed = false'));
        expect(q, contains("name = 'WoodshedPlayer'"));
      },
    );
  });

  group('#54/AK3 list, get, put, delete and quota with the layout of #53', () {
    test('two devices sync tracks, state, backups and audio', () async {
      final drive = FakeDrive();
      final a = await device(drive, 1);
      final b = await device(drive, 2);
      final t = await a.add('a.mp3');
      await a.sync.syncNow();
      await b.sync.syncNow();
      expect(drive.paths, {
        'WoodshedPlayer/format.json',
        'WoodshedPlayer/devices/${a.id}.json',
        'WoodshedPlayer/devices/${b.id}.json',
        'WoodshedPlayer/audio/${t.id}.mp3',
      });
      expect(b.library.hasFile(t.id), isTrue);
      expect(
        await b.library.readAudio(b.library.tracks.single),
        bytes('audio a.mp3'),
      );
      // a change: the old state goes to the backup first
      a.library.editMetadata(t.id, title: 'Neu', artist: null);
      await a.sync.syncNow();
      await b.sync.syncNow();
      expect(b.library.tracks.single.title, 'Neu');
      expect(
        drive.paths,
        contains('WoodshedPlayer/backup/${a.id}/state-2.json'),
      );
      // deleted: the audio file goes
      a.library.delete({t.id});
      await a.sync.syncNow();
      expect(drive.paths.where((p) => p.contains('/audio/')), isEmpty);
      await b.sync.syncNow();
      expect(b.library.tracks, isEmpty);
      expect(a.sync.status, SyncStatus.idle);
      expect(b.sync.devices.keys, containsAll([a.id, b.id]));
    });

    test(
      'list by prefix, nested folders, paging; get of a missing file is null',
      () async {
        final drive = FakeDrive();
        final p = GoogleDriveProvider(
          transport: drive.transport(),
          auth: FixedAuth(),
        );
        await p.put('audio/abc.mp3', bytes('x'));
        await p.put('audio/abd.mp3', bytes('yy'));
        await p.put('backup/dev/state-1.json', bytes('1'));
        expect((await p.list('audio/ab')).map((e) => e.name).toSet(), {
          'audio/abc.mp3',
          'audio/abd.mp3',
        });
        expect((await p.list('audio/abc')).single.size, 1);
        expect(
          (await p.list('backup/')).single.name,
          'backup/dev/state-1.json',
        );
        expect((await p.list('')).length, 3);
        expect(await p.list('nothing/'), isEmpty);
        expect(await p.get('audio/zzz.mp3'), isNull);
        expect(await p.get('nothing/a.json'), isNull);
        expect((await p.get('audio/abd.mp3'))!.bytes, bytes('yy'));
        // more files than one page
        for (var i = 0; i < 1005; i++) {
          drive.addFile(
            'f$i.json',
            drive.files.values.firstWhere((f) => f.name == 'audio').id,
            [i % 256],
          );
        }
        expect((await p.list('audio/')).length, 1007);
      },
    );

    test('a second file of the same name shows as a conflict copy', () async {
      final drive = FakeDrive();
      final p = GoogleDriveProvider(
        transport: drive.transport(),
        auth: FixedAuth(),
      );
      await p.put('devices/0123456789abcdef.json', bytes('first'));
      final devices = drive.files.values.firstWhere((f) => f.name == 'devices');
      drive.addFile('0123456789abcdef.json', devices.id, bytes('second'));
      drive.addFile('0123456789abcdef.json', devices.id, bytes('third'));
      drive.addFile('README', devices.id, bytes('r'));
      drive.addFile('README', devices.id, bytes('r2'));
      final names = (await p.list('devices/')).map((e) => e.name).toList();
      expect(names, [
        'devices/0123456789abcdef.json',
        'devices/0123456789abcdef (1).json',
        'devices/0123456789abcdef (2).json',
        'devices/README',
        'devices/README (1)',
      ]);
      expect(
        CloudSync.parseDeviceName('devices/0123456789abcdef (1).json')!.copy,
        isTrue,
      );
      expect(
        (await p.get('devices/0123456789abcdef (1).json'))!.bytes,
        bytes('second'),
      );
      await p.delete('devices/0123456789abcdef (2).json');
      expect(
        drive.files.values.where((f) => f.name == '0123456789abcdef.json'),
        hasLength(2),
      );
    });

    test('overwrite keeps the file ID; delete of a missing file is no error; quota', () async {
      final drive = FakeDrive()..limit = 1000;
      final p = GoogleDriveProvider(
        transport: drive.transport(),
        auth: FixedAuth(),
      );
      final v1 = await p.put('format.json', bytes('1'));
      final v2 = await p.put('format.json', bytes('22'));
      expect(v1, isNot(v2));
      expect(
        drive.files.values.where((f) => f.name == 'format.json'),
        hasLength(1),
      );
      expect((await p.get('format.json'))!.bytes, bytes('22'));
      await p.delete('format.json');
      await p.delete('format.json');
      await p.delete('none/x.json');
      expect(drive.paths, isEmpty);
      await p.put('a.json', bytes('12345'));
      final q = await p.quota();
      expect(q.used, 5);
      expect(q.total, 1000);
    });

    test(
      'a file removed or replaced by another device in the meantime',
      () async {
        final drive = FakeDrive();
        final p = GoogleDriveProvider(
          transport: drive.transport(),
          auth: FixedAuth(),
        );
        await p.put('devices/x.json', bytes('a'));
        final f = drive.files.values.firstWhere((f) => f.name == 'x.json');
        drive.files.remove(f.id);
        expect(await p.get('devices/x.json'), isNull);
        await p.put('devices/y.json', bytes('b'));
        final y = drive.files.values.firstWhere((f) => f.name == 'y.json');
        drive.files.remove(y.id);
        final again = drive.addFile('y.json', y.parent, bytes('c'));
        expect((await p.get('devices/y.json'))!.bytes, bytes('c'));
        drive.files.remove(again.id);
        await p.put('devices/y.json', bytes('d'));
        expect(drive.paths, contains('WoodshedPlayer/devices/y.json'));
        expect((await p.get('devices/y.json'))!.bytes, bytes('d'));
      },
    );

    test('conditional writes are refused (#53: the engine never writes conditionally)', () async {
      final p = GoogleDriveProvider(
        transport: FakeDrive().transport(),
        auth: FixedAuth(),
      );
      expect(
        () => p.put('a', bytes('x'), ifAbsent: true),
        throwsUnsupportedError,
      );
      expect(
        () => p.put('a', bytes('x'), ifVersion: '1'),
        throwsUnsupportedError,
      );
    });

    test('server errors become CloudError with the reason, no connection CloudOffline', () async {
      final drive = FakeDrive();
      final p = GoogleDriveProvider(
        transport: _Failing(drive, 403),
        auth: FixedAuth(),
      );
      await expectLater(
        p.list('devices/'),
        throwsA(
          isA<CloudError>().having(
            (e) => e.detail,
            'detail',
            contains('rateLimitExceeded'),
          ),
        ),
      );
      drive.cut = (_) => true;
      final q = GoogleDriveProvider(
        transport: drive.transport(),
        auth: FixedAuth(),
      );
      await expectLater(q.list('devices/'), throwsA(isA<CloudOffline>()));
    });
  });

  group('#54/AK4 large files in blocks, continued after an abort', () {
    const kib = 1024;
    Uint8List big(int n) =>
        Uint8List.fromList(List.generate(n, (i) => i * 7 % 251));

    test(
      'blocks of 256 KiB; after an abort the session goes on where it stopped',
      () async {
        final drive = FakeDrive();
        final p = GoogleDriveProvider(
          transport: drive.transport(),
          auth: FixedAuth(),
          resumableAbove: 100 * kib,
          chunkSize: 256 * kib,
        );
        final data = big(700 * kib);
        var blocks = 0;
        drive.cut = (c) =>
            c.url.queryParameters.containsKey('upload_id') &&
            c.body != null &&
            ++blocks == 2;
        await expectLater(
          p.put('audio/big.mp3', data),
          throwsA(isA<CloudOffline>()),
        );
        expect(drive.paths, isEmpty);
        drive.cut = null;
        final sent = p.sentBytes;
        await p.put('audio/big.mp3', data);
        // only the rest went again: the first block was not sent twice
        expect(p.sentBytes - sent, 700 * kib - 256 * kib);
        final starts = [
          for (final c in drive.calls)
            if (c.headers['Content-Range'] case final r? when !r.contains('*'))
              r.split(' ')[1].split('-').first,
        ];
        expect(starts, ['0', '${256 * kib}', '${256 * kib}', '${512 * kib}']);
        expect(
          drive.calls.where(
            (c) => c.headers['Content-Range']?.contains('*') ?? false,
          ),
          hasLength(1),
        );
        expect((await p.get('audio/big.mp3'))!.bytes, data);
        expect(
          drive.files.values.where((f) => f.name == 'big.mp3'),
          hasLength(1),
        );
      },
    );

    test(
      'a block received only in part is sent again from the reported range',
      () async {
        final drive = FakeDrive()..keepAtMost = 100 * kib;
        final p = GoogleDriveProvider(
          transport: drive.transport(),
          auth: FixedAuth(),
          resumableAbove: 100 * kib,
          chunkSize: 256 * kib,
        );
        final data = big(300 * kib);
        await p.put('audio/part.mp3', data);
        expect((await p.get('audio/part.mp3'))!.bytes, data);
      },
    );

    test('an expired session starts again; an existing large file is updated in place', () async {
      final drive = FakeDrive();
      final p = GoogleDriveProvider(
        transport: drive.transport(),
        auth: FixedAuth(),
        resumableAbove: 100 * kib,
        chunkSize: 256 * kib,
      );
      final data = big(600 * kib);
      var n = 0;
      drive.cut = (c) =>
          c.url.queryParameters.containsKey('upload_id') && ++n == 2;
      await expectLater(
        p.put('audio/x.mp3', data),
        throwsA(isA<CloudOffline>()),
      );
      drive.cut = null;
      drive.sessions.clear(); // Google forgot the session
      await p.put('audio/x.mp3', data);
      expect((await p.get('audio/x.mp3'))!.bytes, data);
      // the same name again (update): no second file
      final other = big(500 * kib)..[0] = 9;
      await p.put('audio/x.mp3', other);
      expect(drive.files.values.where((f) => f.name == 'x.mp3'), hasLength(1));
      expect((await p.get('audio/x.mp3'))!.bytes, other);
      // a session whose upload finished but whose answer got lost is not sent again
      final last = big(300 * kib);
      drive.cut = (c) {
        if (!c.url.queryParameters.containsKey('upload_id') || c.body == null) {
          return false;
        }
        if (c.headers['Content-Range']!.startsWith('bytes ${256 * kib}')) {
          drive.cut = null;
          drive.answer(c); // the server takes the block, the answer is lost
          return true;
        }
        return false;
      };
      await expectLater(
        p.put('audio/y.mp3', last),
        throwsA(isA<CloudOffline>()),
      );
      final before = p.sentBytes;
      await p.put('audio/y.mp3', last);
      expect(p.sentBytes, before);
      expect((await p.get('audio/y.mp3'))!.bytes, last);
    });

    test('small files go in one request', () async {
      final drive = FakeDrive();
      final p = GoogleDriveProvider(
        transport: drive.transport(),
        auth: FixedAuth(),
      );
      await p.put('audio/s.mp3', bytes('small'));
      expect(
        drive.calls.where(
          (c) => c.url.queryParameters['uploadType'] == 'multipart',
        ),
        hasLength(1),
      );
      expect(p.sentBytes, 0);
    });
  });

  group('#54/AK5 an expired token is renewed silently', () {
    test(
      'desktop: expired access token: refresh without the browser',
      () async {
        final drive = FakeDrive();
        final secrets = MemorySecretStore();
        await secrets.write(DesktopGoogleAuth.refreshKey, 'refresh-a');
        drive.refresh['refresh-a'] = 'x';
        var now = DateTime.utc(2026, 11, 22);
        final auth = DesktopGoogleAuth(
          transport: drive.transport(),
          secrets: secrets,
          openBrowser: (_) => fail('no browser'),
          now: () => now,
        );
        await auth.load();
        final t1 = await auth.token();
        expect(await auth.token(), t1, reason: 'still valid');
        now = now.add(const Duration(minutes: 59)); // within the margin
        final t2 = await auth.token();
        expect(t2, isNot(t1));
        expect(drive.log.where((c) => c.endsWith('/token')), hasLength(2));
        expect(auth.needsSignIn, isFalse);
      },
    );

    test('desktop: Google refuses the token (401): renewed and the request repeated once', () async {
      final drive = FakeDrive();
      final secrets = MemorySecretStore();
      await secrets.write(DesktopGoogleAuth.refreshKey, 'refresh-a');
      drive.refresh['refresh-a'] = 'x';
      final auth = DesktopGoogleAuth(
        transport: drive.transport(),
        secrets: secrets,
        openBrowser: (_) => fail('no browser'),
      );
      await auth.load();
      final p = GoogleDriveProvider(transport: drive.transport(), auth: auth);
      await p.put('format.json', bytes('1'));
      drive.valid.clear(); // all access tokens revoked at Google
      await p.put('format.json', bytes('2'));
      expect((await p.get('format.json'))!.bytes, bytes('2'));
    });

    test(
      'desktop: refresh refused: sign in again, no further requests',
      () async {
        final drive = FakeDrive();
        final secrets = MemorySecretStore();
        await secrets.write(DesktopGoogleAuth.refreshKey, 'revoked');
        final auth = DesktopGoogleAuth(
          transport: drive.transport(),
          secrets: secrets,
          openBrowser: (_) => fail('no browser'),
        );
        await auth.load();
        final p = GoogleDriveProvider(transport: drive.transport(), auth: auth);
        await expectLater(
          p.list('devices/'),
          throwsA(isA<CloudSignInRequired>()),
        );
        expect(auth.needsSignIn, isTrue);
        expect(auth.signedIn, isFalse);
        expect(secrets.values, isEmpty);
        final n = drive.calls.length;
        await expectLater(
          p.list('devices/'),
          throwsA(isA<CloudSignInRequired>()),
        );
        expect(drive.calls.length, n, reason: 'no request without sign-in');
        // the engine waits as when offline and reports nothing else
        final d = await device(drive, 3, auth: auth);
        await d.sync.syncNow();
        expect(d.sync.status, SyncStatus.offline);
        expect(drive.calls.length, n);
      },
    );

    test('desktop: a token refused twice asks to sign in', () async {
      final drive = FakeDrive();
      final auth = FixedAuth('stale');
      final p = GoogleDriveProvider(transport: drive.transport(), auth: auth);
      await expectLater(p.list('x/'), throwsA(isA<CloudSignInRequired>()));
      expect(auth.rejections, 2);
    });

    test(
      'web: expired while something plays: no redirect, the sync waits',
      () async {
        final store = MemorySecretStore();
        final went = <String>[];
        var playing = true;
        var now = DateTime.utc(2026, 11, 22, 10);
        await store.write(WebGoogleAuth.signedInKey, 'true');
        await store.write(
          WebGoogleAuth.tokenKey,
          jsonEncode({
            'accessToken': 'old',
            'expiresAt': now
                .add(const Duration(minutes: 30))
                .millisecondsSinceEpoch,
          }),
        );
        final auth = WebGoogleAuth(
          transport: FakeDrive().transport(),
          store: store,
          redirectUri: Uri.parse('https://example.test/'),
          navigate: went.add,
          playing: () => playing,
          now: () => now,
        );
        await auth.load();
        expect(await auth.token(), 'old');
        now = now.add(const Duration(hours: 1));
        await expectLater(
          auth.token(),
          throwsA(
            isA<CloudOffline>().having(
              (e) => e is CloudSignInRequired,
              'sign-in',
              isFalse,
            ),
          ),
        );
        expect(went, isEmpty, reason: 'never during playback');
        playing = false;
        await expectLater(auth.token(), throwsA(isA<CloudOffline>()));
        final u = Uri.parse(went.single);
        expect(u.queryParameters['prompt'], 'none');
        expect(u.queryParameters['scope'], googleScope);
        expect(
          jsonDecode((await store.read(WebGoogleAuth.pendingKey))!),
          containsPair('silent', true),
        );
      },
    );

    test(
      'web: silent renewal refused: ask to sign in, no further redirects',
      () async {
        final store = MemorySecretStore();
        await store.write(WebGoogleAuth.signedInKey, 'true');
        await store.write(
          WebGoogleAuth.pendingKey,
          jsonEncode({'state': 's1', 'silent': true, 't': 0}),
        );
        final went = <String>[];
        final auth = WebGoogleAuth(
          transport: FakeDrive().transport(),
          store: store,
          redirectUri: Uri.parse('https://example.test/'),
          navigate: went.add,
          playing: () => false,
          fragment: 'state=s1&error=interaction_required',
        );
        await auth.load();
        expect(auth.needsSignIn, isTrue);
        await expectLater(auth.token(), throwsA(isA<CloudSignInRequired>()));
        expect(went, isEmpty);
        // an interactive sign-in clears it
        await auth.signIn();
        final q = Uri.parse(went.single).queryParameters;
        final back = WebGoogleAuth(
          transport: FakeDrive().transport(),
          store: store,
          redirectUri: Uri.parse('https://example.test/'),
          navigate: went.add,
          playing: () => false,
          fragment: 'state=${q['state']}&access_token=new&expires_in=3599',
        );
        await back.load();
        expect(back.needsSignIn, isFalse);
        expect(await back.token(), 'new');
      },
    );

    test('web: Google refuses the token: dropped from the store', () async {
      final store = MemorySecretStore();
      await store.write(WebGoogleAuth.tokenKey, 'damaged');
      final auth = WebGoogleAuth(
        transport: FakeDrive().transport(),
        store: store,
        redirectUri: Uri.parse('https://example.test/'),
        navigate: (_) {},
        playing: () => false,
      );
      await auth.load();
      expect(
        await store.read(WebGoogleAuth.tokenKey),
        isNull,
        reason: 'damaged entry dropped',
      );
      expect(auth.token(), throwsA(isA<CloudSignInRequired>()));
      await store.write(
        WebGoogleAuth.tokenKey,
        '{"accessToken":"a","expiresAt":0}',
      );
      auth.rejected();
      await Future<void>.delayed(Duration.zero);
      expect(await store.read(WebGoogleAuth.tokenKey), isNull);
    });
  });

  group('#54/AK6 without a chosen sync no connection to Google', () {
    test(
      'the account without a choice loads no provider and sends nothing',
      () async {
        final net = _NoNetwork();
        await HttpOverrides.runZoned(() async {
          final dir = Directory.systemTemp.createTempSync('wp_g_none');
          addTearDown(() => dir.deleteSync(recursive: true));
          final app = TestApp(Directory('${dir.path}/lib'));
          await app.library.load();
          var loaded = 0;
          final account = CloudAccount(
            library: app.library,
            loadGoogle: () async {
              loaded++;
              throw StateError('must not load');
            },
          );
          await account.open();
          await account.syncNow();
          expect(await account.backups(), isEmpty);
          expect(await account.space(), isNull);
          expect(account.choice, CloudChoice.none);
          expect(account.sync.inner, isA<NoSync>());
          expect(loaded, 0);
          await app.controller.start();
          app.controller.resumed();
          await Future<void>.delayed(_quiet); // absence: no request
        }, createHttpClient: net.createHttpClient);
        expect(net.clients, 0);
      },
    );

    test('a module that cannot load leaves the sync off', () async {
      final lib = Library(
        MemoryFileStore(),
        probe: (_) => 1,
        readSource: (_) async => null,
        saveDelay: Duration.zero,
      );
      await lib.load();
      await lib.setSyncProvider('google');
      final account = CloudAccount(
        library: lib,
        loadGoogle: () async => throw StateError('offline, part not cached'),
      );
      await account.open();
      expect(account.sync.inner, isA<NoSync>());
      expect(account.signedIn, isFalse);
    });

    test(
      'chosen but not signed in: the module loads, no request goes out',
      () async {
        final drive = FakeDrive();
        final secrets = MemorySecretStore();
        final lib = Library(
          MemoryFileStore(),
          probe: (_) => 1,
          readSource: (_) async => null,
          saveDelay: Duration.zero,
        );
        await lib.load();
        await lib.setSyncProvider('google');
        GoogleBackend? backend;
        final account = CloudAccount(
          library: lib,
          loadGoogle: () async => backend = GoogleBackend(
            auth: DesktopGoogleAuth(
              transport: drive.transport(),
              secrets: secrets,
              openBrowser: (_) => fail('no browser'),
            ),
            transport: drive.transport(),
            library: lib,
            eagerDownload: true,
          ),
        );
        addTearDown(account.dispose);
        await account.open();
        expect(backend, isNotNull);
        expect(account.sync.inner, isA<NoSync>());
        await account.sync.start();
        await account.syncNow();
        expect(drive.calls, isEmpty);
      },
    );

    test(
      tags: 'repo', // #60: a check of the repository's files, not on Windows

      'engine and providers are reachable only through deferred imports',
      () {
        final direct = {
          ...reachableFrom('lib/main.dart'),
          ...reachableFrom('lib/app/platform_native.dart'),
          ...reachableFrom('lib/app/platform_web.dart'),
        };
        expect(direct.where((f) => f.contains('sync/providers/')), isEmpty);
        expect(direct.where((f) => f.endsWith('google_sync.dart')), isEmpty);
        final all = {
          ...reachableFrom('lib/app/platform_native.dart', deferred: true),
          ...reachableFrom('lib/app/platform_web.dart', deferred: true),
        };
        expect(
          all,
          contains(endsWith('sync/providers/google_drive_provider.dart')),
        );
        expect(all, contains(endsWith('sync/sync_engine.dart')));
        for (final f in [
          'lib/app/platform_native.dart',
          'lib/app/platform_web.dart',
        ]) {
          expect(
            File(f).readAsStringSync(),
            matches(
              RegExp(
                r"import '../sync/providers/google_platform_\w+\.dart' deferred as google;",
              ),
            ),
          );
        }
      },
    );
  });

  group(
    '#54/AK11 sign-out removes the tokens, keeps local data, ends all traffic',
    () {
      test('desktop: revoked at Google, keychain empty, library unchanged, no more requests', () async {
        final drive = FakeDrive();
        final secrets = MemorySecretStore();
        final opened = <Uri>[];
        final lib = Library(
          MemoryFileStore(),
          probe: (_) => 2.5,
          readSource: (s) async => sources[s],
          saveDelay: Duration.zero,
        );
        await lib.load();
        sources['k.mp3'] = bytes('audio k');
        await lib.importFiles(['k.mp3']);
        await lib.setSyncProvider('google');
        final transport = drive.transport();
        final backend = GoogleBackend(
          auth: DesktopGoogleAuth(
            transport: transport,
            secrets: secrets,
            openBrowser: browser(opened),
          ),
          transport: transport,
          library: lib,
          eagerDownload: true,
        );
        final account = CloudAccount(
          library: lib,
          loadGoogle: () async => backend,
        );
        addTearDown(account.dispose);
        await account.open();
        expect(await account.signIn(doneText: 'ok'), isTrue);
        await account.sync.inner.syncNow();
        expect(drive.paths, isNotEmpty);
        final refresh = secrets.values.values.single;
        final before = {...(lib.store as MemoryFileStore).files.keys};
        await account.signOut();
        expect(secrets.values, isEmpty);
        expect(drive.refresh.containsKey(refresh), isFalse, reason: 'revoked');
        expect(account.signedIn, isFalse);
        expect(account.sync.inner, isA<NoSync>());
        expect(lib.tracks, hasLength(1));
        expect((lib.store as MemoryFileStore).files.keys, containsAll(before));
        expect(
          account.choice,
          CloudChoice.google,
          reason: 'the choice stays, the sign-in goes',
        );
        final n = drive.calls.length;
        lib.editMetadata(lib.tracks.single.id, title: 'x', artist: null);
        await backend.engine.syncNow();
        await account.syncNow();
        await expectLater(
          backend.provider.list(''),
          throwsA(isA<CloudOffline>()),
        );
        expect(drive.calls.length, n);
        expect((transport as DriveTransport).closed, isTrue);
        // choosing «Off» afterwards changes nothing else
        await account.choose(CloudChoice.none);
        expect(lib.device.syncProvider, isNull);
      });

      test(
        'web: the stored token goes, the revoke is sent without CORS',
        () async {
          final drive = FakeDrive();
          final store = MemorySecretStore();
          await store.write(WebGoogleAuth.signedInKey, 'true');
          await store.write(
            WebGoogleAuth.tokenKey,
            jsonEncode({
              'accessToken': 'token-1',
              'expiresAt': DateTime.now()
                  .add(const Duration(hours: 1))
                  .millisecondsSinceEpoch,
            }),
          );
          final auth = WebGoogleAuth(
            transport: drive.transport(),
            store: store,
            redirectUri: Uri.parse('https://example.test/'),
            navigate: (_) {},
            playing: () => false,
          );
          await auth.load();
          await auth.signOut();
          expect(store.values, isEmpty);
          expect(auth.signedIn, isFalse);
          final revoke = drive.calls.single;
          expect(revoke.url.path, '/revoke');
          expect(revoke.opaque, isTrue);
          await expectLater(auth.token(), throwsA(isA<CloudSignInRequired>()));
        },
      );

      test(
        'sign-out without connection still removes everything here',
        () async {
          final drive = FakeDrive()..cut = (_) => true;
          final secrets = MemorySecretStore();
          await secrets.write(DesktopGoogleAuth.refreshKey, 'r');
          final auth = DesktopGoogleAuth(
            transport: drive.transport(),
            secrets: secrets,
            openBrowser: (_) async {},
          );
          await auth.load();
          await auth.signOut();
          expect(secrets.values, isEmpty);
          expect(auth.signedIn, isFalse);
        },
      );
    },
  );

  group(
    '#54/AK13 tests answer with simulated responses, never a real account',
    () {
      test('a full sync of two devices opens no HTTP connection', () async {
        final net = _NoNetwork();
        await HttpOverrides.runZoned(() async {
          final drive = FakeDrive();
          final a = await device(drive, 1);
          final b = await device(drive, 2);
          await a.add('z.mp3');
          await a.sync.syncNow();
          await b.sync.syncNow();
          expect(b.library.tracks, hasLength(1));
        }, createHttpClient: net.createHttpClient);
        expect(net.clients, 0);
      });
    },
  );
}

/// How long a test watches that no request goes out.
const _quiet = Duration(milliseconds: 50);

/// Files of lib/ reachable from [entry]; deferred imports only with [deferred].
Set<String> reachableFrom(String entry, {bool deferred = false}) {
  final seen = <String>{};
  final todo = [entry];
  final directive = RegExp(r'^(?:import|export)\s[^;]*;', multiLine: true);
  final uri = RegExp(r"'([^']+)'");
  while (todo.isNotEmpty) {
    final path = todo.removeLast();
    if (!seen.add(path)) continue;
    for (final d in directive.allMatches(File(path).readAsStringSync())) {
      if (!deferred && d.group(0)!.contains(' deferred as ')) continue;
      for (final u in uri.allMatches(d.group(0)!)) {
        final s = u.group(1)!;
        if (s.startsWith('dart:') ||
            (s.startsWith('package:') &&
                !s.startsWith('package:woodshed_player/'))) {
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

class _NoNetwork extends HttpOverrides {
  int clients = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    clients++;
    throw StateError('network access in a test');
  }
}

/// Another device creates the folder right after this one did.
class _Racing extends DriveTransport {
  _Racing(super.drive);

  /// The folder another device created a moment earlier.
  DriveFile? other;

  @override
  Future<HttpReply> send(HttpCall call) async {
    final r = await super.send(call);
    if (call.method == 'POST' &&
        call.url.path == '/drive/v3/files' &&
        other == null) {
      other = DriveFile('other', 'WoodshedPlayer', 'root', 0, folder: true);
      drive.files[other!.id] = other!;
    }
    return r;
  }
}

/// Every list answer is a rate limit error.
class _Failing extends DriveTransport {
  _Failing(super.drive, this.status);
  final int status;
  @override
  Future<HttpReply> send(HttpCall call) async => HttpReply.json(status, {
    'error': {
      'code': status,
      'errors': [
        {'reason': 'rateLimitExceeded'},
      ],
    },
  });
}
