// What the app sees of the sync (#37, plan W5). Without an account the app uses [NoSync]: it sends nothing
// and does not import the engine or any provider (#37/AK2). With an account (from #38/#40) the app gets a
// CloudSync (sync_engine.dart). This file must not import either of them.
import 'package:flutter/foundation.dart';

import '../library/library.dart';

enum SyncStatus {
  /// No account: everything stays on this device.
  off,
  idle,
  syncing,

  /// No connection; the changes wait and are sent later.
  offline,

  /// Some files failed several times and are no longer retried on their own.
  failed,

  /// The cloud holds a newer format than this app writes; nothing is written.
  tooNew,

  /// A source holds another library (`format.json`, #53/AK9); it is neither merged nor written.
  foreignLibrary,
}

/// How to repair a damaged `state.json` (#65).
enum CloudStateRepair {
  /// Restore the last valid state from `backup/` and merge it with this device (suggested first).
  restoreBackup,

  /// Replace it with the state of this device.
  overwriteWithLocal,
}

/// Outcome of [SyncService.repairCloudState].
enum CloudRepairResult {
  /// Restored from the last valid backup, merged with this device and written.
  restored,

  /// Replaced with the state of this device.
  overwritten,

  /// `state.json` is readable again (or missing); the normal sync goes on.
  notDamaged,

  /// No valid backup; only [CloudStateRepair.overwriteWithLocal] is left.
  noBackup,

  /// Not repaired (no connection, conflicts); nothing on this device was lost.
  failed,
}

abstract class SyncService extends ChangeNotifier {
  SyncStatus get status;

  /// The app was started (library loaded).
  Future<void> start();

  /// The app came back to the foreground.
  void resumed();

  /// The library saved a change; syncs after a short delay, several changes together.
  void localChanged();

  /// Syncs now, also retrying files that gave up (button «Sync now», #40).
  Future<void> syncNow();

  /// Repairs a damaged `state.json` in the cloud (#65; since #53 there is none, see CloudSync). Data on this device are
  /// never lost: the backup is merged with them, never put in their place.
  Future<CloudRepairResult> repairCloudState(CloudStateRepair how);

  /// The audio file of the track is in the cloud (as far as the last sync knows).
  bool inCloud(String trackId);

  /// Loads the audio file of a track that is not on this device from the cloud. False if it is not
  /// there or the download failed.
  Future<bool> fetchAudio(Track track);
}

/// Without an account: no request, no timer, no provider module (#37/AK2).
class NoSync extends SyncService {
  @override
  SyncStatus get status => SyncStatus.off;
  @override
  Future<void> start() async {}
  @override
  void resumed() {}
  @override
  void localChanged() {}
  @override
  Future<void> syncNow() async {}
  @override
  Future<CloudRepairResult> repairCloudState(CloudStateRepair how) async =>
      CloudRepairResult.failed;
  @override
  bool inCloud(String trackId) => false;
  @override
  Future<bool> fetchAudio(Track track) async => false;
}
