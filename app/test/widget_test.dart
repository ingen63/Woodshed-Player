import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/time_format.dart';

void main() {
  group('formatTime', () {
    test('Minuten und Sekunden', () {
      expect(formatTime(0), '0:00');
      expect(formatTime(59.9), '0:59');
      expect(formatTime(61), '1:01');
      expect(formatTime(3599), '59:59');
    });
    test('ab einer Stunde mit Stunden', () => expect(formatTime(3661), '1:01:01'));
    test('ungültige Werte ergeben 0:00', () {
      expect(formatTime(-3), '0:00');
      expect(formatTime(double.nan), '0:00');
      expect(formatTime(double.infinity), '0:00');
    });
  });

  test('fileStamp ohne Doppelpunkte', () {
    expect(fileStamp(DateTime(2026, 1, 2, 3, 4, 5)), '2026-01-02 03.04.05');
  });
}
