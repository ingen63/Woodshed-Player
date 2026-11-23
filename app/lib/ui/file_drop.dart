// #121: targets for files dragged in from outside the app (Finder, file explorer). A target marks its
// area with [FileDropRegion]; [fileDropTargetAt] finds the innermost one under a position of the window.
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../app/file_drop.dart';

/// Marks [child] as the place that takes files dropped on it.
class FileDropRegion extends StatelessWidget {
  const FileDropRegion({super.key, required this.target, required this.child});

  /// Null: the child takes no files (they go to the target around it, if any).
  final FileDropTarget? target;
  final Widget child;

  @override
  Widget build(BuildContext context) => target == null
      ? child
      : MetaData(
          metaData: target,
          behavior: HitTestBehavior.translucent,
          child: child,
        );
}

/// The innermost [FileDropRegion] at [position] (logical pixels) of the app's view; null if none.
FileDropTarget? fileDropTargetAt(Offset position) {
  final binding = WidgetsBinding.instance;
  final view = binding.platformDispatcher.implicitView;
  if (view == null) return null;
  final result = HitTestResult();
  binding.hitTestInView(result, position, view.viewId);
  for (final entry in result.path) {
    if (entry.target case RenderMetaData(:final FileDropTarget metaData)) {
      return metaData;
    }
  }
  return null;
}
