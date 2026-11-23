// Google sign-in on the desktop (#54/AK1, AK5): OAuth with PKCE. On macOS in the sign-in window of the
// system (SystemSignIn), the answer comes through the reversed client ID as URL scheme. Elsewhere (later
// Windows, Linux) in the system browser, a receiver on 127.0.0.1 with a free port takes the answer. The
// refresh token goes into the keychain and lasts until the user signs out. Access tokens (about 1 h) stay in memory and are renewed silently.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../cloud_provider.dart';
import '../secret_store.dart';
import '../system_sign_in.dart';
import 'google_auth.dart';
import 'http_transport.dart';

class DesktopGoogleAuth extends GoogleAuth {
  DesktopGoogleAuth({
    required this.transport,
    required this.secrets,
    required this.openBrowser,
    this.systemSignIn,
    this.clientId = googleDesktopClientId,
    this.clientSecret = googleDesktopSecret,
    this.waitForBrowser = const Duration(minutes: 5),
    DateTime Function()? now,
    this.random,
  }) : _now = now ?? DateTime.now;

  static const refreshKey = 'google.refreshToken';

  final HttpTransport transport;
  final SecretStore secrets;

  /// Opens the sign-in page in the system browser.
  final Future<void> Function(String url) openBrowser;

  /// The sign-in window of the system (macOS). If set, the sign-in runs there and [openBrowser] and the
  /// receiver on 127.0.0.1 are not used; Safari with «HTTPS-Only» refuses an http:// redirect.
  final SystemSignIn? systemSignIn;
  final String clientId;
  final String clientSecret;

  /// The secret sent to Google: none with the sign-in window, the client of type «iOS» has none.
  String get _secret => systemSignIn == null ? clientSecret : '';

  /// How long the receiver waits for the browser.
  final Duration waitForBrowser;
  final DateTime Function() _now;

  /// Source of PKCE verifier and state (tests); secure by default.
  final Random? random;

  String? _refresh;
  String? _access;
  DateTime? _expires;
  bool _needsSignIn = false;
  Future<String>? _renewing;
  Completer<Uri?>? _waiting;

  @override
  bool get signedIn => _refresh != null;

  @override
  bool get needsSignIn => _needsSignIn;

  @override
  Future<void> load() async {
    try {
      _refresh = await secrets.read(refreshKey);
    } catch (_) {
      _refresh = null; // no keychain: not signed in
    }
    notifyListeners();
  }

  @override
  Future<String> token() {
    final a = _access;
    final e = _expires;
    if (a != null && e != null && _now().add(tokenMargin).isBefore(e)) {
      return Future.value(a);
    }
    return _renewing ??= _renew().whenComplete(() => _renewing = null);
  }

  Future<String> _renew() async {
    final refresh = _refresh;
    if (refresh == null) throw const CloudSignInRequired('not signed in');
    final reply = await transport.send(
      HttpCall.form('POST', googleTokenUrl, {
        'client_id': clientId,
        if (_secret.isNotEmpty) 'client_secret': _secret,
        'grant_type': 'refresh_token',
        'refresh_token': refresh,
      }),
    );
    if (reply.status == 400 || reply.status == 401) {
      // invalid_grant: revoked, expired or the password changed. The user must sign in again (AK5).
      await _forget();
      _needsSignIn = true;
      notifyListeners();
      throw CloudSignInRequired('refresh refused: ${reply.json['error']}');
    }
    if (!reply.ok) throw CloudError('token renewal: ${reply.status}');
    return _take(reply.json);
  }

  String _take(Map<String, Object?> j) {
    final access = j['access_token'];
    if (access is! String || access.isEmpty) {
      throw const CloudError('token response without access token');
    }
    final seconds = j['expires_in'] is int ? j['expires_in'] as int : 3600;
    _access = access;
    _expires = _now().add(Duration(seconds: seconds));
    return access;
  }

  @override
  void rejected() {
    _access = null;
    _expires = null;
  }

  @override
  Future<SignInResult> signIn({String doneText = ''}) async {
    cancelSignIn();
    final verifier = pkceVerifier(random);
    final state = randomState(random);
    final system = systemSignIn;
    final scheme = googleRedirectScheme(clientId);
    HttpServer? server;
    final String redirect;
    if (system != null) {
      // macOS: the sign-in window of the system, the answer comes through the custom scheme (AK1)
      redirect = '$scheme:/oauthredirect';
    } else {
      try {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      } on SocketException {
        return SignInResult.failed;
      }
      redirect = 'http://127.0.0.1:${server.port}/';
    }
    final waiting = _waiting = Completer<Uri?>();
    void deliver(Uri? uri) {
      if (!waiting.isCompleted) waiting.complete(uri);
    }

    var windowOpen = false;

    server?.listen((req) async {
      final mine = req.uri.queryParameters['state'] == state;
      req.response
        ..statusCode = mine ? HttpStatus.ok : HttpStatus.notFound
        ..headers.contentType = ContentType.html
        ..write(mine ? _page(doneText) : '');
      await req.response.close();
      if (mine) deliver(req.uri);
    }, onError: (_) {});
    try {
      final url = googleAuthUrl.replace(
        queryParameters: {
          'client_id': clientId,
          'redirect_uri': redirect,
          'response_type': 'code',
          'scope': googleScope,
          'code_challenge': pkceChallenge(verifier),
          'code_challenge_method': 'S256',
          'state': state,
          'access_type': 'offline',
          'prompt': 'consent',
        },
      );
      if (system != null) {
        // a closed window, a foreign answer or a failure of the window: no sign-in
        windowOpen = true;
        unawaited(
          system
              .authenticate(url, scheme)
              .then(
                (uri) => uri?.queryParameters['state'] == state ? uri : null,
                onError: (Object _) => null,
              )
              .then((uri) {
                windowOpen = false;
                deliver(uri);
              }),
        );
      } else {
        await openBrowser(url.toString());
      }
      final answer = await waiting.future.timeout(
        waitForBrowser,
        onTimeout: () => null,
      );
      final code = answer?.queryParameters['code'];
      if (code == null) return SignInResult.failed;
      final reply = await transport.send(
        HttpCall.form('POST', googleTokenUrl, {
          'client_id': clientId,
          if (_secret.isNotEmpty) 'client_secret': _secret,
          'code': code,
          'code_verifier': verifier,
          'grant_type': 'authorization_code',
          'redirect_uri': redirect,
        }),
      );
      final j = reply.json;
      final refresh = j['refresh_token'];
      if (!reply.ok ||
          refresh is! String ||
          !grantsDrive(j['scope'] as String?)) {
        return SignInResult.failed;
      }
      _take(j);
      await secrets.write(refreshKey, refresh);
      _refresh = refresh;
      _needsSignIn = false;
      notifyListeners();
      return SignInResult.signedIn;
    } on CloudOffline {
      return SignInResult.failed;
    } on CloudError {
      return SignInResult.failed;
    } finally {
      if (!waiting.isCompleted) waiting.complete(null);
      await server?.close(force: true);
      if (windowOpen) await _closeWindow(system!);
      if (identical(_waiting, waiting)) _waiting = null;
    }
  }

  /// Closes the sign-in window after a timeout or [cancelSignIn]; a failure there changes nothing.
  static Future<void> _closeWindow(SystemSignIn system) async {
    try {
      await system.cancel();
    } catch (_) {}
  }

  static String _page(String text) {
    const esc = HtmlEscape();
    return '<!DOCTYPE html><html><head><meta charset="utf-8">'
        '<title>Woodshed Player</title></head>'
        '<body style="font-family:sans-serif;margin:3em">'
        '<p>${esc.convert(text)}</p></body></html>';
  }

  @override
  void cancelSignIn() {
    final w = _waiting;
    if (w != null && !w.isCompleted) w.complete(null);
  }

  @override
  Future<void> signOut() async {
    cancelSignIn();
    final refresh = _refresh;
    await _forget();
    _needsSignIn = false;
    notifyListeners();
    if (refresh != null) {
      try {
        await transport
            .send(HttpCall.form('POST', googleRevokeUrl, {'token': refresh}))
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        // offline: the token stays valid at Google until the user removes the app in the account
      }
    }
  }

  Future<void> _forget() async {
    _refresh = null;
    _access = null;
    _expires = null;
    try {
      await secrets.delete(refreshKey);
    } catch (_) {}
  }
}
