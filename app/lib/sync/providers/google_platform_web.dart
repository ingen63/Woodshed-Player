// The Google module in the browser (#54), loaded with a deferred import only once Google Drive is chosen:
// fetch for HTTP, sign-in by redirect, token in IndexedDB. Google's answer comes back in the fragment of
// the page address; the start of the app takes it before the first frame and passes it in as [fragment]
// (#131: Flutter replaces the address long before this module is loaded). Audio is loaded only when
// played (cache, #39).
import 'package:web/web.dart' as web;

import '../../library/library.dart';
import '../cloud_account.dart';
import '../google_sync.dart';
import '../secret_store.dart';
import 'google_auth_web.dart';
import 'http_transport_web.dart';
import 'idb_secret_store.dart';

CloudBackend openGoogle({
  required Library library,
  required SecretStore? secrets,
  required Future<void> Function(String url) openUrl,
  required bool Function() playing,
  String fragment = '',
}) {
  final loc = web.window.location;
  final transport = createTransport();
  return GoogleBackend(
    auth: WebGoogleAuth(
      transport: transport,
      store: secrets ?? IdbSecretStore(),
      redirectUri: redirectUriOf(loc.origin, loc.pathname),
      navigate: (url) => loc.assign(url),
      playing: playing,
      fragment: fragment,
    ),
    transport: transport,
    library: library,
    eagerDownload: false,
  );
}
