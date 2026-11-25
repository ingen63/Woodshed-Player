// #148: the help of the app, offline and in the UI language: a page of its own with the contents on the
// left and the section on the right (on the phone a list that opens a section), and the keyboard
// shortcuts in a dialog of their own. All texts come from the ARB files; nothing is loaded.
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'messages.dart';
import 'shortcut_table.dart';
import 'style.dart';

/// The sections of the help, in this order.
enum HelpSection {
  areas,
  player,
  library,
  practice,
  metronome,
  sync,
  appearance,
  recording,
  export,
  commandLine,
  web,
  shortcuts,
}

/// What this platform has, asked the same way as the features themselves (#148/AK13).
class HelpTopics {
  const HelpTopics({
    this.recording = false,
    this.export = false,
    this.commandLine = false,
    this.web = false,
    this.keyboard = false,
  });

  /// Recording and the switch «Armed»: only on the Mac (HomePage shows the recording button).
  final bool recording;

  /// Export as MP3: only where the core encodes MP3 ([AppController.mp3], the Mac).
  final bool export;

  /// The command line `woodshed`: where the platform has its socket (the Mac).
  final bool commandLine;

  /// Install, offline start and the audio cache: only in the browser.
  final bool web;

  /// A keyboard is there (the same rule as the shortcut badges).
  final bool keyboard;

  /// The sections shown here.
  List<HelpSection> get sections => [
    for (final s in HelpSection.values)
      if (switch (s) {
        HelpSection.recording => recording,
        HelpSection.export => export,
        HelpSection.commandLine => commandLine,
        HelpSection.web => web,
        HelpSection.shortcuts => keyboard,
        _ => true,
      })
        s,
  ];
}

/// Title of [s].
String helpSectionTitle(AppLocalizations l, HelpSection s) => switch (s) {
  HelpSection.areas => l.helpAreasTitle,
  HelpSection.player => l.helpPlayerTitle,
  HelpSection.library => l.helpLibraryTitle,
  HelpSection.practice => l.helpPracticeTitle,
  HelpSection.metronome => l.helpMetronomeTitle,
  HelpSection.sync => l.helpSyncTitle,
  HelpSection.appearance => l.helpAppearanceTitle,
  HelpSection.recording => l.helpRecordingTitle,
  HelpSection.export => l.helpExportTitle,
  HelpSection.commandLine => l.helpCommandLineTitle,
  HelpSection.web => l.helpWebTitle,
  HelpSection.shortcuts => l.helpShortcutsTitle,
};

/// Text of [s]; paragraphs are separated by an empty line.
String helpSectionBody(AppLocalizations l, HelpSection s) => switch (s) {
  HelpSection.areas => l.helpAreasBody,
  HelpSection.player => l.helpPlayerBody,
  HelpSection.library => l.helpLibraryBody,
  HelpSection.practice => l.helpPracticeBody,
  HelpSection.metronome => l.helpMetronomeBody,
  HelpSection.sync => l.helpSyncBody,
  HelpSection.appearance => l.helpAppearanceBody,
  HelpSection.recording => l.helpRecordingBody,
  HelpSection.export => l.helpExportBody,
  HelpSection.commandLine => l.helpCommandLineBody,
  HelpSection.web => l.helpWebBody,
  HelpSection.shortcuts => l.helpShortcutsBody,
};

/// Opens the help and the shortcuts; given by the window to the menus that offer them (#148/AK2).
class HelpActions extends InheritedWidget {
  const HelpActions({
    super.key,
    required this.onHelp,
    required this.onShortcuts,
    required super.child,
  });

  final VoidCallback onHelp, onShortcuts;

  static HelpActions? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HelpActions>();

  @override
  bool updateShouldNotify(HelpActions old) =>
      old.onHelp != onHelp || old.onShortcuts != onShortcuts;
}

/// Opens the help as a page of its own.
Future<void> showHelp(BuildContext context, HelpTopics topics) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => HelpPage(topics: topics),
      ),
    );

/// Wide enough for the contents beside the section.
const _twoColumns = 600.0;

class HelpPage extends StatefulWidget {
  const HelpPage({super.key, required this.topics});
  final HelpTopics topics;

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  HelpSection? _selected;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final sections = widget.topics.sections;
    final selected = sections.contains(_selected) ? _selected! : sections.first;
    return _Closable(
      child: Scaffold(
        key: const Key('helpPage'),
        appBar: AppBar(
          title: Text(l.helpTitle),
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              key: const Key('helpClose'),
              tooltip: l.close,
              icon: const Icon(WsIcons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) => box.maxWidth >= _twoColumns
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 240,
                        child: _contents(context, sections, selected),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: _SectionView(
                          key: ValueKey(selected),
                          section: selected,
                        ),
                      ),
                    ],
                  )
                : _contents(context, sections, null),
          ),
        ),
      ),
    );
  }

  /// The contents; [selected] null: on the phone, a tap opens the section as a page.
  Widget _contents(
    BuildContext context,
    List<HelpSection> sections,
    HelpSection? selected,
  ) {
    final l = context.l10n;
    return ListView(
      key: const Key('helpContents'),
      children: [
        for (final s in sections)
          ListTile(
            key: Key('helpTopic:${s.name}'),
            selected: s == selected,
            title: Text(helpSectionTitle(l, s)),
            trailing: selected == null
                ? const Icon(WsIcons.chevronRight, size: 16)
                : null,
            onTap: () => selected == null
                ? Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => _Closable(
                        child: Scaffold(
                          appBar: AppBar(title: Text(helpSectionTitle(l, s))),
                          body: SafeArea(child: _SectionView(section: s)),
                        ),
                      ),
                    ),
                  )
                : setState(() => _selected = s),
          ),
      ],
    );
  }
}

/// Escape closes the page.
class _Closable extends StatelessWidget {
  const _Closable({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          Navigator.maybePop(context),
    },
    child: Focus(autofocus: true, child: child),
  );
}

class _SectionView extends StatelessWidget {
  const _SectionView({super.key, required this.section});
  final HelpSection section;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    final paragraphs = helpSectionBody(l, section).split('\n\n');
    return SingleChildScrollView(
      key: Key('helpSection:${section.name}'),
      padding: const EdgeInsets.all(WsSpace.xl),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: WsSpace.m,
            children: [
              Text(
                helpSectionTitle(l, section),
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              for (final p in paragraphs) SelectableText(p),
              if (section == HelpSection.shortcuts)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    key: const Key('helpShowShortcuts'),
                    onPressed: () => showShortcuts(context),
                    child: Text(l.helpShortcutsShow),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// #148: the keyboard shortcuts as a dialog of their own, grouped by area.
Future<void> showShortcuts(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => const ShortcutsDialog(),
);

class ShortcutsDialog extends StatelessWidget {
  const ShortcutsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ws = WsTheme.of(context);
    final platform = Theme.of(context).platform;
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      key: const Key('shortcutsDialog'),
      title: Text(l.helpShortcutsTitle),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final g in ShortcutGroup.values) ...[
                Padding(
                  padding: const EdgeInsets.only(
                    top: WsSpace.m,
                    bottom: WsSpace.s,
                  ),
                  child: Text(
                    shortcutGroupLabel(l, g),
                    key: Key('shortcutGroup:${g.name}'),
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                for (final row in shortcutTable.where((r) => r.group == g))
                  Padding(
                    key: Key('shortcut:${row.action.name}'),
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: WsSpace.m,
                      children: [
                        SizedBox(
                          width: 170,
                          child: Text(
                            row.keys
                                .map((k) => shortcutKeyLabel(l, platform, k))
                                .join(' / '),
                            style: ws.number(13, color: ws.amber),
                          ),
                        ),
                        Expanded(
                          child: Text(shortcutActionLabel(l, row.action)),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('shortcutsClose'),
          onPressed: () => Navigator.pop(context),
          child: Text(l.close),
        ),
      ],
    );
  }
}
