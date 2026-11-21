// #39/AK2: [MediaSessionApi] over `navigator.mediaSession`. Browsers without the API or without an action
// (older Safari) are skipped silently; playback in the app works the same.
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'media_session.dart';

/// Details of a Media Session action; only the target time of «seekto» is needed.
extension type _ActionDetails._(JSObject _) implements JSObject {
  external double? get seekTime;
}

@JS('navigator.mediaSession')
external JSObject? get _mediaSessionOrNull;

class WebMediaSession implements MediaSessionApi {
  /// null if the browser has no Media Session.
  static WebMediaSession? create() =>
      _mediaSessionOrNull == null ? null : WebMediaSession._();

  WebMediaSession._();

  web.MediaSession get _session => web.window.navigator.mediaSession;

  /// The app icon as artwork on the lock screen (relative to the page).
  static final _artwork = [
    web.MediaImage(
      src: 'icons/Icon-192.png',
      sizes: '192x192',
      type: 'image/png',
    ),
    web.MediaImage(
      src: 'icons/Icon-512.png',
      sizes: '512x512',
      type: 'image/png',
    ),
  ].toJS;

  @override
  void setMetadata(String? title, String? artist) => _try(() {
    _session.metadata = title == null
        ? null
        : web.MediaMetadata(
            web.MediaMetadataInit(
              title: title,
              artist: artist ?? '',
              artwork: _artwork,
            ),
          );
  });

  @override
  void setPlaybackState(String state) =>
      _try(() => _session.playbackState = state);

  @override
  void setPositionState(double duration, double position, double rate) => _try(
    () => _session.setPositionState(
      web.MediaPositionState(
        duration: duration,
        position: position,
        playbackRate: rate,
      ),
    ),
  );

  @override
  void setActionHandler(String action, void Function(double? time) handler) =>
      _try(
        () => _session.setActionHandler(
          action,
          ((JSObject details) => handler(
            (details as _ActionDetails).seekTime,
          )).toJS,
        ),
      );

  static void _try(void Function() f) {
    try {
      f();
    } catch (_) {} // action or state not supported by this browser
  }
}
