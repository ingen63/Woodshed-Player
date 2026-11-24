// #130: default and minimum size of the window. AKn = n-th acceptance criterion of #130. The fonts of the
// app (Inter, JetBrains Mono) are loaded so that the text has its real width and height; the cores are
// fakes. AK2 (fits on a small screen) and AK4 (size kept after a restart) are tested natively in
// macos/RunnerTests. #129: the same with the widest and the narrowest library sidebar. #135: the
// title of the library sidebar at every width of the sidebar.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/app/app_controller.dart';
import 'package:woodshed_player/app/sidebar_width.dart';
import 'package:woodshed_player/l10n/app_localizations.dart';
import 'package:woodshed_player/ui/library_view.dart';
import 'package:woodshed_player/ui/style.dart';
import 'package:woodshed_player/ui/window_size.dart';

import 'fakes.dart';
import 'home_page_test.dart' show pumpApp, select;

Finder byKey(String k) => find.byKey(Key(k));

Future<void> _loadFont(String family, String dir, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(
      Future.value(
        ByteData.sublistView(
          File('assets/fonts/$dir/$f.ttf').readAsBytesSync(),
        ),
      ),
    );
  }
  await loader.load();
}

Future<void> _loadFonts() async {
  await _loadFont(textFont, 'inter', [
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) 'Inter-$w',
  ]);
  await _loadFont(numberFont, 'jetbrains-mono', [
    for (final w in ['Regular', 'Medium', 'Bold']) 'JetBrainsMono-$w',
  ]);
}

/// Overflow errors of the frame (each one an exception of the test).
List<String> _overflows(WidgetTester tester) => [
  for (var e = tester.takeException(); e != null; e = tester.takeException())
    '$e',
];

/// Scroll views that cannot show all of their content. The list of the library may scroll: it grows
/// with the tracks.
List<String> _scrolling(WidgetTester tester) => [
  for (final s in tester.stateList<ScrollableState>(find.byType(Scrollable)))
    if (find
            .ancestor(
              of: find.byWidget(s.widget),
              matching: find.byType(LibraryView),
            )
            .evaluate()
            .isEmpty &&
        s.position.maxScrollExtent > 0)
      '${s.widget.key ?? s.context.widget.runtimeType}: '
          '${s.position.maxScrollExtent.toStringAsFixed(0)} px more',
];

/// The app at [size] in [locale] with a loaded track and a running metronome, so that every area shows its
/// mini bar too (the largest content). [sidebar]: the width of the library sidebar chosen (#129). Calls
/// [check] once per area.
Future<void> _eachArea(
  WidgetTester tester,
  Size size,
  Locale locale,
  void Function(AppArea area) check, {
  double? sidebar,
}) async {
  await _loadFonts();
  final app = await pumpApp(tester, size: size, locale: locale);
  await tester.runAsync(() => app.library.setSidebarWidth(sidebar));
  await select(tester, app, 'Bossa');
  app.controller.metronome.toggle();
  for (final area in AppArea.values) {
    app.controller.setArea(area);
    await tester.pump();
    check(area);
  }
  app.controller.metronome.toggle();
  await tester.pump();
}

void main() {
  for (final locale in const [Locale('de'), Locale('en')]) {
    testWidgets(
      '#130/AK1 #130/AK5 default size, $locale: every area without scrolling or overflow',
      (tester) async {
        await _eachArea(tester, defaultWindowSize, locale, (area) {
          expect(find.byKey(const Key('layout:desktop')), findsOneWidget);
          expect(_overflows(tester), isEmpty, reason: area.name);
          expect(_scrolling(tester), isEmpty, reason: area.name);
        });
      },
    );

    testWidgets(
      '#130/AK3 #133/AK1 minimum size, $locale: library sidebar, every area without scrolling '
      'or overflow',
      (tester) async {
        await _eachArea(tester, minWindowSize, locale, (area) {
          expect(find.byKey(const Key('layout:desktop')), findsOneWidget);
          expect(_overflows(tester), isEmpty, reason: area.name);
          expect(_scrolling(tester), isEmpty, reason: area.name);
        });
        // the library sidebar in its standard width beside the player (#129 makes it draggable)
        expect(minWindowSize.width, greaterThan(WsSize.tabletMax));
      },
    );

    for (final (name, chosen) in [
      ('widest', sidebarMaxWidth),
      ('narrowest', sidebarMinWidth),
    ]) {
      for (final size in [minWindowSize, defaultWindowSize]) {
        testWidgets(
          '#129/AK2 #130/AK3 $name sidebar, window $size, $locale: nothing overflows, Player and '
          'Practice without scrolling',
          (tester) async {
            await _eachArea(tester, size, locale, sidebar: chosen, (area) {
              expect(find.byKey(const Key('layout:desktop')), findsOneWidget);
              expect(_overflows(tester), isEmpty, reason: area.name);
              if (area != AppArea.metronome || size == defaultWindowSize) {
                expect(_scrolling(tester), isEmpty, reason: area.name);
              }
              if (area == AppArea.player) {
                expect(
                  tester.getSize(find.byKey(const Key('librarySidebar'))).width,
                  sidebarWidth(chosen, size.width),
                );
              }
            });
          },
        );
      }
    }
  }

  // #133: the area Metronome with every state of the ramp (off, by bars, by time), the largest content
  for (final locale in const [Locale('de'), Locale('en')]) {
    for (final (name, size) in [
      ('minimum', minWindowSize),
      ('default', defaultWindowSize),
    ]) {
      testWidgets(
        '#133/AK1 #133/AK2 #133/AK4 #133/AK5 metronome at the $name size, $locale: every ramp '
        'state without scrolling or overflow',
        (tester) async {
          await _loadFonts();
          final app = await pumpApp(tester, size: size, locale: locale);
          await select(tester, app, 'Bossa', area: AppArea.metronome);
          final m = app.controller.metronome;
          for (final (enabled, byTime) in [
            (false, false),
            (true, false),
            (true, true),
          ]) {
            m.setRamp(enabled: enabled, byTime: byTime);
            await tester.pump();
            final state = 'ramp $enabled, by time $byTime';
            expect(byKey('metronomeColumns'), findsOneWidget, reason: state);
            expect(byKey('miniBar:track'), findsOneWidget, reason: state);
            expect(_overflows(tester), isEmpty, reason: state);
            expect(_scrolling(tester), isEmpty, reason: state);
          }
        },
      );
    }
  }

  testWidgets('#133/AK3 tablet and phone: the metronome stays in one column', (
    tester,
  ) async {
    for (final size in const [Size(820, 1180), Size(390, 844)]) {
      final app = await pumpApp(tester, size: size);
      app.controller.setArea(AppArea.metronome);
      await tester.pump();
      expect(byKey('metronomeScreen'), findsOneWidget);
      expect(byKey('metronomeColumns'), findsNothing);
      final tempo = tester.getRect(byKey('card:metronome'));
      final ramp = tester.getRect(byKey('card:ramp'));
      expect(ramp.top, greaterThan(tempo.bottom), reason: '$size');
    }
  });

  testWidgets(
    '#130/AK3 below the minimum height Practice would need scrolling',
    (tester) async {
      // the minimum is not larger than needed: 40 points less and the practice screen scrolls
      await _eachArea(
        tester,
        Size(minWindowSize.width, minWindowSize.height - 40),
        testLocale,
        (area) {
          if (area == AppArea.practice) {
            expect(_scrolling(tester), isNotEmpty);
          }
        },
      );
    },
  );

  // #135: the header of the library sidebar at the narrowest, the standard and the widest width, with
  // mouse-sized (macOS) and touch-sized buttons (iPad)
  for (final locale in const [Locale('de'), Locale('en')]) {
    for (final platform in const [TargetPlatform.macOS, TargetPlatform.iOS]) {
      for (final chosen in const [
        sidebarMinWidth,
        sidebarDefaultWidth,
        370.0,
        sidebarMaxWidth,
      ]) {
        testWidgets(
          '#135/AK1 #135/AK2 #135/AK3 sidebar $chosen pt, $platform, $locale: title at least body '
          'text size on one line, every action reachable, buttons large enough',
          (tester) async {
            debugDefaultTargetPlatformOverride = platform;
            addTearDown(() => debugDefaultTargetPlatformOverride = null);
            await _loadFonts();
            final app = await pumpApp(
              tester,
              size: const Size(1366, 1024),
              locale: locale,
            );
            await tester.runAsync(() => app.library.setSidebarWidth(chosen));
            await select(
              tester,
              app,
              'Bossa',
              area: AppArea.player,
            ); // rebuilds
            final sidebar = tester.getRect(byKey('librarySidebar'));
            expect(sidebar.width, chosen);
            final l = lookupAppLocalizations(locale);

            // AK1: the title, measured as drawn (a FittedBox would scale it down)
            final title = byKey('libraryTitle');
            expect(find.text(l.library), findsWidgets);
            final paragraph = tester.renderObject<RenderParagraph>(title);
            final scale = tester.getRect(title).height / paragraph.size.height;
            final fontSize = paragraph.text.style!.fontSize! * scale;
            final body = Theme.of(tester.element(title))
                .textTheme
                .bodyMedium!
                .fontSize!;
            expect(fontSize, greaterThanOrEqualTo(body));
            expect(paragraph.didExceedMaxLines, isFalse);
            expect(
              paragraph.size.height,
              lessThan(paragraph.text.style!.fontSize! * 2),
            ); // one line

            // AK2: no overflow, both buttons and the "⋯" menu inside the sidebar
            expect(_overflows(tester), isEmpty);
            final buttons = ['addFiles', 'sortMenu', 'libraryMoreMenu'];
            for (final k in buttons) {
              final r = tester.getRect(byKey(k));
              expect(r.left, greaterThanOrEqualTo(sidebar.left), reason: k);
              expect(r.right, lessThanOrEqualTo(sidebar.right), reason: k);
              expect(
                r.left,
                greaterThanOrEqualTo(tester.getRect(title).right),
                reason: k,
              );
            }
            await tester.tap(byKey('libraryMoreMenu'));
            await tester.pumpAndSettle();
            for (final k in [
              'newFolder',
              'appearance-system',
              'appearance-light',
              'appearance-dark',
              'aboutButton',
            ]) {
              expect(byKey(k).hitTestable(), findsOneWidget, reason: k);
            }
            expect(_overflows(tester), isEmpty);
            await tester.tapAt(Offset.zero);
            await tester.pumpAndSettle();

            // AK3: touch-sized buttons on the iPad
            if (platform == TargetPlatform.iOS) {
              for (final k in buttons) {
                final r = tester.getSize(byKey(k));
                expect(r.width, greaterThanOrEqualTo(44), reason: k);
                expect(r.height, greaterThanOrEqualTo(44), reason: k);
              }
            }
            debugDefaultTargetPlatformOverride = null;
          },
        );
      }
    }
  }

  test('#130 the native window uses the same sizes', () {
    final swift = File('macos/Runner/MainFlutterWindow.swift')
        .readAsStringSync();
    String size(Size s) =>
        'NSSize(width: ${s.width.toInt()}, height: ${s.height.toInt()})';
    expect(swift, contains('defaultContentSize = ${size(defaultWindowSize)}'));
    expect(swift, contains('minContentSize = ${size(minWindowSize)}'));
  });
}
