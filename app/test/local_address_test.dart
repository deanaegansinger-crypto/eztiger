import 'package:eztiger/local_address.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("the PC's address: the real Wi-Fi or cable, not virtual or self-assigned ones", () {
    // As on Dean's PC: the Wi-Fi at .12, and unused 169.254 adapters.
    final seen = {
      ('Local Area Connection* 2', '169.254.1.0'),
      ('Bluetooth Network Connection', '169.254.80.191'),
      ('vEthernet (WSL)', '172.20.16.1'),
      ('WiFi', '192.168.88.12'),
      ('Loopback Pseudo-Interface 1', '127.0.0.1'),
    };
    final best = seen.reduce((a, b) => addressScore(a.$1, a.$2) >= addressScore(b.$1, b.$2) ? a : b);
    expect(best.$2, '192.168.88.12');
    expect(addressScore('Local Area Connection* 2', '169.254.1.0'), 0);
    expect(addressScore('Loopback Pseudo-Interface 1', '127.0.0.1'), 0);
    expect(addressScore('Ethernet', '10.0.0.5'), greaterThan(addressScore('vEthernet (Default Switch)', '172.20.16.1')));
  });

  test('a local-network link moves to the new address, keeping its port and page', () {
    expect(isPrivateIp('192.168.88.12'), isTrue);
    expect(isPrivateIp('172.31.0.1'), isTrue);
    expect(isPrivateIp('172.32.0.1'), isFalse);
    expect(isPrivateIp('8.8.8.8'), isFalse);
    expect(isLocalNetworkUrl('http://192.168.88.2:8080/'), isTrue);
    expect(isLocalNetworkUrl('https://deano.github.io/songbook/'), isFalse);
    expect(withAddress('http://192.168.88.2:8080/', '192.168.88.12'), 'http://192.168.88.12:8080/');
    expect(requestPageUrl('10.0.0.7'), 'http://10.0.0.7:8080/');
  });
}
