// #109: the screen stays on in the web app while a track plays (Screen Wake Lock API). On pause, stop and the
// end of the track the lock is released, so the device's own screen timeout applies again. The browser
// releases the lock when the page is hidden; on return with playback running it is requested again. This
// file holds the logic without the browser (testable with a fake [WakeLockApi]); wake_lock_web.dart talks
// to `navigator.wakeLock`. #157/AK7: the screen also stays on while a recording runs or «Armed» is on.
import 'package:flutter/foundation.dart';

import '../player/player_service.dart';

/// A held screen wake lock.
abstract class WakeLockHandle {
  /// True once the lock is gone, by [release] or by the browser (page hidden).
  bool get released;

  void release();
}

/// What the app needs of `navigator.wakeLock` and the page visibility.
abstract class WakeLockApi {
  /// Requests the screen lock; null if the browser refuses it. Never throws.
  Future<WakeLockHandle?> request();

  /// [handler] runs each time the page becomes visible again.
  void onVisible(void Function() handler);
}

class WakeLockLink {
  WakeLockLink(this.api, this.player, {this.recording, this.recordingActive}) {
    api.onVisible(_resume);
    player.addListener(_update);
    recording?.addListener(_update);
    _update();
  }

  final WakeLockApi api;
  final PlayerService player;

  /// #157/AK7: tells of changes of the recording; [recordingActive] says whether one runs or is armed.
  final Listenable? recording;
  final bool Function()? recordingActive;

  bool _wanted = false;
  bool _requesting = false;
  bool _again = false;
  WakeLockHandle? _lock;

  /// The lock currently held (for tests).
  @visibleForTesting
  WakeLockHandle? get lock => _lock;

  void _update() {
    final wanted =
        (player.hasTrack && player.isPlaying) ||
        (recordingActive?.call() ?? false);
    if (wanted == _wanted) return;
    _wanted = wanted;
    if (wanted) {
      _acquire();
    } else {
      _lock?.release();
      _lock = null;
    }
  }

  /// The browser released the lock while the page was hidden: request it again if a track still plays.
  void _resume() {
    if (_wanted && (_lock?.released ?? true)) {
      _lock = null;
      _acquire();
    }
  }

  Future<void> _acquire() async {
    if (_requesting) {
      _again = true; // e.g. visible again while a request from the hidden page is still running
      return;
    }
    _requesting = true;
    final lock = await api.request();
    _requesting = false;
    final again = _again;
    _again = false;
    if (!_wanted) {
      lock?.release(); // paused while the request was on its way
      return;
    }
    _lock = lock;
    if (again && (lock == null || lock.released)) await _acquire();
  }

  void dispose() {
    player.removeListener(_update);
    recording?.removeListener(_update);
    _lock?.release();
    _lock = null;
  }
}
