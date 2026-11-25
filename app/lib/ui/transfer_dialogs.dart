import 'dart:io';

import 'package:eztiger_core/eztiger_core.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../playlist_transfer.dart';
import '../theme.dart';
import 'android_folders.dart';
import 'common.dart';

/// The app's state without listening to it: allowed in initState.
AppState _stateOf(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;

String _mb(int bytes) => bytes >= 1073741824
    ? '${(bytes / 1073741824).toStringAsFixed(1)} GB'
    : '${(bytes / 1048576).toStringAsFixed(bytes < 10485760 ? 1 : 0)} MB';

/// A progress bar with the file being copied.
class _Progress extends StatelessWidget {
  const _Progress({required this.done, required this.total, required this.file});
  final int done, total;
  final String file;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(value: total > 0 ? (done / total).clamp(0, 1).toDouble() : null, minHeight: 8),
          const SizedBox(height: 6),
          Text(
            total > 1 ? '${_mb(done)} of ${_mb(total)}${file.isEmpty ? '' : ' · $file'}' : file,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: context.ez.textDim),
          ),
        ],
      );
}

// ------------------------------------------------------------- the PC

/// EZTiger Pro: a playlist and its song files to a USB stick, an SD card or
/// Dropbox, as a folder or one zip.
Future<void> showExportPlaylist(BuildContext context, Playlist pl) =>
    showDialog<void>(context: context, barrierDismissible: false, builder: (_) => _ExportDialog(pl));

class _ExportDialog extends StatefulWidget {
  const _ExportDialog(this.pl);
  final Playlist pl;
  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  PlaylistPackage? pkg;
  bool zip = false, busy = false;
  int done = 0, total = 0;
  String file = '', message = '';

  @override
  void initState() {
    super.initState();
    final s = _stateOf(context);
    PlaylistPackage.fromPlaylist(s.db, widget.pl, keyShifts: s.keyShifts).then((x) {
      if (mounted) setState(() => pkg = x);
    });
  }

  Future<void> _export() async {
    final dest = await FilePicker.getDirectoryPath(
      dialogTitle: zip ? 'Where should the zip go? (e.g. your Dropbox folder)' : 'Where should it go? (e.g. the USB stick or SD card)',
    );
    if (dest == null || !mounted) return;
    setState(() {
      busy = true;
      message = '';
    });
    try {
      void progress(int d, int t, String f) {
        if (mounted) {
          setState(() {
            done = d;
            total = t;
            file = f;
          });
        }
      }

      final out = zip ? await exportToZip(pkg!, dest, onProgress: progress) : await exportToFolder(pkg!, dest, onProgress: progress);
      message = '✓ Exported to $out\n\nOn the tablet: ☰ Menu → Import playlist, and find it there.';
    } catch (e) {
      message = 'Could not export it: $e';
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final x = pkg;
    return AlertDialog(
      title: Text('Export ★ ${widget.pl.name}'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(x == null
                ? 'Gathering the songs…'
                : '${x.songs.length} songs, ${_mb(x.totalBytes)}, with their CDG and lyric files and the playlist, '
                    'ready for the tablet.'),
            const SizedBox(height: 10),
            RadioGroup<bool>(
              groupValue: zip,
              onChanged: (v) {
                if (!busy) setState(() => zip = v ?? false);
              },
              child: const Column(
                children: [
                  RadioListTile<bool>(
                    key: Key('export-folder'),
                    value: false,
                    title: Text('A folder'),
                    subtitle: Text('For a USB stick or SD card: the tablet reads it straight off.'),
                  ),
                  RadioListTile<bool>(
                    key: Key('export-zip'),
                    value: true,
                    title: Text('One zip file'),
                    subtitle: Text('For Dropbox or email: the tablet unpacks it.'),
                  ),
                ],
              ),
            ),
            if (busy) _Progress(done: done, total: total, file: file),
            if (message.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(message)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Close')),
        FilledButton.icon(
          key: const Key('export-go'),
          onPressed: busy || x == null || x.songs.isEmpty ? null : _export,
          icon: const Icon(Icons.save_alt),
          label: const Text('Choose where, and export…'),
        ),
      ],
    );
  }
}

/// EZTiger Pro: offers a playlist to the tablet over the Wi-Fi until closed.
Future<void> showSendPlaylist(BuildContext context, Playlist pl) =>
    showDialog<void>(context: context, barrierDismissible: false, builder: (_) => _SendDialog(pl));

class _SendDialog extends StatefulWidget {
  const _SendDialog(this.pl);
  final Playlist pl;
  @override
  State<_SendDialog> createState() => _SendDialogState();
}

class _SendDialogState extends State<_SendDialog> {
  PlaylistSender? sender;
  String? address, problem;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final s = _stateOf(context);
    try {
      final pkg = await PlaylistPackage.fromPlaylist(s.db, widget.pl, keyShifts: s.keyShifts);
      final ip = await s.detectPcAddress();
      final x = PlaylistSender(pkg)
        ..onChange = () {
          if (mounted) setState(() {});
        };
      await x.start();
      if (!mounted) {
        await x.stop();
        return;
      }
      setState(() {
        sender = x;
        address = ip;
      });
    } catch (e) {
      if (mounted) setState(() => problem = "Couldn't start sending: $e");
    }
  }

  @override
  void dispose() {
    sender?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final x = sender;
    final big = TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: EzColors.brass, letterSpacing: 1);
    return AlertDialog(
      title: Text('Send ★ ${widget.pl.name} to the tablet'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (problem != null)
              Text(problem!, style: TextStyle(color: EzColors.red))
            else if (x == null)
              const Text('Getting ready…')
            else ...[
              Text('${x.pkg.songs.length} songs, ${_mb(x.pkg.totalBytes)}. On the tablet, on the same Wi-Fi: '
                  '☰ Menu → Receive from PC, and type in:'),
              const SizedBox(height: 12),
              Row(children: [
                const SizedBox(width: 90, child: Text('PC address')),
                SelectableText(address ?? '(not on a network)', key: const Key('send-address'), style: big),
              ]),
              Row(children: [
                const SizedBox(width: 90, child: Text('Code')),
                SelectableText(x.code, key: const Key('send-code'), style: big),
              ]),
              const SizedBox(height: 12),
              if (x.finished)
                Row(key: const Key('send-success'), children: [
                  Icon(Icons.check_circle, color: EzColors.green),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Transfer successful. The tablet has the playlist.',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ])
              else if (x.bytesSent > 0)
                _Progress(done: x.bytesSent, total: x.pkg.totalBytes, file: x.sending)
              else
                Text(
                  'Waiting for the tablet. If Windows asks, allow EZTiger on Private networks.',
                  style: TextStyle(fontSize: 12, color: context.ez.textDim),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('send-stop'),
          onPressed: () => Navigator.pop(context),
          child: Text(x != null && x.finished ? 'Close' : 'Stop sending'),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ the tablet

/// "Import playlist": from an EZTiger export on the tablet, an SD card or a
/// USB stick (a folder or a zip). Every song is copied into EZTiger imports.
Future<void> importPlaylist(BuildContext context) async {
  if (!await _canSaveSongs(context) || !context.mounted) return;
  final source = await pickAndroidExport(context);
  if (source == null || !context.mounted) return;
  final again = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CopyDialog(
      title: 'Importing the playlist',
      againLabel: 'Import another',
      run: (s, progress) async =>
          s.addImportedPlaylist(await importPackage(source, askUpdateOrNew(context, s), onProgress: progress)),
    ),
  );
  if (again == true && context.mounted) await importPlaylist(context);
}

/// "Receive playlist from PC": over the Wi-Fi from EZTiger Pro's "Send to
/// the tablet", with the PC's address and code.
Future<void> receivePlaylist(BuildContext context) async {
  if (!await _canSaveSongs(context) || !context.mounted) return;
  final s = AppScope.of(context);
  final host = TextEditingController(text: s.transferHost.isNotEmpty ? s.transferHost : _hostOf(s.requestsLink));
  final code = TextEditingController();
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      // On a phone the keyboard takes half the screen: the box scrolls, so
      // the field being typed in and the Receive button can be reached.
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      title: const Text('Receive a playlist from the PC'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('On the PC: right-click the playlist → 📶 Send to the tablet. Type in what it shows.'),
            TextField(
              key: const Key('receive-host'),
              controller: host,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              scrollPadding: const EdgeInsets.only(bottom: 120),
              decoration: const InputDecoration(labelText: 'PC address', hintText: 'e.g. 192.168.1.20'),
            ),
            TextField(
              key: const Key('receive-code'),
              controller: code,
              keyboardType: TextInputType.number,
              // The keyboard's ✓ receives straight away.
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => Navigator.pop(context, true),
              scrollPadding: const EdgeInsets.only(bottom: 120),
              decoration: const InputDecoration(labelText: 'Code'),
            ),
            const SizedBox(height: 14),
            _SaveToRow(s),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(key: const Key('receive-go'), onPressed: () => Navigator.pop(context, true), child: const Text('Receive')),
      ],
    ),
  );
  final h = host.text.trim(), c = code.text.trim();
  if (go != true || h.isEmpty || !context.mounted) return;
  s.setTransferHost(h);
  final again = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CopyDialog(
      title: 'Receiving the playlist',
      againLabel: 'Receive another',
      run: (s, progress) async =>
          s.addImportedPlaylist(await receivePackage(h, c, askUpdateOrNew(context, s), onProgress: progress)),
    ),
  );
  // Receive another: back to the address and code, with the address kept.
  if (again == true && context.mounted) await receivePlaylist(context);
}

/// "Save the songs to": where received songs go (the tablet, an SD card or
/// a USB stick), with Change… to pick another folder and Usual place to go
/// back. The choice is remembered for next time.
class _SaveToRow extends StatelessWidget {
  const _SaveToRow(this.s);
  final AppState s;

  Future<void> _change(BuildContext context, AppState s) async {
    final chosen = Platform.isAndroid
        ? await pickAndroidFolder(context)
        : await FilePicker.getDirectoryPath(dialogTitle: 'Where should the songs go?');
    if (chosen == null || !context.mounted) return;
    if (!s.setImportsFolder(chosen)) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            "EZTiger can't save songs there. Android keeps some SD cards read-only for apps: "
            'pick a folder on the tablet, or set the SD card up as tablet storage.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: s, builder: (context, _) => _row(context));

  Widget _row(BuildContext context) {
    return Row(
      key: const Key('receive-save-to'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2, right: 10),
          child: Icon(s.importsRoot.startsWith('/storage/emulated') ? Icons.smartphone : Icons.sd_card, color: EzColors.brass, size: 20),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Save the songs to', style: TextStyle(fontSize: 12)),
              Text(s.importsRoot, key: const Key('receive-folder'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Wrap(
                spacing: 4,
                children: [
                  TextButton(
                    key: const Key('receive-change-folder'),
                    onPressed: () => _change(context, s),
                    child: const Text('Change…'),
                  ),
                  if (s.importsFolder.isNotEmpty)
                    TextButton(onPressed: () => s.setImportsFolder(''), child: const Text('Usual place')),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Android: the songs, their CDGs and the half-copied ".part" files go in
/// EZTiger imports, which needs "All files access" (without it Android lets
/// the app save only music files there, so the copy fails). A phone that
/// has never had a karaoke folder added hasn't been asked yet: ask now.
Future<bool> _canSaveSongs(BuildContext context) async {
  if (!Platform.isAndroid || await hasStorageAccess()) return true;
  if (!context.mounted) return false;
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: const Text('Allow EZTiger to save the songs'),
      content: const Text(
        'The songs, with their CDG lyrics, are copied into the EZTiger imports folder. '
        'Android needs you to allow that once: on the next screen, switch on '
        '"Allow access to manage all files" for EZTiger, then come back.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Allow')),
      ],
    ),
  );
  if (go != true) return false;
  if (await ensureStorageAccess()) return true;
  if (context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Without "manage all files" EZTiger can\'t save the songs. Try again to allow it.')),
    );
  }
  return false;
}

/// When the playlist coming in has the name of one already on the tablet:
/// update that one, or keep both (the new one under a dated name)?
PlanFor askUpdateOrNew(BuildContext context, AppState s) => (pkg) async {
  final plain = s.importPlan(pkg);
  if (!plain.update) return plain;
  if (!context.mounted) return null;
  final both = s.labelledName(plain.name);
  final choice = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text('You already have ★ ${plain.name}'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Update it to match the PC, or keep both?'),
            const SizedBox(height: 12),
            const Text(
              'Update: the playlist takes the new order and keys. Only new or changed songs are copied; '
              'songs taken off the list are removed from its folder.',
            ),
            const SizedBox(height: 8),
            Text('Keep both: this one comes in as ★ $both, beside the one you have.'),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        OutlinedButton(
          key: const Key('import-keep-both'),
          onPressed: () => Navigator.pop(context, 'both'),
          child: const Text('Keep both'),
        ),
        FilledButton(
          key: const Key('import-update'),
          onPressed: () => Navigator.pop(context, 'update'),
          child: const Text('Update'),
        ),
      ],
    ),
  );
  return switch (choice) {
    'update' => plain,
    'both' => s.importPlan(pkg, keepBoth: true),
    _ => null,
  };
};

String _hostOf(String link) {
  final u = Uri.tryParse(link.contains('://') ? link : 'http://$link');
  final h = u?.host ?? '';
  return h == 'localhost' ? '' : h;
}

/// Runs a copy with a progress bar, then says how it went. On success it
/// offers Close or [againLabel] (e.g. "Receive another"): the dialog
/// returns true for that one.
class _CopyDialog extends StatefulWidget {
  const _CopyDialog({required this.title, required this.run, required this.againLabel});
  final String title, againLabel;
  final Future<String> Function(AppState s, TransferProgress progress) run;
  @override
  State<_CopyDialog> createState() => _CopyDialogState();
}

class _CopyDialogState extends State<_CopyDialog> {
  int done = 0, total = 0;
  String file = '';
  String? result;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    final s = _stateOf(context);
    widget.run(s, (d, t, f) {
      if (!mounted) return;
      setState(() {
        done = d;
        total = t;
        file = f;
      });
    }).then((r) {
      if (mounted) setState(() => result = r);
    }, onError: (Object e) {
      // Cancelled at "Update or keep both?": nothing was copied.
      if (e is TransferCancelled) {
        if (mounted) Navigator.pop(context);
        return;
      }
      if (mounted) {
        setState(() {
          failed = true;
          result = e is FileSystemException ? 'Could not copy: ${e.message} (${e.path})' : '$e';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ok = result != null && !failed;
    return AlertDialog(
      title: result == null
          ? Text(widget.title)
          : failed
              ? const Text('That didn’t work')
              : Row(children: [
                  Icon(Icons.check_circle, color: EzColors.green, size: 30),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Transfer successful', key: Key('copy-success'))),
                ]),
      content: SizedBox(
        width: 460,
        child: result == null
            ? _Progress(done: done, total: total, file: file.isEmpty ? 'Starting…' : file)
            : Text(result!, key: const Key('copy-result')),
      ),
      actions: [
        if (result != null)
          TextButton(key: const Key('copy-close'), onPressed: () => Navigator.pop(context, false), child: const Text('Close')),
        if (result != null)
          FilledButton.icon(
            key: const Key('copy-again'),
            onPressed: () => Navigator.pop(context, true),
            icon: Icon(ok ? Icons.download : Icons.refresh),
            label: Text(ok ? widget.againLabel : 'Try again'),
          ),
      ],
    );
  }
}
