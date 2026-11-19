// AudioCore über FFI (#15): der C++-Kern mit eigenem Audiogerät (macOS, iOS).
import 'package:wp_core/wp_core.dart';

import 'audio_core.dart';

/// Der echte Kern über FFI.
class WpAudioCore implements AudioCore {
  WpAudioCore(this.player);
  final WpPlayer player;

  @override
  int loadAsync(String path) => player.loadAsync(path);
  @override
  int get loadState => player.loadState;
  @override
  double get loadProgress => player.loadProgress;
  @override
  void play() => player.play();
  @override
  void pause() => player.pause();
  @override
  bool get isPlaying => player.isPlaying;
  @override
  void seek(double seconds) => player.seek(seconds);
  @override
  set rate(double rate) => player.rate = rate;
  @override
  void setLoop(double a, double b) => player.setLoop(a, b);
  @override
  void clearLoop() => player.clearLoop();
  @override
  set volume(double volume) => player.volume = volume;
  @override
  double get position => player.position;
  @override
  double get duration => player.duration;
  @override
  int get loopPasses => player.loopPasses;
  @override
  WpWaveform? waveform(double start, double end, int count) =>
      player.waveform(start, end, count);
}
