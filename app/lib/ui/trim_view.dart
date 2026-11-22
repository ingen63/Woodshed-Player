// #116: trimming the start and end of a track. The view shows the waveform of the whole track with two
// handles for the new start and end (dragged or typed as mm:ss.d), plays the part between them and asks
// before the file is cut, because the parts cut off are deleted.
import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:wp_core/wp_types.dart';

import '../app/app_controller.dart';
import '../library/library.dart';
import '../time_format.dart';
import 'messages.dart';
import 'style.dart';
import 'timeline.dart';

/// #116/AK1: loads [t] if needed and opens the trim view for it.
Future<void> openTrimView(
  BuildContext context,
  AppController c,
  Track t,
) async {
  if (!Library.trimmable(t)) return;
  if (!await c.openForTrim(t) || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => TrimView(controller: c, trackId: t.id),
  );
  c.player.stopPreview();
}

/// #116/AK1: the trim view of the loaded track [trackId].
class TrimView extends StatefulWidget {
  const TrimView({super.key, required this.controller, required this.trackId});
  final AppController controller;
  final String trackId;

  @override
  State<TrimView> createState() => _TrimViewState();
}

class _TrimViewState extends State<TrimView> {
  AppController get c => widget.controller;
  double get duration => c.player.duration;

  late double _start = 0, _end = duration;
  late final _startField = TextEditingController(text: formatTimePrecise(0));
  late final _endField = TextEditingController(
    text: formatTimePrecise(duration),
  );
  bool _startInvalid = false, _endInvalid = false;

  /// #116/AK7: at least 1 s remains and the end lies after the start.
  bool get _valid =>
      _end - _start >= WpTrimmed.minSeconds && !_startInvalid && !_endInvalid;

  @override
  void initState() {
    super.initState();
    c.player.addListener(_changed);
    c.addListener(_changed);
  }

  @override
  void dispose() {
    c.player.removeListener(_changed);
    c.removeListener(_changed);
    _startField.dispose();
    _endField.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Moves a bound: the start stays at least 1 s before the end and the end 1 s after the start, both
  /// within the track (where the track is shorter than 1 s nothing can be kept).
  void _set({double? start, double? end}) {
    final d = duration;
    setState(() {
      if (start != null) {
        _start = start.clamp(0.0, max(0.0, _end - WpTrimmed.minSeconds));
        _startField.text = formatTimePrecise(_start);
        _startInvalid = false;
      }
      if (end != null) {
        _end = end.clamp(min(d, _start + WpTrimmed.minSeconds), d);
        _endField.text = formatTimePrecise(_end);
        _endInvalid = false;
      }
    });
  }

  /// A typed time: taken if it is a time within the track, else the field is marked.
  void _typed(String text, {required bool start}) {
    final t = parseTime(text);
    final ok =
        t != null &&
        t <= duration &&
        (start
            ? _end - t >= WpTrimmed.minSeconds
            : t - _start >= WpTrimmed.minSeconds);
    if (!ok) {
      setState(() => start ? _startInvalid = true : _endInvalid = true);
      return;
    }
    start ? _set(start: t) : _set(end: t);
  }

  void _togglePreview() {
    final p = c.player;
    if (p.preview != null) {
      p.stopPreview();
    } else {
      p.previewRange(_start, _end);
    }
  }

  Future<void> _apply() async {
    final l = context.l10n;
    final title = c.library.track(widget.trackId)?.title ?? '';
    c.player.stopPreview();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.trimConfirmTitle),
        content: Text(
          l.trimConfirmText(
            title,
            formatTimePrecise(_start),
            formatTimePrecise(_end),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('trimCancel'),
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          TextButton(
            key: const Key('trimConfirm'),
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l.trimConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final next = await c.trimTrack(widget.trackId, _start, _end);
    if (next != null && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ws = WsTheme.of(context);
    final track = c.library.track(widget.trackId);
    final busy = c.trimming != null;
    final previewing = c.player.preview != null;
    return AlertDialog(
      key: const Key('trimView'),
      title: Text(l.trimTitle(track?.title ?? '')),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TrimWave(
              duration: duration,
              start: _start,
              end: _end,
              position: c.player.position,
              wave: (count) => c.player.waveform(0, duration, count),
              onStart: (t) => _set(start: t),
              onEnd: (t) => _set(end: t),
            ),
            const SizedBox(height: WsSpace.m),
            Row(
              spacing: WsSpace.m,
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('trimStartField'),
                    controller: _startField,
                    enabled: !busy,
                    decoration: InputDecoration(
                      labelText: l.trimStart,
                      hintText: l.trimTimeHint,
                      errorText: _startInvalid ? l.trimTimeHint : null,
                    ),
                    onSubmitted: (v) => _typed(v, start: true),
                    onTapOutside: (_) => _typed(_startField.text, start: true),
                  ),
                ),
                Expanded(
                  child: TextField(
                    key: const Key('trimEndField'),
                    controller: _endField,
                    enabled: !busy,
                    decoration: InputDecoration(
                      labelText: l.trimEnd,
                      hintText: l.trimTimeHint,
                      errorText: _endInvalid ? l.trimTimeHint : null,
                    ),
                    onSubmitted: (v) => _typed(v, start: false),
                    onTapOutside: (_) => _typed(_endField.text, start: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: WsSpace.s),
            Text(
              _valid
                  ? l.trimRemaining(formatTimePrecise(_end - _start))
                  : l.trimRangeInvalid,
              key: const Key('trimRemaining'),
              style: TextStyle(
                color: _valid ? ws.muted : Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          key: const Key('trimPreview'),
          onPressed: busy || !_valid ? null : _togglePreview,
          icon: Icon(previewing ? WsIcons.pause : WsIcons.play, size: 16),
          label: Text(previewing ? l.trimStopPreview : l.trimPreview),
        ),
        TextButton(
          key: const Key('trimClose'),
          onPressed: busy ? null : () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        TextButton(
          key: const Key('trimApply'),
          onPressed: busy || !_valid ? null : _apply,
          child: Text(busy ? l.trimming : l.trimApply),
        ),
      ],
    );
  }
}

/// Waveform of the whole track: the part kept in amber, the parts cut off grey, a handle at the start and
/// the end; a drag moves the handle nearest to where it began.
class _TrimWave extends StatefulWidget {
  const _TrimWave({
    required this.duration,
    required this.start,
    required this.end,
    required this.position,
    required this.wave,
    required this.onStart,
    required this.onEnd,
  });

  final double duration, start, end, position;
  final WpWaveform? Function(int count) wave;
  final ValueChanged<double> onStart, onEnd;

  @override
  State<_TrimWave> createState() => _TrimWaveState();
}

class _TrimWaveState extends State<_TrimWave> {
  static const height = 96.0;
  bool? _draggingStart;
  WpWaveform? _wave;
  int _count = 0;
  Timer? _retry;

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  /// The waveform for [count] bars; in the browser it arrives shortly after loading, so it is asked again.
  WpWaveform? _waveFor(int count) {
    if (_wave != null && _count == count) return _wave;
    final w = widget.wave(count);
    if (w != null) {
      _wave = w;
      _count = count;
    } else {
      _retry ??= Timer(const Duration(milliseconds: 200), () {
        _retry = null;
        if (mounted) setState(() {});
      });
    }
    return w;
  }

  double _time(double x, double width) =>
      (x / width).clamp(0.0, 1.0) * widget.duration;

  @override
  Widget build(BuildContext context) {
    final ws = WsTheme.of(context);
    final l = context.l10n;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final d = widget.duration;
        double x(double t) => d > 0 ? w * t / d : 0;
        final wave = _waveFor(max(1, (w / 3).floor()));
        void drag(double dx, {bool begin = false}) {
          final t = _time(dx, w);
          if (begin) {
            _draggingStart = (t - widget.start).abs() <= (t - widget.end).abs();
          }
          (_draggingStart ?? true) ? widget.onStart(t) : widget.onEnd(t);
        }

        Widget handle(String key, double t, String label) => Positioned(
          key: Key(key),
          left: x(t) - 8,
          top: 0,
          bottom: 0,
          width: 16,
          child: Semantics(
            label: label,
            child: Center(
              child: Container(
                width: 3,
                decoration: BoxDecoration(
                  color: ws.amber,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        );

        return GestureDetector(
          key: const Key('trimWaveform'),
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (e) => drag(e.localPosition.dx, begin: true),
          onHorizontalDragUpdate: (e) => drag(e.localPosition.dx),
          onHorizontalDragEnd: (_) => _draggingStart = null,
          onTapUp: (e) => drag(e.localPosition.dx, begin: true),
          child: SizedBox(
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (wave != null)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: WavePainter(
                        wave: wave,
                        start: 0,
                        end: d,
                        loop: (widget.start, widget.end),
                        color: ws.wave,
                        loopColor: ws.amber,
                      ),
                    ),
                  )
                else
                  Positioned.fill(
                    child: Center(child: ColoredBox(color: ws.wave)),
                  ),
                // the parts cut off, dimmed
                Positioned(
                  left: 0,
                  width: x(widget.start),
                  top: 0,
                  bottom: 0,
                  child: ColoredBox(color: ws.bg.withValues(alpha: 0.5)),
                ),
                Positioned(
                  left: x(widget.end),
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: ColoredBox(color: ws.bg.withValues(alpha: 0.5)),
                ),
                Positioned(
                  left: x(widget.position.clamp(0, d)) - 0.5,
                  top: 0,
                  bottom: 0,
                  width: 1,
                  child: ColoredBox(color: ws.text),
                ),
                handle('trimStartHandle', widget.start, l.trimStart),
                handle('trimEndHandle', widget.end, l.trimEnd),
              ],
            ),
          ),
        );
      },
    );
  }
}
