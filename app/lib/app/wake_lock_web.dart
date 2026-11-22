// #109: [WakeLockApi] over `navigator.wakeLock` and the page visibility. Browsers without the API (older
// Safari, Firefox before 126) are skipped silently, as is a refused request; playback works the same.
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'wake_lock.dart';

@JS('navigator.wakeLock')
external JSObject? get _wakeLockOrNull;

class _Sentinel implements WakeLockHandle {
  _Sentinel(this._s);

  final web.WakeLockSentinel _s;

  @override
  bool get released => _s.released;

  @override
  void release() {
    try {
      _s.release().toDart.ignore();
    } catch (_) {} // already released
  }
}

class WebWakeLock implements WakeLockApi {
  /// null if the browser has no Screen Wake Lock API.
  static WebWakeLock? create() =>
      _wakeLockOrNull == null ? null : WebWakeLock._();

  WebWakeLock._();

  @override
  Future<WakeLockHandle?> request() async {
    try {
      return _Sentinel(
        await web.window.navigator.wakeLock.request('screen').toDart,
      );
    } catch (_) {
      return null; // refused, e.g. page hidden or battery saver
    }
  }

  @override
  void onVisible(void Function() handler) => web.document.addEventListener(
    'visibilitychange',
    ((web.Event _) {
      if (web.document.visibilityState == 'visible') handler();
    }).toJS,
  );
}
