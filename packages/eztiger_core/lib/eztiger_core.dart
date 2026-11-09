/// EZtiger core: the library scanner and the SQLite song database.
///
/// Pure Dart, no Flutter. The Flutter app depends on this package.
library;

export 'src/audio/audio_edges.dart';
export 'src/cdg/cdg_decoder.dart';
export 'src/data/database.dart';
export 'src/data/daos.dart' hide trackSelect;
export 'src/data/models.dart';
export 'src/data/search.dart' show SearchDao, SearchSort, cleanListLine, compareForSort;
export 'src/scanner/filename_parser.dart';
export 'src/scanner/folder_walker.dart';
export 'src/scanner/library_scanner.dart';
export 'src/songbook.dart';
export 'src/text.dart' show normalize;
