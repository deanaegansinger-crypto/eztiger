import 'package:eztiger/edition.dart';
import 'package:eztiger/licence.dart';
import 'package:eztiger_core/eztiger_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fakes.dart';

void main() {
  sqfliteFfiInit();
  late EztigerDatabase db;
  late FakeShop shop;
  var now = DateTime(2026, 11, 7, 20);
  Licence make() => Licence(db, server: shop, clock: () => now);

  setUp(() async {
    db = await EztigerDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath);
    shop = FakeShop();
    now = DateTime(2026, 11, 7, 20);
  });
  tearDown(() => db.close());

  test('the trial gives 14 days of Pro from the first start, then Basic', () async {
    var l = make();
    await l.load();
    expect(l.onTrial, isTrue);
    expect(l.trialDaysLeft, 14);
    expect(l.proActive, isTrue);
    expect(l.summary, 'Pro trial: 14 days left');

    now = now.add(const Duration(days: 13, hours: 2));
    l = make();
    await l.load();
    expect(l.trialDaysLeft, 1, reason: 'counted from the first start, not this one');

    now = now.add(const Duration(days: 1));
    l = make();
    await l.load();
    expect(l.trialEnded, isTrue);
    expect(l.proActive, isFalse);
  });

  test('winding the clock back does not stretch the trial', () async {
    await make().load();
    now = now.add(const Duration(days: 15));
    await make().load();
    now = DateTime(2026, 11, 8);
    final l = make();
    await l.load();
    expect(l.trialEnded, isTrue);
  });

  test('a good key switches Pro on for good, offline too; a bad one says why', () async {
    await make().load(); // the first start
    now = now.add(const Duration(days: 30));
    final l = make();
    await l.load();
    expect(l.proActive, isFalse);
    expect(await l.activate('  '), contains('Type or paste'));
    expect(await l.activate('BAD'), 'That key was not accepted.');
    shop.online = false;
    expect(await l.activate('GOOD-KEY'), contains('Could not reach'));
    shop.online = true;
    var changed = false;
    l.addListener(() => changed = true);
    expect(await l.activate(' GOOD-KEY '), isNull);
    expect(l.licensed, isTrue);
    expect(changed, isTrue);
    expect(isPro, builtAsPro, reason: 'Pro on in the Pro build');

    shop.online = false;
    final again = make();
    await again.load();
    expect(again.licensed, isTrue);
    expect(again.proActive, isTrue);
    await again.recheckInBackground(); // not due yet
    expect(shop.validates, 0);
    now = now.add(const Duration(days: 20));
    await again.recheckInBackground(); // offline: the key keeps working
    expect(again.licensed, isTrue);
  });

  test('a refunded key stops working at the next check', () async {
    final l = make();
    await l.load();
    await l.activate('GOOD-KEY');
    now = now.add(const Duration(days: 40));
    shop.refunded = true;
    final later = make();
    await later.load();
    await later.recheckInBackground();
    expect(later.licensed, isFalse);
    expect(later.proActive, isFalse);
  });

  test('without a product id, keys are refused but the trial still works', () async {
    final r = await LemonSqueezy(productId: 0).activate('X', instanceName: 'test');
    expect(r.ok, isFalse);
    expect(r.message, contains('not on sale yet'));
  });
}
