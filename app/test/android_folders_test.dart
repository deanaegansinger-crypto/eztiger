import 'dart:io';

import 'package:eztiger/ui/android_folders.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('eztiger/storage');
  late Directory internal;
  late Directory sdCard;

  setUp(() {
    internal = Directory.systemTemp.createTempSync('internal');
    sdCard = Directory.systemTemp.createTempSync('sdcard');
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    internal.deleteSync(recursive: true);
    sdCard.deleteSync(recursive: true);
  });

  test('lists the SD card Android reports, not only internal storage', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'volumes');
      return [
        {'path': internal.path, 'label': 'Internal storage', 'removable': false},
        {'path': sdCard.path, 'label': 'Samsung SD card', 'removable': true},
        {'path': '/no/such/volume', 'label': 'Unplugged USB', 'removable': true},
      ];
    });
    final roots = await storageRoots();
    expect(roots.map((r) => r.path), containsAllInOrder([internal.path, sdCard.path]));
    final sd = roots.firstWhere((r) => r.path == sdCard.path);
    expect(sd.label, 'Samsung SD card');
    expect(sd.removable, isTrue);
    expect(roots.where((r) => r.path == '/no/such/volume'), isEmpty);
  });

  test('still works when Android gives no list', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => throw PlatformException(code: 'volumes'),
    );
    expect(await storageRoots(), isA<List<StorageRoot>>());
  });
}
