// #130: default and minimum size of the window. AKn = n-th acceptance criterion of #130. The fonts of the
// app (Inter, JetBrains Mono) are loaded so that the text has its real width and height; the cores are
// fakes. AK2 (fits on a small screen) and AK4 (size kept after a restart) are tested natively in
// macos/RunnerTests.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/app/app_controller.dart';
import 'package:woodshed_player/ui/library_view.dart';
import 'package:woodshed_player/ui/style.dart';
import 'package:woodshed_player/ui/window_size.dart';

import 'fakes.dart';
import 'home_page_test.dart' show pumpApp, select;

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
/// mini bar too (the largest content). Calls [check] once per area.
Future<void> _eachArea(
  WidgetTester tester,
  Size size,
  Locale locale,
  void Function(AppArea area) check,
) async {
  await _loadFonts();
  final app = await pumpApp(tester, size: size, locale: locale);
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
      '#130/AK3 minimum size, $locale: library sidebar, nothing overflows, Player and Practice '
      'without scrolling',
      (tester) async {
        await _eachArea(tester, minWindowSize, locale, (area) {
          expect(find.byKey(const Key('layout:desktop')), findsOneWidget);
          expect(_overflows(tester), isEmpty, reason: area.name);
          if (area != AppArea.metronome) {
            expect(_scrolling(tester), isEmpty, reason: area.name);
          }
        });
        // the library sidebar in its standard width beside the player (#129 makes it draggable)
        expect(minWindowSize.width, greaterThan(WsSize.tabletMax));
      },
    );
  }

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

  test('#130 the native window uses the same sizes', () {
    final swift = File('macos/Runner/MainFlutterWindow.swift')
        .readAsStringSync();
    String size(Size s) =>
        'NSSize(width: ${s.width.toInt()}, height: ${s.height.toInt()})';
    expect(swift, contains('defaultContentSize = ${size(defaultWindowSize)}'));
    expect(swift, contains('minContentSize = ${size(minWindowSize)}'));
  });
}
