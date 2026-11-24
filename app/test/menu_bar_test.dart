// #144/AK1: the macOS menu bar in the UI language, built with PlatformMenuBar from the ARB files. The
// native side (MainFlutterWindow.localizeMenuBar, RunnerTests MenuBarTests) gives the standard items the
// titles handed over here.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/l10n/app_localizations.dart';
import 'package:woodshed_player/main.dart';
import 'package:woodshed_player/ui/app_menu_bar.dart';

import 'fakes.dart';

/// The AppKit actions of the standard items, as the macOS embedder maps them (FlutterMenuPlugin.mm).
const _selectors = {
  PlatformProvidedMenuItemType.quit: 'terminate:',
  PlatformProvidedMenuItemType.hide: 'hide:',
  PlatformProvidedMenuItemType.hideOtherApplications: 'hideOtherApplications:',
  PlatformProvidedMenuItemType.showAllApplications: 'unhideAllApplications:',
  PlatformProvidedMenuItemType.startSpeaking: 'startSpeaking:',
  PlatformProvidedMenuItemType.stopSpeaking: 'stopSpeaking:',
  PlatformProvidedMenuItemType.toggleFullScreen: 'toggleFullScreen:',
  PlatformProvidedMenuItemType.minimizeWindow: 'performMiniaturize:',
  PlatformProvidedMenuItemType.zoomWindow: 'performZoom:',
  PlatformProvidedMenuItemType.arrangeWindowsInFront: 'arrangeInFront:',
  // no selector of its own; the native side finds it as the submenu of the app menu
  PlatformProvidedMenuItemType.servicesSubmenu: 'services',
};

final _macOS = TargetPlatformVariant.only(TargetPlatform.macOS);

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('wp_menu'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// The menus sent to the platform (channel «flutter/menu»), the last one first.
  late List<List<Map<Object?, Object?>>> sent;

  /// Records the menus sent to the platform in [sent].
  void capture(WidgetTester tester) {
    sent = [];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.menu,
      (call) async {
        if (call.method == 'Menu.setMenus') {
          final menus = (call.arguments as Map<Object?, Object?>)['0']!;
          sent.insert(0, (menus as List).cast<Map<Object?, Object?>>());
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.menu,
        null,
      ),
    );
  }

  Future<TestApp> pump(
    WidgetTester tester,
    Locale locale, {
    bool menuBar = true,
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    capture(tester);
    final app = TestApp(Directory('${tmp.path}/lib'));
    app.files.hasMenuBar = menuBar;
    await tester.runAsync(app.library.load);
    await tester.pumpWidget(
      WoodshedApp(controller: app.controller, locale: locale),
    );
    await tester.pumpAndSettle();
    return app;
  }

  Iterable<Map<Object?, Object?>> all(List<Map<Object?, Object?>> items) sync* {
    for (final i in items) {
      yield i;
      yield* all(
        ((i['children'] as List?) ?? const []).cast<Map<Object?, Object?>>(),
      );
    }
  }

  List<String?> titles(List<Map<Object?, Object?>> items) =>
      items.map((i) => i['label'] as String?).toList();

  Map<Object?, Object?> item(String label) =>
      all(sent.first).firstWhere((i) => i['label'] == label);

  Future<void> select(WidgetTester tester, String label) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.menu.name,
      SystemChannels.menu.codec.encodeMethodCall(
        MethodCall('Menu.selectedCallback', item(label)['id']),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();
  }

  for (final (locale, expected) in [
    (
      const Locale('de'),
      ['Woodshed Player', 'Bearbeiten', 'Darstellung', 'Fenster', 'Hilfe'],
    ),
    (const Locale('en'), ['Woodshed Player', 'Edit', 'View', 'Window', 'Help']),
  ]) {
    testWidgets('#144/AK1 menu bar in $locale', (tester) async {
      final app = await pump(tester, locale);
      final l = lookupAppLocalizations(locale);
      expect(sent, isNotEmpty);
      expect(titles(sent.first), expected);
      // App menu: About, Services, Hide, Hide Others, Show All, Quit
      final appMenu = all([sent.first.first]).toList();
      expect(appMenu.map((i) => i['label']), contains(l.aboutApp));
      expect(
        [
          for (final i in appMenu)
            if (i['platformProvidedMenu'] case final int t)
              PlatformProvidedMenuItemType.values[t],
        ],
        [
          PlatformProvidedMenuItemType.servicesSubmenu,
          PlatformProvidedMenuItemType.hide,
          PlatformProvidedMenuItemType.hideOtherApplications,
          PlatformProvidedMenuItemType.showAllApplications,
          PlatformProvidedMenuItemType.quit,
        ],
      );
      // Edit: the text commands with their usual shortcuts
      for (final label in [
        l.menuUndo,
        l.menuRedo,
        l.menuCut,
        l.menuCopy,
        l.menuPaste,
        l.menuDelete,
        l.menuSelectAll,
      ]) {
        expect(item(label)['enabled'], isTrue, reason: label);
      }
      expect(
        item(l.menuCopy)['shortcutCharacter'] ??
            item(l.menuCopy)['shortcutTrigger'],
        isNotNull,
      );
      // Every standard item gets its title in the UI language from the native side.
      expect(app.files.menuTitles, menuBarTitles(l));
      for (final i in all(sent.first)) {
        if (i['platformProvidedMenu'] case final int t) {
          final key = _selectors[PlatformProvidedMenuItemType.values[t]];
          expect(app.files.menuTitles![key], isNotEmpty, reason: '$key');
        }
      }
      expect(app.files.menuTitles!['windowsMenu'], l.menuWindow);
      expect(app.files.menuTitles!['helpMenu'], l.menuHelp);
      expect(tester.takeException(), isNull);
    }, variant: _macOS);
  }

  testWidgets('#144/AK1 the standard titles in German', (tester) async {
    final app = await pump(tester, const Locale('de'));
    expect(
      app.files.menuTitles,
      containsPair('terminate:', 'Woodshed Player beenden'),
    );
    expect(
      app.files.menuTitles,
      containsPair('hide:', 'Woodshed Player ausblenden'),
    );
    expect(
      app.files.menuTitles,
      containsPair('performMiniaturize:', 'Im Dock ablegen'),
    );
    expect(app.files.menuTitles, containsPair('services', 'Dienste'));
  }, variant: _macOS);

  testWidgets('#144/AK1 a change of language rebuilds the menu bar', (
    tester,
  ) async {
    final app = await pump(tester, const Locale('en'));
    expect(titles(sent.first), contains('Edit'));
    await tester.pumpWidget(
      WoodshedApp(controller: app.controller, locale: const Locale('de')),
    );
    await tester.pumpAndSettle();
    expect(titles(sent.first), contains('Bearbeiten'));
    expect(app.files.menuTitles!['terminate:'], 'Woodshed Player beenden');
  }, variant: _macOS);

  testWidgets('#144/AK1 after a rebuild the standard items keep their titles', (
    tester,
  ) async {
    final app = await pump(tester, const Locale('de'));
    Future<void> rebuild() async {
      app.files.menuTitles = null;
      await tester.pumpWidget(
        WoodshedApp(controller: app.controller, locale: const Locale('de')),
      );
      await tester.pumpAndSettle();
      // whatever PlatformMenuBar sent, the titles follow
      expect(app.files.menuTitles, menuBarTitles(de));
    }

    await rebuild();
    final count = sent.length;
    await rebuild();
    // the same menus in the same language are not sent again
    expect(sent.length, count);
  }, variant: _macOS);

  testWidgets(
    '#144/AK1 without a menu bar (iPhone, iPad, browser) nothing is sent',
    (tester) async {
      final app = await pump(tester, const Locale('de'), menuBar: false);
      expect(sent, isEmpty);
      expect(app.files.menuTitles, isNull);
    },
  );

  testWidgets(
    '#50/AK6 «About Woodshed Player» in the app menu opens the dialog',
    (tester) async {
      await pump(tester, const Locale('de'));
      expect(find.byType(AboutDialog), findsNothing);
      await select(tester, de.aboutApp);
      expect(find.byType(AboutDialog), findsOneWidget);
    },
    variant: _macOS,
  );

  testWidgets('#144/AK1 Edit works on the focused text field', (tester) async {
    capture(tester);
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => switch (call.method) {
        'Clipboard.setData' =>
          clipboard =
              (call.arguments as Map<Object?, Object?>)['text'] as String?,
        'Clipboard.getData' => {'text': clipboard},
        'Clipboard.hasStrings' => {'value': clipboard != null},
        _ => null,
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final field = TextEditingController(text: 'abc def');
    addTearDown(field.dispose);
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppMenuBar(
            files: (FakeFiles()..hasMenuBar = true),
            onAbout: () {},
            child: TextField(controller: field, focusNode: focus),
          ),
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        locale: const Locale('en'),
      ),
    );
    focus.requestFocus();
    await tester.pumpAndSettle();
    await select(tester, 'Select All');
    expect(
      field.selection,
      const TextSelection(baseOffset: 0, extentOffset: 7),
    );
    await select(tester, 'Copy');
    expect(clipboard, 'abc def');
    await select(tester, 'Delete');
    expect(field.text, isEmpty);
    await select(tester, 'Paste');
    await select(tester, 'Paste');
    expect(field.text, 'abc defabc def');
    await select(tester, 'Undo');
    expect(field.text, isNot('abc defabc def'));
    await select(tester, 'Redo');
    expect(field.text, 'abc defabc def');
    await select(tester, 'Select All');
    await select(tester, 'Cut');
    expect(field.text, isEmpty);
    // nothing focused: the commands do nothing and fail nowhere
    focus.unfocus();
    await tester.pumpAndSettle();
    await select(tester, 'Paste');
    expect(field.text, isEmpty);
    expect(tester.takeException(), isNull);
  }, variant: _macOS);
}
