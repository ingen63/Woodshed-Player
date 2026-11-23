// The sync as the app and its settings see it (#54/AK6, AK7–AK11). Without a chosen sync the app keeps
// NoSync and never loads the engine or a provider module: [CloudAccount.open] loads the Google module
// (deferred import in platform_native.dart / platform_web.dart) only if Google Drive was chosen on this
// device. This file must not import the engine or any provider (test #37/AK2, #54/AK6).
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../library/library.dart';
import 'sync_service.dart';

/// Storage of the library (docs/KONZEPT-SYNC.md: exactly one per library).
enum CloudChoice { none, google }

/// A backup of the own state at the provider (`backup/<device>/state-<n>.json`).
class CloudBackup {
  const CloudBackup(this.name, this.written, this.state);
  final String name;

  /// When the state was written; null if unknown.
  final DateTime? written;
  final SharedState state;
}

/// What the settings show of the storage space: used and granted bytes (null if unlimited).
class CloudSpace {
  const CloudSpace(this.used, this.total);
  final int used;
  final int? total;

  int? get free => total == null ? null : (total! - used).clamp(0, total!);
}

/// The provider part, loaded only once a sync is chosen (google_sync.dart).
abstract class CloudBackend implements Listenable {
  /// The engine for this provider.
  SyncService get sync;

  /// Read what is stored (tokens, redirect answer).
  Future<void> load();
  bool get signedIn;
  bool get needsSignIn;
  Future<bool?> signIn({String doneText = ''});
  void cancelSignIn();
  Future<void> signOut();

  DateTime? get lastSync;

  /// Device ID → when it last wrote its state (the own one included).
  Map<String, DateTime?> get devices;

  /// Errors of files given up (text for the details), empty if none.
  List<String> get errors;
  Future<CloudSpace?> space();
  Future<List<CloudBackup>> backups();
  void dispose();
}

/// The sync the app talks to; points to [NoSync] or to the engine of the chosen provider.
class SyncSwitch extends SyncService {
  SyncService _inner = NoSync();

  SyncService get inner => _inner;

  /// Uses [s] from now on; the previous one is not disposed here (its owner does it).
  void use(SyncService s) {
    if (identical(s, _inner)) return;
    _inner.removeListener(notifyListeners);
    _inner = s;
    s.addListener(notifyListeners);
    notifyListeners();
  }

  @override
  SyncStatus get status => _inner.status;
  @override
  Future<void> start() => _inner.start();
  @override
  void resumed() => _inner.resumed();
  @override
  void localChanged() => _inner.localChanged();
  @override
  Future<void> syncNow() => _inner.syncNow();
  @override
  bool inCloud(String trackId) => _inner.inCloud(trackId);
  @override
  Future<bool> fetchAudio(Track track) => _inner.fetchAudio(track);

  @override
  void dispose() {
    _inner.removeListener(notifyListeners);
    super.dispose();
  }
}

/// A folder of the library with the size of its audio files on this device (AK10).
class FolderSize {
  const FolderSize(this.folder, this.bytes);
  final TrackFolder folder;
  final int bytes;
}

class CloudAccount extends ChangeNotifier {
  CloudAccount({
    required this.library,
    SyncSwitch? sync,
    this.loadGoogle,
    this.chooseFolders = false,
  }) : sync = sync ?? SyncSwitch() {
    this.sync.addListener(notifyListeners);
  }

  final Library library;
  final SyncSwitch sync;

  /// Loads the Google module; null where Google Drive is not offered (native iPhone/iPad: only in the
  /// web app there).
  final Future<CloudBackend> Function()? loadGoogle;

  /// Desktop: the first sign-in asks which folders to sync (AK10).
  final bool chooseFolders;

  CloudBackend? _backend;
  bool _signingIn = false;
  bool _folderChoice = false;

  /// Google Drive can be chosen on this device.
  bool get googleAvailable => loadGoogle != null;

  CloudChoice get choice =>
      library.device.syncProvider == CloudChoice.google.name && googleAvailable
      ? CloudChoice.google
      : CloudChoice.none;

  bool get signedIn => _backend?.signedIn ?? false;
  bool get needsSignIn => _backend?.needsSignIn ?? false;
  bool get signingIn => _signingIn;

  /// After the first sign-in on the desktop: the folders must be chosen before the first sync (AK10).
  bool get needsFolderChoice => _folderChoice;

  SyncStatus get status => sync.status;
  DateTime? get lastSync => _backend?.lastSync;
  Map<String, DateTime?> get devices => _backend?.devices ?? const {};
  List<String> get errors => _backend?.errors ?? const [];
  String get deviceId => library.device.deviceId;

  /// At start, before the first sync: loads the provider only if one was chosen here (AK6).
  Future<void> open() async {
    if (choice != CloudChoice.google) return;
    try {
      final b = await _load();
      if (b.signedIn) sync.use(b.sync);
    } catch (_) {
      // module or stored sign-in not readable: no sync this run, the settings offer to sign in
    }
  }

  Future<CloudBackend> _load() async {
    if (_backend case final b?) return b;
    final b = await loadGoogle!();
    await b.load();
    b.addListener(notifyListeners);
    return _backend = b;
  }

  /// AK7: chooses the storage. «None» signs out first; nothing local is removed.
  Future<void> choose(CloudChoice c) async {
    if (c == choice) return;
    if (c == CloudChoice.none) await signOut();
    await library.setSyncProvider(c == CloudChoice.none ? null : c.name);
    notifyListeners();
  }

  /// AK1, AK7: signs in (macOS: sign-in window of the system). True when signed in, false if it failed, null when
  /// the page went to Google and comes back signed in (web).
  Future<bool?> signIn({String doneText = ''}) async {
    if (choice != CloudChoice.google || _signingIn) return false;
    _signingIn = true;
    notifyListeners();
    try {
      final b = await _load();
      final ok = await b.signIn(doneText: doneText);
      if (ok != true) return ok;
      if (chooseFolders && !library.device.synced) {
        _folderChoice =
            true; // AK10: the sync starts once the folders are chosen
      } else {
        _startSync(b);
      }
      return true;
    } finally {
      _signingIn = false;
      notifyListeners();
    }
  }

  void cancelSignIn() => _backend?.cancelSignIn();

  void _startSync(CloudBackend b) {
    sync.use(b.sync);
    unawaited(sync.syncNow());
  }

  /// AK10: the folders of the library with their size on this device.
  Future<List<FolderSize>> folderSizes() async => [
    for (final f in library.sortedFolders)
      FolderSize(f, await library.folderBytes(f.id)),
  ];

  /// AK10: sets «sync» per folder and starts the first sync.
  Future<void> confirmFolders(Map<String, bool> sync) async {
    for (final e in sync.entries) {
      library.setFolderSync(e.key, e.value);
    }
    _folderChoice = false;
    if (_backend case final b? when b.signedIn) _startSync(b);
    notifyListeners();
  }

  /// AK11: removes the tokens, stops every request and timer; the library stays as it is.
  Future<void> signOut() async {
    final b = _backend;
    _folderChoice = false;
    sync.use(NoSync());
    if (b != null) {
      _backend = null;
      b.removeListener(notifyListeners);
      await b.signOut();
      b.dispose();
    }
    notifyListeners();
  }

  /// AK8: «Sync now».
  Future<void> syncNow() async {
    if (_backend case final b? when b.signedIn && !_folderChoice) {
      await b.sync.syncNow();
    }
  }

  /// AK10: used and free space at the provider; null if unknown or not reachable.
  Future<CloudSpace?> space() async {
    try {
      return await _backend?.space();
    } catch (_) {
      return null;
    }
  }

  /// AK9: the backups of this device, newest first.
  Future<List<CloudBackup>> backups() async {
    final b = _backend;
    if (b == null || !b.signedIn) return const [];
    try {
      final list = await b.backups();
      return [...list]..sort(
        (x, y) =>
            (y.written ?? DateTime(0)).compareTo(x.written ?? DateTime(0)),
      );
    } catch (_) {
      return const [];
    }
  }

  /// AK9: takes the state of [backup] as a new change and syncs it.
  Future<bool> restore(CloudBackup backup) async {
    final ok = await library.restore(backup.state);
    if (ok) unawaited(syncNow());
    return ok;
  }

  @override
  void dispose() {
    sync.removeListener(notifyListeners);
    final b = _backend;
    if (b != null) {
      b.removeListener(notifyListeners);
      b.dispose();
    }
    super.dispose();
  }
}
