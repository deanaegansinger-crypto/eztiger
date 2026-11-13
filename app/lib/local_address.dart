import 'dart:io';

/// This PC's address on the network it's joined (the venue Wi-Fi or your own
/// router), such as 192.168.1.20, or null if it isn't on one. Real network
/// adapters (Wi-Fi, Ethernet) win over virtual ones (Hyper-V, VirtualBox,
/// VPNs, Bluetooth); self-assigned 169.254 addresses don't count.
Future<String?> thisPcAddress() async {
  try {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    String? best;
    var bestScore = -1;
    for (final i in interfaces) {
      for (final a in i.addresses) {
        final score = addressScore(i.name, a.address);
        if (score > bestScore) {
          best = a.address;
          bestScore = score;
        }
      }
    }
    return bestScore > 0 ? best : null;
  } catch (_) {
    return null;
  }
}

/// How likely [ip] on the adapter called [adapter] is the address phones on
/// the same network reach this PC at: 0 for never.
int addressScore(String adapter, String ip) {
  if (!isPrivateIp(ip)) return 0;
  final name = adapter.toLowerCase();
  const virtual = ['vethernet', 'virtualbox', 'vmware', 'hyper-v', 'wsl', 'docker', 'bluetooth', 'tailscale',
      'zerotier', 'vpn', 'tap-', 'tun', 'loopback', 'npcap'];
  if (virtual.any(name.contains)) return 1;
  var score = 10;
  if (const ['wi-fi', 'wifi', 'wlan', 'wireless', 'ethernet', 'eth', 'en'].any(name.startsWith)) score += 10;
  if (ip.startsWith('192.168.')) score += 3;
  if (ip.startsWith('10.')) score += 2;
  return score;
}

/// A home or venue network address: 10.x, 172.16–31.x or 192.168.x.
bool isPrivateIp(String ip) {
  final p = ip.split('.').map(int.tryParse).toList();
  if (p.length != 4 || p.any((x) => x == null)) return false;
  final a = p[0]!, b = p[1]!;
  return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168);
}

/// True when [url] points at a PC on the local network (an address that
/// changes from venue to venue), not a web site.
bool isLocalNetworkUrl(String url) {
  final host = Uri.tryParse(url.trim())?.host ?? '';
  return isPrivateIp(host);
}

/// [url] with its address changed to [ip], keeping the rest (port, page).
String withAddress(String url, String ip) => Uri.parse(url.trim()).replace(host: ip).toString();

/// The song-request page on this PC ("Start song requests", port 8080).
String requestPageUrl(String ip) => 'http://$ip:8080/';
