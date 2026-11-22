// Settings «Sync» (#54/AK7–AK10): choose Google Drive, sign in and out, status with the last sync per
// device and the errors, «Sync now», restore a backup, and on the desktop the folders to sync at the first
// sign-in. On iPhone and iPad (native app) Google Drive is not offered: the sync runs in the web app there.
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../app/app_controller.dart';
import '../sync/cloud_account.dart';
import '../sync/sync_service.dart';
import 'messages.dart';

Future<void> showSyncSettings(BuildContext context, AppController c) =>
    showDialog<void>(
      context: context,
      builder: (context) => _SyncSettings(controller: c),
    );

String syncStatusText(AppLocalizations l, CloudAccount a) {
  if (a.choice == CloudChoice.none) return l.syncStatusOff;
  if (a.needsSignIn) return l.syncSignInAgain;
  if (!a.signedIn) return l.syncNotSignedIn;
  return switch (a.status) {
    SyncStatus.off => l.syncStatusWaiting,
    SyncStatus.idle => l.syncStatusIdle,
    SyncStatus.syncing => l.syncStatusSyncing,
    SyncStatus.offline => l.syncStatusOffline,
    SyncStatus.failed => l.syncStatusFailed,
    SyncStatus.tooNew => l.syncStatusTooNew,
    SyncStatus.foreignLibrary => l.syncStatusForeign,
  };
}

String _time(AppLocalizations l, DateTime t) =>
    DateFormat.yMd(l.localeName).add_Hm().format(t.toLocal());

class _SyncSettings extends StatelessWidget {
  const _SyncSettings({required this.controller});
  final AppController controller;

  CloudAccount get a => controller.cloud;

  Future<void> _signIn(BuildContext context) async {
    final l = context.l10n;
    final ok = await a.signIn(doneText: l.syncBrowserDone);
    if (!context.mounted) return;
    if (ok == false) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(l.syncSignInFailed)));
      return;
    }
    if (a.needsFolderChoice) await showFolderChoice(context, a);
  }

  Future<void> _signOut(BuildContext context) async {
    final l = context.l10n;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.syncSignOut),
        content: Text(l.syncSignOutText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          TextButton(
            key: const Key('syncSignOutConfirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.syncSignOut),
          ),
        ],
      ),
    );
    if (yes == true) await a.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return ListenableBuilder(
      listenable: a,
      builder: (context, _) {
        final google = a.choice == CloudChoice.google;
        return AlertDialog(
          key: const Key('syncSettings'),
          title: Text(l.settings),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.syncSection,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  RadioGroup<CloudChoice>(
                    groupValue: a.choice,
                    onChanged: (c) {
                      if (c != null) a.choose(c);
                    },
                    child: Column(
                      children: [
                        RadioListTile<CloudChoice>(
                          key: const Key('syncChoice-none'),
                          value: CloudChoice.none,
                          title: Text(l.syncOff),
                          contentPadding: EdgeInsets.zero,
                        ),
                        if (a.googleAvailable)
                          RadioListTile<CloudChoice>(
                            key: const Key('syncChoice-google'),
                            value: CloudChoice.google,
                            title: Text(l.syncGoogle),
                            contentPadding: EdgeInsets.zero,
                          ),
                      ],
                    ),
                  ),
                  if (!a.googleAvailable)
                    Text(l.syncGoogleWebOnly, key: const Key('syncWebOnly')),
                  if (google) ..._google(context, l),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              key: const Key('syncSettingsClose'),
              onPressed: () => Navigator.pop(context),
              child: Text(l.ok),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _google(BuildContext context, AppLocalizations l) {
    final devices = a.devices.entries.toList()
      ..sort((x, y) {
        if (x.key == a.deviceId) return -1;
        if (y.key == a.deviceId) return 1;
        return (y.value ?? DateTime(0)).compareTo(x.value ?? DateTime(0));
      });
    final errors = a.errors;
    return [
      const Divider(),
      Text(syncStatusText(l, a), key: const Key('syncStatus')),
      const SizedBox(height: 8),
      if (a.signingIn) ...[
        Text(l.syncSigningIn),
        TextButton(onPressed: a.cancelSignIn, child: Text(l.cancel)),
      ] else if (!a.signedIn || a.needsSignIn)
        FilledButton(
          key: const Key('syncSignIn'),
          onPressed: () => _signIn(context),
          child: Text(l.syncSignIn),
        )
      else ...[
        Text(
          a.lastSync == null
              ? l.syncNever
              : l.syncLastSync(_time(l, a.lastSync!)),
          key: const Key('syncLastSync'),
        ),
        if (errors.isNotEmpty)
          Tooltip(
            message: errors.join('\n'),
            child: Text(
              l.syncErrors(errors.length),
              key: const Key('syncErrors'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (devices.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(l.syncDevices, style: Theme.of(context).textTheme.titleSmall),
          for (final d in devices)
            Row(
              key: Key('syncDevice-${d.key}'),
              children: [
                Expanded(
                  child: Text(
                    d.key == a.deviceId
                        ? l.syncThisDevice
                        : l.syncDevice(d.key.substring(0, 6)),
                  ),
                ),
                Text(d.value == null ? l.syncUnknown : _time(l, d.value!)),
              ],
            ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              key: const Key('syncNow'),
              onPressed: a.status == SyncStatus.syncing ? null : a.syncNow,
              child: Text(l.syncNow),
            ),
            OutlinedButton(
              key: const Key('syncRestore'),
              onPressed: () => showRestore(context, a),
              child: Text(l.syncRestoreEllipsis),
            ),
            TextButton(
              key: const Key('syncSignOut'),
              onPressed: () => _signOut(context),
              child: Text(l.syncSignOut),
            ),
          ],
        ),
      ],
    ];
  }
}

/// AK9: the backups of this device, newest first; the chosen one becomes the state of all devices.
Future<void> showRestore(BuildContext context, CloudAccount a) async {
  final l = context.l10n;
  final chosen = await showDialog<CloudBackup>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('syncRestoreDialog'),
      title: Text(l.syncRestoreTitle),
      content: SizedBox(
        width: 400,
        child: FutureBuilder<List<CloudBackup>>(
          future: a.backups(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const SizedBox(
                height: 60,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final list = snap.data!;
            if (list.isEmpty) {
              return Text(l.syncRestoreNone, key: const Key('syncRestoreNone'));
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.syncRestoreText),
                const SizedBox(height: 8),
                for (final (i, b) in list.indexed)
                  ListTile(
                    key: Key('syncBackup-$i'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      b.written == null
                          ? l.syncUnknown
                          : l.syncBackupOf(_time(l, b.written!)),
                    ),
                    onTap: () => Navigator.pop(context, b),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
      ],
    ),
  );
  if (chosen == null || !context.mounted) return;
  final ok = await a.restore(chosen);
  if (ok && context.mounted) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(l.syncRestoreDone)));
  }
}

/// AK10: after the first sign-in on the desktop: which folders go to Google Drive, with their size and
/// the free space there. The sync starts once confirmed.
Future<void> showFolderChoice(BuildContext context, CloudAccount a) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _FolderChoice(account: a),
    );

class _FolderChoice extends StatefulWidget {
  const _FolderChoice({required this.account});
  final CloudAccount account;

  @override
  State<_FolderChoice> createState() => _FolderChoiceState();
}

class _FolderChoiceState extends State<_FolderChoice> {
  late final Future<(List<FolderSize>, CloudSpace?)> _data = () async {
    final sizes = await widget.account.folderSizes();
    return (sizes, await widget.account.space());
  }();
  final _sync = <String, bool>{};

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      key: const Key('syncFolders'),
      title: Text(l.syncFoldersTitle),
      content: SizedBox(
        width: 420,
        child: FutureBuilder(
          future: _data,
          builder: (context, snap) {
            if (!snap.hasData) {
              return const SizedBox(
                height: 60,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final (folders, space) = snap.data!;
            final free = space?.free;
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.syncFoldersText),
                  const SizedBox(height: 8),
                  Text(
                    free == null
                        ? l.syncFreeUnknown
                        : l.syncFree(formatBytes(free, l.localeName)),
                    key: const Key('syncFree'),
                  ),
                  const SizedBox(height: 8),
                  if (folders.isEmpty) Text(l.syncNoFolders),
                  for (final f in folders)
                    CheckboxListTile(
                      key: Key('syncFolder-${f.folder.id}'),
                      contentPadding: EdgeInsets.zero,
                      value: _sync[f.folder.id] ?? f.folder.sync,
                      onChanged: (v) =>
                          setState(() => _sync[f.folder.id] = v ?? false),
                      title: Text(f.folder.name),
                      secondary: Text(
                        formatBytes(f.bytes, l.localeName),
                        key: Key('syncFolderSize-${f.folder.id}'),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        FilledButton(
          key: const Key('syncFoldersStart'),
          onPressed: () {
            widget.account.confirmFolders(_sync);
            Navigator.pop(context);
          },
          child: Text(l.syncStart),
        ),
      ],
    );
  }
}
