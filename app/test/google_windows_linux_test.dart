// #161: Google sync on Windows and Linux. The sign-in runs in the system browser with PKCE and a receiver on
// 127.0.0.1 (the desktop client, no secret in the repository), the refresh token goes into the token store of
// the system through the channel «woodshed/keychain» (Credential Manager, libsecret). These tests run on
// every platform and in the Windows job of CI; the smoke test of the built app (WP_SMOKE=google) runs the
// same flow with the real token store of Windows and Linux.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/app/keychain_store.dart';
import 'package:woodshed_player/app/platform_native.dart';
import 'package:woodshed_player/sync/providers/google_auth.dart';
import 'package:woodshed_player/sync/providers/google_auth_desktop.dart';
import 'package:woodshed_player/sync/providers/google_smoke.dart';
import 'package:woodshed_player/sync/providers/http_transport.dart';
import 'package:woodshed_player/sync/providers/http_transport_io.dart';
import 'package:woodshed_player/sync/secret_store.dart';

/// A token store that refuses to write (Linux: keyring locked, no Secret Service).
class RefusingStore extends MemorySecretStore {
  @override
  Future<void> write(String key, String value) async =>
      throw PlatformException(code: 'keychain', message: 'locked');
}

/// The HTTP of the app, noting whether it was closed.
class _ClosingTransport implements HttpTransport {
  final inner = createTransport();
  bool closed = false;

  @override
  Future<HttpReply> send(HttpCall call) => inner.send(call);

  @override
  void close() {
    closed = true;
    inner.close();
  }
}

String _read(String path) => File(path).readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // the binding answers every HttpClient with 400; here the connections stay on 127.0.0.1 and are real
  HttpOverrides.global = null;

  test('#161/AK1 Google Drive is offered on macOS, Windows and Linux', () {
    expect(
      googleOnThisPlatform,
      Platform.isMacOS || Platform.isWindows || Platform.isLinux,
    );
    if (Platform.isWindows || Platform.isLinux) {
      expect(googleOnThisPlatform, isTrue);
    }
  });

  group(
    '#161/AK1 sign-in in the system browser against a simulated Google',
    () {
      test('PKCE, receiver on 127.0.0.1, token stored, found again, renewed, removed on sign-out', () async {
        final secrets = MemorySecretStore();
        expect(await smokeGoogleSignIn(secrets), isNull);
        // the smoke test leaves nothing behind and never touches the key of a real sign-in
        expect(secrets.values, isEmpty);
      });

      test(
        'the simulated Google and the HTTP of the app are closed at the end',
        () async {
          final google = await FakeGoogle.start();
          final port = google.port;
          final http = _ClosingTransport();
          expect(
            await smokeGoogleSignIn(
              MemorySecretStore(),
              google: google,
              http: http,
            ),
            isNull,
          );
          expect(google.problem, isNull, reason: 'the receiver answered 200');
          expect(http.closed, isTrue);
          await expectLater(
            Socket.connect(InternetAddress.loopbackIPv4, port),
            throwsA(isA<SocketException>()),
          );
        },
      );

      test('a real sign-in in the store stays untouched', () async {
        final secrets = MemorySecretStore()
          ..values[DesktopGoogleAuth.refreshKey] = 'users-token';
        expect(await smokeGoogleSignIn(secrets), isNull);
        expect(secrets.values, {DesktopGoogleAuth.refreshKey: 'users-token'});
      });

      test('the simulated Google refuses a foreign client, a code without PKCE and other servers', () async {
        final google = await FakeGoogle.start();
        final transport = google.transport(createTransport());
        addTearDown(() async {
          transport.close();
          await google.close();
        });
        final noPkce = await transport.send(
          HttpCall.form('POST', googleTokenUrl, {
            'client_id': googleDesktopClientId,
            'grant_type': 'authorization_code',
            'code': 'guessed',
            'code_verifier': 'x',
          }),
        );
        expect(noPkce.status, 400);
        final foreign = await transport.send(
          HttpCall.form('POST', googleTokenUrl, {'client_id': 'other'}),
        );
        expect(foreign.status, 401);
        await expectLater(
          transport.send(HttpCall('GET', Uri.parse('https://example.org/'))),
          throwsStateError,
        );
      });

      test(
        'another client is refused by the simulated Google at once',
        () async {
          final google = await FakeGoogle.start();
          final transport = google.transport(createTransport());
          addTearDown(() async {
            transport.close();
            await google.close();
          });
          final secrets = MemorySecretStore();
          final auth = DesktopGoogleAuth(
            transport: transport,
            secrets: secrets,
            openBrowser: google.consent,
            clientId: googleMacClientId,
          );
          final watch = Stopwatch()..start();
          expect(await auth.signIn(), SignInResult.failed);
          expect(watch.elapsed, lessThan(const Duration(minutes: 1)));
          expect(google.problem, contains('desktop client'));
          expect(secrets.values, isEmpty);
        },
      );

      test('the desktop client is the one of the issue and has no secret in the repository', () {
        expect(
          googleDesktopClientId,
          '1006497985345-53qpph7kj3k35ataaj4tqav631o3eih9.apps.googleusercontent.com',
        );
        expect(
          googleDesktopSecret,
          isEmpty,
          reason: 'only given at build time',
        );
      });
    },
  );

  group('#161/AK2 token store of the system', () {
    const channel = MethodChannel('woodshed/keychain');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('the channel stores, reads and deletes under the key', () async {
      final values = <String, String>{};
      messenger.setMockMethodCallHandler(channel, (call) async {
        final args = (call.arguments as Map).cast<String, String?>();
        final key = args['key'] as String;
        switch (call.method) {
          case 'write':
            values[key] = args['value']!;
          case 'read':
            return values[key];
          case 'delete':
            values.remove(key);
        }
        return null;
      });
      final store = KeychainStore();
      await store.write('k', 'v');
      expect(await store.read('k'), 'v');
      await store.delete('k');
      expect(await store.read('k'), isNull);
    });

    test('available: true, false, error and no answer', () async {
      Object? answer = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'available');
        final a = answer;
        if (a is PlatformException) throw a;
        return answer;
      });
      expect(await KeychainStore().available(), isTrue);
      answer = false;
      expect(await KeychainStore().available(), isFalse);
      answer = null;
      expect(await KeychainStore().available(), isFalse);
      answer = PlatformException(code: 'unavailable');
      expect(await KeychainStore().available(), isFalse);
      messenger.setMockMethodCallHandler(channel, null);
      expect(await KeychainStore().available(), isFalse);
    });

    test(
      'a store that refuses to write: not signed in, nothing kept',
      () async {
        final google = await FakeGoogle.start();
        final transport = google.transport(createTransport());
        addTearDown(() async {
          transport.close();
          await google.close();
        });
        final auth = DesktopGoogleAuth(
          transport: transport,
          secrets: RefusingStore(),
          openBrowser: google.consent,
        );
        expect(await auth.signIn(), SignInResult.failed);
        expect(auth.signedIn, isFalse);
        await expectLater(auth.token(), throwsA(anything));
      },
    );

    test('runners: Credential Manager on Windows, libsecret loaded at run time on Linux', () {
      final win = _read('windows/runner/keychain_channel.cpp');
      expect(win, contains('"woodshed/keychain"'));
      expect(win, contains('CredWriteW'));
      expect(win, contains('CRED_PERSIST_LOCAL_MACHINE'));
      expect(
        _read('windows/runner/flutter_window.cpp'),
        contains('CreateKeychainChannel'),
      );
      final linux = _read('linux/runner/keychain_channel.cc');
      expect(linux, contains('"woodshed/keychain"'));
      expect(linux, contains('dlopen("libsecret-1.so.0"'));
      expect(
        _read('linux/runner/my_application.cc'),
        contains('keychain_channel_new'),
      );
      // LGPL system library: never linked, never in the package, named in the licence notes
      expect(_read('linux/runner/CMakeLists.txt'), isNot(contains('secret')));
      expect(_read('linux/CMakeLists.txt'), isNot(contains('libsecret')));
      final notes = _read('linux/SYSTEM-LIBRARIES.txt');
      expect(notes, contains('libsecret'));
      expect(notes, contains('libsecret-1-0'));
    }, tags: 'repo');
  });

  test('#161/AK5 CI: smoke test of the sign-in with the token store on Windows and Linux', () {
    final ci = _read('../.github/workflows/test-quality.yml');
    final windows = ci.substring(ci.indexOf('\n  windows:'));
    final linux = ci.substring(ci.indexOf('\n  linux:'));
    expect(
      windows.substring(0, windows.indexOf('\n  linux:')),
      contains(
        'tools/smoke_app.sh app/build/windows/x64/runner/Release/WoodshedPlayer.exe google',
      ),
    );
    expect(linux, contains('woodshed-player google'));
    expect(linux, contains('gnome-keyring'));
  }, tags: 'repo');
}
