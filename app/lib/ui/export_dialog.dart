// #141: «Export as MP3 …» for one or several tracks: the target folder, a dialog with progress and
// «Cancel» while it runs, and the result with every track that failed.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../app/app_controller.dart';
import '../app/track_export.dart';
import 'messages.dart';
import 'style.dart';

/// The menu item; null where the export is not offered (not on the Mac).
Widget? exportMenuItem(
  BuildContext context,
  AppController c,
  List<String> ids, {
  VoidCallback? done,
}) {
  if (c.mp3 == null) return null;
  return MenuItemButton(
    key: const Key('exportTracks'),
    leadingIcon: const Icon(WsIcons.share, size: 16),
    onPressed: () async {
      await exportTracks(context, c, ids);
      done?.call();
    },
    child: Text(context.l10n.exportEllipsis),
  );
}

/// #141/AK4: asks for the folder, exports [ids] in the order given and shows the result.
Future<ExportResult?> exportTracks(
  BuildContext context,
  AppController c,
  List<String> ids,
) async {
  final exporter = c.exporter;
  final tracks = [for (final id in ids) ?c.library.track(id)];
  if (exporter == null || tracks.isEmpty) return null;
  final l = context.l10n;
  final folder = await c.files.pickFolder(l.exportHere);
  if (folder == null || !context.mounted) return null;
  final progress = ValueNotifier<(int, double)>((0, 0));
  final cancel = Completer<void>();
  final running = exporter.run(
    tracks,
    folder,
    cancel: cancel.future,
    progress: (i, _, f) => progress.value = (i, f),
  );
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ExportProgress(
        tracks: [for (final t in tracks) t.title],
        progress: progress,
        onCancel: () {
          if (!cancel.isCompleted) cancel.complete();
        },
      ),
    ),
  );
  final result = await running;
  progress.dispose();
  if (!context.mounted) return result;
  Navigator.of(context, rootNavigator: true).pop();
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('exportResult'),
      title: Text(l.exportResultTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result.cancelled
                  ? l.exportCancelled(result.exported.length)
                  : l.exportDone(result.exported.length),
            ),
            for (final f in result.failures) ...[
              const SizedBox(height: 8),
              Text(
                exportProblemText(l, f),
                key: Key('exportFailed:${f.track.id}'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.ok),
        ),
      ],
    ),
  );
  return result;
}

/// #141/AK13: why [f] failed, with its title.
String exportProblemText(AppLocalizations l, ExportFailure f) =>
    switch (f.problem) {
      ExportProblem.notLoaded => l.exportFailedNotLoaded(f.track.title),
      ExportProblem.format => l.exportFailedFormat(f.track.title),
      ExportProblem.encoderMissing => l.exportFailedEncoder(f.track.title),
      ExportProblem.write => l.exportFailedWrite(f.track.title),
      ExportProblem.failed => l.exportFailed(f.track.title),
    };

class _ExportProgress extends StatelessWidget {
  const _ExportProgress({
    required this.tracks,
    required this.progress,
    required this.onCancel,
  });

  final List<String> tracks;
  final ValueListenable<(int, double)> progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      key: const Key('exportProgress'),
      title: Text(l.exportTitle(tracks.length)),
      content: ValueListenableBuilder<(int, double)>(
        valueListenable: progress,
        builder: (context, p, _) {
          final (i, f) = p;
          final index = i.clamp(0, tracks.length - 1);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.exportProgress(index + 1, tracks.length, tracks[index])),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: ((i + f.clamp(0.0, 1.0)) / tracks.length).clamp(
                  0.0,
                  1.0,
                ),
              ),
            ],
          );
        },
      ),
      actions: [
        TextButton(
          key: const Key('exportCancel'),
          onPressed: onCancel,
          child: Text(l.cancel),
        ),
      ],
    );
  }
}
