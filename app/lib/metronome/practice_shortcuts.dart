import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'metronome_controller.dart';

/// Tastenkürzel (#3): M Metronom an/aus, T Tap-Tempo, ↑/↓ Tempo ±1 (mit Shift ±10),
/// Leertaste Play/Pause des Titels. In Textfeldern sind die Kürzel aus.
class PracticeShortcuts extends StatelessWidget {
  const PracticeShortcuts({
    super.key,
    required this.metronome,
    required this.onPlayPause,
    required this.child,
  });

  final MetronomeController metronome;
  final VoidCallback onPlayPause;
  final Widget child;

  static bool _typing() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null &&
        (ctx.widget is EditableText ||
            ctx.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || _typing()) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final repeat = event is KeyRepeatEvent;
    if (key == LogicalKeyboardKey.arrowUp) {
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
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) =>
      Focus(autofocus: true, onKeyEvent: _onKey, child: child);
}
