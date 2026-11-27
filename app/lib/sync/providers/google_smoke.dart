// #161: smoke test of the Google sign-in in the built desktop app (WP_SMOKE=google, tools/smoke_app.sh),
// for Windows and Linux in CI, where no real Google account can sign in. The real DesktopGoogleAuth (system
// browser, PKCE, receiver on 127.0.0.1) and the real token store of the system (Credential Manager,
// libsecret) run against a simulated Google on 127.0.0.1: an authorization page that answers like the
// browser after the consent, and a token endpoint that checks client, code, PKCE verifier and redirect.
// The flow: sign in, the token is in the store, a second start finds it and renews the access token,
// sign out, the token is gone and revoked. Only loopback connections; the entry is under its own key
// ([smokeKeyPrefix]), so a sign-in of the user is never touched. Loaded with a deferred import.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../secret_store.dart';
import 'google_auth.dart';
import 'google_auth_desktop.dart';
import 'http_transport.dart';
import 'http_transport_io.dart';

/// The smoke test keeps its token under this prefix, never under the key of a real sign-in.
const smokeKeyPrefix = 'smoke.';

/// Runs the flow against [secrets] (the token store of the system). Null when every step worked,
/// otherwise the step that failed. [google] and [http] replace the simulated Google and the HTTP of the
/// app (tests); both are closed at the end.
Future<String?> smokeGoogleSignIn(
  SecretStore secrets, {
  FakeGoogle? google,
  HttpTransport? http,
}) async {
  final store = PrefixedSecretStore(secrets, smokeKeyPrefix);
  final fake = google ?? await FakeGoogle.start();
  final transport = fake.transport(http ?? createTransport());
  try {
    final auth = DesktopGoogleAuth(
      transport: transport,
      secrets: store,
      openBrowser: fake.consent,
      waitForBrowser: const Duration(seconds: 30),
    );
    if (await auth.signIn(doneText: 'ok') != SignInResult.signedIn) {
      return 'sign-in failed${fake.problem == null ? '' : ': ${fake.problem}'}';
    }
    final stored = await store.read(DesktopGoogleAuth.refreshKey);
    if (stored != fake.refreshToken) {
      return 'refresh token not in the token store';
    }
    // the next start of the app: the sign-in comes from the token store, the access token is renewed
    final again = DesktopGoogleAuth(
      transport: transport,
      secrets: store,
      openBrowser: (_) async {},
    );
    await again.load();
    if (!again.signedIn) return 'stored sign-in not found';
    if (await again.token() != FakeGoogle.renewedAccess) {
      return 'renewal failed';
    }
    await again.signOut();
    if (await store.read(DesktopGoogleAuth.refreshKey) != null) {
      return 'refresh token still in the token store after signing out';
    }
    if (fake.revoked != stored) return 'token not revoked';
    return null;
  } catch (e) {
    return 'exception: $e';
  } finally {
    transport.close();
    await fake.close();
  }
}

/// Every key of [inner] with [prefix] in front.
class PrefixedSecretStore implements SecretStore {
  PrefixedSecretStore(this.inner, this.prefix);
  final SecretStore inner;
  final String prefix;

  @override
  Future<String?> read(String key) => inner.read('$prefix$key');

  @override
  Future<void> write(String key, String value) =>
      inner.write('$prefix$key', value);

  @override
  Future<void> delete(String key) => inner.delete('$prefix$key');
}

/// Google's authorization page and token endpoint, simulated on 127.0.0.1.
class FakeGoogle {
  FakeGoogle._(this._server, Random random)
    : refreshToken = 'smoke-refresh-${random.nextInt(1 << 30)}',
      _code = 'smoke-code-${random.nextInt(1 << 30)}' {
    _server.listen(_answer, onError: (_) {});
  }

  static Future<FakeGoogle> start() async => FakeGoogle._(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    Random.secure(),
  );

  final HttpServer _server;
  final String refreshToken;

  /// The port of the simulated Google on 127.0.0.1.
  int get port => _server.port;
  final String _code;
  static const firstAccess = 'smoke-access-1';
  static const renewedAccess = 'smoke-access-2';

  String? _challenge;
  String? _redirect;

  /// The token revoked on sign-out.
  String? revoked;

  /// Why the simulated Google refused, for the report.
  String? problem;

  /// Sends the calls to Google's token and revoke endpoints to this server instead.
  HttpTransport transport(HttpTransport inner) => _Rerouted(inner, this);

  Uri _local(Uri url) => Uri(
    scheme: 'http',
    host: InternetAddress.loopbackIPv4.address,
    port: _server.port,
    path: url.path,
  );

  /// The browser after the consent: checks the authorization request and calls the app's receiver
  /// with code and state, as Google's redirect does; a request not as for the desktop client gets
  /// Google's error answer instead, so the sign-in ends at once.
  Future<void> consent(String url) async {
    final q = Uri.parse(url).queryParameters;
    final redirect = Uri.tryParse(q['redirect_uri'] ?? '');
    if (redirect == null || redirect.host != '127.0.0.1') {
      problem = 'redirect not to 127.0.0.1';
      return;
    }
    final ok =
        q['client_id'] == googleDesktopClientId &&
        q['code_challenge_method'] == 'S256' &&
        q['response_type'] == 'code';
    if (ok) {
      _challenge = q['code_challenge'];
      _redirect = redirect.toString();
    } else {
      problem = 'authorization request not as for the desktop client';
    }
    final back = redirect.replace(
      queryParameters: {
        if (ok) 'code': _code else 'error': 'invalid_request',
        'state': q['state'] ?? '',
      },
    );
    // one request without keep-alive: no connection stays open after it
    final request = await HttpClient().getUrl(back);
    request.persistentConnection = false;
    final reply = await request.close();
    await reply.drain<void>();
    if (reply.statusCode != HttpStatus.ok) {
      problem ??= 'receiver answered ${reply.statusCode}';
    }
  }

  Future<void> _answer(HttpRequest req) async {
    final form = Uri.splitQueryString(await utf8.decodeStream(req));
    final reply = switch (req.uri.path) {
      '/token' => _token(form),
      '/revoke' => _revoke(form),
      _ => (404, <String, Object?>{}),
    };
    req.response
      ..statusCode = reply.$1
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(reply.$2));
    await req.response.close();
  }

  (int, Map<String, Object?>) _token(Map<String, String> f) {
    if (f['client_id'] != googleDesktopClientId) {
      problem = 'token request with another client';
      return (401, {'error': 'invalid_client'});
    }
    if (f['grant_type'] == 'refresh_token') {
      return f['refresh_token'] == refreshToken
          ? (200, {'access_token': renewedAccess, 'expires_in': 3600})
          : (400, {'error': 'invalid_grant'});
    }
    final verifier = f['code_verifier'];
    if (f['grant_type'] != 'authorization_code' ||
        f['code'] != _code ||
        f['redirect_uri'] != _redirect ||
        verifier == null ||
        pkceChallenge(verifier) != _challenge) {
      problem = 'code exchange without matching code, redirect or PKCE';
      return (400, {'error': 'invalid_grant'});
    }
    return (
      200,
      {
        'access_token': firstAccess,
        'expires_in': 3600,
        'refresh_token': refreshToken,
        'scope': googleScope,
      },
    );
  }

  (int, Map<String, Object?>) _revoke(Map<String, String> f) {
    revoked = f['token'];
    return (200, {});
  }

  Future<void> close() => _server.close(force: true);
}

class _Rerouted implements HttpTransport {
  _Rerouted(this.inner, this.google);
  final HttpTransport inner;
  final FakeGoogle google;

  @override
  Future<HttpReply> send(HttpCall call) {
    final url = call.url;
    if (url != googleTokenUrl && url != googleRevokeUrl) {
      return Future.error(StateError('smoke test: no call to $url'));
    }
    return inner.send(
      HttpCall(
        call.method,
        google._local(url),
        headers: call.headers,
        body: call.body,
        opaque: call.opaque,
      ),
    );
  }

  @override
  void close() => inner.close();
}
