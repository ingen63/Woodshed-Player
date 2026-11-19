// #6: App icon (Waveform Loop from #48) in the macOS and iOS asset catalogs,
// display name "Woodshed Player", documented icon source.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

const _macIcons = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';
const _iosIcons = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';

/// Reads width, height and colour type from the PNG IHDR chunk.
({int width, int height, int colorType}) _pngHeader(File file) {
  final bytes = file.readAsBytesSync();
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  expect(bytes.sublist(0, 8), signature, reason: '${file.path} is no PNG');
  final data = ByteData.sublistView(bytes);
  return (
    width: data.getUint32(16),
    height: data.getUint32(20),
    colorType: bytes[25],
  );
}

/// Expected pixel edge per Contents.json entry ("size" in points × "scale").
List<({String file, int px})> _expectedIcons(String dir) {
  final json =
      jsonDecode(File('$dir/Contents.json').readAsStringSync())
          as Map<String, dynamic>;
  return [
    for (final e in (json['images'] as List).cast<Map<String, dynamic>>())
      (
        file: e['filename'] as String,
        px:
            (double.parse((e['size'] as String).split('x').first) *
                    int.parse((e['scale'] as String).replaceAll('x', '')))
                .round(),
      ),
  ];
}

/// Value of a string key in an Info.plist (flat lookup, enough for these files).
String? _plistString(String path, String key) {
  final match = RegExp(
    '<key>$key</key>\\s*<string>([^<]*)</string>',
  ).firstMatch(File(path).readAsStringSync());
  return match?.group(1);
}

String? _xcconfig(String path, String key) {
  final match = RegExp(
    '^$key = (.*)\$',
    multiLine: true,
  ).firstMatch(File(path).readAsStringSync());
  return match?.group(1)?.trim();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('#6/AK2 every size requested by Contents.json exists', () {
    for (final dir in [_macIcons, _iosIcons]) {
      test(dir, () {
        final expected = _expectedIcons(dir);
        expect(expected, isNotEmpty);
        for (final icon in expected) {
          final file = File('$dir/${icon.file}');
          expect(file.existsSync(), isTrue, reason: '${icon.file} missing');
          final header = _pngHeader(file);
          expect(header.width, icon.px, reason: icon.file);
          expect(header.height, icon.px, reason: icon.file);
        }
      });
    }

    test('iOS icons have no alpha channel (App Store requirement)', () {
      for (final icon in _expectedIcons(_iosIcons)) {
        // Colour type 2 = RGB, 0 = grey; 4 and 6 carry alpha.
        final type = _pngHeader(File('$_iosIcons/${icon.file}')).colorType;
        expect(type, isNot(anyOf(4, 6)), reason: icon.file);
      }
    });
  });

  testWidgets('#6/AK1 icons show the Waveform Loop motif, not Flutter default', (
    tester,
  ) async {
    Future<List<int>> pixel(String path, int x, int y) async {
      final codec = await ui.instantiateImageCodec(
        File(path).readAsBytesSync(),
      );
      final image = (await codec.getNextFrame()).image;
      final data = (await image.toByteData())!;
      final i = (y * image.width + x) * 4;
      return [data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2)];
    }

    await tester.runAsync(() async {
      for (final path in [
        '$_macIcons/app_icon_1024.png',
        '$_iosIcons/Icon-App-1024x1024@1x.png',
      ]) {
        // Centre: amber middle third of the waveform (#FF9F0A).
        expect(await pixel(path, 512, 512), [0xFF, 0x9F, 0x0A], reason: path);
        // Left of the loop bracket: studio background (#121214).
        expect(await pixel(path, 100, 512), [0x12, 0x12, 0x14], reason: path);
      }
    });
  });

  test('#6/AK3 icon source documented as own work under MIT', () {
    final readme = File('assets/icons/README.md');
    expect(readme.existsSync(), isTrue);
    final text = readme.readAsStringSync();
    expect(text, contains('icon_1_waveform_loop.svg'));
    expect(text, contains('selbst erstellt'));
    expect(text, contains('MIT'));
    expect(text, contains('#48'));
  });

  group('#6 display name "Woodshed Player", bundle IDs unchanged', () {
    test('macOS', () {
      const config = 'macos/Runner/Configs/AppInfo.xcconfig';
      expect(_xcconfig(config, 'PRODUCT_NAME'), 'Woodshed Player');
      expect(
        _plistString('macos/Runner/Info.plist', 'CFBundleName'),
        r'$(PRODUCT_NAME)',
      );
      // The sandbox container (library data) depends on the bundle ID.
      expect(
        _xcconfig(config, 'PRODUCT_BUNDLE_IDENTIFIER'),
        'ch.woodshed-player-app.desktop',
      );
    });

    test('iOS', () {
      const plist = 'ios/Runner/Info.plist';
      expect(_plistString(plist, 'CFBundleDisplayName'), 'Woodshed Player');
      expect(_plistString(plist, 'CFBundleName'), 'Woodshed Player');
      expect(
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync(),
        contains('PRODUCT_BUNDLE_IDENTIFIER = ch.woodshed-player-app.ios;'),
      );
    });

    test('web manifest', () {
      final manifest =
          jsonDecode(File('web/manifest.json').readAsStringSync())
              as Map<String, dynamic>;
      expect(manifest['name'], 'Woodshed Player');
    });
  });
}
