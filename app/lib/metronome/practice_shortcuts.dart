import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'metronome_controller.dart';

/// Tastenkürzel (#3, #17): M Metronom an/aus, T Tap-Tempo, ↑/↓ Tempo ±1 (mit Shift ±10),
/// Leertaste Play/Pause des Titels, S/E Loop-Anfang/-Ende, ←/→ Geschwindigkeit, Entf Titel löschen.
/// In Textfeldern sind die Kürzel aus.
class PracticeShortcuts extends StatelessWidget {
  const PracticeShortcuts({
    super.key,
    required this.metronome,
    required this.onPlayPause,
    required this.child,
    this.onLoopStart,
    this.onLoopEnd,
    this.onSpeedStep,
    this.onDelete,
  });

  final MetronomeController metronome;
  final VoidCallback onPlayPause;
  final VoidCallback? onLoopStart, onLoopEnd, onDelete;
  final void Function(int steps)? onSpeedStep;
  final Widget child;

  static bool _typing() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null &&
        (ctx.widget is EditableText ||
            ctx.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  /// Handles [event]; public so that one Focus can switch between the shortcuts of the areas (#115).
  KeyEventResult onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || _typing()) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final repeat = event is KeyRepeatEvent;
    final meta =
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    if (meta) return KeyEventResult.ignored; // ⌘-Kürzel gehören der App
    if (key == LogicalKeyboardKey.arrowLeft && onSpeedStep != null) {
      onSpeedStep!(-1);
    } else if (key == LogicalKeyboardKey.arrowRight && onSpeedStep != null) {
      onSpeedStep!(1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      metronome.changeBpm(shift ? 10 : 1);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      metronome.changeBpm(shift ? -10 : -1);
    } else if (repeat) {
      return KeyEventResult.ignored; // M, T und Leertaste nicht wiederholen
    } else if (key == LogicalKeyboardKey.keyM) {
      metronome.toggle();
    } else if (key == LogicalKeyboardKey.keyT) {
      metronome.tap();
    } else if (key == LogicalKeyboardKey.space) {
      onPlayPause();
    } else if (key == LogicalKeyboardKey.keyS && onLoopStart != null) {
      onLoopStart!();
    } else if (key == LogicalKeyboardKey.keyE && onLoopEnd != null) {
      onLoopEnd!();
    } else if ((key == LogicalKeyboardKey.delete ||
            key == LogicalKeyboardKey.backspace) &&
        onDelete != null) {
      onDelete!();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) =>
      Focus(autofocus: true, onKeyEvent: onKey, child: child);
}
