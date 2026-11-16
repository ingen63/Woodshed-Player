import 'dart:async';

import 'package:material_ui/material_ui.dart';

/// Knopf, der beim Gedrückthalten den Schritt wiederholt: nach [delay], dann alle [interval].
class RepeatButton extends StatefulWidget {
  const RepeatButton({
    super.key,
    required this.icon,
    required this.onStep,
    this.tooltip,
    this.delay = const Duration(milliseconds: 400),
    this.interval = const Duration(milliseconds: 80),
  });

  final IconData icon;
  final VoidCallback onStep;
  final String? tooltip;
  final Duration delay;
  final Duration interval;

  @override
  State<RepeatButton> createState() => _RepeatButtonState();
}

class _RepeatButtonState extends State<RepeatButton> {
  Timer? _timer;

  void _down(_) {
    widget.onStep();
    _timer?.cancel();
    _timer = Timer(widget.delay, () {
      _timer = Timer.periodic(widget.interval, (_) => widget.onStep());
    });
  }

  void _up([_]) {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _up();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip ?? '',
      child: Listener(
        onPointerDown: _down,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: IconButton.outlined(onPressed: () {}, icon: Icon(widget.icon)),
      ),
    );
  }
}
