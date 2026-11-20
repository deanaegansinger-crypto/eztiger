import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'local_address.dart';

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

  /// True when the request list runs on this device (localhost).
  bool get onThisDevice => const ['localhost', '127.0.0.1', '::1'].contains(base.host);

  /// True for the online request list (cloud/requests on Cloudflare): not this
  /// PC and not another device on the venue Wi-Fi. Singers use their own data.
  bool get online => !onThisDevice && !isPrivateIp(base.host) && !base.host.endsWith('.local');

  /// The singers' page: what the songbook QR code opens.
  String get singerPage => base.replace(path: '/').toString();

  /// The DJ list in a browser.
  String get djList => _at('/dj').toString();

  /// Puts the singers' page ([html], with the songs) on the online request
  /// list, with the show's [name] and this PC's time zone for the request times.
  Future<void> publishPage(HttpClient http, String html, {required String name}) async {
    final offset = DateTime.now().timeZoneOffset.inMinutes;
    final req = await http
        .openUrl('PUT', _at('/dj/page', {'name': name, 'tz': '$offset'}))
        .timeout(const Duration(seconds: 15));
    req.headers.contentType = ContentType('application', 'gzip');
    req.add(gzip.encode(utf8.encode(html)));
    final res = await req.close().timeout(const Duration(seconds: 60));
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode == 403) throw const RequestServerRefused();
    if (res.statusCode != 200) {
      String? why;
      try {
        why = (jsonDecode(body) as Map)['error'] as String?;
      } catch (_) {}
      throw HttpException(why ?? 'The online request list answered ${res.statusCode}');
    }
  }

  /// The songs in the singing queue that haven't gone into EZTiger yet, top first.
  /// [ip] is the address EZTiger's QR code uses, so the request list's QR
  /// code (on the DJ list and poster) shows the same one; sent only when the
  /// request list runs on this PC.
  Future<List<SongRequest>> waiting(HttpClient http, {String? ip}) async {
    final send = ip != null && ip.isNotEmpty && onThisDevice;
    final req = await http.getUrl(_at('/app/next', send ? {'ip': ip} : const {})).timeout(_timeout);
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
