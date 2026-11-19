// Localized macOS permission dialog for recording (#49): English in
// Info.plist, every translation in <lang>.lproj/InfoPlist.strings.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _key = 'NSAudioCaptureUsageDescription';
const _runner = 'macos/Runner';

/// Value of `<key>name</key><string>…</string>` in an XML plist.
String? _plistValue(String plist, String name) =>
    RegExp('<key>${RegExp.escape(name)}</key>\\s*<string>([^<]*)</string>')
        .firstMatch(plist)
        ?.group(1);

/// Value of `"name" = "…";` in a .strings file.
String? _stringsValue(String strings, String name) =>
    RegExp('"${RegExp.escape(name)}"\\s*=\\s*"((?:[^"\\\\]|\\\\.)*)"\\s*;')
        .firstMatch(strings)
        ?.group(1);

Map<String, String?> _translations() {
  final result = <String, String?>{};
  for (final dir in Directory(_runner).listSync().whereType<Directory>()) {
    final name = dir.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (!name.endsWith('.lproj')) continue;
    final file = File('${dir.path}/InfoPlist.strings');
    if (!file.existsSync()) continue;
    result[name.replaceAll('.lproj', '')] = _stringsValue(
      file.readAsStringSync(),
      _key,
    );
  }
  return result;
}

void main() {
  final english = _plistValue(
    File('$_runner/Info.plist').readAsStringSync(),
    _key,
  );
  final translations = _translations();

  test('#49/AK5 key present and non-empty in default language and every '
      'translation', () {
    expect(english, isNotNull);
    expect(english!.trim(), isNotEmpty);
    expect(translations, contains('de'));
    translations.forEach((lang, value) {
      expect(value, isNotNull, reason: '$lang.lproj misses $_key');
      expect(value!.trim(), isNotEmpty, reason: '$lang.lproj: empty $_key');
      expect(value, isNot(english), reason: '$lang.lproj not translated');
    });
  });

  test('#49/AK3 both texts describe the local practice recording', () {
    expect(
      english,
      allOf(
        contains('music currently playing on your Mac'),
        contains('practice'),
        contains('slower'),
        contains('loop'),
        contains('stays on your Mac'),
      ),
    );
    final german = translations['de']!;
    expect(
      german,
      allOf(
        contains('Musik'),
        contains('Übungsmitschnitt'),
        contains('langsamer'),
        contains('loopen'),
        contains('bleibt auf Deinem Mac'),
        contains('Du '),
      ),
    );
    expect(german, isNot(contains('ß')));
  });

  test('#49/AK4 Xcode project knows the regions and bundles the strings', () {
    final project = File('$_runner.xcodeproj/project.pbxproj')
        .readAsStringSync();
    final regions = RegExp(r'knownRegions = \(([^)]*)\)')
        .firstMatch(project)!
        .group(1)!;
    for (final lang in ['en', ...translations.keys]) {
      expect(regions, contains(RegExp('\\b$lang,')), reason: lang);
      if (lang != 'en') {
        expect(project, contains('path = $lang.lproj/InfoPlist.strings;'));
      }
    }
    expect(project, contains('InfoPlist.strings in Resources */,'));
  });
}
