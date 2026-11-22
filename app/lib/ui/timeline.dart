// Zeitleiste des Designs «Studio» (#30): Wellenform als Übersicht und Ausschnitt mit Loop-Bereich,
// ziehbaren Markern S und E (#22) und Playhead. Ohne Wellenform-Daten ein schlichter Fortschrittsbalken.
import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:wp_core/wp_types.dart';

import '../time_format.dart';
import 'style.dart';

/// Liefert die Wellenform von [start] bis [end] Sekunden in [count] Abschnitten oder null.
typedef WaveformQuery = WpWaveform? Function(
  double start,
  double end,
  int count,
);

/// Zeitleiste: mit Wellenform Übersicht + Ausschnitt, sonst [ProgressScrubber].
class Timeline extends StatefulWidget {
  const Timeline({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.loop,
    this.onLoopStart,
    this.onLoopEnd,
    this.waveform,
    this.trackKey,
  });

  final double position, duration;

  /// Aktiver Loop (Anfang, Ende) oder null.
  final (double, double)? loop;
  final ValueChanged<double> onSeek;
  final ValueChanged<double>? onLoopStart, onLoopEnd;
  final WaveformQuery? waveform;

  /// Wechselt mit dem Titel; leert den Zwischenspeicher der Wellenform.
  final Object? trackKey;

  @override
  State<Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<Timeline> {
  final _cache = <(double, double, int), WpWaveform>{};

  /// Ausschnitt bleibt beim Ziehen eines Markers stehen, damit der Marker nicht wegspringt.
  (double, double)? _frozen;

  @override
  void didUpdateWidget(Timeline old) {
    super.didUpdateWidget(old);
    if (old.trackKey != widget.trackKey || old.duration != widget.duration) {
      _cache.clear();
      _frozen = null;
    }
  }

  WpWaveform? _query(double a, double b, int count) {
    final q = widget.waveform;
    if (q == null || count <= 0 || b <= a) return null;
    final key = (a, b, count);
    final hit = _cache[key];
    if (hit != null) return hit;
    final w = q(a, b, count);
    if (w != null) {
      if (_cache.length > 12) _cache.clear();
      _cache[key] = w;
    }
    return w;
  }

  /// Ausschnitt: um den Loop herum, sonst die 30-Sekunden-Seite mit dem Playhead.
  (double, double) _window() {
    final d = widget.duration;
    final loop = widget.loop;
    if (loop != null) {
      final pad = max(1.0, (loop.$2 - loop.$1) * 0.25);
      return (max(0, loop.$1 - pad), min(d, loop.$2 + pad));
    }
    final span = min(d, 30.0);
    var a = (widget.position / span).floor() * span;
    if (a + span > d) a = max(0, d - span);
    return (a, a + span);
  }

  ValueChanged<double>? _freezing(ValueChanged<double>? f) => f == null
      ? null
      : (v) {
          _frozen ??= _window();
          f(v);
        };

  @override
  Widget build(BuildContext context) {
    final m = WsLayout.of(context);
    final ws = WsTheme.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final d = widget.duration;
        final overview = d > 0 ? _query(0, d, max(1, w ~/ 3)) : null;
        if (overview == null) {
          return ProgressScrubber(
            key: const Key('timeline:progress'),
            position: widget.position,
            duration: d,
            loop: widget.loop,
            onSeek: widget.onSeek,
            onLoopStart: widget.onLoopStart,
            onLoopEnd: widget.onLoopEnd,
          );
        }
        final win = _frozen ?? _window();
        final detail = _query(win.$1, win.$2, max(1, w ~/ 3));
        return Column(
          key: const Key('timeline:waveform'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: WsSpace.s,
          children: [
            _Overview(
              wave: overview,
              duration: d,
              position: widget.position,
              loop: widget.loop,
              window: win,
              height: m.overviewHeight,
              onSeek: widget.onSeek,
            ),
            if (m.size != WsSize.phone)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var i = 0; i < 6; i++)
                    Text(
                      formatTime(win.$1 + (win.$2 - win.$1) * i / 5),
                      style: ws.number(
                        11,
                        color: ws.muted,
                        weight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            if (detail != null)
              Listener(
                onPointerUp: (_) => setState(() => _frozen = null),
                onPointerCancel: (_) => setState(() => _frozen = null),
                child: _Lane(
                  key: const Key('waveformDetail'),
                  start: win.$1,
                  end: win.$2,
                  height: m.detailHeight,
                  position: widget.position,
                  loop: widget.loop,
                  onSeek: widget.onSeek,
                  onLoopStart: _freezing(widget.onLoopStart),
                  onLoopEnd: _freezing(widget.onLoopEnd),
                  wave: detail,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Ganzer Titel klein, mit Rahmen um den Ausschnitt; Tippen springt.
class _Overview extends StatelessWidget {
  const _Overview({
    required this.wave,
    required this.duration,
    required this.position,
    required this.loop,
    required this.window,
    required this.height,
    required this.onSeek,
  });

  final WpWaveform wave;
  final double duration, position, height;
  final (double, double)? loop;
  final (double, double) window;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    final ws = WsTheme.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        double x(double t) => duration > 0 ? w * (t / duration) : 0;
        return GestureDetector(
          key: const Key('waveformOverview'),
          behavior: HitTestBehavior.opaque,
          onTapUp: (e) =>
              onSeek((e.localPosition.dx / w).clamp(0.0, 1.0) * duration),
          child: SizedBox(
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: WavePainter(
                      wave: wave,
                      start: 0,
                      end: duration,
                      loop: loop,
                      color: ws.wave,
                      loopColor: ws.amber,
                      gap: 1,
                    ),
                  ),
                ),
                Positioned(
                  left: x(window.$1),
                  width: max(4, x(window.$2) - x(window.$1)),
                  top: -2,
                  bottom: -2,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: ws.text),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                Positioned(
                  left: x(position) - 0.5,
                  top: 0,
                  bottom: 0,
                  width: 1,
                  child: ColoredBox(color: ws.text),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Zeichnet Balken aus Minimum und Maximum je Abschnitt; im Loop in Bernstein.
class WavePainter extends CustomPainter {
  WavePainter({
    required this.wave,
    required this.start,
    required this.end,
    required this.loop,
    required this.color,
    required this.loopColor,
    this.gap = 1,
  });

  final WpWaveform wave;
  final double start, end, gap;
  final (double, double)? loop;
  final Color color, loopColor;

  @override
  void paint(Canvas canvas, Size size) {
    final n = wave.length;
    if (n == 0) return;
    final bw = size.width / n;
    final mid = size.height / 2;
    final normal = Paint()..color = color;
    final inLoop = Paint()..color = loopColor;
    for (var i = 0; i < n; i++) {
      final amp = max(wave.max[i].abs(), wave.min[i].abs()).clamp(0.0, 1.0);
      final h = max(2.0, amp * size.height);
      final t = start + (end - start) * (i + 0.5) / n;
      final l = loop;
      final p = l != null && t >= l.$1 && t < l.$2 ? inLoop : normal;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * bw, mid - h / 2, max(1.0, bw - gap), h),
          const Radius.circular(1),
        ),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(WavePainter old) =>
      old.wave != wave ||
      old.loop != loop ||
      old.color != color ||
      old.loopColor != loopColor ||
      old.start != start ||
      old.end != end;
}

/// Ausschnitt [start, end]: Wellenform, Loop-Bereich, Marker S/E und Playhead.
class _Lane extends StatefulWidget {
  const _Lane({
    super.key,
    required this.start,
    required this.end,
    required this.height,
    required this.position,
    required this.loop,
    required this.onSeek,
    required this.wave,
    this.onLoopStart,
    this.onLoopEnd,
  });

  final double start, end, height, position;
  final (double, double)? loop;
  final ValueChanged<double> onSeek;
  final ValueChanged<double>? onLoopStart, onLoopEnd;
  final WpWaveform wave;

  @override
  State<_Lane> createState() => _LaneState();
}

class _LaneState extends State<_Lane> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final ws = WsTheme.of(context);
    final m = WsLayout.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final span = widget.end - widget.start;
        double xOf(double t) =>
            span > 0 ? w * ((t - widget.start) / span).clamp(0.0, 1.0) : 0;
        double timeAt(double x) =>
            widget.start + (w <= 0 ? 0 : (x / w).clamp(0.0, 1.0)) * span;
        final loop = widget.loop;
        final x = xOf(_drag ?? widget.position);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (e) =>
              setState(() => _drag = timeAt(e.localPosition.dx)),
          onHorizontalDragUpdate: (e) =>
              setState(() => _drag = timeAt(e.localPosition.dx)),
          onHorizontalDragEnd: (_) {
            if (_drag != null) widget.onSeek(_drag!);
            setState(() => _drag = null);
          },
          onTapUp: (e) => widget.onSeek(timeAt(e.localPosition.dx)),
          child: SizedBox(
            height: widget.height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: WavePainter(
                      wave: widget.wave,
                      start: widget.start,
                      end: widget.end,
                      loop: loop,
                      color: ws.wave,
                      loopColor: ws.amber,
                      gap: 1,
                    ),
                  ),
                ),
                if (loop != null)
                  Positioned(
                    key: const Key('loopRange'),
                    left: xOf(loop.$1),
                    width: max(2, xOf(loop.$2) - xOf(loop.$1)),
                    top: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: ws.amberSoft,
                        border: Border.symmetric(
                          vertical: BorderSide(color: ws.amber, width: 2),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  key: const Key('playhead'),
                  left: x - 1,
                  top: 0,
                  bottom: 0,
                  width: 2,
                  child: ColoredBox(color: ws.text),
                ),
                if (loop != null) ...[
                  LoopMarker(
                    label: 'S',
                    markerKey: const Key('loopStartMarker'),
                    x: xOf(loop.$1),
                    top: m.touch ? null : -2,
                    bottom: m.touch ? -6 : null,
                    timeAt: timeAt,
                    onDrag: widget.onLoopStart,
                  ),
                  LoopMarker(
                    label: 'E',
                    markerKey: const Key('loopEndMarker'),
                    x: xOf(loop.$2),
                    top: m.touch ? null : -2,
                    bottom: m.touch ? -6 : null,
                    timeAt: timeAt,
                    onDrag: widget.onLoopEnd,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Marker S oder E in Bernstein; mit [onDrag] ziehbar. Griff-Fläche mindestens ein Touch-Ziel.
class LoopMarker extends StatelessWidget {
  const LoopMarker({
    super.key,
    required this.label,
    required this.markerKey,
    required this.x,
    required this.timeAt,
    this.onDrag,
    this.top,
    this.bottom,
  });

  final String label;
  final Key markerKey;
  final double x;
  final double? top, bottom;
  final double Function(double localX) timeAt;
  final ValueChanged<double>? onDrag;

  @override
  Widget build(BuildContext context) {
    final ws = WsTheme.of(context);
    final m = WsLayout.of(context);
    final grip = max(m.target, m.markerSize);
    final visible = m.markerSize;
    final visibleH = m.touch ? visible : visible * 0.8;
    double timeOf(DragUpdateDetails e) {
      // Der Marker liegt direkt im Stack der Spur; dessen Koordinaten sind die der Spur.
      final parent = (context.findRenderObject() as RenderBox?)?.parent;
      final local = parent is RenderBox
          ? parent.globalToLocal(e.globalPosition).dx
          : 0.0;
      return timeAt(local);
    }

    return Positioned(
      key: markerKey,
      left: x - grip / 2,
      top: top == null ? null : top! - (grip - visibleH) / 2,
      bottom: bottom == null ? null : bottom! - (grip - visibleH) / 2,
      child: MouseRegion(
        cursor: onDrag == null
            ? MouseCursor.defer
            : SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: onDrag == null
              ? null
              : (e) => onDrag!(timeOf(e)),
          child: SizedBox(
            width: grip,
            height: grip,
            child: Center(
              child: Container(
                width: visible,
                height: visibleH,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ws.amber,
                  borderRadius: BorderRadius.circular(m.touch ? 10 : 4),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: ws.onAmber,
                    fontWeight: FontWeight.w700,
                    fontSize: m.touch ? 16 : 12,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Schlichter Fortschrittsbalken (ohne Wellenform-Daten): Tippen/Ziehen springt, Loop in Bernstein
/// mit ziehbaren Markern S und E.
class ProgressScrubber extends StatefulWidget {
  const ProgressScrubber({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.loop,
    this.onLoopStart,
    this.onLoopEnd,
  });

  final double position, duration;
  final (double, double)? loop;
  final ValueChanged<double> onSeek;

  /// Ziehen der Loop-Marker; wird laufend gerufen, damit die Zeitanzeige live mitgeht.
  final ValueChanged<double>? onLoopStart, onLoopEnd;

  @override
  State<ProgressScrubber> createState() => _ProgressScrubberState();
}

class _ProgressScrubberState extends State<ProgressScrubber> {
  double? _drag;

  double _timeAt(double x, double width) =>
      width <= 0 ? 0 : (x / width).clamp(0.0, 1.0) * widget.duration;

  @override
  Widget build(BuildContext context) {
    final ws = WsTheme.of(context);
    final m = WsLayout.of(context);
    final height = max(24.0, m.target);
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth, d = widget.duration;
        double xOf(double t) => d > 0 ? w * (t / d).clamp(0.0, 1.0) : 0;
        final x = xOf(_drag ?? widget.position);
        final loop = d > 0 ? widget.loop : null;
        Widget bar(double left, double width, double h, Color color) =>
            Positioned(
              left: left,
              top: (height - h) / 2,
              child: Container(
                width: max(0, width),
                height: h,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(h / 2),
                ),
              ),
            );
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (e) =>
              setState(() => _drag = _timeAt(e.localPosition.dx, w)),
          onHorizontalDragUpdate: (e) =>
              setState(() => _drag = _timeAt(e.localPosition.dx, w)),
          onHorizontalDragEnd: (_) {
            if (_drag != null) widget.onSeek(_drag!);
            setState(() => _drag = null);
          },
          onTapUp: (e) => widget.onSeek(_timeAt(e.localPosition.dx, w)),
          child: SizedBox(
            height: height,
            width: w,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                bar(0, w, 6, ws.border),
                bar(0, x, 6, ws.muted),
                if (loop != null)
                  Positioned(
                    key: const Key('loopRange'),
                    left: xOf(loop.$1),
                    top: (height - 10) / 2,
                    child: Container(
                      width: max(3, xOf(loop.$2) - xOf(loop.$1)),
                      height: 10,
                      decoration: BoxDecoration(
                        color: ws.amberSoft,
                        border: Border.all(color: ws.amber),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                Positioned(
                  left: (x - 1).clamp(0, max(0, w - 2)),
                  top: 0,
                  bottom: 0,
                  width: 2,
                  child: ColoredBox(color: ws.text),
                ),
                if (loop != null) ...[
                  LoopMarker(
                    label: 'S',
                    markerKey: const Key('loopStartMarker'),
                    x: xOf(loop.$1),
                    top: (height - m.markerSize * (m.touch ? 1 : 0.8)) / 2,
                    timeAt: (lx) => _timeAt(lx, w),
                    onDrag: widget.onLoopStart,
                  ),
                  LoopMarker(
                    label: 'E',
                    markerKey: const Key('loopEndMarker'),
                    x: xOf(loop.$2),
                    top: (height - m.markerSize * (m.touch ? 1 : 0.8)) / 2,
                    timeAt: (lx) => _timeAt(lx, w),
                    onDrag: widget.onLoopEnd,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
