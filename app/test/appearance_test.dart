// #31: light, dark or system appearance. Libraries live in temporary folders, never the real settings.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/app/file_store_io.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/main.dart';
import 'package:woodshed_player/ui/style.dart';

import 'fakes.dart';

late Directory tmp;

Library lib(Directory base) => Library(
  IoFileStore(base),
  probe: (_) => 1,
  readSource: readLocalFile,
  saveDelay: Duration.zero,
);

Future<Library> loaded(Directory base) async {
  final l = lib(base);
  await l.load();
  return l;
}

File prefs(Directory base) => File('${base.path}/preferences.json');

/// Waits until the fire-and-forget save has written [key] = [value] into library.json (#95/AK1: a state, not a
/// time). A file caught in the middle of a write counts as not yet saved.
Future<void> saved(String key, String value) => eventually(() {
  try {
    final json = jsonDecode(
      File('${tmp.path}/library.json').readAsStringSync(),
    );
    return (((json as Map)['settings'] as Map)['values'] as Map)[key] == value;
  } on Object {
    return false;
  }
}, 'library.json: $key = $value');

/// The shared settings in library.json.
Map<Object?, Object?> settings() =>
    ((jsonDecode(File('${tmp.path}/library.json').readAsStringSync())
                as Map)['settings']
            as Map)['values']
        as Map;

void main() {
  setUp(() => tmp = Directory.systemTemp.createTempSync('wp_appearance'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('#31 storage', () {
    test('#31/AK6 tests use a temporary folder, not the real settings', () {
      final l = lib(tmp);
      expect((l.store as IoFileStore).base.path, startsWith(tmp.path));
    });

    test('#149/AK1 without a saved appearance (first start, new library) it is dark', () async {
      final l = await loaded(tmp);
      expect(Appearance.standard, Appearance.dark);
      expect(l.appearance, Appearance.dark);
      // #10: the default is never chosen on this device, so it is not saved (and does not win a sync)
      l.sortOrder = TrackSortOrder.alphabetical;
      await saved('sortOrder', 'alphabetical');
      expect(settings().containsKey('appearance'), isFalse);
      expect((await loaded(tmp)).appearance, Appearance.dark);
    });

    test(
      '#31/AK4 #31/AK7 #149/AK3 the choice is saved and loaded after a restart',
      () async {
        // dark last: on a new library it is the default already and nothing would be saved
        for (final a in [
          Appearance.light,
          Appearance.system,
          Appearance.dark,
        ]) {
          final l = await loaded(tmp);
          l.appearance = a;
          await saved('appearance', a.name);
          expect((await loaded(tmp)).appearance, a);
        }
      },
    );

    test('#31/AK4 stored next to the sort order, which stays intact', () async {
      final l = await loaded(tmp);
      l.sortOrder = TrackSortOrder.alphabetical;
      await saved('sortOrder', 'alphabetical');
      l.appearance = Appearance.light;
      await saved('appearance', 'light');
      // #36/AK5: both are shared settings in library.json.
      final shared = settings();
      expect(shared['appearance'], 'light');
      expect(shared['sortOrder'], 'alphabetical');
      final again = await loaded(tmp);
      expect(again.sortOrder, TrackSortOrder.alphabetical);
      expect(again.appearance, Appearance.light);
    });

    test('#149/AK4 an existing library with a saved System keeps it, also after the next save', () async {
      final l = await loaded(tmp);
      l.appearance = Appearance.light;
      await saved('appearance', 'light');
      l.appearance = Appearance.system;
      await saved('appearance', 'system');
      final existing = await loaded(tmp);
      expect(existing.appearance, Appearance.system);
      existing.sortOrder = TrackSortOrder.alphabetical;
      await saved('sortOrder', 'alphabetical');
      expect(settings()['appearance'], 'system');
      expect((await loaded(tmp)).appearance, Appearance.system);
    });

    test('#149/AK4 an old preferences.json with System keeps it and moves it into library.json', () async {
      prefs(tmp).writeAsStringSync('{"appearance":"system"}');
      final l = await loaded(tmp);
      expect(l.appearance, Appearance.system);
      l.sortOrder = TrackSortOrder.alphabetical;
      await saved('appearance', 'system');
      prefs(tmp).deleteSync();
      expect((await loaded(tmp)).appearance, Appearance.system);
    });

    test(
      '#31/AK5 #149/AK1 old preferences.json without the key means dark',
      () async {
        prefs(tmp).writeAsStringSync('{"sortOrder":"alphabetical"}');
        final l = await loaded(tmp);
        expect(l.appearance, Appearance.dark);
        expect(l.sortOrder, TrackSortOrder.alphabetical);
      },
    );

    test('#149/AK2 unknown or wrongly typed value means dark', () async {
      for (final v in ['"sepia"', '42', 'null', '""', '"DARK"']) {
        prefs(tmp).writeAsStringSync('{"appearance":$v}');
        expect((await loaded(tmp)).appearance, Appearance.dark, reason: v);
      }
    });

    test('#149/AK2 unknown value in library.json means dark', () async {
      final l = await loaded(tmp);
      l.appearance = Appearance.light;
      await saved('appearance', 'light');
      final file = File('${tmp.path}/library.json');
      file.writeAsStringSync(
        file.readAsStringSync().replaceFirst('"light"', '"sepia"'),
      );
      expect(settings()['appearance'], 'sepia');
      expect((await loaded(tmp)).appearance, Appearance.dark);
    });

    test('#149/AK2 unreadable preferences.json means dark', () async {
      prefs(tmp).writeAsStringSync('{kaputt');
      expect((await loaded(tmp)).appearance, Appearance.dark);
    });

    test('#31/AK2 #31/AK3 theme mode for each choice', () {
      expect(themeModeFor(Appearance.system), ThemeMode.system);
      expect(themeModeFor(Appearance.light), ThemeMode.light);
      expect(themeModeFor(Appearance.dark), ThemeMode.dark);
    });
  });

  group('#31 UI', () {
    Future<TestApp> pump(
      WidgetTester tester, {
      Size size = const Size(1100, 900),
      String folder = 'lib',
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final app = TestApp(Directory('${tmp.path}/$folder'));
      await tester.runAsync(app.library.load);
      await tester.pumpWidget(
        WoodshedApp(controller: app.controller, locale: testLocale),
      );
      await tester.pumpAndSettle();
      return app;
    }

    Brightness brightness(WidgetTester tester) =>
        Theme.of(tester.element(find.byKey(const Key('libraryMoreMenu'))))
            .brightness;

    WsTheme ws(WidgetTester tester) =>
        WsTheme.of(tester.element(find.byKey(const Key('libraryMoreMenu'))));

    Future<void> choose(WidgetTester tester, Appearance a) async {
      await tester.tap(find.byKey(const Key('libraryMoreMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('appearance-${a.name}')));
      await tester.pumpAndSettle();
    }

    testWidgets(
      '#149/AK1 the first start is dark, whatever the system setting',
      (tester) async {
        for (final system in Brightness.values) {
          tester.platformDispatcher.platformBrightnessTestValue = system;
          final app = await pump(tester, folder: 'new-${system.name}');
          expect(app.library.appearance, Appearance.dark);
          expect(brightness(tester), Brightness.dark, reason: '$system');
          expect(ws(tester).bg, WsTheme.dark.bg);
        }
      },
    );

    testWidgets('#31/AK1 menu offers System, Light and Dark', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('libraryMoreMenu')));
      await tester.pumpAndSettle();
      for (final t in [
        de.appearanceSystem,
        de.appearanceLight,
        de.appearanceDark,
      ]) {
        expect(find.text(t), findsOneWidget);
      }
      expect(
        find.text(de.appearance),
        findsOneWidget,
      ); // #135: heading in the "⋯" menu
    });

    testWidgets('#31/AK1 the button is reachable in the phone layout', (
      tester,
    ) async {
      await pump(tester, size: const Size(390, 844));
      expect(find.byKey(const Key('layout:phone')), findsOneWidget);
      await choose(tester, Appearance.dark);
      expect(brightness(tester), Brightness.dark);
    });

    testWidgets(
      '#31/AK2 Light and Dark apply at once, regardless of the system',
      (tester) async {
        final app = await pump(tester);
        tester.platformDispatcher.platformBrightnessTestValue =
            Brightness.light;
        await tester.pumpAndSettle();
        await choose(tester, Appearance.dark);
        expect(app.library.appearance, Appearance.dark);
        expect(brightness(tester), Brightness.dark);
        expect(
          ws(tester).bg,
          WsTheme.dark.bg,
        ); // own Studio colours follow the choice

        tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
        await tester.pumpAndSettle();
        await choose(tester, Appearance.light);
        expect(brightness(tester), Brightness.light);
        expect(ws(tester).bg, WsTheme.light.bg);

        tester.platformDispatcher.platformBrightnessTestValue =
            Brightness.light;
        await tester.pumpAndSettle();
        expect(brightness(tester), Brightness.light);
      },
    );

    testWidgets(
      '#31/AK3 System follows a change of the system setting while running',
      (tester) async {
        final app = await pump(tester);
        await choose(tester, Appearance.system);
        expect(app.library.appearance, Appearance.system);
        tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
        await tester.pumpAndSettle();
        expect(brightness(tester), Brightness.dark);
        expect(ws(tester).bg, WsTheme.dark.bg);
        tester.platformDispatcher.platformBrightnessTestValue =
            Brightness.light;
        await tester.pumpAndSettle();
        expect(brightness(tester), Brightness.light);
        expect(ws(tester).bg, WsTheme.light.bg);
      },
    );

    for (final p in [TargetPlatform.macOS, TargetPlatform.iOS]) {
      testWidgets(
        '#31/AK1 the library title stays on one line next to the buttons ($p)',
        (tester) async {
          debugDefaultTargetPlatformOverride = p;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          await pump(tester);
          final title = tester.getRect(find.text(de.library));
          final button = tester.getRect(find.byKey(const Key('addFiles')));
          expect(title.height, lessThan(30)); // one line of titleLarge (22)
          expect(title.right, lessThanOrEqualTo(button.left));
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }
  });

  // #149/AK5: before Flutter draws its first frame the platform shows its own background. The saved
  // appearance is not known there yet, so it is the dark background of the app (WsTheme.dark.bg).
  group('#149/AK5 no light state at the start', () {
    final bg = WsTheme.dark.bg.toARGB32() & 0xFFFFFF;
    final hex = '#${bg.toRadixString(16).padLeft(6, '0').toUpperCase()}';
    final (r, g, b) = (bg >> 16, (bg >> 8) & 0xFF, bg & 0xFF);

    test('web: page background and manifest', () {
      final index = File('web/index.html').readAsStringSync();
      expect(index, contains('background-color: $hex'));
      expect(index, contains('<meta name="theme-color" content="$hex">'));
      final m = jsonDecode(File('web/manifest.json').readAsStringSync()) as Map;
      expect(m['background_color'], hex);
      expect(m['theme_color'], hex);
    });

    /// The sRGB components of a storyboard colour as 0…255.
    (int, int, int) storyboardColor(String xml) {
      final c = RegExp(
        r'<color key="backgroundColor" red="([\d.]+)" green="([\d.]+)" blue="([\d.]+)"',
      ).firstMatch(xml)!;
      int v(int i) => (double.parse(c.group(i)!) * 255).round();
      return (v(1), v(2), v(3));
    }

    test('iPhone/iPad: launch screen and the view of Flutter', () {
      for (final f in ['LaunchScreen', 'Main']) {
        final xml = File('ios/Runner/Base.lproj/$f.storyboard')
            .readAsStringSync();
        expect(storyboardColor(xml), (r, g, b), reason: f);
      }
    });

    test('macOS: the window and the Flutter view (MainFlutterWindow)', () {
      final swift = File('macos/Runner/MainFlutterWindow.swift')
          .readAsStringSync();
      expect(
        swift,
        contains(
          'NSColor(srgbRed: 0x${hex.substring(1, 3)} / 255, '
          'green: 0x${hex.substring(3, 5)} / 255, '
          'blue: 0x${hex.substring(5, 7)} / 255, alpha: 1)',
        ),
      );
      expect(swift, contains('backgroundColor = Self.launchBackground'));
      expect(
        swift,
        contains(
          'flutterViewController.backgroundColor = Self.launchBackground',
        ),
      );
    });
  });
}
