// #158: the audio session of the page (Audio Session API, Safari 17+). Safari on iPhone/iPad puts Web Audio
// into a session that follows the ring/silent switch by default; with the type 'playback' the app sounds
// like a music app even in silent mode. Browsers without the API are left alone, without an error.
// Recording in the browser (#157) will switch to [AudioSessionType.playAndRecord].
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Values of `navigator.audioSession.type` the app uses.
enum AudioSessionType {
  playback('playback'),
  playAndRecord('play-and-record');

  const AudioSessionType(this.value);

  /// The string the Audio Session API expects.
  final String value;
}

/// Sets `navigator.audioSession.type` to [type]. Returns false, and changes nothing, if the browser has no
/// Audio Session API or refuses the value. [navigator] is for tests; by default the page's navigator.
bool setAudioSessionType(AudioSessionType type, {JSObject? navigator}) {
  try {
    final nav = navigator ?? web.window.navigator as JSObject;
    final session = nav['audioSession'];
    if (session == null || !session.isA<JSObject>()) return false;
    (session as JSObject)['type'] = type.value.toJS;
    return true;
  } catch (_) {
    return false; // unknown value or a read-only property: playback works as before
  }
}
