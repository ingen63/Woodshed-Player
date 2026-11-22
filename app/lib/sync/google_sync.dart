// The Google Drive part of the sync (#54), loaded only once Google Drive is chosen on this device (deferred
// import, AK6): sign-in, GoogleDriveProvider and the engine (CloudSync) together, as the settings see them.
import 'package:flutter/foundation.dart';

import '../library/library.dart';
import 'cloud_account.dart';
import 'providers/google_auth.dart';
import 'providers/google_drive_provider.dart';
import 'providers/http_transport.dart';
import 'sync_engine.dart';
import 'sync_service.dart';

class GoogleBackend extends ChangeNotifier implements CloudBackend {
  GoogleBackend({
    required this.auth,
    required HttpTransport transport,
    required this.library,
    required bool eagerDownload,
  }) : provider = GoogleDriveProvider(transport: transport, auth: auth) {
    engine = CloudSync(provider, library, eagerDownload: eagerDownload);
    auth.addListener(notifyListeners);
    engine.addListener(notifyListeners);
  }

  final GoogleAuth auth;
  final GoogleDriveProvider provider;
  final Library library;
  late final CloudSync engine;
  bool _disposed = false;

  @override
  SyncService get sync => engine;

  @override
  Future<void> load() => auth.load();

  @override
  bool get signedIn => auth.signedIn;

  @override
  bool get needsSignIn => auth.needsSignIn;

  @override
  Future<bool?> signIn({String doneText = ''}) async =>
      switch (await auth.signIn(doneText: doneText)) {
        SignInResult.signedIn => true,
        SignInResult.redirected => null,
        SignInResult.failed => false,
      };

  @override
  void cancelSignIn() => auth.cancelSignIn();

  /// AK11: no more timers and requests; the tokens are revoked (if reachable) and removed.
  @override
  Future<void> signOut() async {
    _stopEngine();
    await auth.signOut();
    provider.close();
  }

  void _stopEngine() {
    if (_disposed) return;
    _disposed = true;
    engine.removeListener(notifyListeners);
    engine.dispose();
  }

  @override
  DateTime? get lastSync => engine.lastSync;

  @override
  Map<String, DateTime?> get devices => engine.devices;

  @override
  List<String> get errors => [
    for (final t in engine.failed) '${t.key}: ${t.lastError}',
  ];

  @override
  Future<CloudSpace?> space() async {
    final q = await provider.quota();
    return CloudSpace(q.used, q.total);
  }

  /// AK9: the backups of this device (`backup/<device>/state-<n>.json`); unreadable ones are left out.
  @override
  Future<List<CloudBackup>> backups() async {
    final me = library.device.deviceId;
    final out = <CloudBackup>[];
    for (final e in await provider.list('backup/$me/')) {
      final f = await provider.get(e.name);
      if (f == null) continue;
      try {
        final d = CloudSync.decodeDevice(CloudSync.deviceName(me), f.bytes);
        out.add(CloudBackup(e.name, d.written, d.state));
      } catch (_) {
        // damaged or newer: not offered
      }
    }
    return out;
  }

  @override
  void dispose() {
    _stopEngine();
    auth.removeListener(notifyListeners);
    super.dispose();
  }
}
