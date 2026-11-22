// The Google module on the desktop (#54), loaded with a deferred import only once Google Drive is chosen:
// dart:io for HTTP, the system browser and a receiver on 127.0.0.1 for the sign-in, the keychain for the
// refresh token. Every file is downloaded right away (eager).
import '../../library/library.dart';
import '../cloud_account.dart';
import '../google_sync.dart';
import '../secret_store.dart';
import 'google_auth_desktop.dart';
import 'http_transport_io.dart';

CloudBackend openGoogle({
  required Library library,
  required SecretStore secrets,
  required Future<void> Function(String url) openUrl,
  required bool Function() playing,
}) {
  final transport = createTransport();
  return GoogleBackend(
    auth: DesktopGoogleAuth(
      transport: transport,
      secrets: secrets,
      openBrowser: openUrl,
    ),
    transport: transport,
    library: library,
    eagerDownload: true,
  );
}
