// Google sign-in in the browser (#54/AK1, AK5), as in the test page of M0 (#52): a full-page redirect with
// `response_type=token` (about 1 h, no refresh token, because Google wants the client secret for the code
// exchange of a web client). The token stays in IndexedDB of this origin. Renewal is a redirect with
// `prompt=none`, never while something plays: the sync waits until playback ends (next sync or start).
// If the silent renewal is refused, the app asks to sign in again and redirects no more on its own.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../cloud_provider.dart';
import '../secret_store.dart';
import 'google_auth.dart';
import 'http_transport.dart';
import '../oauth_return.dart';

class WebGoogleAuth extends GoogleAuth {
  WebGoogleAuth({
    required this.transport,
    required this.store,
    required this.redirectUri,
    required this.navigate,
    required this.playing,
    this.fragment = '',
    this.clientId = googleWebClientId,
    DateTime Function()? now,
    this.random,
  }) : _now = now ?? DateTime.now;

  static const tokenKey = 'google.token';
  static const pendingKey = 'google.pending';
  static const signedInKey = 'google.signedIn';
  static const needsKey = 'google.needsSignIn';

  final HttpTransport transport;
  final SecretStore store;

  /// The address Google sends the browser back to (the app's page, registered at Google).
  final Uri redirectUri;

  /// Leaves the page for [url].
  final void Function(String url) navigate;

  /// Something plays: no redirect now (AK5).
  final bool Function() playing;

  /// The fragment of the page address at start (without «#»): Google's answer after a redirect.
  final String fragment;
  final String clientId;
  final DateTime Function() _now;

  /// Source of PKCE verifier and state (tests); secure by default.
  final Random? random;

  String? _access;
  DateTime? _expires;
  bool _signedIn = false;
  bool _needsSignIn = false;

  @override
  bool get signedIn => _signedIn;

  @override
  bool get needsSignIn => _needsSignIn;

  /// The fragment is an answer of Google (token or error).
  static bool isAnswer(String fragment) => isOAuthAnswer(fragment);

  @override
  Future<void> load() async {
    _signedIn = await store.read(signedInKey) == 'true';
    _needsSignIn = await store.read(needsKey) == 'true';
    if (isAnswer(fragment)) await _takeAnswer(fragment);
    final t = await store.read(tokenKey);
    if (t != null) {
      try {
        final j = jsonDecode(t) as Map;
        _access = j['accessToken'] as String;
        _expires = DateTime.fromMillisecondsSinceEpoch(j['expiresAt'] as int);
      } catch (_) {
        await store.delete(tokenKey);
      }
    }
    notifyListeners();
  }

  Future<void> _takeAnswer(String fragment) async {
    final p = Uri.splitQueryString(fragment);
    final pendingText = await store.read(pendingKey);
    await store.delete(pendingKey);
    Map<Object?, Object?>? pending;
    try {
      pending = pendingText == null ? null : jsonDecode(pendingText) as Map;
    } catch (_) {}
    if (pending == null || pending['state'] != p['state']) return; // not ours
    final silent = pending['silent'] == true;
    final access = p['access_token'];
    if (p['error'] != null || access == null || !grantsDrive(p['scope'])) {
      if (silent) {
        // AK5: renewal refused (e.g. interaction_required): ask the user, no further redirects
        _needsSignIn = true;
        await store.write(needsKey, 'true');
      }
      return;
    }
    final seconds = int.tryParse(p['expires_in'] ?? '') ?? 3600;
    final expires = _now().add(Duration(seconds: seconds));
    await store.write(
      tokenKey,
      jsonEncode({
        'accessToken': access,
        'expiresAt': expires.millisecondsSinceEpoch,
      }),
    );
    await store.write(signedInKey, 'true');
    await store.delete(needsKey);
    _signedIn = true;
    _needsSignIn = false;
  }

  bool get _valid {
    final e = _expires;
    return _access != null && e != null && _now().add(tokenMargin).isBefore(e);
  }

  @override
  Future<String> token() async {
    if (!_signedIn) throw const CloudSignInRequired('not signed in');
    if (_valid) return _access!;
    if (_needsSignIn) throw const CloudSignInRequired('renewal refused');
    // AK5: the redirect would interrupt playback; the sync waits and tries again later
    if (playing()) throw const CloudOffline('renewal waits for playback');
    await _redirect(silent: true);
    throw const CloudOffline('renewing the sign-in');
  }

  Future<void> _redirect({required bool silent}) async {
    final state = randomState(random);
    await store.write(
      pendingKey,
      jsonEncode({
        'state': state,
        'silent': silent,
        't': _now().millisecondsSinceEpoch,
      }),
    );
    navigate(
      googleAuthUrl
          .replace(
            queryParameters: {
              'client_id': clientId,
              'redirect_uri': redirectUri.toString(),
              'response_type': 'token',
              'scope': googleScope,
              'state': state,
              'include_granted_scopes': 'true',
              if (silent) 'prompt': 'none',
            },
          )
          .toString(),
    );
  }

  @override
  void rejected() {
    _access = null;
    _expires = null;
    unawaited(store.delete(tokenKey));
  }

  @override
  Future<SignInResult> signIn({String doneText = ''}) async {
    await _redirect(silent: false);
    return SignInResult.redirected;
  }

  @override
  Future<void> signOut() async {
    final access = _access;
    _access = null;
    _expires = null;
    _signedIn = false;
    _needsSignIn = false;
    for (final k in [tokenKey, pendingKey, signedInKey, needsKey]) {
      await store.delete(k);
    }
    notifyListeners();
    if (access != null) {
      try {
        // the revoke endpoint sends no CORS headers; an opaque answer is enough
        await transport
            .send(
              HttpCall(
                'POST',
                googleRevokeUrl.replace(queryParameters: {'token': access}),
                opaque: true,
              ),
            )
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        // offline: the token lapses within the hour
      }
    }
  }
}

/// The app's page without file name, query and fragment (must be registered at Google exactly so).
Uri redirectUriOf(String origin, String path) {
  final dir = path.endsWith('/')
      ? path
      : path.substring(0, path.lastIndexOf('/') + 1);
  return Uri.parse('$origin$dir');
}
