// The Google module on the desktop (#54), loaded with a deferred import only once Google Drive is chosen:
// dart:io for HTTP, the keychain for the refresh token. The sign-in runs on macOS in the sign-in window of
// the system with the client of type «iOS» (it has no secret, none is sent); elsewhere in the system browser with a receiver on
// 127.0.0.1. Every file is downloaded right away (eager).
import '../../library/library.dart';
import '../cloud_account.dart';
import '../google_sync.dart';
import '../secret_store.dart';
import '../system_sign_in.dart';
import 'google_auth.dart';
import 'google_auth_desktop.dart';
import 'http_transport_io.dart';

CloudBackend openGoogle({
  required Library library,
  required SecretStore secrets,
  required Future<void> Function(String url) openUrl,
  required bool Function() playing,
  SystemSignIn? systemSignIn,
}) {
  final transport = createTransport();
  return GoogleBackend(
    auth: DesktopGoogleAuth(
      transport: transport,
      secrets: secrets,
      openBrowser: openUrl,
      systemSignIn: systemSignIn,
      clientId: systemSignIn == null
          ? googleDesktopClientId
          : googleMacClientId,
    ),
    transport: transport,
    library: library,
    eagerDownload: true,
  );
}
