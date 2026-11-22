// #119: license texts of the core libraries (core/third_party/) on the app's license page.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/ui/core_licenses.dart';

const _thirdParty = '../core/third_party';

/// Library folders listed in the table of core/third_party/README.md (rows like «| `flac/` | …»).
List<String> _readmeFolders() {
  final readme = File('$_thirdParty/README.md').readAsStringSync();
  return RegExp(
    r'^\|\s*`([^`/]+)/`',
    multiLine: true,
  ).allMatches(readme).map((m) => m.group(1)!).toList();
}

String _words(String text) => text.trim().split(RegExp(r'\s+')).join(' ');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(registerCoreLicenses);

  test('#119/AK1 every core library is in the LicenseRegistry with its full '
      'license text and copyright notice', () async {
    final entries = await LicenseRegistry.licenses.toList();
    for (final lib in coreLicenses.values) {
      final e = entries.where((l) => l.packages.contains(lib.name)).toList();
      expect(e, hasLength(1), reason: lib.name);
      // The page reflows lines into paragraphs, so compare the words.
      final text = _words(e.single.paragraphs.map((p) => p.text).join(' '));
      final asset = await rootBundle.loadString(lib.asset);
      expect(text, _words(asset), reason: lib.name);
      expect(text, contains('Copyright'), reason: lib.name);
    }
    expect(coreLicenses.values.map((l) => l.name), {
      'libFLAC',
      'Signalsmith Stretch',
      'Signalsmith Linear',
      'miniaudio',
    });
  });

  testWidgets('#119/AK1 the license page lists the core libraries', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LicensePage()));
    // The page collects the licenses in real time (asset loading) and in
    // scheduled tasks (frames): alternate both until the entries appear.
    const hangGuard = Duration(seconds: 60);
    final watch = Stopwatch()..start();
    while (find.text('libFLAC').evaluate().isEmpty &&
        watch.elapsed < hangGuard) {
      await tester.runAsync(() => Future<void>.delayed(Durations.short1));
      await tester.pump();
    }
    for (final lib in coreLicenses.values) {
      expect(find.text(lib.name), findsOneWidget, reason: lib.name);
    }
  });

  test('#119/AK2 the core libraries are built on macOS, iOS and web', () {
    final builds = {
      'macOS': [
        '../app/packages/wp_core/macos/wp_core.podspec',
        '../app/packages/wp_core/macos/Classes',
      ],
      'iOS': [
        '../app/packages/wp_core/ios/wp_core.podspec',
        '../app/packages/wp_core/ios/Classes',
      ],
      'web': ['../core/web/web.cmake', '../core/CMakeLists.txt'],
    };
    for (final MapEntry(key: platform, value: paths) in builds.entries) {
      final text = StringBuffer();
      for (final p in paths) {
        if (FileSystemEntity.isDirectorySync(p)) {
          for (final f in Directory(p).listSync().whereType<File>()) {
            text.writeln(f.readAsStringSync());
          }
        } else {
          text.writeln(File(p).readAsStringSync());
        }
      }
      for (final folder in coreLicenses.keys) {
        expect(
          text.toString(),
          anyOf(
            contains('third_party/$folder'),
            contains('THIRD_PARTY}/$folder'),
          ),
          reason: '$platform: $folder',
        );
      }
    }
    // main() registers the entries on every platform, without a platform switch.
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('registerCoreLicenses();'));
  });

  test('#119/AK3 every library in core/third_party/README.md has an entry', () {
    final folders = _readmeFolders();
    expect(folders, isNotEmpty);
    expect(coreLicenses.keys.toSet(), folders.toSet());
  });

  test('#119/AK3 the asset texts match the license files in '
      'core/third_party/', () {
    for (final MapEntry(key: folder, value: lib) in coreLicenses.entries) {
      final original = File('$_thirdParty/$folder/${lib.file}');
      expect(original.existsSync(), isTrue, reason: original.path);
      expect(
        File(lib.asset).readAsStringSync(),
        original.readAsStringSync(),
        reason: folder,
      );
    }
  });
}
