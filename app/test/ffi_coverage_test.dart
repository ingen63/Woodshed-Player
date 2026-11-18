// #15/AK3: Die Dart-Anbindung deckt die ganze C-API ab, Fehlercodes stimmen mit wp_core.h überein.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wp_core/wp_core.dart';

void main() {
  final header = File('../core/include/wp_core.h').readAsStringSync();
  final binding = File('packages/wp_core/lib/wp_core.dart').readAsStringSync();

  test('jede WP_API-Funktion ist angebunden', () {
    final functions = RegExp(r'WP_API\s+[\w\s\*]*?\b(wp_\w+)\s*\(')
        .allMatches(header)
        .map((m) => m.group(1)!)
        .toSet();
    expect(functions.length, greaterThan(30));
    final missing = functions.where((f) => !binding.contains("'$f'")).toList();
    expect(missing, isEmpty, reason: 'nicht angebunden: $missing');
  });

  test('Fehlercodes und Ladezustände wie in wp_core.h', () {
    int define(String name) => int.parse(
      RegExp('#define $name (-?\\d+)').firstMatch(header)!.group(1)!,
    );
    expect(WpCode.ok, define('WP_OK'));
    expect(WpCode.invalidArgument, define('WP_ERR_INVALID_ARGUMENT'));
    expect(WpCode.fileNotFound, define('WP_ERR_FILE_NOT_FOUND'));
    expect(WpCode.unsupportedFormat, define('WP_ERR_UNSUPPORTED_FORMAT'));
    expect(WpCode.deviceUnavailable, define('WP_ERR_DEVICE_UNAVAILABLE'));
    expect(WpCode.outOfMemory, define('WP_ERR_OUT_OF_MEMORY'));
    expect(WpCode.fileUnreadable, define('WP_ERR_FILE_UNREADABLE'));
    expect(WpCode.cancelled, define('WP_ERR_CANCELLED'));
    expect(WpCode.busy, define('WP_ERR_BUSY'));
    expect(WpCode.loadIdle, define('WP_LOAD_IDLE'));
    expect(WpCode.loadRunning, define('WP_LOAD_RUNNING'));
    expect(WpCode.loadReady, define('WP_LOAD_READY'));
    final errDefines = RegExp(r'#define WP_ERR_\w+').allMatches(header).length;
    expect(
      errDefines,
      8,
      reason: 'neuer Fehlercode in wp_core.h: WpCode und loadErrorMessage nachführen',
    );
  });
}
