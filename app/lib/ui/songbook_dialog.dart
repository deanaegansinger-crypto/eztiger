import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../theme.dart';
import 'common.dart';

/// "Audience songbook": a web page of your songs for people to search on
/// their phones, and the QR code that opens it.
Future<void> showSongbook(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _SongbookDialog());

/// The QR code, big, for the audience to scan. Tap anywhere to close.
Future<void> showSongbookQr(BuildContext context) {
  final s = AppScope.of(context);
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog.fullscreen(
      backgroundColor: Colors.white,
      child: GestureDetector(
        key: const Key('songbook-qr'),
        onTap: () => Navigator.pop(context),
        child: LayoutBuilder(
          builder: (context, c) {
            final size = (c.biggest.shortestSide * 0.62).clamp(160.0, 900.0);
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    s.songbookTitle.trim().isEmpty ? 'Song list' : s.songbookTitle.trim(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.black),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Scan with your phone camera to see the songs',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, color: Colors.black87),
                  ),
                  const SizedBox(height: 18),
                  QrImageView(data: s.songbookUrl, size: size, backgroundColor: Colors.white),
                  const SizedBox(height: 12),
                  Text(s.songbookUrl, style: const TextStyle(fontSize: 15, color: Colors.black54)),
                  const SizedBox(height: 6),
                  const Text('Tap to close', style: TextStyle(fontSize: 13, color: Colors.black38)),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}

class _SongbookDialog extends StatefulWidget {
  const _SongbookDialog();
  @override
  State<_SongbookDialog> createState() => _SongbookDialogState();
}

class _SongbookDialogState extends State<_SongbookDialog> {
  late final title = TextEditingController(text: AppScope.of(context).songbookTitle);
  late final url = TextEditingController(text: AppScope.of(context).songbookUrl);
  String? message;
  bool saving = false;

  @override
  void dispose() {
    title.dispose();
    url.dispose();
    super.dispose();
  }

  void _keep() {
    var address = url.text.trim();
    if (address.isNotEmpty && !address.contains('://')) address = 'https://$address';
    AppScope.of(context).setSongbook(title: title.text.trim(), url: address);
  }

  Future<void> _save() async {
    final s = AppScope.of(context);
    _keep();
    setState(() => saving = true);
    try {
      final book = await s.buildSongbook();
      final where = await FilePicker.saveFile(
        dialogTitle: 'Save the songbook page',
        fileName: 'index.html',
        bytes: Uint8List.fromList(utf8.encode(book.html)),
        mimeType: 'text/html',
      );
      if (where == null) {
        message = 'Not saved.';
      } else {
        s.songbookWasSaved(book.fingerprint);
        message =
            'Saved ${book.count} songs. Upload it to your songbook site to replace the old one '
            '(see the Read me for how).';
      }
    } catch (e) {
      message = 'Could not save it: $e';
    }
    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return AlertDialog(
      title: const Text('Audience songbook'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'A web page listing your songs that people can search on their phones. '
                'They scan the QR code to open it. It only shows titles and artists; '
                'your song files stay on this device.',
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('songbook-title'),
                controller: title,
                decoration: const InputDecoration(labelText: 'Heading', hintText: "e.g. Deano's song list"),
                onChanged: (_) => _keep(),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('songbook-url'),
                controller: url,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Web address of your songbook (for the QR code)',
                  hintText: 'e.g. https://yourname.github.io/songbook/',
                ),
                onChanged: (_) => setState(_keep),
              ),
              const SizedBox(height: 14),
              if (s.songbookOutOfDate)
                Container(
                  key: const Key('songbook-out-of-date'),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: EzColors.brass.withValues(alpha: 0.15),
                    border: Border.all(color: EzColors.brass),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Your songs have changed since you last saved the songbook '
                    '(songs added or removed, or titles corrected). Save it again and upload it.',
                  ),
                )
              else if (s.songbookSaved.isNotEmpty)
                const Text('✓ The songbook matches your library.', style: TextStyle(color: EzColors.green)),
              if (message != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(message!)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        OutlinedButton.icon(
          key: const Key('songbook-show-qr'),
          onPressed: s.songbookUrl.isEmpty ? null : () => showSongbookQr(context),
          icon: const Icon(Icons.qr_code_2),
          label: const Text('Show QR code'),
        ),
        FilledButton.icon(
          key: const Key('songbook-save'),
          onPressed: saving ? null : _save,
          icon: const Icon(Icons.save_alt),
          label: Text(s.songbookSaved.isEmpty ? 'Save songbook page…' : 'Update songbook page…'),
        ),
      ],
    );
  }
}
