// The sign-in window of the system (#54/AK1): on macOS ASWebAuthenticationSession through a small channel
// of the app (lib/app/web_auth_channel.dart, «woodshed/webauth»). The answer of the provider comes back
// through a custom URL scheme, never through http://127.0.0.1: Safari with «HTTPS-Only» refuses that.
// Lies outside providers/, so the app can hand it to the deferred Google module without loading it.

abstract class SystemSignIn {
  /// Opens [url] in the sign-in window and waits for the redirect to [callbackScheme]. The full redirect
  /// URL, or null if the user closed the window.
  Future<Uri?> authenticate(Uri url, String callbackScheme);

  /// Closes a sign-in window that is still open.
  Future<void> cancel();
}
