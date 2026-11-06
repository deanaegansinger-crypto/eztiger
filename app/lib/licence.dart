import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:eztiger_core/eztiger_core.dart';
import 'package:flutter/foundation.dart';

import 'edition.dart';

/// EZTiger Pro's 14-day trial and licence key.
///
/// The Pro installer is the trial: for [trialDays] days from the first start
/// everything Pro is on. After that EZTiger carries on as Basic until a
/// licence key is entered. Keys are sold through Lemon Squeezy, which emails
/// the buyer a key; EZTiger checks it online once, then works offline, and
/// checks again now and then in the background (a refunded key stops working).
///
/// Lemon Squeezy's product id is set at build time with
/// `--dart-define=EZ_LS_PRODUCT_ID=<id>`, and the shop page with
/// `--dart-define=EZ_BUY_URL=<url>`, so keys for other products don't work.
class Licence extends ChangeNotifier {
  Licence(this.db, {LicenceServer? server, DateTime Function()? clock})
    : server = server ?? LemonSqueezy(),
      _clock = clock ?? DateTime.now;

  final EztigerDatabase db;
  final LicenceServer server;
  final DateTime Function() _clock;

  static const trialDays = 14;

  /// How often a key is checked again online.
  static const recheck = Duration(days: 14);

  static const buyUrl = String.fromEnvironment('EZ_BUY_URL');

  DateTime? trialStarted;
  String? key;
  String? _instance;

  /// A key has been accepted.
  bool get licensed => key != null;

  /// Days of the trial left, 0 once it has ended.
  int get trialDaysLeft {
    final start = trialStarted;
    if (start == null) return trialDays;
    final used = _now().difference(start).inHours / 24;
    return (trialDays - used).ceil().clamp(0, trialDays);
  }

  bool get onTrial => !licensed && trialDaysLeft > 0;
  bool get trialEnded => !licensed && trialDaysLeft == 0;

  /// Pro features on: a key, or days left on the trial.
  bool get proActive => licensed || trialDaysLeft > 0;

  DateTime? _lastSeen;

  /// The clock, never earlier than the last time EZTiger ran (so winding the
  /// PC's clock back doesn't stretch the trial).
  DateTime _now() {
    final n = _clock();
    final seen = _lastSeen;
    return seen != null && n.isBefore(seen) ? seen : n;
  }

  /// Reads the trial and key; starts the trial on the first run. Quick and
  /// offline, so it can run before the window opens.
  Future<void> load() async {
    _lastSeen = DateTime.tryParse(await db.getMeta('licence_seen') ?? '');
    trialStarted = DateTime.tryParse(await db.getMeta('trial_started') ?? '');
    if (trialStarted == null) {
      trialStarted = _now();
      await db.setMeta('trial_started', trialStarted!.toIso8601String());
    }
    key = await db.getMeta('licence_key');
    _instance = await db.getMeta('licence_instance');
    _lastSeen = _now();
    await db.setMeta('licence_seen', _lastSeen!.toIso8601String());
  }

  /// Checks the key with the shop and keeps it. Returns null when it worked,
  /// or why it didn't.
  Future<String?> activate(String input) async {
    final k = input.trim();
    if (k.isEmpty) return 'Type or paste your licence key.';
    final LicenceCheck r;
    try {
      r = await server.activate(k, instanceName: _instanceName());
    } catch (_) {
      return 'Could not reach the licence server. Check the internet connection and try again.';
    }
    if (!r.ok) return r.message ?? 'That key was not accepted.';
    key = k;
    _instance = r.instance;
    await db.setMeta('licence_key', k);
    if (r.instance != null) await db.setMeta('licence_instance', r.instance!);
    await db.setMeta('licence_checked', _now().toIso8601String());
    _apply();
    return null;
  }

  /// Every [recheck], asks the shop if the key is still good. No internet
  /// is fine: the key keeps working. Only a definite "no" (refunded,
  /// disabled) removes it.
  Future<void> recheckInBackground() async {
    final k = key;
    if (k == null) return;
    final last = DateTime.tryParse(await db.getMeta('licence_checked') ?? '');
    if (last != null && _now().difference(last) < recheck) return;
    final LicenceCheck r;
    try {
      r = await server.validate(k, instance: _instance);
    } catch (_) {
      return;
    }
    if (r.ok) {
      await db.setMeta('licence_checked', _now().toIso8601String());
      return;
    }
    if (r.definite) {
      key = null;
      _instance = null;
      await db.db.delete('meta', where: 'key IN (?, ?)', whereArgs: ['licence_key', 'licence_instance']);
      _apply();
    }
  }

  /// Switches the Pro features on or off to match.
  void _apply() {
    isPro = builtAsPro && proActive;
    notifyListeners();
  }

  String _instanceName() {
    try {
      return 'EZTiger Pro on ${Platform.localHostname}';
    } catch (_) {
      return 'EZTiger Pro';
    }
  }

  /// A short line for the brand row and the menu.
  String get summary {
    if (licensed) return 'EZTiger Pro, licensed';
    if (onTrial) return 'Pro trial: $trialDaysLeft day${trialDaysLeft == 1 ? '' : 's'} left';
    return 'Pro trial ended: EZTiger is running as Basic';
  }
}

/// The current build's licence, or null in Basic and in the tests.
Licence? licence;

class LicenceCheck {
  const LicenceCheck({required this.ok, this.message, this.instance, this.definite = true});
  final bool ok;
  final String? message;
  final String? instance;

  /// The shop answered no for certain (rather than an odd reply).
  final bool definite;
}

abstract class LicenceServer {
  Future<LicenceCheck> activate(String key, {required String instanceName});
  Future<LicenceCheck> validate(String key, {String? instance});
}

/// Lemon Squeezy's licence API, which needs no secret in the app.
/// https://docs.lemonsqueezy.com/api/license-api
class LemonSqueezy implements LicenceServer {
  LemonSqueezy({this.productId = const int.fromEnvironment('EZ_LS_PRODUCT_ID')});
  final int productId;

  static final _base = Uri.parse('https://api.lemonsqueezy.com/v1/licenses/');

  @override
  Future<LicenceCheck> activate(String key, {required String instanceName}) async {
    if (productId == 0) {
      return const LicenceCheck(ok: false, message: 'Licence keys are not on sale yet. The trial still works.');
    }
    final m = await _post('activate', {'license_key': key, 'instance_name': instanceName});
    if (m['activated'] != true) return LicenceCheck(ok: false, message: _why(m));
    if (!_ours(m)) return const LicenceCheck(ok: false, message: 'That key is for a different product.');
    return LicenceCheck(ok: true, instance: (m['instance'] as Map?)?['id']?.toString());
  }

  @override
  Future<LicenceCheck> validate(String key, {String? instance}) async {
    final m = await _post('validate', {'license_key': key, 'instance_id': ?instance});
    if (m['valid'] == true && _ours(m)) return const LicenceCheck(ok: true);
    final status = (m['license_key'] as Map?)?['status'];
    // Only drop the key for a clear answer about this key.
    return LicenceCheck(ok: false, message: _why(m), definite: status == 'disabled' || status == 'expired');
  }

  bool _ours(Map<String, dynamic> m) => (m['meta'] as Map?)?['product_id'] == productId;

  static String _why(Map<String, dynamic> m) {
    final e = m['error'] as String?;
    if (e == null) return 'That key was not accepted.';
    if (e.contains('activation limit')) {
      return 'That key is already in use on its limit of computers. Contact Deano to move it.';
    }
    return 'That key was not accepted ($e).';
  }

  static Future<Map<String, dynamic>> _post(String path, Map<String, String> form) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.postUrl(_base.resolve(path));
      req.headers
        ..set(HttpHeaders.acceptHeader, 'application/json')
        ..contentType = ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      req.write(Uri(queryParameters: form).query);
      final res = await req.close().timeout(const Duration(seconds: 15));
      final body = await res.transform(utf8.decoder).join();
      return jsonDecode(body) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }
}
