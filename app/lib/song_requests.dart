import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// How the link to the song-request list is doing.
enum RequestsState {
  /// No link set.
  off,
  connecting,
  connected,

  /// Nothing answers at the link: the request list isn't running, or this
  /// device is on another network.
  unreachable,

  /// The request list wants the DJ code (on a tablet: use the DJ link).
  needsCode,
}

/// A song the DJ has put in the singing queue on the song-request list
/// (the request server, "Start song requests" on the PC), waiting to go into
/// Tonight's playlist.
class SongRequest {
  SongRequest({
    required this.id,
    required this.singer,
    required this.title,
    required this.artist,
    this.path = '',
    this.file = '',
  });

  factory SongRequest.fromJson(Map<String, dynamic> j) => SongRequest(
        id: '${j['Id'] ?? ''}',
        singer: '${j['Singer'] ?? ''}'.trim(),
        title: '${j['Title'] ?? ''}'.trim(),
        artist: '${j['Artist'] ?? ''}'.trim(),
        path: '${j['Path'] ?? ''}',
        file: '${j['File'] ?? ''}',
      );

  final String id, singer, title, artist;

  /// The song file on the request server's PC, and the same file inside the
  /// library folder (for a tablet, whose library is somewhere else). Empty
  /// when the request server didn't know the exact file.
  final String path, file;
}

/// The request server, from the link typed in ☰ Menu → Song requests:
/// `localhost:8080` on the PC that runs it, or the "DJ link" it shows, such
/// as `http://192.168.1.20:8080/dj?key=abc123`, on a tablet.
class RequestServer {
  RequestServer._(this.base, this.key);

  /// Null when [link] is empty or not a web address.
  static RequestServer? parse(String link) {
    var s = link.trim();
    if (s.isEmpty) return null;
    if (!s.contains('://')) s = 'http://$s';
    final u = Uri.tryParse(s);
    if (u == null || u.host.isEmpty || !(u.scheme == 'http' || u.scheme == 'https')) return null;
    return RequestServer._(Uri(scheme: u.scheme, host: u.host, port: u.hasPort ? u.port : null),
        u.queryParameters['key'] ?? '');
  }

  final Uri base;

  /// The DJ code from the DJ link; not needed on the PC itself.
  final String key;

  static const _timeout = Duration(seconds: 4);

  Uri _at(String path, [Map<String, String> query = const {}]) {
    final q = {if (key.isNotEmpty) 'key': key, ...query};
    return base.replace(path: path, queryParameters: q.isEmpty ? null : q);
  }

  /// The songs in the singing queue that haven't gone into EZTiger yet, top first.
  Future<List<SongRequest>> waiting(HttpClient http) async {
    final req = await http.getUrl(_at('/app/next')).timeout(_timeout);
    final res = await req.close().timeout(_timeout);
    final body = await res.transform(utf8.decoder).join().timeout(_timeout);
    if (res.statusCode == 403) throw const RequestServerRefused();
    if (res.statusCode != 200) throw HttpException('The request list answered ${res.statusCode}');
    return [for (final j in jsonDecode(body) as List) SongRequest.fromJson(j as Map<String, dynamic>)];
  }

  /// Tells the request list that [id] is in Tonight's playlist, or that the
  /// song couldn't be found in the library ([found] false), so the DJ sees it.
  Future<void> collected(HttpClient http, String id, {required bool found}) async {
    final req = await http.postUrl(_at('/app/sent', {'id': id, 'found': found ? '1' : '0'})).timeout(_timeout);
    final res = await req.close().timeout(_timeout);
    await res.drain<void>().timeout(_timeout);
    if (res.statusCode != 200) throw HttpException('The request list answered ${res.statusCode}');
  }
}

/// The request server is there but wants the DJ code (the link has none, or
/// an old one).
class RequestServerRefused implements Exception {
  const RequestServerRefused();
}
