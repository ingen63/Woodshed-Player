// #39/AK2: Media Session in the browser. The lock screen, the notification and headphone buttons show the
// loaded track and control play, pause and seek. This file holds the logic without the browser (testable
// with a fake [MediaSessionApi]); media_session_web.dart talks to `navigator.mediaSession`.
import 'app_controller.dart';

/// Actions the app answers (names as in the Media Session API).
abstract final class MediaAction {
  static const play = 'play';
  static const pause = 'pause';
  static const stop = 'stop';
  static const seekTo = 'seekto';
  static const seekBackward = 'seekbackward';
  static const seekForward = 'seekforward';
  static const all = [play, pause, stop, seekTo, seekBackward, seekForward];
}

/// What the app needs of `navigator.mediaSession`.
abstract class MediaSessionApi {
  /// Title and artist of the loaded track; null clears them (no track).
  void setMetadata(String? title, String? artist);

  /// «playing», «paused» or «none».
  void setPlaybackState(String state);

  /// Duration, position (seconds) and rate, so the system can show and move the position itself.
  void setPositionState(double duration, double position, double rate);

  /// [handler] gets the target time (seconds) for «seekto», else null.
  void setActionHandler(String action, void Function(double? time) handler);
}

class MediaSessionLink {
  MediaSessionLink(this.api, this.controller) {
    for (final a in MediaAction.all) {
      api.setActionHandler(a, (t) => handle(a, t));
    }
    controller.player.addListener(_update);
    controller.library.addListener(_update);
    _update();
  }

  /// Seconds for the skip buttons, as the ±15 s buttons of the player.
  static const skipSeconds = 15.0;

  final MediaSessionApi api;
  final AppController controller;

  (String?, String?)? _metadata;
  String? _state;
  String? _trackId;
  bool? _playing;
  double? _rate;
  double? _position;

  /// Runs [action] as if the button in the app was pressed.
  void handle(String action, double? time) {
    final p = controller.player;
    if (!p.hasTrack) return;
    switch (action) {
      case MediaAction.play:
        if (!p.isPlaying) controller.session.playTitle();
      case MediaAction.pause || MediaAction.stop:
        if (p.isPlaying) p.pause();
      case MediaAction.seekTo:
        if (time != null) p.seek(time);
      case MediaAction.seekBackward:
        p.skip(-skipSeconds);
      case MediaAction.seekForward:
        p.skip(skipSeconds);
    }
  }

  void _update() {
    final p = controller.player;
    final metadata = p.hasTrack
        ? (controller.currentTitle, controller.currentTrack?.artist)
        : (null, null);
    if (metadata != _metadata) {
      _metadata = metadata;
      api.setMetadata(metadata.$1, metadata.$2);
    }
    final state = !p.hasTrack
        ? 'none'
        : p.isPlaying
        ? 'playing'
        : 'paused';
    if (state != _state) {
      _state = state;
      api.setPlaybackState(state);
    }
    if (!p.hasTrack || p.duration <= 0) {
      _trackId = null;
      return;
    }
    final s = p.settings;
    final rate = s.speedEnabled ? s.speed : 1.0;
    // The system moves the position on by itself; it is sent again only when something changes: another
    // track, play or pause, tempo, or a jump (seek, loop) away from where the position should be.
    final jumped =
        _position == null ||
        (p.position - _position!).abs() > (p.isPlaying ? 1.0 : 0.05);
    if (p.trackId != _trackId ||
        p.isPlaying != _playing ||
        rate != _rate ||
        jumped) {
      _trackId = p.trackId;
      _playing = p.isPlaying;
      _rate = rate;
      api.setPositionState(
        p.duration,
        p.position.clamp(0.0, p.duration).toDouble(),
        rate,
      );
    }
    // Position at this tick; between two ticks playback moves it on by a fraction of a second only.
    _position = p.position;
  }

  void dispose() {
    controller.player.removeListener(_update);
    controller.library.removeListener(_update);
  }
}
