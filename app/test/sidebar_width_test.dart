// #129: the width of the library sidebar is changed by dragging its edge. AKn = n-th acceptance criterion of
// #129. German UI (testLocale), widgets found by key. That nothing overflows with the widest sidebar at the
// minimum window size is measured with the real fonts in window_size_test.dart.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/app/app_controller.dart';
import 'package:woodshed_player/app/sidebar_width.dart';
import 'package:woodshed_player/library/library.dart';

import 'fakes.dart';
import 'home_page_test.dart' show phone, pumpApp, wide;

const sidebar = Key('librarySidebar');
const edge = Key('sidebarEdge');

double shownWidth(WidgetTester tester) =>
    tester.getSize(find.byKey(sidebar)).width;

/// Drags the edge of the sidebar by [dx] with the mouse (or a finger).
Future<void> dragEdge(
  WidgetTester tester,
  double dx, {
  PointerDeviceKind kind = PointerDeviceKind.mouse,
}) async {
  await tester.drag(find.byKey(edge), Offset(dx, 0), kind: kind);
  await tester.pump(kDoubleTapTimeout);
}

/// A double click (or double tap) on the edge.
Future<void> doubleClickEdge(WidgetTester tester) async {
  await tester.tap(find.byKey(edge), kind: PointerDeviceKind.mouse);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(find.byKey(edge), kind: PointerDeviceKind.mouse);
  await tester.pumpAndSettle();
}

void main() {
  group('#129/AK2 the width stays within its limits', () {
    test('the default without a chosen width, the chosen width in between', () {
      expect(sidebarWidth(null, 1200), sidebarDefaultWidth);
      expect(sidebarDefaultWidth, 280);
      expect(sidebarWidth(350, 1200), 350);
      expect(sidebarWidth(sidebarMinWidth, 1200), sidebarMinWidth);
      expect(sidebarWidth(sidebarMaxWidth, 1200), sidebarMaxWidth);
    });

    test('never narrower than the minimum, never wider than the maximum', () {
      expect(sidebarWidth(sidebarMinWidth - 1, 1200), sidebarMinWidth);
      expect(sidebarWidth(0, 1200), sidebarMinWidth);
      expect(sidebarWidth(sidebarMaxWidth + 1, 3000), sidebarMaxWidth);
      expect(sidebarWidth(2000, 3000), sidebarMaxWidth);
      expect(sidebarMinWidth, lessThan(sidebarDefaultWidth));
      expect(sidebarMaxWidth, greaterThan(sidebarDefaultWidth));
    });

    test('a narrower window makes the sidebar narrower, the player keeps its width', () {
      // 1050 - 600 = 450: the player keeps playerMinWidth
      expect(sidebarWidth(sidebarMaxWidth, 1050), 1050 - playerMinWidth);
      expect(sidebarWidth(1050 - playerMinWidth, 1050), 1050 - playerMinWidth);
      expect(sidebarWidth(1050 - playerMinWidth - 1, 1050), 449);
      // ... but never below the minimum
      expect(sidebarWidth(sidebarMaxWidth, 800), sidebarMinWidth);
      expect(
        sidebarWidth(sidebarMaxWidth, sidebarMinWidth + playerMinWidth),
        sidebarMinWidth,
      );
      expect(sidebarWidth(null, 700), sidebarMinWidth);
      // a wider window gives the chosen width back
      expect(sidebarWidth(sidebarMaxWidth, 1200), sidebarMaxWidth);
    });
  });

  testWidgets(
    '#129/AK1 the edge shows the resize cursor; dragging makes the sidebar wider or narrower',
    (tester) async {
      await pumpApp(tester, size: const Size(1200, 880));
      expect(shownWidth(tester), sidebarDefaultWidth);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: tester.getCenter(find.byKey(edge)));
      await tester.pump();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.resizeColumn,
      );
      // the edge lies on the border between library and player
      final grip = tester.getRect(find.byKey(edge));
      expect(grip.left, lessThan(sidebarDefaultWidth));
      expect(grip.right, greaterThan(sidebarDefaultWidth + 1));

      await dragEdge(tester, 60);
      expect(shownWidth(tester), sidebarDefaultWidth + 60);
      await dragEdge(tester, -70);
      expect(shownWidth(tester), sidebarDefaultWidth - 10);
      // the player takes the rest
      expect(
        tester.getTopLeft(find.byKey(const Key('playerScreen'))).dx,
        greaterThan(sidebarDefaultWidth - 10),
      );
    },
  );

  testWidgets('#129/AK2 dragging stops at the minimum and the maximum', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(1400, 880));
    await dragEdge(tester, -200);
    expect(shownWidth(tester), sidebarMinWidth);
    await dragEdge(tester, 600);
    expect(shownWidth(tester), sidebarMaxWidth);
  });

  testWidgets(
    '#129/AK2 a narrower window makes the sidebar narrower, a wider one gives the width back',
    (tester) async {
      final app = await pumpApp(tester, size: const Size(1400, 880));
      await dragEdge(tester, 600);
      expect(shownWidth(tester), sidebarMaxWidth);
      expect(app.library.sidebarWidth, sidebarMaxWidth);

      tester.view.physicalSize = const Size(1010, 880);
      await tester.pump();
      expect(shownWidth(tester), 1010 - playerMinWidth);
      // the player beside it: the window less the sidebar and its 1 pt edge
      expect(
        tester.getTopLeft(find.byKey(const Key('playerScreen'))).dx,
        greaterThan(1010 - playerMinWidth),
      );

      tester.view.physicalSize = const Size(1400, 880);
      await tester.pump();
      expect(shownWidth(tester), sidebarMaxWidth);
    },
  );

  testWidgets('#129/AK3 the width chosen is kept on this device', (
    tester,
  ) async {
    final app = await pumpApp(tester, size: const Size(1200, 880));
    expect(app.library.sidebarWidth, isNull);
    await dragEdge(tester, 45.4);
    expect(app.library.sidebarWidth, sidebarDefaultWidth + 45);
    expect(shownWidth(tester), sidebarDefaultWidth + 45);
  });

  test(
    '#129/AK3 the width is written to device.json and read after a restart',
    () async {
      final dir = Directory.systemTemp.createTempSync('wp_sidebar_width');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/${DeviceSettings.fileName}');

      final first = TestApp(dir);
      final Library lib = first.library;
      await lib.load();
      var notified = 0;
      lib.addListener(() => notified++);
      await lib.setSidebarWidth(340);
      expect(notified, 1);
      await lib.setSidebarWidth(340); // unchanged: no write, no notice
      expect(notified, 1);
      expect(jsonDecode(file.readAsStringSync())['sidebarWidth'], 340);

      final again = TestApp(dir);
      await again.library.load();
      expect(again.library.sidebarWidth, 340);
      await again.library.setSidebarWidth(null);
      expect(again.library.sidebarWidth, isNull);
      expect(file.readAsStringSync(), isNot(contains('sidebarWidth')));
      // device-local: the device ID stays the one of the first start
      expect(again.library.device.deviceId, first.library.device.deviceId);
    },
  );

  testWidgets(
    '#129/AK4 a double click on the edge restores the default width',
    (tester) async {
      final app = await pumpApp(tester, size: const Size(1200, 880));
      await dragEdge(tester, 100);
      expect(shownWidth(tester), sidebarDefaultWidth + 100);
      // a single click keeps the width
      await tester.tap(find.byKey(edge), kind: PointerDeviceKind.mouse);
      await tester.pump(kDoubleTapTimeout);
      expect(shownWidth(tester), sidebarDefaultWidth + 100);
      expect(app.library.sidebarWidth, sidebarDefaultWidth + 100);
      await doubleClickEdge(tester);
      expect(shownWidth(tester), sidebarDefaultWidth);
      expect(app.library.sidebarWidth, isNull);
    },
  );

  testWidgets(
    '#129/AK5 iPad with the library beside the player: the edge follows a finger',
    (tester) async {
      // iPad Pro 13" in landscape: the desktop layout with the library beside the player
      final app = await pumpApp(tester, size: const Size(1376, 1032));
      expect(find.byKey(const Key('layout:desktop')), findsOneWidget);
      // a finger gets a wider grip than the mouse
      expect(tester.getSize(find.byKey(edge)).width, greaterThanOrEqualTo(24));
      await dragEdge(tester, 80, kind: PointerDeviceKind.touch);
      expect(shownWidth(tester), sidebarDefaultWidth + 80);
      expect(app.library.sidebarWidth, sidebarDefaultWidth + 80);
      await tester.tap(find.byKey(edge));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(edge));
      await tester.pumpAndSettle();
      expect(shownWidth(tester), sidebarDefaultWidth);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    '#129/AK5 iPhone and iPad in portrait: the library is no sidebar, nothing to drag',
    (tester) async {
      for (final size in [phone, const Size(820, 1180)]) {
        final app = await pumpApp(tester, size: size);
        expect(find.byKey(edge), findsNothing, reason: '$size');
        expect(find.byKey(sidebar), findsNothing, reason: '$size');
        expect(app.library.sidebarWidth, isNull);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('#129 only the area Player shows the sidebar and its edge', (
    tester,
  ) async {
    final app = await pumpApp(tester, size: wide);
    expect(find.byKey(edge), findsOneWidget);
    app.controller.setArea(AppArea.practice);
    await tester.pump();
    expect(find.byKey(edge), findsNothing);
  });
}
