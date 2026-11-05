import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

import '../theme.dart';

/// Asks Android for "All files access", which the app needs to read the
/// karaoke folder on the SD card (CDG and lyric files are not "media", so
/// the ordinary music and video permissions don't cover them).
Future<bool> ensureStorageAccess() async {
  if (await Permission.manageExternalStorage.isGranted) return true;
  if ((await Permission.manageExternalStorage.request()).isGranted) return true;
  // Android 10 and older have no "All files access": the old storage
  // permission does the same job there.
  return (await Permission.storage.request()).isGranted;
}

/// True if the app can already read the SD card, without asking.
Future<bool> hasStorageAccess() async =>
    await Permission.manageExternalStorage.isGranted || await Permission.storage.isGranted;

/// The tablet's storage: internal storage and any SD card or USB stick.
List<(String, String)> storageRoots() {
  final roots = <(String, String)>[];
  const internal = '/storage/emulated/0';
  if (Directory(internal).existsSync()) roots.add(('Tablet storage', internal));
  try {
    for (final d in Directory('/storage').listSync().whereType<Directory>()) {
      final name = p.basename(d.path);
      if (name == 'emulated' || name == 'self') continue;
      roots.add(('SD card ($name)', d.path));
    }
  } catch (_) {
    // /storage can't be listed on some tablets; internal storage still works.
  }
  return roots;
}

/// A simple folder browser for the tablet, used by "Add folder". Returns the
/// chosen folder, or null if cancelled.
Future<String?> pickAndroidFolder(BuildContext context) async {
  if (!await ensureStorageAccess()) {
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('EZtiger needs to see your files'),
          content: const Text(
            'To read your karaoke folder on the SD card, turn on "Allow access to manage all files" '
            'for EZtiger in the screen that opens, then come back and press Add folder again.',
          ),
          actions: [
            TextButton(onPressed: () => openAppSettings(), child: const Text('Open settings')),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
          ],
        ),
      );
    }
    return null;
  }
  if (!context.mounted) return null;
  return showDialog<String>(context: context, builder: (_) => const _FolderBrowser());
}

class _FolderBrowser extends StatefulWidget {
  const _FolderBrowser();
  @override
  State<_FolderBrowser> createState() => _FolderBrowserState();
}

class _FolderBrowserState extends State<_FolderBrowser> {
  final roots = storageRoots();
  String? dir; // null: the list of storage places
  List<Directory> subfolders = [];

  void _open(String? path) {
    var subs = <Directory>[];
    if (path != null) {
      try {
        subs =
            Directory(path).listSync().whereType<Directory>().where((d) => !p.basename(d.path).startsWith('.')).toList()
              ..sort((a, b) => p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase()));
      } catch (_) {
        // Unreadable: show it empty.
      }
    }
    setState(() {
      dir = path;
      subfolders = subs;
    });
  }

  String? get _parent {
    final d = dir;
    if (d == null || roots.any((r) => r.$2 == d)) return null;
    return p.dirname(d);
  }

  @override
  Widget build(BuildContext context) {
    final d = dir;
    return AlertDialog(
      title: Text(d == null ? 'Choose your karaoke folder' : p.basename(d)),
      content: SizedBox(
        width: 520,
        height: 420,
        child: ListView(
          children: [
            if (d != null)
              ListTile(leading: const Icon(Icons.arrow_upward), title: const Text('Back'), onTap: () => _open(_parent)),
            if (d == null)
              for (final (label, path) in roots)
                ListTile(
                  leading: Icon(label.startsWith('SD') ? Icons.sd_card : Icons.tablet_android, color: EzColors.brass),
                  title: Text(label),
                  onTap: () => _open(path),
                )
            else if (subfolders.isEmpty)
              const ListTile(title: Text('No folders in here.'))
            else
              for (final f in subfolders)
                ListTile(
                  leading: const Icon(Icons.folder, color: EzColors.brass),
                  title: Text(p.basename(f.path)),
                  onTap: () => _open(f.path),
                ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        if (d != null) FilledButton(onPressed: () => Navigator.pop(context, d), child: const Text('Use this folder')),
      ],
    );
  }
}
