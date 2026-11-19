// Design «Studio» (#30, Mockups in docs/design/A-*.dc.html): Farben, Schriften, Abstände und Grössen
// an einer Stelle. Die Views holen alles über `WsTheme.of(context)` und `WsLayout.of(context)`.
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Symbole aus der Schrift von `cupertino_icons` (wie die SF Symbols der alten App).
abstract final class WsIcons {
  static const _f = 'CupertinoIcons', _p = 'cupertino_icons';
  static const back15 = IconData(0xf690, fontFamily: _f, fontPackage: _p);
  static const forward15 = IconData(0xf699, fontFamily: _f, fontPackage: _p);
  static const play = IconData(0xf488, fontFamily: _f, fontPackage: _p);
  static const pause = IconData(0xf478, fontFamily: _f, fontPackage: _p);
  static const speakerOff = IconData(0xf3b9, fontFamily: _f, fontPackage: _p);
  static const speaker1 = IconData(0xf3b7, fontFamily: _f, fontPackage: _p);
  static const speaker2 = IconData(0xf7ec, fontFamily: _f, fontPackage: _p);
  static const speaker3 = IconData(0xf3ba, fontFamily: _f, fontPackage: _p);
  static const speedometer = IconData(0xf7f5, fontFamily: _f, fontPackage: _p);
  static const repeat = IconData(0xf7bf, fontFamily: _f, fontPackage: _p);
  static const musicNote = IconData(0xf46b, fontFamily: _f, fontPackage: _p);
  static const location = IconData(0xf6f1, fontFamily: _f, fontPackage: _p);
  static const backwardEnd = IconData(0xf57b, fontFamily: _f, fontPackage: _p);
  static const leftRight = IconData(0xf500, fontFamily: _f, fontPackage: _p);
  static const metronome = IconData(0xf70b, fontFamily: _f, fontPackage: _p);
  static const timer = IconData(0xf868, fontFamily: _f, fontPackage: _p);
  static const folder = IconData(0xf434, fontFamily: _f, fontPackage: _p);
  static const stop = IconData(0xf82b, fontFamily: _f, fontPackage: _p);
  static const record = IconData(0xf400, fontFamily: _f, fontPackage: _p);
  static const warning = IconData(0xf661, fontFamily: _f, fontPackage: _p);
  static const tray = IconData(0xf871, fontFamily: _f, fontPackage: _p);
  static const add = IconData(0xf489, fontFamily: _f, fontPackage: _p);
  static const pencil = IconData(0xf37e, fontFamily: _f, fontPackage: _p);
  static const trash = IconData(0xf4c4, fontFamily: _f, fontPackage: _p);
  static const chevronDown = IconData(0xf5d5, fontFamily: _f, fontPackage: _p);
  static const chevronRight = IconData(0xf3d3, fontFamily: _f, fontPackage: _p);
  static const chevronLeft = IconData(0xf3d2, fontFamily: _f, fontPackage: _p);
  static const ellipsis = IconData(0xf46a, fontFamily: _f, fontPackage: _p);
  static const sidebar = IconData(0xf7d6, fontFamily: _f, fontPackage: _p);
  static const slider = IconData(0xf7dc, fontFamily: _f, fontPackage: _p);
  static const ellipsisVertical = IconData(
    0xf8da,
    fontFamily: _f,
    fontPackage: _p,
  );
  static const close = IconData(0xf404, fontFamily: _f, fontPackage: _p);
  static const folderBadgePlus = IconData(
    0xf678,
    fontFamily: _f,
    fontPackage: _p,
  );
  static const sort = IconData(0xf51f, fontFamily: _f, fontPackage: _p);
  static const appearanceAuto = IconData(
    0xf5f0,
    fontFamily: _f,
    fontPackage: _p,
  );
  static const sun = IconData(0xf4b6, fontFamily: _f, fontPackage: _p);
  static const moon = IconData(0xf716, fontFamily: _f, fontPackage: _p);
  static const musicNoteList = IconData(
    0xf726,
    fontFamily: _f,
    fontPackage: _p,
  );
}

// MARK: Farben, Schriften, Abstände

/// Schrift für Text und für Zahlen (gleich breite Ziffern).
const textFont = 'Inter';
const numberFont = 'JetBrains Mono';

/// Abstände (logische Pixel).
abstract final class WsSpace {
  static const xs = 4.0, s = 8.0, m = 12.0, l = 16.0, xl = 24.0;
}

/// Farben des Designs «Studio» (#30/AK2). Dunkel ist der Standard der Mockups, Hell folgt dem System.
@immutable
class WsTheme extends ThemeExtension<WsTheme> {
  const WsTheme({
    required this.bg,
    required this.panel,
    required this.panel2,
    required this.border,
    required this.text,
    required this.muted,
    required this.amber,
    required this.amberSoft,
    required this.onAmber,
    required this.blue,
    required this.wave,
    required this.led,
    required this.record,
    required this.shadow,
  });

  /// Hintergrund, Karten, Knöpfe/Auswahl, Rahmen.
  final Color bg, panel, panel2, border;

  /// Text und gedämpfter Text.
  final Color text, muted;

  /// Loop und Playhead (Bernstein), Hintergrund des Loop-Bereichs, Schrift auf Bernstein.
  final Color amber, amberSoft, onAmber;

  /// Metronom.
  final Color blue;

  /// Wellenform ausserhalb des Loops, ausgeschaltete Zählzeit.
  final Color wave, led;

  /// Aufnahme und Fehler.
  final Color record;
  final Color shadow;

  static const dark = WsTheme(
    bg: Color(0xFF121214),
    panel: Color(0xFF1C1C1F),
    panel2: Color(0xFF26262A),
    border: Color(0xFF2C2C30),
    text: Color(0xFFECECEF),
    muted: Color(0xFF9A9AA3),
    amber: Color(0xFFFF9F0A),
    amberSoft: Color(0x29FF9F0A), // 16 %
    onAmber: Color(0xFF121214),
    blue: Color(0xFF4DA3FF),
    wave: Color(0xFF4A4A52),
    led: Color(0xFF2C2C30),
    record: Color(0xFFFF453A),
    shadow: Color(0x66000000),
  );

  static const light = WsTheme(
    bg: Color(0xFFECECEF),
    panel: Color(0xFFFFFFFF),
    panel2: Color(0xFFF4F4F6),
    border: Color(0xFFD4D4D9),
    text: Color(0xFF18181B),
    muted: Color(0xFF5A5A63),
    amber: Color(0xFFA85F00),
    amberSoft: Color(0x2EFF9F0A), // 18 %
    onAmber: Color(0xFF121214),
    blue: Color(0xFF0A63C2),
    wave: Color(0xFFB9B9C0),
    led: Color(0xFFD4D4D9),
    record: Color(0xFFD70015),
    shadow: Color(0x33000000),
  );

  static WsTheme of(BuildContext context) =>
      Theme.of(context).extension<WsTheme>() ?? dark;

  /// Zahlen (Zeiten, Tempo, BPM) in JetBrains Mono mit tabellarischen Ziffern (#30/AK3).
  TextStyle number(
    double size, {
    Color? color,
    FontWeight weight = FontWeight.w600,
  }) => TextStyle(
    fontFamily: numberFont,
    fontSize: size,
    fontWeight: weight,
    height: 1.1,
    color: color ?? text,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// Kleine Überschrift eines Moduls in Grossbuchstaben («LOOP», «TEMPO»).
  TextStyle label({Color? color}) => TextStyle(
    fontFamily: textFont,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.1,
    color: color ?? muted,
  );

  @override
  WsTheme copyWith() => this;

  @override
  WsTheme lerp(WsTheme? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return WsTheme(
      bg: c(bg, other.bg),
      panel: c(panel, other.panel),
      panel2: c(panel2, other.panel2),
      border: c(border, other.border),
      text: c(text, other.text),
      muted: c(muted, other.muted),
      amber: c(amber, other.amber),
      amberSoft: c(amberSoft, other.amberSoft),
      onAmber: c(onAmber, other.onAmber),
      blue: c(blue, other.blue),
      wave: c(wave, other.wave),
      led: c(led, other.led),
      record: c(record, other.record),
      shadow: c(shadow, other.shadow),
    );
  }
}

ThemeData woodshedTheme(Brightness brightness) {
  final ws = brightness == Brightness.dark ? WsTheme.dark : WsTheme.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: ws.amber,
    onPrimary: ws.onAmber,
    secondary: ws.blue,
    onSecondary: ws.bg,
    error: ws.record,
    onError: ws.panel,
    surface: ws.panel,
    onSurface: ws.text,
    onSurfaceVariant: ws.muted,
    surfaceContainerHighest: ws.panel2,
    surfaceContainerHigh: ws.panel2,
    surfaceContainer: ws.panel,
    surfaceContainerLow: ws.panel,
    outline: ws.border,
    outlineVariant: ws.border,
    shadow: ws.shadow,
  );
  final base = ThemeData(
    colorScheme: scheme,
    brightness: brightness,
    fontFamily: textFont,
    scaffoldBackgroundColor: ws.bg,
    canvasColor: ws.panel,
    dividerColor: ws.border,
    extensions: [ws],
  );
  return base.copyWith(
    dividerTheme: DividerThemeData(color: ws.border, space: 1, thickness: 1),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? ws.amber : ws.panel2,
      ),
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? ws.onAmber : ws.muted,
      ),
      trackOutlineColor: WidgetStatePropertyAll(ws.border),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: ws.amber,
      inactiveTrackColor: ws.border,
      thumbColor: ws.text,
      overlayColor: ws.amberSoft,
    ),
    dialogTheme: DialogThemeData(backgroundColor: ws.panel),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: ws.panel),
    drawerTheme: DrawerThemeData(backgroundColor: ws.panel),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: ws.panel2,
        border: Border.all(color: ws.border),
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: TextStyle(color: ws.text, fontSize: 12),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: ws.amber,
      linearTrackColor: ws.border,
    ),
  );
}

// MARK: Grössen (#30/AK4) und Touch-Ziele (#30/AK8)

/// Grösse nach Fensterbreite in logischen Pixeln.
enum WsSize {
  /// < 600: einspaltig, Bibliothek als eigene Seite.
  phone,

  /// 600–1000: Bibliothek einblendbar, zwei Spalten.
  tablet,

  /// > 1000: feste Bibliothek links, drei Module nebeneinander.
  desktop;

  static const phoneMax = 600.0, tabletMax = 1000.0;

  static WsSize forWidth(double width) => width > tabletMax
      ? desktop
      : width >= phoneMax
      ? tablet
      : phone;
}

bool isDesktopPlatform(TargetPlatform p) =>
    p == TargetPlatform.macOS ||
    p == TargetPlatform.windows ||
    p == TargetPlatform.linux;

bool isApplePlatform(TargetPlatform p) =>
    p == TargetPlatform.macOS || p == TargetPlatform.iOS;

/// Masse einer Grösse auf einer Plattform. Liegt über dem Inhalt als [WsLayout].
@immutable
class WsMetrics {
  const WsMetrics(this.size, this.platform);

  final WsSize size;
  final TargetPlatform platform;

  bool get touch => size != WsSize.desktop;

  /// Kleinstes Touch-Ziel: 44 × 44 pt (iOS), 48 × 48 dp (Android und übrige), am Desktop 32.
  double get target => !touch
      ? 32
      : platform == TargetPlatform.iOS
      ? 44
      : 48;

  /// Schriftgrösse für Fliesstext.
  double get body => switch (size) {
    WsSize.desktop => 13,
    WsSize.tablet => 15,
    WsSize.phone => 14,
  };

  double get radius => touch ? 12 : 8;
  double get gap => touch ? WsSpace.l : WsSpace.m;
  double get pad => touch ? WsSpace.l : 14;

  /// Tempo ist das grösste Zahlenelement (#30/AK7).
  double get tempo => switch (size) {
    WsSize.desktop => 48,
    WsSize.tablet => 60,
    WsSize.phone => 52,
  };
  double get bpm => switch (size) {
    WsSize.desktop => 40,
    WsSize.tablet => 40,
    WsSize.phone => 26,
  };
  double get loopTimes => switch (size) {
    WsSize.desktop => 20,
    WsSize.tablet => 26,
    WsSize.phone => 18,
  };
  double get clock => switch (size) {
    WsSize.desktop => 22,
    WsSize.tablet => 18,
    WsSize.phone => 14,
  };
  double get detailHeight => switch (size) {
    WsSize.desktop => 200,
    WsSize.tablet => 240,
    WsSize.phone => 130,
  };
  double get overviewHeight => switch (size) {
    WsSize.desktop => 22,
    WsSize.tablet => 26,
    WsSize.phone => 16,
  };

  /// Kantenlänge der Marker S und E (sichtbar); die Griff-Fläche ist mindestens [target].
  double get markerSize => touch ? target : 24;
}

/// Gibt die aktuellen [WsMetrics] an den Inhalt weiter.
class WsLayout extends InheritedWidget {
  const WsLayout({super.key, required this.metrics, required super.child});
  final WsMetrics metrics;

  /// Ohne umgebendes [WsLayout] gilt Desktop.
  static WsMetrics of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WsLayout>()?.metrics ??
      WsMetrics(WsSize.desktop, Theme.of(context).platform);

  @override
  bool updateShouldNotify(WsLayout old) => old.metrics != metrics;
}

// MARK: Tastatur (#30/AK9)

/// Ist eine Tastatur da? Am Desktop immer; auf iPhone/iPad und Android, sobald eine Taste kam.
class KeyboardPresence extends ValueNotifier<bool> {
  KeyboardPresence._() : super(false) {
    attach();
  }

  static final instance = KeyboardPresence._();

  /// Auf Tastendrücke horchen (mehrfach aufrufbar, z. B. beim Aufbau des Hauptfensters).
  void attach() {
    HardwareKeyboard.instance
      ..removeHandler(_onKey)
      ..addHandler(_onKey);
  }

  bool _onKey(KeyEvent e) {
    if (e is KeyDownEvent) value = true;
    return false;
  }

  static bool available(TargetPlatform p) =>
      isDesktopPlatform(p) || instance.value;
}

/// Beschriftung eines Kürzels: ⌘ auf macOS (und iPad), Ctrl auf Windows und Linux.
String shortcutLabel(
  TargetPlatform platform,
  String key, {
  bool command = false,
  bool shift = false,
}) {
  if (!command) return key;
  return isApplePlatform(platform)
      ? '${shift ? '⇧' : ''}⌘$key'
      : 'Ctrl+${shift ? 'Shift+' : ''}$key';
}

/// Kürzel-Badge, nur sichtbar mit Tastatur.
class ShortcutBadge extends StatelessWidget {
  const ShortcutBadge(
    this.keyLabel, {
    super.key,
    this.command = false,
    this.shift = false,
  });

  final String keyLabel;
  final bool command, shift;

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    return ValueListenableBuilder<bool>(
      valueListenable: KeyboardPresence.instance,
      builder: (context, _, _) {
        if (!KeyboardPresence.available(platform)) {
          return const SizedBox.shrink();
        }
        final ws = WsTheme.of(context);
        return Text(
          shortcutLabel(platform, keyLabel, command: command, shift: shift),
          key: const Key('shortcutBadge'),
          style: ws.number(11, color: ws.muted, weight: FontWeight.w500),
        );
      },
    );
  }
}

// MARK: Bausteine

/// Fläche eines Moduls: Karte mit Rahmen.
class WsPanel extends StatelessWidget {
  const WsPanel({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final ws = WsTheme.of(context);
    final m = WsLayout.of(context);
    return Container(
      padding: padding ?? EdgeInsets.all(m.pad),
      decoration: BoxDecoration(
        color: ws.panel,
        border: Border.all(color: ws.border),
        borderRadius: BorderRadius.circular(m.radius),
      ),
      child: child,
    );
  }
}

/// Karte: Modul mit untereinander angeordnetem Inhalt.
class WsCard extends StatelessWidget {
  const WsCard({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => WsPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: WsSpace.m,
      children: children,
    ),
  );
}

/// Kopf eines Moduls: Überschrift in Grossbuchstaben, rechts Kürzel, Schalter oder anderes.
class CardHeader extends StatelessWidget {
  const CardHeader({
    super.key,
    required this.title,
    this.icon,
    this.value,
    this.onChanged,
    this.trailing,
    this.color,
    this.tooltip,
  });

  /// Erklärung zur Überschrift (Hover bzw. langes Drücken).
  final String? tooltip;
  final IconData? icon;
  final String title;
  final bool? value;
  final ValueChanged<bool>? onChanged;
  final Widget? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ws = WsTheme.of(context);
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Tooltip(
              message: tooltip ?? '',
              child: Text(
                title.toUpperCase(),
                style: ws.label(color: color),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        ?trailing,
        if (value != null)
          ExcludeFocus(
            child: Switch(
              key: Key('switch:$title'),
              value: value!,
              onChanged: onChanged,
            ),
          ),
      ],
    );
  }
}

/// Inhalt eines ausgeschalteten Moduls: abgeblendet (45 %) und nicht bedienbar.
class Dimmed extends StatelessWidget {
  const Dimmed({super.key, required this.enabled, required this.child});
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: enabled ? 1 : 0.45,
    child: IgnorePointer(ignoring: !enabled, child: child),
  );
}

/// Kleiner, gedämpfter Hinweistext.
class HintText extends StatelessWidget {
  const HintText(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(fontSize: 12, color: WsTheme.of(context).muted),
  );
}

/// Knopf mit Rahmen; [selected] hebt ihn in Bernstein hervor. Mindesthöhe = Touch-Ziel der Grösse.
class BorderedButton extends StatelessWidget {
  const BorderedButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.selected = false,
    this.tooltip,
    this.iconOnly = false,
    this.shortcut,
    this.mono = false,
    this.expand = false,
  });

  /// Nur das Symbol zeigen (schmaler Platz); [label] dient dann als Tooltip.
  final bool iconOnly;
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool selected;
  final String? tooltip;

  /// Kürzel-Badge rechts im Knopf.
  final ShortcutBadge? shortcut;

  /// Beschriftung in der Zahlenschrift.
  final bool mono;

  /// Ganze verfügbare Breite nutzen.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final ws = WsTheme.of(context);
    final m = WsLayout.of(context);
    final style = TextButton.styleFrom(
      foregroundColor: ws.text,
      backgroundColor: selected ? ws.amberSoft : ws.panel2,
      disabledForegroundColor: ws.muted,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      minimumSize: Size(m.target, m.target),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: mono
          ? ws.number(m.touch ? 14 : 12, weight: FontWeight.w500)
          : TextStyle(
              fontFamily: textFont,
              fontSize: m.touch ? 15 : 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: selected ? ws.amber : ws.border),
        borderRadius: BorderRadius.circular(m.touch ? 8 : 6),
      ),
    );
    final content = iconOnly && icon != null
        ? Icon(icon, size: 16, semanticLabel: label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              if (icon != null) Icon(icon, size: 16),
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
              ?shortcut,
            ],
          );
    final button = TextButton(
      onPressed: onPressed,
      style: style,
      child: expand ? Center(child: content) : content,
    );
    // Knöpfe nehmen keinen Tastaturfokus, damit Leertaste und Pfeile immer die Kürzel auslösen.
    final tip = tooltip ?? (iconOnly ? label : null);
    return ExcludeFocus(
      child: tip == null ? button : Tooltip(message: tip, child: button),
    );
  }
}

/// Spalte von Modulen mit Abstand, scrollbar.
class CardColumn extends StatelessWidget {
  const CardColumn({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final m = WsLayout.of(context);
    return ListView(
      padding: EdgeInsets.all(m.gap),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: m.gap,
          children: children,
        ),
      ],
    );
  }
}
