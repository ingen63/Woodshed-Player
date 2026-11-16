// Erscheinungsbild wie in der alten SwiftUI-App (FEA-19).
import 'package:material_ui/material_ui.dart';

/// Akzentfarbe der alten App (sRGB 0 / 0,478 / 0,870).
const accentColor = Color.fromARGB(255, 0, 122, 222);

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
}

ThemeData woodshedTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: accentColor,
    brightness: brightness,
  ).copyWith(primary: accentColor, onPrimary: Colors.white);
  return ThemeData(
    colorScheme: scheme,
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? accentColor : null,
      ),
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : null,
      ),
    ),
  );
}

/// Verlauf der Akzentfarbe von oben links (30 %) nach unten rechts (6 %).
class AccentBackground extends StatelessWidget {
  const AccentBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    key: const Key('accentBackground'),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          accentColor.withValues(alpha: 0.30),
          accentColor.withValues(alpha: 0.06),
        ],
      ),
    ),
    child: child,
  );
}

/// Spalte der Karten: höchstens 760 pt breit, zentriert, 16 pt Abstand.
class CardColumn extends StatelessWidget {
  const CardColumn({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: 16),
                children[i],
              ],
            ],
          ),
        ),
      ),
    ],
  );
}

/// Karte mit 18 pt Innenabstand und Eckradius auf halbtransparentem Grund.
class WsCard extends StatelessWidget {
  const WsCard({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Kopfzeile einer Karte: Symbol, Überschrift, rechts der Schalter.
class CardHeader extends StatelessWidget {
  const CardHeader({
    super.key,
    required this.icon,
    required this.title,
    this.value,
    this.onChanged,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final bool? value;
  final ValueChanged<bool>? onChanged;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleMedium
        ?.copyWith(fontWeight: FontWeight.w600);
    return Row(
      children: [
        Icon(icon, size: 20, color: accentColor),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: style)),
        if (value != null)
          ExcludeFocus(
            child: Switch(
              key: Key('switch:$title'),
              value: value!,
              onChanged: onChanged,
            ),
          ),
        ?trailing,
      ],
    );
  }
}

/// Inhalt einer ausgeschalteten Karte: abgeblendet (45 %) und nicht bedienbar.
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

/// Kleiner, grauer Hinweistext unter dem Inhalt einer Karte.
class HintText extends StatelessWidget {
  const HintText(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// Knopf mit Rahmen wie `.bordered` in SwiftUI; [selected] färbt ihn in der Akzentfarbe.
class BorderedButton extends StatelessWidget {
  const BorderedButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.selected = false,
    this.tooltip,
    this.iconOnly = false,
  });

  /// Nur das Symbol zeigen (schmaler Platz); [label] dient dann als Tooltip.
  final bool iconOnly;
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool selected;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? accentColor : scheme.onSurface;
    final style = TextButton.styleFrom(
      foregroundColor: fg,
      backgroundColor: selected
          ? accentColor.withValues(alpha: 0.18)
          : scheme.onSurface.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      minimumSize: const Size(0, 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
    final button = iconOnly && icon != null
        ? TextButton(
            onPressed: onPressed,
            style: style,
            child: Icon(icon, size: 16, semanticLabel: label),
          )
        : icon == null
        ? TextButton(onPressed: onPressed, style: style, child: Text(label))
        : TextButton.icon(
            onPressed: onPressed,
            style: style,
            icon: Icon(icon, size: 16),
            label: Text(label),
          );
    // Knöpfe nehmen keinen Tastaturfokus, damit Leertaste und Pfeile immer die Kürzel auslösen.
    final tip = tooltip ?? (iconOnly ? label : null);
    return ExcludeFocus(
      child: tip == null ? button : Tooltip(message: tip, child: button),
    );
  }
}
