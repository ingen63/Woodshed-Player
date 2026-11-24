// The macOS menu bar (#144) in the UI language: built here with PlatformMenuBar, its texts come from the ARB
// files like every other UI text. The same entries as the former MainMenu.xib: app menu (About, Services,
// Hide, Quit), Edit, View, Window and Help. Flutter copies the standard items (Hide, Quit, Minimize …) with
// their English titles from MainMenu.xib; [menuBarTitles] gives the native side their titles in the UI
// language (MainFlutterWindow.swift, «localizeMenuBar»).
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app/file_platform.dart';
import 'messages.dart';

/// Wraps [child] in the macOS menu bar if [files] has one; elsewhere [child] alone.
class AppMenuBar extends StatefulWidget {
  const AppMenuBar({
    super.key,
    required this.files,
    required this.onAbout,
    required this.child,
  });
  final FilePlatform files;

  /// «About Woodshed Player» was chosen (#50/AK6).
  final VoidCallback onAbout;
  final Widget child;

  @override
  State<AppMenuBar> createState() => _AppMenuBarState();
}

class _AppMenuBarState extends State<AppMenuBar> {
  /// The menus of the current UI language; built anew only when it changes, so a rebuild of the page
  /// does not send a changed menu bar to the platform.
  List<PlatformMenuItem>? _menus;
  AppLocalizations? _texts;
  bool _localizing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l = context.l10n;
    if (identical(l, _texts)) return;
    _texts = l;
    _menus = appMenus(l, onAbout: () => widget.onAbout());
  }

  @override
  Widget build(BuildContext context) {
    final menus = _menus;
    if (!widget.files.hasMenuBar || menus == null) return widget.child;
    // PlatformMenuBar may send the menus again on any rebuild (the first one after the start, a change
    // of language); afterwards the standard items get their titles again (#144/AK1).
    if (!_localizing) {
      _localizing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _localizing = false;
        if (mounted) widget.files.localizeMenuBar(menuBarTitles(_texts!));
      });
    }
    return PlatformMenuBar(menus: menus, child: widget.child);
  }
}

/// Runs [intent] on the focused widget (a text field), if there is one.
void _invoke(Intent intent) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context != null) Actions.maybeInvoke(context, intent);
}

PlatformProvidedMenuItem _provided(PlatformProvidedMenuItemType type) =>
    PlatformProvidedMenuItem(type: type);

PlatformMenuItem _edit(
  String label,
  Intent intent, [
  MenuSerializableShortcut? shortcut,
]) => PlatformMenuItem(
  label: label,
  shortcut: shortcut,
  onSelected: () => _invoke(intent),
);

SingleActivator _command(LogicalKeyboardKey key, {bool shift = false}) =>
    SingleActivator(key, meta: true, shift: shift);

/// The menus of the menu bar (#144/AK1). The first one is the app menu; macOS shows the app name as its
/// title.
List<PlatformMenuItem> appMenus(
  AppLocalizations l, {
  required VoidCallback onAbout,
}) {
  const cause = SelectionChangedCause.keyboard;
  return [
    PlatformMenu(
      label: 'Woodshed Player',
      menus: [
        PlatformMenuItemGroup(
          members: [PlatformMenuItem(label: l.aboutApp, onSelected: onAbout)],
        ),
        PlatformMenuItemGroup(
          members: [_provided(PlatformProvidedMenuItemType.servicesSubmenu)],
        ),
        PlatformMenuItemGroup(
          members: [
            _provided(PlatformProvidedMenuItemType.hide),
            _provided(PlatformProvidedMenuItemType.hideOtherApplications),
            _provided(PlatformProvidedMenuItemType.showAllApplications),
          ],
        ),
        PlatformMenuItemGroup(
          members: [_provided(PlatformProvidedMenuItemType.quit)],
        ),
      ],
    ),
    PlatformMenu(
      label: l.menuEdit,
      menus: [
        PlatformMenuItemGroup(
          members: [
            _edit(
              l.menuUndo,
              const UndoTextIntent(cause),
              _command(LogicalKeyboardKey.keyZ),
            ),
            _edit(
              l.menuRedo,
              const RedoTextIntent(cause),
              _command(LogicalKeyboardKey.keyZ, shift: true),
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            _edit(
              l.menuCut,
              const CopySelectionTextIntent.cut(cause),
              _command(LogicalKeyboardKey.keyX),
            ),
            _edit(
              l.menuCopy,
              CopySelectionTextIntent.copy,
              _command(LogicalKeyboardKey.keyC),
            ),
            _edit(
              l.menuPaste,
              const PasteTextIntent(cause),
              _command(LogicalKeyboardKey.keyV),
            ),
            _edit(l.menuDelete, const DeleteCharacterIntent(forward: true)),
            _edit(
              l.menuSelectAll,
              const SelectAllTextIntent(cause),
              _command(LogicalKeyboardKey.keyA),
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenu(
              label: l.menuSpeech,
              menus: [
                _provided(PlatformProvidedMenuItemType.startSpeaking),
                _provided(PlatformProvidedMenuItemType.stopSpeaking),
              ],
            ),
          ],
        ),
      ],
    ),
    PlatformMenu(
      label: l.menuView,
      menus: [_provided(PlatformProvidedMenuItemType.toggleFullScreen)],
    ),
    PlatformMenu(
      label: l.menuWindow,
      menus: [
        PlatformMenuItemGroup(
          members: [
            _provided(PlatformProvidedMenuItemType.minimizeWindow),
            _provided(PlatformProvidedMenuItemType.zoomWindow),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            _provided(PlatformProvidedMenuItemType.arrangeWindowsInFront),
          ],
        ),
      ],
    ),
    // macOS fills the Help menu (search field); the native side gives it its menu.
    PlatformMenu(label: l.menuHelp, menus: const []),
  ];
}

/// Titles of the standard items in the UI language, by their AppKit action (selector), plus the titles
/// of the menus the native side looks after: Services, Window list and Help (#144/AK1).
Map<String, String> menuBarTitles(AppLocalizations l) => {
  'services': l.menuServices,
  'windowsMenu': l.menuWindow,
  'helpMenu': l.menuHelp,
  'hide:': l.menuHide,
  'hideOtherApplications:': l.menuHideOthers,
  'unhideAllApplications:': l.menuShowAll,
  'terminate:': l.menuQuit,
  'startSpeaking:': l.menuStartSpeaking,
  'stopSpeaking:': l.menuStopSpeaking,
  'toggleFullScreen:': l.menuFullScreen,
  'performMiniaturize:': l.menuMinimize,
  'performZoom:': l.menuZoom,
  'arrangeInFront:': l.menuBringAllToFront,
};
