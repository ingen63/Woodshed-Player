// #158: the audio session of the page in a real browser (flutter test --platform chrome, make test-web).
// Chrome has no Audio Session API, so the "API present" case uses a stand-in navigator object.
// The VM run of flutter test skips this file.
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/player/audio_session_web.dart';

void main() {
  test('#158/AK4 sets the session type to playback when the API is there', () {
    final session = JSObject()..['type'] = 'auto'.toJS;
    final nav = JSObject()..['audioSession'] = session;
    expect(
      setAudioSessionType(AudioSessionType.playback, navigator: nav),
      isTrue,
    );
    expect((session['type'] as JSString).toDart, 'playback');
  });

  test('#158/AK4 play-and-record for recording later (#157)', () {
    final session = JSObject();
    final nav = JSObject()..['audioSession'] = session;
    expect(
      setAudioSessionType(AudioSessionType.playAndRecord, navigator: nav),
      isTrue,
    );
    expect((session['type'] as JSString).toDart, 'play-and-record');
  });

  test('#158/AK4 without the API nothing changes and nothing throws', () {
    final nav = JSObject();
    expect(
      setAudioSessionType(AudioSessionType.playback, navigator: nav),
      isFalse,
    );
    expect(nav.has('audioSession'), isFalse);
  });

  test('#158/AK4 a session that refuses the value throws nothing', () {
    final session = _freeze(JSObject()..['type'] = 'auto'.toJS);
    final nav = JSObject()..['audioSession'] = session;
    expect(
      () => setAudioSessionType(AudioSessionType.playback, navigator: nav),
      returnsNormally,
    );
    expect((session['type'] as JSString).toDart, 'auto');
  });

  test('#158/AK4 the page navigator: no error, true exactly with the API', () {
    final hasApi = _navigator.has('audioSession');
    expect(setAudioSessionType(AudioSessionType.playback), hasApi);
  });
}

@JS('navigator')
external JSObject get _navigator;

@JS('Object.freeze')
external JSObject _freeze(JSObject o);
