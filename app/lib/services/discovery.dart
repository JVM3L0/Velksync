import 'dart:async';
import 'dart:convert';
import 'dart:io';

class DiscoveredPc {
  final String name;
  final String os;
  final String host;
  final int port;
  final String mac;

  DiscoveredPc({required this.name, required this.os, required this.host, required this.port, required this.mac});
}

const _discoveryPort = 41101;

/// Broadcasts a probe on the LAN and collects replies from velksync agents.
Future<List<DiscoveredPc>> discover({Duration wait = const Duration(seconds: 2)}) async {
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  final found = <String, DiscoveredPc>{};
  socket.broadcastEnabled = true;
  final sub = socket.listen((event) {
    if (event != RawSocketEvent.read) return;
    final dg = socket.receive();
    if (dg == null) return;
    try {
      final j = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
      found[dg.address.address] = DiscoveredPc(
        name: j['name'] as String? ?? dg.address.address,
        os: j['os'] as String? ?? '',
        host: dg.address.address,
        port: j['port'] as int? ?? 41100,
        mac: j['mac'] as String? ?? '',
      );
    } on FormatException {
      // resposta que não é de um agente
    }
  });
  final probe = utf8.encode('VELKSYNC_DISCOVER');
  for (var i = 0; i < 3; i++) {
    socket.send(probe, InternetAddress('255.255.255.255'), _discoveryPort);
    await Future<void>.delayed(wait ~/ 3);
  }
  await sub.cancel();
  socket.close();
  return found.values.toList();
}
