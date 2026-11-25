// #148: every keyboard shortcut of the app in one table, grouped by area. The overview (help_page.dart)
// shows it; a test presses every key of the table in the app and every other key, so a shortcut that
// works but is missing here, or one listed here that does not work, fails it (#148/AK15).
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'messages.dart';
import 'style.dart';

/// The groups of the overview.
enum ShortcutGroup { general, player, practice, library }

/// What a shortcut does; one text per action in the ARB files.
enum ShortcutAction {
  switchArea,
  open,
  newFolder,
  search,
  help,
  shortcuts,
  playerPlayPause,
  shuffle,
  repeat,
  mute,
  previousNext,
  seek,
  volume,
  practicePlayPause,
  metronome,
  tap,
  speed,
  bpm,
  bpm10,
  loopStart,
  loopEnd,
  deleteTrack,
  endSelection,
  deleteSelection,
  rangeClick,
  toggleClick,
}

/// Names of keys that are words in the overview.
enum KeyName { space, escape, delete, backspace, click }

/// One key with its modifiers. [shift] and [alt] null: the shortcut works with or without them, and the
/// overview does not show them.
class ShortcutKey {
  const ShortcutKey(
    this.trigger, {
    this.command = false,
    this.shift = false,
    this.alt = false,
  }) : character = null,
       name = null;

  /// A key named by a word ([KeyName]).
  const ShortcutKey.named(
    KeyName this.name,
    this.trigger, {
    this.command = false,
    this.shift = false,
    this.alt = false,
  }) : character = null;

  /// A key found by the character it types, whatever the keyboard layout (the «?» is ⇧ß on a German
  /// keyboard and ⇧/ on an English one); [shift] does not count.
  const ShortcutKey.character(
    String this.character, {
    this.command = false,
    this.alt = false,
  }) : trigger = null,
       shift = null,
       name = null;

  /// A click with a modifier.
  const ShortcutKey.click({this.command = false, this.shift = false})
    : trigger = null,
      character = null,
      name = KeyName.click,
      alt = false;

  final LogicalKeyboardKey? trigger;
  final String? character;
  final KeyName? name;
  final bool command;
  final bool? shift, alt;

  bool get isClick => name == KeyName.click;
}

/// A line of the overview: an action and its keys (alternatives such as ← and →).
class ShortcutRow {
  const ShortcutRow(this.group, this.action, this.keys);
  final ShortcutGroup group;
  final ShortcutAction action;
  final List<ShortcutKey> keys;
}

const _l = LogicalKeyboardKey.arrowLeft, _r = LogicalKeyboardKey.arrowRight;
const _u = LogicalKeyboardKey.arrowUp, _d = LogicalKeyboardKey.arrowDown;

/// The keys Delete and Backspace, with or without ⇧ and ⌥.
const _deleteKeys = [
  ShortcutKey.named(
    KeyName.delete,
    LogicalKeyboardKey.delete,
    shift: null,
    alt: null,
  ),
  ShortcutKey.named(
    KeyName.backspace,
    LogicalKeyboardKey.backspace,
    shift: null,
    alt: null,
  ),
];

/// Every shortcut of the app. ⌘ means Ctrl outside Apple's platforms.
const shortcutTable = <ShortcutRow>[
  // General: home_page.dart (CallbackShortcuts, «?»), the Help menu on the Mac (app_menu_bar.dart).
  ShortcutRow(ShortcutGroup.general, ShortcutAction.switchArea, [
    ShortcutKey(LogicalKeyboardKey.digit1, command: true),
    ShortcutKey(LogicalKeyboardKey.digit2, command: true),
    ShortcutKey(LogicalKeyboardKey.digit3, command: true),
  ]),
  ShortcutRow(ShortcutGroup.general, ShortcutAction.open, [
    ShortcutKey(LogicalKeyboardKey.keyO, command: true),
  ]),
  ShortcutRow(ShortcutGroup.general, ShortcutAction.newFolder, [
    ShortcutKey(LogicalKeyboardKey.keyN, command: true, shift: true),
  ]),
  ShortcutRow(ShortcutGroup.general, ShortcutAction.search, [
    ShortcutKey(LogicalKeyboardKey.keyK, command: true),
  ]),
  ShortcutRow(ShortcutGroup.general, ShortcutAction.help, [
    ShortcutKey.character('?', command: true),
  ]),
  ShortcutRow(ShortcutGroup.general, ShortcutAction.shortcuts, [
    ShortcutKey.character('?'),
  ]),
  // Player: PlayerShortcuts (areas.dart).
  ShortcutRow(ShortcutGroup.player, ShortcutAction.playerPlayPause, [
    ShortcutKey.named(KeyName.space, LogicalKeyboardKey.space, shift: null),
  ]),
  ShortcutRow(ShortcutGroup.player, ShortcutAction.shuffle, [
    ShortcutKey(LogicalKeyboardKey.keyS, alt: true, shift: null),
  ]),
  ShortcutRow(ShortcutGroup.player, ShortcutAction.repeat, [
    ShortcutKey(LogicalKeyboardKey.keyR, alt: true, shift: null),
  ]),
  ShortcutRow(ShortcutGroup.player, ShortcutAction.mute, [
    ShortcutKey(LogicalKeyboardKey.keyM, shift: null),
  ]),
  ShortcutRow(ShortcutGroup.player, ShortcutAction.previousNext, [
    ShortcutKey(_l, command: true),
    ShortcutKey(_r, command: true),
  ]),
  ShortcutRow(ShortcutGroup.player, ShortcutAction.seek, [
    ShortcutKey(_l, command: true, shift: true),
    ShortcutKey(_r, command: true, shift: true),
  ]),
  ShortcutRow(ShortcutGroup.player, ShortcutAction.volume, [
    ShortcutKey(_u, command: true),
    ShortcutKey(_d, command: true),
  ]),
  // Practice and Metronome: PracticeShortcuts (metronome/practice_shortcuts.dart); ⇧ and ⌥ do not count,
  // except ⇧ with ↑ and ↓.
  ShortcutRow(ShortcutGroup.practice, ShortcutAction.practicePlayPause, [
    ShortcutKey.named(
      KeyName.space,
      LogicalKeyboardKey.space,
      shift: null,
      alt: null,
    ),
  ]),
  ShortcutRow(ShortcutGroup.practice, ShortcutAction.metronome, [
    ShortcutKey(LogicalKeyboardKey.keyM, shift: null, alt: null),
  ]),
  ShortcutRow(ShortcutGroup.practice, ShortcutAction.tap, [
    ShortcutKey(LogicalKeyboardKey.keyT, shift: null, alt: null),
  ]),
  ShortcutRow(ShortcutGroup.practice, ShortcutAction.speed, [
    ShortcutKey(_l, shift: null, alt: null),
    ShortcutKey(_r, shift: null, alt: null),
  ]),
  ShortcutRow(ShortcutGroup.practice, ShortcutAction.bpm, [
    ShortcutKey(_u, alt: null),
    ShortcutKey(_d, alt: null),
  ]),
  ShortcutRow(ShortcutGroup.practice, ShortcutAction.bpm10, [
    ShortcutKey(_u, shift: true, alt: null),
    ShortcutKey(_d, shift: true, alt: null),
  ]),
  ShortcutRow(ShortcutGroup.practice, ShortcutAction.loopStart, [
    ShortcutKey(LogicalKeyboardKey.keyS, shift: null, alt: null),
  ]),
  ShortcutRow(ShortcutGroup.practice, ShortcutAction.loopEnd, [
    ShortcutKey(LogicalKeyboardKey.keyE, shift: null, alt: null),
  ]),
  ShortcutRow(ShortcutGroup.practice, ShortcutAction.deleteTrack, _deleteKeys),
  // Library: LibraryView (library_view.dart), with a selection or in the search field.
  ShortcutRow(ShortcutGroup.library, ShortcutAction.endSelection, [
    ShortcutKey.named(
      KeyName.escape,
      LogicalKeyboardKey.escape,
      shift: null,
      alt: null,
    ),
  ]),
  ShortcutRow(
    ShortcutGroup.library,
    ShortcutAction.deleteSelection,
    _deleteKeys,
  ),
  ShortcutRow(ShortcutGroup.library, ShortcutAction.rangeClick, [
    ShortcutKey.click(shift: true),
  ]),
  ShortcutRow(ShortcutGroup.library, ShortcutAction.toggleClick, [
    ShortcutKey.click(command: true),
  ]),
];

String _keyName(AppLocalizations l, KeyName n) => switch (n) {
  KeyName.space => l.spaceKey,
  KeyName.escape => l.helpKeyEscape,
  KeyName.delete => l.helpKeyDelete,
  KeyName.backspace => l.helpKeyBackspace,
  KeyName.click => l.helpKeyClick,
};

String _triggerLabel(LogicalKeyboardKey k) => switch (k) {
  LogicalKeyboardKey.arrowLeft => '←',
  LogicalKeyboardKey.arrowRight => '→',
  LogicalKeyboardKey.arrowUp => '↑',
  LogicalKeyboardKey.arrowDown => '↓',
  _ => k.keyLabel.toUpperCase(),
};

/// The key as the overview shows it: ⌥⇧⌘ on macOS and iPad, Ctrl+, Alt+, Shift+ elsewhere.
String shortcutKeyLabel(
  AppLocalizations l,
  TargetPlatform platform,
  ShortcutKey k,
) {
  final name = k.name;
  final trigger = k.trigger;
  final key = name != null
      ? _keyName(l, name)
      : trigger != null
      ? _triggerLabel(trigger)
      : k.character!;
  final apple = isApplePlatform(platform);
  final click = k.isClick;
  final alt = k.alt ?? false, shift = k.shift ?? false;
  final buffer = StringBuffer();
  if (apple) {
    // Apple's order: ⌥⇧⌘
    if (alt) buffer.write('⌥');
    if (shift) buffer.write('⇧');
    if (k.command) buffer.write('⌘');
    if (click && buffer.isNotEmpty) buffer.write('-');
  } else {
    if (k.command) buffer.write('Ctrl+');
    if (alt) buffer.write('Alt+');
    if (shift) buffer.write('Shift+');
  }
  buffer.write(key);
  return buffer.toString();
}

/// Heading of a group.
String shortcutGroupLabel(AppLocalizations l, ShortcutGroup g) => switch (g) {
  ShortcutGroup.general => l.helpShortcutsGeneral,
  ShortcutGroup.player => l.areaPlayer,
  ShortcutGroup.practice => l.helpShortcutsPractice,
  ShortcutGroup.library => l.library,
};

/// What the shortcut does.
String shortcutActionLabel(AppLocalizations l, ShortcutAction a) => switch (a) {
  ShortcutAction.switchArea => l.helpShortcutSwitchArea,
  ShortcutAction.open => l.helpShortcutOpen,
  ShortcutAction.newFolder => l.newFolder,
  ShortcutAction.search => l.helpShortcutSearch,
  ShortcutAction.help => l.helpTitle,
  ShortcutAction.shortcuts => l.helpShortcutsTitle,
  ShortcutAction.playerPlayPause => l.helpShortcutPlayPause,
  ShortcutAction.shuffle => l.helpShortcutShuffle,
  ShortcutAction.repeat => l.helpShortcutRepeat,
  ShortcutAction.mute => l.helpShortcutMute,
  ShortcutAction.previousNext => l.helpShortcutPreviousNext,
  ShortcutAction.seek => l.helpShortcutSeek,
  ShortcutAction.volume => l.helpShortcutVolume,
  ShortcutAction.practicePlayPause => l.helpShortcutPracticePlayPause,
  ShortcutAction.metronome => l.helpShortcutMetronome,
  ShortcutAction.tap => l.helpShortcutTap,
  ShortcutAction.speed => l.helpShortcutSpeed,
  ShortcutAction.bpm => l.helpShortcutBpm,
  ShortcutAction.bpm10 => l.helpShortcutBpm10,
  ShortcutAction.loopStart => l.helpShortcutLoopStart,
  ShortcutAction.loopEnd => l.helpShortcutLoopEnd,
  ShortcutAction.deleteTrack => l.helpShortcutDeleteTrack,
  ShortcutAction.endSelection => l.helpShortcutEndSelection,
  ShortcutAction.deleteSelection => l.helpShortcutDeleteSelection,
  ShortcutAction.rangeClick => l.helpShortcutRangeClick,
  ShortcutAction.toggleClick => l.helpShortcutToggleClick,
};

/// #148/AK3: «?» opens the shortcuts, whatever key types it on this keyboard.
const shortcutsActivator = CharacterActivator('?');

/// #148/AK1: ⌘? (Ctrl+? outside Apple) opens the help.
CharacterActivator helpActivator(TargetPlatform platform) =>
    isApplePlatform(platform)
    ? const CharacterActivator('?', meta: true)
    : const CharacterActivator('?', control: true);
