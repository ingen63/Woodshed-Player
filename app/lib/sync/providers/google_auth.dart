// Sign-in at Google for the Drive sync (#54/AK1, AK5). Only the right `drive.file` is asked for: the app
// sees only the files it created itself. Desktop: OAuth with PKCE in the system browser and a receiver on
// 127.0.0.1, refresh token in the keychain (google_auth_desktop.dart). Browser: redirect with
// `response_type=token` (Google wants the client secret for the code exchange of a web client), token in
// IndexedDB, renewed by a redirect with `prompt=none` (google_auth_web.dart).
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

const googleScope = 'https://www.googleapis.com/auth/drive.file';
final googleAuthUrl = Uri.parse('https://accounts.google.com/o/oauth2/v2/auth');
final googleTokenUrl = Uri.parse('https://oauth2.googleapis.com/token');
final googleRevokeUrl = Uri.parse('https://oauth2.googleapis.com/revoke');

/// OAuth clients of the Google Cloud project (public IDs, no secret).
const googleWebClientId =
    '1006497985345-me94u7thnv7bupkmcq7370q2v4qu3v4c.apps.googleusercontent.com';
const googleDesktopClientId =
    '1006497985345-53qpph7kj3k35ataaj4tqav631o3eih9.apps.googleusercontent.com';

/// Google may want the «secret» of the desktop client in the code exchange although an installed app
/// cannot keep it secret. It is not in the repository; a build passes it with
/// `--dart-define=WP_GOOGLE_DESKTOP_SECRET=…`. Empty: none is sent.
const googleDesktopSecret = String.fromEnvironment('WP_GOOGLE_DESKTOP_SECRET');

/// A token is treated as expired a minute early, so no request starts with a token about to lapse.
const tokenMargin = Duration(minutes: 1);

enum SignInResult {
  signedIn,

  /// The browser left for Google; the app comes back signed in (web).
  redirected,

  /// Cancelled, refused or no answer in time.
  failed,
}

abstract class GoogleAuth extends ChangeNotifier {
  /// Reads what is stored (keychain, IndexedDB); in the browser it also takes the answer of a redirect.
  Future<void> load();

  /// Signed in: a token or refresh token is stored.
  bool get signedIn;

  /// The silent renewal failed (#54/AK5): the user must sign in again.
  bool get needsSignIn;

  /// A valid access token; renews it if needed. Throws `CloudSignInRequired` if there is no sign-in,
  /// `CloudOffline` without connection or while the renewal has to wait.
  Future<String> token();

  /// Google refused the token (401): it is dropped, the next [token] renews it.
  void rejected();

  /// Interactive sign-in. [doneText] is shown in the browser at the end (desktop).
  Future<SignInResult> signIn({String doneText = ''});

  /// Stops a sign-in waiting for the browser.
  void cancelSignIn() {}

  /// Revokes the tokens at Google (if reachable) and removes them here (#54/AK11).
  Future<void> signOut();
}

/// PKCE (RFC 7636): a random verifier of 64 unreserved characters.
String pkceVerifier([Random? random]) {
  const chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
  final r = random ?? Random.secure();
  return List.generate(64, (_) => chars[r.nextInt(chars.length)]).join();
}

/// The S256 challenge of [verifier]: base64url of its SHA-256, without padding.
String pkceChallenge(String verifier) => base64Url
    .encode(sha256.convert(ascii.encode(verifier)).bytes)
    .replaceAll('=', '');

/// Random state against forged redirects.
String randomState([Random? random]) {
  final r = random ?? Random.secure();
  return List.generate(
    16,
    (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// Whether the granted [scope] (space separated) contains `drive.file`.
bool grantsDrive(String? scope) =>
    scope == null || scope.split(' ').contains(googleScope);
