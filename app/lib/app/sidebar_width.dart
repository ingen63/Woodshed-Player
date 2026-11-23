// #129: width of the library sidebar beside the player (desktop layout: macOS, Windows, Linux, the browser
// and a wide iPad). The user drags its edge; the width chosen is kept per device (`device.json`).
import 'dart:math';

/// Width on first start and after a double click on the edge.
const sidebarDefaultWidth = 280.0;

/// Narrowest sidebar: the five buttons of the header fit beside each other also at touch size (48 pt), and
/// a track title keeps about 110 pt.
const sidebarMinWidth = 260.0;

/// Widest sidebar in a large window.
const sidebarMaxWidth = 480.0;

/// Width the player beside the sidebar keeps at least (with the 1 pt edge), so that every control stays
/// usable; a narrower window makes the sidebar narrower, down to [sidebarMinWidth].
const playerMinWidth = 600.0;

/// Width of the sidebar shown in a window [windowWidth] wide when [chosen] was chosen (null: the default).
double sidebarWidth(double? chosen, double windowWidth) {
  final widest = min(sidebarMaxWidth, windowWidth - playerMinWidth);
  return (chosen ?? sidebarDefaultWidth).clamp(
    sidebarMinWidth,
    max(sidebarMinWidth, widest),
  );
}
