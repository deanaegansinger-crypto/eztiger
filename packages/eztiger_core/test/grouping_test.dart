import 'package:eztiger_core/eztiger_core.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('a leading "The" on the artist does not split a song in two', () {
    expect(groupKey('Yesterday', 'The Beatles'), groupKey('Yesterday', 'Beatles'));
    expect(groupKey('Yesterday', 'THE BEATLES'), groupKey('Yesterday', 'beatles'));
    expect(groupKey('This Is The Day', 'The The'), 'the|this is the day', reason: 'the band The The keeps its name');
    expect(groupKey('Song', 'The'), 'the|song');
    expect(groupKey('Yesterday', 'Theatre Of Hate'), isNot(groupKey('Yesterday', 'atre Of Hate')));
  });

  test('The Beatles and Beatles copies show as one song with both versions', () async {
    final lib = await TestLibrary.create();
    addTearDown(lib.dispose);
    lib.touch('Sunfly/The Beatles - Yesterday.mp3');
    lib.touch('Zoom/Beatles - Yesterday.mp3');
    await lib.scan();
    final found = await lib.db.search.search('yesterday');
    expect(found, hasLength(1));
    expect(found.single.versions, hasLength(2));
  });

  test('upgrading an older library regroups its songs', () async {
    final lib = await TestLibrary.create();
    lib.touch('Sunfly/The Beatles - Yesterday.mp3');
    lib.touch('Zoom/Beatles - Yesterday.mp3');
    await lib.scan();
    // As an older EZTiger saved it: "The" kept in the key, database version 3.
    final raw = lib.db.db;
    await raw.update('tracks', {'group_key': 'the beatles|yesterday'}, where: "artist LIKE 'the %'");
    await raw.execute('PRAGMA user_version = 3');
    expect(await lib.db.search.search('yesterday'), hasLength(2), reason: 'split before the upgrade');
    await lib.db.close();

    final again = await EztigerDatabase.open(databaseFactoryFfiNoIsolate, p.join(lib.dir.path, 'test.db'));
    addTearDown(() async {
      await again.close();
      lib.dir.deleteSync(recursive: true);
    });
    final found = await again.search.search('yesterday');
    expect(found, hasLength(1));
    expect(found.single.versions, hasLength(2));
  });
}
