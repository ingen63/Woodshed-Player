// #130: size of the window on macOS (later Windows, Linux), as the logical size of the Flutter view. The
// native window sets them (app/macos/Runner/MainFlutterWindow.swift); test/window_size_test.dart measures
// them and checks that both places agree. In the browser and on iPhone/iPad the window has no fixed size.
import 'dart:ui' show Size;

import 'style.dart';

/// First start: Player, Practice and Metronome show every control without scrolling or overflow, in every
/// language, also with a mini bar and the library sidebar.
const defaultWindowSize = Size(1200, 880);

/// Smallest size: the desktop layout with the library sidebar (wider than [WsSize.tabletMax]); nothing
/// overflows, Player and Practice need no scrolling.
const minWindowSize = Size(1010, 650);
