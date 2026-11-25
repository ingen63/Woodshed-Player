// #147: what the main window needs of the armed practice recording (practice_recording.dart): whether
// it is on, and ending a take with the space bar. Without the core, so the browser build stays free of
// FFI; there it is never present.
import 'package:flutter/widgets.dart';

abstract interface class PracticeArming implements Listenable {
  /// The switch «Armed» is on.
  bool get on;

  /// #147/AK4: ends a running take; nothing while waiting for sound.
  Future<void> endTake();
}

/// #147: the switch «Armed» and its state, handed to the main window where the microphone records.
typedef ArmedSwitchSlot = ({PracticeArming arming, Widget widget});
