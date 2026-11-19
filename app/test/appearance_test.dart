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

/// Waits until the fire-and-forget preferences write has reached the disk.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  setUp(() => tmp = Directory.systemTemp.createTempSync('wp_appearance'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('#31 storage', () {
    test('#31/AK6 tests use a temporary folder, not the real settings', () {
      final l = lib(tmp);
      expect((l.store as IoFileStore).base.path, startsWith(tmp.path));
    });

    test(
      '#31/AK5 without preferences.json (first start) the appearance is system',
      () async {
        final l = await loaded(tmp);
        expect(l.appearance, Appearance.system);
      },
    );

    test(
      '#31/AK4 #31/AK7 the choice is saved and loaded after a restart',
      () async {
        for (final a in [
          Appearance.dark,
          Appearance.light,
          Appearance.system,
        ]) {
          final l = await loaded(tmp);
          l.appearance = a;
          await settle();
          expect((await loaded(tmp)).appearance, a);
        }
      },
    );

    test('#31/AK4 stored next to the sort order, which stays intact', () async {
      final l = await loaded(tmp);
      l.sortOrder = TrackSortOrder.alphabetical;
      await settle();
      l.appearance = Appearance.dark;
      await settle();
      // #36/AK5: both are shared settings in library.json.
      final shared =
          ((jsonDecode(File('${tmp.path}/library.json').readAsStringSync())
                      as Map)['settings']
                  as Map)['values']
              as Map;
      expect(shared['appearance'], 'dark');
      expect(shared['sortOrder'], 'alphabetical');
      final again = await loaded(tmp);
      expect(again.sortOrder, TrackSortOrder.alphabetical);
      expect(again.appearance, Appearance.dark);
    });

    test('#31/AK5 old preferences.json without the key means system', () async {
      prefs(tmp).writeAsStringSync('{"sortOrder":"alphabetical"}');
      final l = await loaded(tmp);
      expect(l.appearance, Appearance.system);
      expect(l.sortOrder, TrackSortOrder.alphabetical);
    });

    test('#31/AK5 unknown or wrongly typed value means system', () async {
      for (final v in ['"sepia"', '42', 'null', '""']) {
        prefs(tmp).writeAsStringSync('{"appearance":$v}');
        expect((await loaded(tmp)).appearance, Appearance.system, reason: v);
      }
    });

    test('#31/AK5 unreadable preferences.json means system', () async {
      prefs(tmp).writeAsStringSync('{kaputt');
      expect((await loaded(tmp)).appearance, Appearance.system);
    });

    test('#31/AK5 parse falls back to system', () {
      expect(Appearance.parse(null), Appearance.system);
      expect(Appearance.parse('dark'), Appearance.dark);
      expect(Appearance.parse('light'), Appearance.light);
      expect(Appearance.parse('DARK'), Appearance.system);
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
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final app = TestApp(Directory('${tmp.path}/lib'));
      await tester.runAsync(app.library.load);
      await tester.pumpWidget(
        WoodshedApp(controller: app.controller, locale: testLocale),
      );
      await tester.pumpAndSettle();
      return app;
    }

    Brightness brightness(WidgetTester tester) =>
        Theme.of(tester.element(find.byKey(const Key('appearanceMenu'))))
            .brightness;

    WsTheme ws(WidgetTester tester) =>
        WsTheme.of(tester.element(find.byKey(const Key('appearanceMenu'))));

    Future<void> choose(WidgetTester tester, Appearance a) async {
      await tester.tap(find.byKey(const Key('appearanceMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('appearance-${a.name}')));
      await tester.pumpAndSettle();
    }

    testWidgets('#31/AK1 menu offers System, Light and Dark', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('appearanceMenu')));
      await tester.pumpAndSettle();
      for (final t in [
        de.appearanceSystem,
        de.appearanceLight,
        de.appearanceDark,
      ]) {
        expect(find.text(t), findsOneWidget);
      }
      expect(find.byTooltip(de.appearance), findsOneWidget);
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
        '#31/AK1 the library title stays on one line next to the new button ($p)',
        (tester) async {
          debugDefaultTargetPlatformOverride = p;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          await pump(tester);
          final title = tester.getRect(find.text(de.library));
          final button = tester.getRect(
            find.byKey(const Key('appearanceMenu')),
          );
          expect(title.height, lessThan(30)); // one line of titleLarge (22)
          expect(title.right, lessThanOrEqualTo(button.left));
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }
  });
}
