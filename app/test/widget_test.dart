import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/time_format.dart';
import 'package:woodshed_player/ui/messages.dart';

import 'fakes.dart';

import 'dart:ui' show Locale;

void main() {
  group('formatTime (mm:ss wie die alte App, #19)', () {
    test('Minuten und Sekunden zweistellig', () {
      expect(formatTime(0), '00:00');
      expect(formatTime(59.9), '00:59');
      expect(formatTime(61), '01:01');
      expect(formatTime(3599), '59:59');
    });
    test(
      'ab einer Stunde mit Stunden',
      () => expect(formatTime(3661), '1:01:01'),
    );
    test('ungültige Werte ergeben 00:00', () {
      expect(formatTime(-3), '00:00');
      expect(formatTime(double.nan), '00:00');
      expect(formatTime(double.infinity), '00:00');
    });
    test('Zeitfeld mit Zehntel nur, wenn nötig', () {
      expect(formatTimeField(83), '01:23');
      expect(formatTimeField(83.46), '01:23.5');
    });
  });

  group('parseTime', () {
    test('gültige Eingaben', () {
      expect(parseTime('83'), 83);
      expect(parseTime('1:23'), 83);
      expect(parseTime('01:23.5'), 83.5);
      expect(parseTime('01:23,5'), 83.5);
      expect(parseTime('1:02:05'), 3725);
    });
    test('ungültige Eingaben ergeben null', () {
      for (final t in ['', 'abc', '1:60', '-3', '1:2:3:4']) {
        expect(parseTime(t), isNull, reason: t);
      }
    });
  });

  test('#19 Geschwindigkeit mit Dezimalkomma (#43: nach Gebietsschema)', () {
    expect(de.rate(0.75), '0,75×');
    expect(de.rate(1), '1,00×');
    expect(lookupAppLocalizations(const Locale('en')).rate(0.75), '0.75×');
  });

  test('fileStamp ohne Doppelpunkte', () {
    expect(fileStamp(DateTime(2026, 1, 2, 3, 4, 5)), '2026-01-02 03.04.05');
  });
}
