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
      if (!mounted) return x.stop();
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
                  '☰ Menu → Receive playlist from PC, and type in:'),
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
              if (x.bytesSent > 0)
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
          child: Text(x != null && x.bytesSent >= x.pkg.totalBytes && x.bytesSent > 0 ? 'Done' : 'Stop sending'),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ the tablet

/// "Import playlist": from an EZTiger export on the tablet, an SD card or a
/// USB stick (a folder or a zip). Every song is copied into EZTiger imports.
Future<void> importPlaylist(BuildContext context) async {
  final source = await pickAndroidExport(context);
  if (source == null || !context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CopyDialog(
      title: 'Importing the playlist',
      run: (s, progress) async {
        final (pkg, folder) = await importPackage(
          source,
          s.importFolderFor,
          workDir: s.importsRoot,
          onProgress: progress,
        );
        return s.addImportedPlaylist(pkg, folder);
      },
    ),
  );
}

/// "Receive playlist from PC": over the Wi-Fi from EZTiger Pro's "Send to
/// the tablet", with the PC's address and code.
Future<void> receivePlaylist(BuildContext context) async {
  final s = AppScope.of(context);
  final host = TextEditingController(text: s.transferHost.isNotEmpty ? s.transferHost : _hostOf(s.requestsLink));
  final code = TextEditingController();
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
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
              decoration: const InputDecoration(labelText: 'PC address', hintText: 'e.g. 192.168.1.20'),
            ),
            TextField(
              key: const Key('receive-code'),
              controller: code,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Code'),
            ),
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
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CopyDialog(
      title: 'Receiving the playlist',
      run: (s, progress) async {
        final (pkg, folder) = await receivePackage(h, c, s.importFolderFor, onProgress: progress);
        return s.addImportedPlaylist(pkg, folder);
      },
    ),
  );
}

String _hostOf(String link) {
  final u = Uri.tryParse(link.contains('://') ? link : 'http://$link');
  final h = u?.host ?? '';
  return h == 'localhost' ? '' : h;
}

/// Runs a copy with a progress bar, then says how it went.
class _CopyDialog extends StatefulWidget {
  const _CopyDialog({required this.title, required this.run});
  final String title;
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
      if (mounted) {
        setState(() {
          failed = true;
          result = e is FileSystemException ? 'Could not copy: ${e.message} (${e.path})' : '$e';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(result == null ? widget.title : (failed ? 'That didn’t work' : 'Done')),
        content: SizedBox(
          width: 460,
          child: result == null
              ? _Progress(done: done, total: total, file: file.isEmpty ? 'Starting…' : file)
              : Text(result!, key: const Key('copy-result')),
        ),
        actions: [
          if (result != null) TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      );
}
