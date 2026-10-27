import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';

import '../data/catalog_repository.dart';
import '../data/diagnostics.dart';
import '../data/updater.dart';
import '../domain/releases.dart';
import 'feedback.dart';
import 'paper.dart';

Future<bool> openExternal(Uri uri) async {
  try {
    return uri.scheme == 'https' && await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Object {
    return false;
  }
}

Widget _sheetTitle(BuildContext context, String title, String closeTooltip) => Row(
  children: [
    Expanded(child: Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600))),
    PaperIconButton(icon: Icons.close, tooltip: closeTooltip, onPressed: () => Navigator.pop(context)),
  ],
);

String _stamp() => DateFormat('yyyyMMdd-HHmm').format(DateTime.now());

/// Saves a full copy of the catalog wherever the user chooses.
Future<void> backupCatalog(BuildContext context, CatalogRepository repository) async {
  final toasts = ToastHost.of(context);
  final temp = await Directory.systemTemp.createTemp('vastra-backup');
  try {
    final file = File(path.join(temp.path, 'catalog.sqlite'));
    repository.backupTo(file.path);
    final saved = await FilePicker.saveFile(
      dialogTitle: 'Back up Vastra catalog',
      fileName: 'vastra-backup-${_stamp()}.sqlite',
      bytes: await file.readAsBytes(),
      mimeType: 'application/vnd.sqlite3',
    );
    if (saved != null) toasts.show(ToastKind.success, 'Catalog backed up. Keep the file somewhere safe.');
  } on Object {
    toasts.show(ToastKind.error, 'The backup could not be saved. Your catalog is unchanged.');
  } finally {
    await temp.delete(recursive: true);
  }
}

/// Adds the finds from a backup file; finds already on this device are kept.
Future<int?> restoreCatalog(BuildContext context, CatalogRepository repository) async {
  final toasts = ToastHost.of(context);
  final picked = await FilePicker.pickFile(dialogTitle: 'Choose a Vastra backup');
  if (picked == null) return null;
  final temp = await Directory.systemTemp.createTemp('vastra-restore');
  try {
    final file = File(path.join(temp.path, 'backup.sqlite'));
    await file.writeAsBytes(await picked.readAsBytes());
    final added = repository.restoreFrom(file.path);
    toasts.show(
      ToastKind.success,
      added == 0 ? 'Everything in that backup is already in your catalog.' : 'Restored $added finds. Finds already here were kept.',
    );
    return added;
  } on FormatException catch (e) {
    toasts.show(ToastKind.error, e.message);
  } on Object {
    toasts.show(ToastKind.error, 'That backup could not be read. Your catalog is unchanged.');
  } finally {
    await temp.delete(recursive: true);
  }
  return null;
}

/// Downloads, verifies and installs one release, newer or older.
class UpdateSheet extends StatefulWidget {
  const UpdateSheet({super.key, required this.release, required this.updates, required this.repository, required this.quit});
  final Release release;
  final UpdateService updates;
  final CatalogRepository repository;
  final void Function() quit;
  @override
  State<UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<UpdateSheet> {
  int _step = -1;
  double? _progress;
  String? _error, _notice;

  bool get _rollback => Version.current > widget.release.version;

  Future<void> _run() async {
    final feedback = FeedbackScope.of(context);
    setState(() {
      _step = 0;
      _error = null;
      _notice = null;
      _progress = null;
    });
    try {
      await widget.updates.snapshot(widget.repository);
      if (!mounted) return;
      setState(() => _step = 1);
      final file = await widget.updates.download(
        widget.release,
        progress: (f) {
          if (mounted) setState(() => _progress = f);
        },
      );
      if (!mounted) return;
      setState(() => _step = 2);
      final result = await widget.updates.install(file, widget.release, quit: widget.quit);
      if (!mounted) return;
      unawaited(feedback.play(Cue.success));
      setState(() {
        _step = result == 'permission' ? 1 : 3;
        _notice = result == 'permission'
            ? 'Allow Vastra to install apps in the screen that opened, then come back and tap Install again.'
            : 'Android will ask you to confirm the install. Your catalog stays on this device.';
      });
    } on Object catch (e) {
      unawaited(feedback.play(Cue.error));
      if (mounted) {
        setState(() {
          _error = e is UpdateFailure ? e.message : 'The update stopped unexpectedly. Your catalog is unchanged.';
          _step = -1;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.release;
    final busy = _step >= 0 && _step < 3 && _notice == null;
    return PaperSheet(
      maxWidth: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sheetTitle(context, _rollback ? 'Roll back to ${r.version}' : 'Vastra ${r.version}', 'Close'),
            const SizedBox(height: Space.s),
            Text(
              _rollback
                  ? 'You are on $appVersion. Going back replaces the app with ${r.version}; your catalog is kept, and a copy is saved first.'
                  : 'You are on $appVersion. The update is checked against its published SHA-256 before it is installed, and your catalog is copied first.',
              style: const TextStyle(color: Tone.inkSoft),
            ),
            if (r.notes.isNotEmpty) ...[
              const SizedBox(height: Space.l),
              const SectionHeader('What changed'),
              const SizedBox(height: Space.s),
              Text(r.notes, maxLines: 10, overflow: TextOverflow.fade),
            ],
            const SizedBox(height: Space.xl),
            StepTrack(steps: const ['Back up', 'Download and verify', 'Install'], active: _step.clamp(0, 2)),
            if (_step == 1 && _notice == null) ...[
              const SizedBox(height: Space.l),
              CopperProgress(value: _progress, label: 'Downloading Vastra ${r.version}'),
            ],
            if (Platform.isWindows || Platform.isLinux) ...[
              const SizedBox(height: Space.m),
              const Text(
                'Vastra closes while it installs and reopens afterwards. If it does not reopen, start it from your launcher.',
                style: TextStyle(fontSize: 12.5, color: Tone.inkSoft),
              ),
            ],
            if (_notice != null) ...[
              const SizedBox(height: Space.l),
              AlertBanner(title: 'Almost there:', message: _notice!, icon: Icons.info_outline),
            ],
            if (_error != null) ...[
              const SizedBox(height: Space.l),
              AlertBanner(title: 'Not installed:', message: _error!, icon: Icons.error_outline),
            ],
            const SizedBox(height: Space.xl),
            Wrap(
              spacing: Space.s,
              runSpacing: Space.s,
              alignment: WrapAlignment.end,
              children: [
                PaperButton(label: 'Release page', icon: Icons.north_east, compact: true, onPressed: () => openExternal(r.page)),
                CopperButton(
                  label: _rollback ? 'Roll back' : (_error != null || _notice != null ? 'Install again' : 'Install'),
                  icon: _rollback ? Icons.history : Icons.system_update_alt,
                  busy: busy,
                  onPressed: busy ? null : _run,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Android only installs an older version after the newer one is removed,
/// which also removes the catalog. This walks through doing that safely.
class AndroidRollbackSheet extends StatefulWidget {
  const AndroidRollbackSheet({super.key, required this.release, required this.updates, required this.repository});
  final Release release;
  final UpdateService updates;
  final CatalogRepository repository;
  @override
  State<AndroidRollbackSheet> createState() => _AndroidRollbackSheetState();
}

class _AndroidRollbackSheetState extends State<AndroidRollbackSheet> {
  bool _busy = false;
  double? _progress;

  Future<void> _savePackage() async {
    final toasts = ToastHost.of(context);
    setState(() => _busy = true);
    try {
      final file = await widget.updates.download(widget.release, progress: (f) => mounted ? setState(() => _progress = f) : null);
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save Vastra ${widget.release.version}',
        fileName: path.basename(file.path),
        bytes: await file.readAsBytes(),
        mimeType: 'application/vnd.android.package-archive',
      );
      if (saved != null) toasts.show(ToastKind.success, 'Saved Vastra ${widget.release.version}. It matched its published checksum.');
    } on UpdateFailure catch (e) {
      toasts.show(ToastKind.error, e.message);
    } on Object {
      toasts.show(ToastKind.error, 'The package could not be saved.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.release.version;
    Widget step(String n, String text, [Widget? action]) => Padding(
      padding: const EdgeInsets.only(bottom: Space.l),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PaperAvatar(n),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Text(text), if (action != null) ...[const SizedBox(height: Space.s), action]],
            ),
          ),
        ],
      ),
    );
    return PaperSheet(
      maxWidth: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sheetTitle(context, 'Roll back to $v', 'Close'),
            const SizedBox(height: Space.s),
            const Text(
              'Android installs an older version only after the current one is uninstalled, and uninstalling erases the catalog. Back it up first.',
              style: TextStyle(color: Tone.inkSoft),
            ),
            const SizedBox(height: Space.xl),
            step('1', 'Back up your catalog to a file you can find again.', PaperButton(
              label: 'Back up catalog',
              icon: Icons.save_alt,
              compact: true,
              onPressed: () => backupCatalog(context, widget.repository),
            )),
            step('2', 'Save the verified Vastra $v package.', _busy
                ? CopperProgress(value: _progress, label: 'Downloading Vastra $v')
                : PaperButton(label: 'Save package', icon: Icons.download, compact: true, onPressed: _savePackage)),
            step('3', 'Uninstall Vastra from Android settings, then open the saved package to install $v.'),
            step(
              '4',
              v < const Version(0, 3, 0)
                  ? 'Vastra $v cannot restore backups or update itself. Keep your backup: install 0.3.0 or later from the release page to restore it.'
                  : 'Open Vastra, go to Settings, and choose Restore from backup.',
            ),
          ],
        ),
      ),
    );
  }
}

/// Every published version, with update or rollback actions.
class VersionsSheet extends StatefulWidget {
  const VersionsSheet({super.key, required this.updates, required this.repository, required this.quit});
  final UpdateService updates;
  final CatalogRepository repository;
  final void Function() quit;
  @override
  State<VersionsSheet> createState() => _VersionsSheetState();
}

class _VersionsSheetState extends State<VersionsSheet> {
  late Future<List<Release>> _releases = widget.updates.releases();

  void _choose(Release r) {
    final u = widget.updates;
    if (u.canInstall(r)) {
      showPaperDialog<void>(
        context,
        builder: (_) => UpdateSheet(release: r, updates: u, repository: widget.repository, quit: widget.quit),
      );
    } else if (u.target == Target.android && r.packageFor(Target.android) != null && r.checksums != null) {
      showPaperDialog<void>(context, builder: (_) => AndroidRollbackSheet(release: r, updates: u, repository: widget.repository));
    } else {
      openExternal(r.page);
    }
  }

  @override
  Widget build(BuildContext context) => PaperSheet(
    maxWidth: 620,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sheetTitle(context, 'All versions', 'Close versions'),
        const SizedBox(height: Space.s),
        Text(
          widget.updates.mode == InstallMode.automatic
              ? 'Install any published version. Your catalog is copied before every change.'
              : 'This copy of Vastra is managed outside the app, such as a portable folder or a system package. Versions open on their release page.',
          style: const TextStyle(color: Tone.inkSoft),
        ),
        const SizedBox(height: Space.l),
        Flexible(
          child: FutureBuilder<List<Release>>(
            future: _releases,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) return const SkeletonRows(rows: 4);
              if (snap.hasError || (snap.data?.isEmpty ?? true)) {
                return EmptyState(
                  title: snap.hasError ? 'Versions unavailable' : 'No published versions yet',
                  message: snap.error is UpdateFailure ? (snap.error! as UpdateFailure).message : 'Releases appear here once they are published.',
                  action: 'Try again',
                  onAction: () => setState(() => _releases = widget.updates.releases()),
                );
              }
              final list = snap.data!;
              return ListView.separated(
                shrinkWrap: true,
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: Space.m),
                itemBuilder: (context, i) {
                  final r = list[i];
                  final current = r.version == Version.current;
                  final newer = r.version > Version.current;
                  return Arrive(
                    index: i,
                    child: Paper(
                      padding: const EdgeInsets.all(Space.l),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text('Vastra ${r.version}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                    const SizedBox(width: Space.s),
                                    if (current) const RibbonBadge('Installed') else if (i == 0) const RibbonBadge('Latest'),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  [
                                    if (r.published != null) DateFormat.yMMMd().format(r.published!.toLocal()),
                                    if (r.prerelease) 'Pre-release',
                                  ].join(' · '),
                                  style: const TextStyle(fontSize: 12.5, color: Tone.inkSoft),
                                ),
                              ],
                            ),
                          ),
                          if (!current)
                            PaperButton(
                              label: newer ? 'Update' : 'Roll back',
                              icon: newer ? Icons.system_update_alt : Icons.history,
                              compact: true,
                              onPressed: () => _choose(r),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );
}

/// Writes a bug report the user reads in full before it opens as a public
/// GitHub issue. Nothing is sent by Vastra itself.
class ReportSheet extends StatefulWidget {
  const ReportSheet({super.key, required this.diagnostics, required this.finds});
  final Diagnostics diagnostics;
  final int finds;
  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  final _title = TextEditingController(), _summary = TextEditingController(), _steps = TextEditingController();
  late bool _errors = widget.diagnostics.recent.isNotEmpty;

  @override
  void dispose() {
    _title.dispose();
    _summary.dispose();
    _steps.dispose();
    super.dispose();
  }

  String get _body => bugReport(
    summary: _summary.text,
    steps: _steps.text,
    errors: _errors ? widget.diagnostics.recent : const [],
    finds: widget.finds,
  );

  @override
  Widget build(BuildContext context) {
    final count = widget.diagnostics.recent.where((l) => !l.startsWith(' ')).length;
    return PaperSheet(
      maxWidth: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sheetTitle(context, 'Report a problem', 'Close report'),
            const SizedBox(height: Space.s),
            const Text(
              'This opens a prefilled issue on GitHub in your browser. It becomes public when you submit it there; Vastra sends nothing itself.',
              style: TextStyle(color: Tone.inkSoft),
            ),
            const SizedBox(height: Space.l),
            PaperField(controller: _title, label: 'Title', hint: 'Sharing from my browser does nothing', maxLength: 120),
            const SizedBox(height: Space.m),
            PaperField(controller: _summary, label: 'What happened, and what did you expect?', maxLines: 4, onChanged: (_) => setState(() {})),
            const SizedBox(height: Space.m),
            PaperField(controller: _steps, label: 'Steps to reproduce', maxLines: 4, onChanged: (_) => setState(() {})),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Include recent errors'),
              subtitle: Text(
                count == 0
                    ? 'No errors recorded on this device.'
                    : '$count recorded. Links are shortened to their store and your home folder is hidden.',
              ),
              value: _errors && count > 0,
              onChanged: count == 0 ? null : (v) => setState(() => _errors = v),
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Preview the report'),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(Space.m),
                  decoration: paperDecoration(surface: Surface.inset, radius: Radii.xs),
                  child: SelectableText(_body, style: const TextStyle(fontSize: 12, height: 1.4)),
                ),
              ],
            ),
            const SizedBox(height: Space.l),
            Wrap(
              spacing: Space.s,
              runSpacing: Space.s,
              alignment: WrapAlignment.end,
              children: [
                PaperButton(
                  label: 'Copy report',
                  icon: Icons.copy,
                  compact: true,
                  onPressed: () async {
                    final toasts = ToastHost.of(context);
                    await Clipboard.setData(ClipboardData(text: '${_title.text.trim()}\n\n$_body'));
                    toasts.show(ToastKind.success, 'Report copied.');
                  },
                ),
                CopperButton(
                  label: 'Open GitHub issue',
                  icon: Icons.north_east,
                  onPressed: () async {
                    final toasts = ToastHost.of(context);
                    final navigator = Navigator.of(context);
                    if (await openExternal(issueLink(_title.text, _body))) {
                      navigator.pop();
                    } else {
                      toasts.show(ToastKind.warning, 'No browser opened. Copy the report and post it on the project page.');
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
