// #54/AK1 on macOS: the sign-in runs in the sign-in window of the system (ASWebAuthenticationSession through
// the channel «woodshed/webauth») with the client of type «iOS». The answer comes through the reversed
// client ID as URL scheme; no http:// loopback URL is ever opened, Safari with «HTTPS-Only» refuses it.
// Only the simulated Google of google_fakes.dart, never a real account (AK13).
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/app/web_auth_channel.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/sync/google_sync.dart';
import 'package:woodshed_player/sync/providers/google_auth.dart';
import 'package:woodshed_player/sync/providers/google_auth_desktop.dart';
import 'package:woodshed_player/sync/providers/google_platform_io.dart';
import 'package:woodshed_player/sync/secret_store.dart';
import 'package:woodshed_player/sync/system_sign_in.dart';

import 'fakes.dart';
import 'google_fakes.dart';

/// The sign-in window: records what it opens and answers like Google with [answer].
class FakeWindow implements SystemSignIn {
  FakeWindow([this.answer]);

  /// Builds the redirect from the opened URL; null: the user closed the window.
  final FutureOr<Uri?> Function(Uri url)? answer;
  final opened = <Uri>[];
  final schemes = <String>[];
  var cancels = 0;

  @override
  Future<Uri?> authenticate(Uri url, String callbackScheme) async {
    opened.add(url);
    schemes.add(callbackScheme);
    final a = answer;
    return a == null ? null : await a(url);
  }

  @override
  Future<void> cancel() async => cancels++;
}

/// Google's redirect to the custom scheme with [code] and the state of the request.
Uri redirectOf(Uri url, {String code = 'code-1', String? state}) =>
    Uri.parse(url.queryParameters['redirect_uri']!).replace(
      queryParameters: {
        'state': state ?? url.queryParameters['state']!,
        'code': code,
      },
    );

void main() {
  test('#54/AK1 macOS: the reversed client ID is the URL scheme', () {
    expect(
      googleRedirectScheme('123-abc.apps.googleusercontent.com'),
      'com.googleusercontent.apps.123-abc',
    );
    expect(
      googleRedirectScheme('123-abc'),
      'com.googleusercontent.apps.123-abc',
    );
    expect(googleMacClientId, endsWith('.apps.googleusercontent.com'));
    expect(googleMacClientId, isNot(googleDesktopClientId));
  });

  test(
    '#54/AK1 macOS: sign-in window with PKCE, never an http:// loopback URL',
    () async {
      final drive = FakeDrive();
      final secrets = MemorySecretStore();
      final browser = <String>[];
      final window = FakeWindow(redirectOf);
      final auth = DesktopGoogleAuth(
        transport: drive.transport(),
        secrets: secrets,
        openBrowser: (url) async => browser.add(url),
        systemSignIn: window,
        clientId: googleMacClientId,
        clientSecret: 'desktop-secret',
      );
      expect(await auth.signIn(), SignInResult.signedIn);
      expect(browser, isEmpty, reason: 'the system browser is not used');
      final url = window.opened.single;
      final q = url.queryParameters;
      final scheme = googleRedirectScheme(googleMacClientId);
      expect(window.schemes.single, scheme);
      expect(url.host, 'accounts.google.com');
      expect(q['client_id'], googleMacClientId);
      expect(q['redirect_uri'], '$scheme:/oauthredirect');
      expect(q['redirect_uri'], isNot(startsWith('http')));
      expect(q['redirect_uri'], isNot(contains('127.0.0.1')));
      expect(q['scope'], googleScope, reason: 'only drive.file');
      expect(q['response_type'], 'code');
      expect(q['code_challenge_method'], 'S256');
      final ex = drive.lastExchange!;
      expect(ex['code'], 'code-1');
      expect(pkceChallenge(ex['code_verifier']!), q['code_challenge']);
      expect(ex['redirect_uri'], q['redirect_uri']);
      expect(ex['client_id'], googleMacClientId);
      expect(ex.containsKey('client_secret'), isFalse, reason: 'iOS client');
      expect(secrets.values.keys, [DesktopGoogleAuth.refreshKey]);
      expect(auth.signedIn, isTrue);
      expect(window.cancels, 0, reason: 'the window closed by itself');
      // renewing uses the same client, again without a secret
      expect(await auth.token(), startsWith('token-'));
    },
  );

  test('#54/AK1 macOS: closed window, foreign answer or failing window store nothing', () async {
    final drive = FakeDrive();
    final secrets = MemorySecretStore();
    Future<SignInResult> signIn(SystemSignIn window) => DesktopGoogleAuth(
      transport: drive.transport(),
      secrets: secrets,
      openBrowser: (_) async => fail('no system browser'),
      systemSignIn: window,
      clientId: googleMacClientId,
    ).signIn();
    final closed = FakeWindow();
    expect(await signIn(closed), SignInResult.failed);
    expect(closed.cancels, 0);
    final forged = FakeWindow((u) => redirectOf(u, state: 'other'));
    expect(await signIn(forged), SignInResult.failed);
    final broken = FakeWindow((_) => throw PlatformException(code: 'x'));
    expect(await signIn(broken), SignInResult.failed);
    expect(drive.lastExchange, isNull, reason: 'no code was exchanged');
    expect(secrets.values, isEmpty);
  });

  test(
    '#54/AK1 macOS: a timeout or cancelling closes the open window',
    () async {
      final drive = FakeDrive();
      final never = Completer<Uri?>();
      addTearDown(() => never.isCompleted ? null : never.complete(null));
      final window = FakeWindow((_) => never.future);
      final timeout = DesktopGoogleAuth(
        transport: drive.transport(),
        secrets: MemorySecretStore(),
        openBrowser: (_) async {},
        systemSignIn: window,
        waitForBrowser: const Duration(milliseconds: 20),
      );
      expect(await timeout.signIn(), SignInResult.failed);
      expect(window.cancels, 1);
      final cancelled = DesktopGoogleAuth(
        transport: drive.transport(),
        secrets: MemorySecretStore(),
        openBrowser: (_) async {},
        systemSignIn: window,
      );
      final running = cancelled.signIn();
      await pumpEventQueue();
      cancelled.cancelSignIn();
      expect(await running, SignInResult.failed);
      expect(window.cancels, 2);
      // a window that cannot be closed changes nothing
      final stubborn = _StubbornWindow();
      final third = DesktopGoogleAuth(
        transport: drive.transport(),
        secrets: MemorySecretStore(),
        openBrowser: (_) async {},
        systemSignIn: stubborn,
        waitForBrowser: const Duration(milliseconds: 20),
      );
      expect(await third.signIn(), SignInResult.failed);
    },
  );

  test('#54/AK1 the desktop module: macOS with the window and the iOS client, otherwise the browser', () {
    Library lib() => Library(
      MemoryFileStore(),
      probe: (_) => 1,
      readSource: (_) async => null,
    );
    final window = FakeWindow();
    final mac = openGoogle(
      library: lib(),
      secrets: MemorySecretStore(),
      openUrl: (_) async {},
      playing: () => false,
      systemSignIn: window,
    ) as GoogleBackend;
    addTearDown(mac.dispose);
    final a = mac.auth as DesktopGoogleAuth;
    expect(a.systemSignIn, same(window));
    expect(a.clientId, googleMacClientId);
    expect(a.clientSecret, googleDesktopSecret, reason: 'not sent, see above');
    final other = openGoogle(
      library: lib(),
      secrets: MemorySecretStore(),
      openUrl: (_) async {},
      playing: () => false,
    ) as GoogleBackend;
    addTearDown(other.dispose);
    final b = other.auth as DesktopGoogleAuth;
    expect(b.systemSignIn, isNull);
    expect(b.clientId, googleDesktopClientId);
    expect(b.clientSecret, googleDesktopSecret);
    expect(b.clientId, isNot(a.clientId));
  });

  group('#54/AK1 channel woodshed/webauth', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('woodshed/webauth');
    final calls = <MethodCall>[];
    Object? reply;
    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return call.method == 'start' ? reply : null;
          });
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    test('start passes URL and scheme, returns the redirect', () async {
      reply = 'com.googleusercontent.apps.x:/oauthredirect?code=c&state=s';
      final w = WebAuthChannel();
      final uri = await w.authenticate(
        Uri.parse('https://accounts.google.com/o?a=1'),
        'com.googleusercontent.apps.x',
      );
      expect(uri!.scheme, 'com.googleusercontent.apps.x');
      expect(uri.queryParameters, {'code': 'c', 'state': 's'});
      expect(calls.single.method, 'start');
      expect(calls.single.arguments, {
        'url': 'https://accounts.google.com/o?a=1',
        'scheme': 'com.googleusercontent.apps.x',
      });
      reply = null;
      expect(await w.authenticate(Uri.parse('https://x.test/'), 's'), isNull);
      await w.cancel();
      expect(calls.last.method, 'cancel');
    });
  });
}

class _StubbornWindow implements SystemSignIn {
  @override
  Future<Uri?> authenticate(Uri url, String callbackScheme) =>
      Completer<Uri?>().future;

  @override
  Future<void> cancel() async => throw PlatformException(code: 'gone');
}
