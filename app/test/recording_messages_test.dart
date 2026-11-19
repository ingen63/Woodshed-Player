// #44: recording errors in the language of the UI.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wp_core/wp_types.dart';
import 'package:woodshed_player/ui/messages.dart';

void main() {
  final de = lookupAppLocalizations(const Locale('de'));
  final en = lookupAppLocalizations(const Locale('en'));
  String msg(AppLocalizations l, int code, [int status = 0]) =>
      recordingErrorMessage(l, WpRecordingException(code, status, 'log text'));

  test('#44/AK4: every recording error code has its own text in German and English', () {
    for (final l in [de, en]) {
      final texts = WpRecCode.all.map((c) => msg(l, c)).toSet();
      expect(texts.length, WpRecCode.all.length, reason: l.localeName);
      expect(texts, isNot(contains(msg(l, -99))));
    }
    for (final c in WpRecCode.all) {
      expect(msg(de, c), isNot(msg(en, c)), reason: 'code $c');
    }
  });

  test('#44/AK2: no German in English messages, no English in German ones', () {
    final german = RegExp(
      r'[äöüÄÖÜ]|\b(Aufnahme|nicht|konnte|kein|Kein|der|die|das|für)\b',
    );
    final english = RegExp(
      r'\b(the|could|not|recording|Recording|found|for|No)\b',
    );
    for (final c in [...WpRecCode.all, -99]) {
      final e = en.recordingFailed(msg(en, c, -50));
      final d = de.recordingFailed(msg(de, c, -50));
      expect(german.hasMatch(e), isFalse, reason: e);
      expect(english.hasMatch(d), isFalse, reason: d);
      expect(e, contains('OSStatus -50'));
      expect(d, contains('OSStatus -50'));
      expect(e, isNot(contains('log text')));
    }
    expect(msg(en, WpRecCode.noOutput), isNot(contains('OSStatus')));
  });

  final recorder = File('../core/src/recorder_mac.mm').readAsStringSync();

  test('#44/AK3: aggregate device and tap have a language-neutral name', () {
    expect(
      recorder,
      contains('kAudioAggregateDeviceNameKey : @"Woodshed Player Recording"'),
    );
    expect(recorder, contains('desc.name = @"Woodshed Player Recording"'));
    expect(recorder, isNot(contains('Player Aufnahme')));
  });

  test('#44/AK5: wp_rec_error is English and only meant for logs', () {
    final stub = File('../core/src/recorder_stub.cpp').readAsStringSync();
    final literals = RegExp(r'fail\(r, WP_REC_ERR_\w+, "([^"]*)"')
        .allMatches(recorder)
        .map((m) => m.group(1)!)
        .toList();
    expect(literals.length, greaterThanOrEqualTo(WpRecCode.all.length));
    for (final t in [
      ...literals,
      RegExp(r'wp_rec_error\(void\) \{ return "([^"]*)"')
          .firstMatch(stub)!
          .group(1)!,
    ]) {
      expect(t, matches(RegExp(r'^[\x20-\x7e]+$')), reason: t);
    }
    final button = File('lib/ui/recording_button.dart').readAsStringSync();
    expect(button, isNot(contains('.message')));
  });
}
