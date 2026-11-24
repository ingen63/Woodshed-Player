// #15/AK3: Die Dart-Anbindung deckt die ganze C-API ab, Fehlercodes stimmen mit wp_core.h überein.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wp_core/wp_core.dart';

/// One deviation between a `WP_API` declaration and its `lookupFunction` binding.
typedef SignatureFinding = ({String function, String detail});

const _scalarTypes = {
  'void': 'Void',
  'int': 'Int32',
  'long long': 'Int64',
  'float': 'Float',
  'double': 'Double',
  'size_t': 'Size', // #116
};

/// Native type of a pointer's target; `char` is bound as `Utf8` (C strings).
const _pointeeTypes = {
  'char': 'Utf8',
  'float': 'Float',
  'wp_player': '_Player',
  'void': 'Void', // #116: file bytes
  'wp_trim_result': '_TrimResult', // #116
  'int': 'Int32', // #141: cancel flag of wp_mp3_export
  'double': 'Double', // #141: progress of wp_mp3_export
};

/// Maps a C type from wp_core.h to the native type of the Dart binding, or `null` if unknown.
String? nativeTypeFor(String cType) {
  final t = cType
      .replaceAll(RegExp(r'\bconst\b'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(' *', '*')
      .trim();
  if (t.endsWith('*')) {
    final target = t.substring(0, t.length - 1).trim();
    // #116: a pointer to a pointer (wp_trim_result **out)
    final native = target.endsWith('*')
        ? nativeTypeFor(target)
        : _pointeeTypes[target];
    return native == null ? null : 'Pointer<$native>';
  }
  return _scalarTypes[t];
}

/// C types of every `WP_API` function: return type first, then the parameters.
Map<String, List<String>> headerSignatures(String header) {
  final result = <String, List<String>>{};
  for (final m in RegExp(
    r'^WP_API\s+([^;(]*?)\s*\b(wp_\w+)\s*\(([^)]*)\)\s*;',
    multiLine: true,
  ).allMatches(header)) {
    final params = m.group(3)!.trim();
    result[m.group(2)!] = [
      m.group(1)!,
      if (params != 'void')
        for (final p in params.split(','))
          RegExp(r'^(.*[\s*])\w+$').firstMatch(p.trim())?.group(1) ?? p.trim(),
    ];
  }
  return result;
}

/// Index of the `>` closing the `<` at [open].
int _closingAngle(String s, int open) {
  var depth = 0;
  for (var i = open; i < s.length; i++) {
    if (s[i] == '<') depth++;
    if (s[i] == '>' && --depth == 0) return i;
  }
  throw StateError('unbalanced <> at $open');
}

/// Splits [s] at commas outside of `<>` and `()`, dropping empty parts.
List<String> _splitTopLevel(String s) {
  final parts = <String>[];
  var depth = 0;
  var start = 0;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == '<' || c == '(') depth++;
    if (c == '>' || c == ')') depth--;
    if (c == ',' && depth == 0) {
      parts.add(s.substring(start, i));
      start = i + 1;
    }
  }
  parts.add(s.substring(start));
  return [
    for (final p in parts)
      if (p.trim().isNotEmpty) p.replaceAll(RegExp(r'\s+'), ''),
  ];
}

/// Native types in `lookupFunction<Native, Dart>('wp_…')`: return type first, then the parameters.
Map<String, List<String>> bindingSignatures(String binding) {
  final result = <String, List<String>>{};
  const marker = 'lookupFunction<';
  for (
    var at = binding.indexOf(marker);
    at >= 0;
    at = binding.indexOf(marker, at + 1)
  ) {
    final open = at + marker.length - 1;
    final close = _closingAngle(binding, open);
    final name = RegExp(r"^\s*\(\s*'(wp_\w+)'")
        .firstMatch(binding.substring(close + 1))
        ?.group(1);
    if (name == null) continue;
    final native = _splitTopLevel(binding.substring(open + 1, close)).first;
    final fn = native.indexOf('Function(');
    result[name] = [
      native.substring(0, fn),
      ..._splitTopLevel(
        native.substring(fn + 'Function('.length, native.length - 1),
      ),
    ];
  }
  return result;
}

/// Compares every `WP_API` declaration with the native signature of its binding.
List<SignatureFinding> compareSignatures(String header, String binding) {
  final findings = <SignatureFinding>[];
  final declared = headerSignatures(header);
  final declarations = RegExp(
    r'^WP_API\s',
    multiLine: true,
  ).allMatches(header).length;
  if (declared.length != declarations) {
    findings.add((
      function: '*',
      detail: 'parsed ${declared.length} of $declarations WP_API declarations',
    ));
  }
  final bound = bindingSignatures(binding);
  for (final MapEntry(key: function, value: cTypes) in declared.entries) {
    final expected = <String>[];
    for (final cType in cTypes) {
      final native = nativeTypeFor(cType);
      if (native == null) {
        findings.add((
          function: function,
          detail: 'unknown C type "${cType.trim()}"',
        ));
      }
      expected.add(native ?? '?');
    }
    final found = bound[function];
    if (found == null) {
      findings.add((function: function, detail: 'no lookupFunction binding'));
      continue;
    }
    if (found.length != expected.length) {
      findings.add((
        function: function,
        detail:
            'expected ${expected.length - 1} parameters, found ${found.length - 1}',
      ));
      continue;
    }
    for (var i = 0; i < expected.length; i++) {
      if (expected[i] == '?' || expected[i] == found[i]) continue;
      final where = i == 0 ? 'return type' : 'parameter $i';
      findings.add((
        function: function,
        detail: '$where: expected ${expected[i]}, found ${found[i]}',
      ));
    }
  }
  return findings;
}

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
    expect(missing, isEmpty, reason: 'not bound: $missing');
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
    expect(
      WpCode.unsupportedSampleRate,
      define('WP_ERR_UNSUPPORTED_SAMPLE_RATE'),
    );
    expect(WpCode.multipleTracks, define('WP_ERR_MULTIPLE_TRACKS'));
    expect(WpCode.fragmented, define('WP_ERR_FRAGMENTED'));
    expect(WpCode.encoderUnavailable, define('WP_ERR_ENCODER_UNAVAILABLE'));
    expect(WpCode.fileUnwritable, define('WP_ERR_FILE_UNWRITABLE'));
    expect(WpMp3.sampleRate, define('WP_MP3_SAMPLE_RATE'));
    expect(WpMp3.minBitrate, define('WP_MP3_MIN_BITRATE'));
    expect(WpMp3.maxBitrate, define('WP_MP3_MAX_BITRATE'));
    expect(WpSampleRate.min, define('WP_MIN_SAMPLE_RATE'));
    expect(
      WpTrimmed.minSeconds,
      double.parse(
        RegExp(r'#define WP_TRIM_MIN_SECONDS ([\d.]+)')
            .firstMatch(header)!
            .group(1)!,
      ),
    );
    expect(WpSampleRate.max, define('WP_MAX_SAMPLE_RATE'));
    expect(WpCode.loadIdle, define('WP_LOAD_IDLE'));
    expect(WpCode.loadRunning, define('WP_LOAD_RUNNING'));
    expect(WpCode.loadReady, define('WP_LOAD_READY'));
    final errDefines = RegExp(r'#define WP_ERR_\w+').allMatches(header).length;
    // #120: WP_ERR_MULTIPLE_TRACKS and WP_ERR_FRAGMENTED only come from wp_trim (TrimProblem), never from
    // loading; #141: WP_ERR_ENCODER_UNAVAILABLE and WP_ERR_FILE_UNWRITABLE only from wp_mp3_export
    // (ExportProblem)
    expect(
      errDefines,
      13,
      reason: 'new WP_ERR_* in wp_core.h: update WpCode and loadErrorMessage',
    );
  });

  test('#97/AK6: an output runs at most at WpSampleRate.max', () {
    for (final rate in [WpSampleRate.min, 44100, 48000, 96000, 192000]) {
      expect(WpSampleRate.output(rate), rate);
    }
    for (final rate in [192001, 352800, 384000, 768000]) {
      expect(WpSampleRate.output(rate), WpSampleRate.max);
    }
  });

  test('#44/AK1: recording error codes as in wp_core.h', () {
    final defines = {
      for (final m in RegExp(
        r'#define WP_REC_ERR_\w+ (-?\d+)',
      ).allMatches(header))
        int.parse(m.group(1)!),
    };
    expect(
      defines,
      WpRecCode.all.toSet(),
      reason: 'new WP_REC_ERR_* in wp_core.h: update WpRecCode and recordingErrorMessage',
    );
    expect(WpRecCode.all.toSet().length, WpRecCode.all.length);
  });

  group('#100 #15/AK3: native types of the binding match wp_core.h', () {
    test('#100/AK1: every WP_API function has the same types', () {
      expect(headerSignatures(header).length, greaterThan(30));
      expect(compareSignatures(header, binding), isEmpty);
    });

    test('#100/AK1: mapping of C types to native types', () {
      expect(nativeTypeFor('void'), 'Void');
      expect(nativeTypeFor('int'), 'Int32');
      expect(nativeTypeFor('long long'), 'Int64');
      expect(nativeTypeFor('float'), 'Float');
      expect(nativeTypeFor('double'), 'Double');
      expect(nativeTypeFor('const char *'), 'Pointer<Utf8>');
      expect(nativeTypeFor('float *'), 'Pointer<Float>');
      expect(nativeTypeFor('wp_player *'), 'Pointer<_Player>');
      expect(nativeTypeFor('short *'), isNull);
      // #116: sizes, untyped bytes and the result of wp_trim through an out pointer
      expect(nativeTypeFor('size_t'), 'Size');
      expect(nativeTypeFor('const void *'), 'Pointer<Void>');
      expect(
        nativeTypeFor('wp_trim_result **'),
        'Pointer<Pointer<_TrimResult>>',
      );
      expect(nativeTypeFor('short **'), isNull);
    });

    test('#100/AK2: Double instead of Float in wp_set_volume is reported', () {
      final start = binding.indexOf('final _setVolume');
      final end = binding.indexOf("('wp_set_volume')", start);
      expect(start, isNonNegative);
      expect(end, greaterThan(start));
      final broken =
          binding.substring(0, start) +
          binding.substring(start, end).replaceFirst('Float', 'Double') +
          binding.substring(end);
      expect(compareSignatures(header, broken), [
        (
          function: 'wp_set_volume',
          detail: 'parameter 2: expected Float, found Double',
        ),
      ]);
    });

    test('#100/AK2: Int32 instead of Int64 in wp_loop_passes is reported', () {
      final broken = binding.replaceFirst(
        'Int64 Function(Pointer<_Player>)',
        'Int32 Function(Pointer<_Player>)',
      );
      expect(compareSignatures(header, broken), [
        (
          function: 'wp_loop_passes',
          detail: 'return type: expected Int64, found Int32',
        ),
      ]);
    });

    test('#100/AK3: an unknown C type fails with the function name', () {
      final extended = header.replaceFirst(
        'WP_API void wp_play(wp_player *p);',
        'WP_API void wp_play(wp_player *p);\n'
            'WP_API unsigned short wp_new_call(wp_player *p, ssize_t n);',
      );
      final findings = compareSignatures(extended, binding);
      expect(
        findings,
        contains((
          function: 'wp_new_call',
          detail: 'unknown C type "unsigned short"',
        )),
      );
      expect(
        findings,
        contains((function: 'wp_new_call', detail: 'unknown C type "ssize_t"')),
      );
    });

    test('#100/AK3: a declaration the parser misses is reported', () {
      final extended = '$header\nWP_API int wp_odd(int (*callback)(void));\n';
      expect(
        compareSignatures(extended, binding).map((f) => f.function),
        contains('*'),
      );
    });
  });
}
