/// Plain data classes returned by the DAOs.
library;

/// What the app shows in the Type column. A CDG pair (or a zipped MP3+G)
/// shows as CDG, a video as MP4, anything audio-only as MP3.
enum TrackType {
  cdg('CDG'),
  mp4('MP4'),
  mp3('MP3');

  const TrackType(this.label);
  final String label;

  static TrackType? fromLabel(String? label) {
    for (final t in values) {
      if (t.label == label) return t;
    }
    return null;
  }

  static TrackType fromKind(String kind) => switch (kind) {
        'cdg' || 'cdg_zip' => TrackType.cdg,
        'video' => TrackType.mp4,
        _ => TrackType.mp3,
      };
}

class Folder {
  Folder({
    required this.id,
    required this.path,
    required this.parentId,
    required this.name,
    required this.isRoot,
    required this.included,
    required this.trackCount,
    required this.totalCount,
    this.hasChildren = false,
  });

  factory Folder.fromRow(Map<String, Object?> r) => Folder(
        id: r['id'] as int,
        path: r['path'] as String,
        parentId: r['parent_id'] as int?,
        name: r['name'] as String,
        isRoot: (r['is_root'] as int) == 1,
        included: (r['included'] as int) == 1,
        trackCount: r['track_count'] as int,
        totalCount: r['total_count'] as int,
        hasChildren: ((r['has_children'] as int?) ?? 0) == 1,
      );

  final int id;
  final String path;
  final int? parentId;
  final String name;
  final bool isRoot;

  /// False when Dean has taken this folder out of the searchable library.
  final bool included;

  /// Tracks directly in the folder, and in it plus all subfolders.
  final int trackCount;
  final int totalCount;
  final bool hasChildren;
}

class Track {
  Track({
    required this.id,
    required this.folderId,
    required this.path,
    required this.fileName,
    required this.kind,
    required this.cdgPath,
    required this.lyricsPath,
    required this.hasStems,
    required this.category,
    required this.size,
    required this.mtime,
    required this.parsedTitle,
    required this.parsedArtist,
    required this.version,
    required this.catalogueCode,
    required this.groupKey,
    required this.userTitle,
    required this.userArtist,
    required this.userType,
    this.folderPath,
  });

  factory Track.fromRow(Map<String, Object?> r) => Track(
        id: r['id'] as int,
        folderId: r['folder_id'] as int,
        path: r['path'] as String,
        fileName: r['file_name'] as String,
        kind: r['kind'] as String,
        cdgPath: r['cdg_path'] as String?,
        lyricsPath: r['lyrics_path'] as String?,
        hasStems: (r['has_stems'] as int) == 1,
        category: r['category'] as String,
        size: r['size'] as int,
        mtime: r['mtime'] as int,
        parsedTitle: r['title'] as String,
        parsedArtist: r['artist'] as String?,
        version: r['version'] as String?,
        catalogueCode: r['catalogue_code'] as String?,
        groupKey: r['group_key'] as String,
        userTitle: r['user_title'] as String?,
        userArtist: r['user_artist'] as String?,
        userType: TrackType.fromLabel(r['user_kind'] as String?),
        folderPath: r['folder_path'] as String?,
      );

  final int id;
  final int folderId;

  /// The file to play: the .mp3 of a CDG pair, a video, an audio file, or a
  /// .zip holding MP3+G (unzip when played).
  final String path;
  final String fileName;

  /// cdg | cdg_zip | video | audio
  final String kind;
  final String? cdgPath;
  final String? lyricsPath;
  final bool hasStems;

  /// song | mix
  final String category;
  final int size;
  final int mtime;
  final String parsedTitle;
  final String? parsedArtist;
  final String? version;
  final String? catalogueCode;
  final String groupKey;
  final String? userTitle;
  final String? userArtist;
  final TrackType? userType;
  final String? folderPath;

  /// What to show. Dean's own tag edits win over the parsed file name.
  String get title => userTitle ?? parsedTitle;
  String? get artist => userArtist ?? parsedArtist;
  TrackType get type => userType ?? TrackType.fromKind(kind);
  bool get hasLyricSheet => lyricsPath != null;
  bool get isZipped => kind == 'cdg_zip';
}

/// One song in search results, with every copy of it across folders.
class SearchGroup {
  SearchGroup(this.versions);

  /// Best match first.
  final List<Track> versions;
  Track get primary => versions.first;
}

class Playlist {
  Playlist({required this.id, required this.name, required this.trackCount});
  final int id;
  final String name;
  final int trackCount;
}

class QueueEntry {
  QueueEntry({required this.id, required this.position, required this.singer, required this.track});
  final int id;
  final int position;
  final String? singer;
  final Track track;
}

class HistoryEntry {
  HistoryEntry({required this.id, required this.singer, required this.sungAt, required this.track});
  final int id;
  final String? singer;
  final DateTime sungAt;
  final Track track;
}
