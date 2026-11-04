import 'dart:io';

import 'package:path/path.dart' as p;

class FileEntry {
  FileEntry(this.name, this.size, this.mtime);
  final String name;
  final int size;

  /// Milliseconds since epoch.
  final int mtime;

  String get lowerName => name.toLowerCase();
}

class DirListing {
  DirListing(this.path, this.files, this.subdirs, {this.unreadable = false});
  final String path;
  final List<FileEntry> files;
  final List<String> subdirs;

  /// Could not be listed (permissions, a drive going away mid-scan). The
  /// scanner must not treat its tracks as deleted.
  final bool unreadable;
}

/// Walks [root] depth-first, parents before children.
///
/// A lazy sync generator with no database dependency: memory stays bounded
/// by the depth of the tree, and moving the walk into an Isolate later is a
/// small change. Folders for which [skip] returns true are not entered.
/// Symlinks and junctions are not followed.
Iterable<DirListing> walkFolders(String root, {bool Function(String dir)? skip}) sync* {
  final stack = <String>[root];
  while (stack.isNotEmpty) {
    final dir = stack.removeLast();
    List<FileSystemEntity> entries;
    try {
      entries = Directory(dir).listSync(followLinks: false);
    } on FileSystemException {
      yield DirListing(dir, const [], const [], unreadable: true);
      continue;
    }
    final files = <FileEntry>[];
    final subdirs = <String>[];
    for (final e in entries) {
      if (e is File) {
        try {
          final st = e.statSync();
          files.add(FileEntry(p.basename(e.path), st.size, st.modified.millisecondsSinceEpoch));
        } on FileSystemException {
          // Vanished between list and stat; next scan will see it.
        }
      } else if (e is Directory) {
        subdirs.add(e.path);
      }
    }
    subdirs.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    yield DirListing(dir, files, subdirs);
    for (final s in subdirs.reversed) {
      if (skip == null || !skip(s)) stack.add(s);
    }
  }
}
