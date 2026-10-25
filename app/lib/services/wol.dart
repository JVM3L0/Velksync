import 'dart:io';
import 'dart:typed_data';

/// Sends a Wake-on-LAN magic packet: 6 x 0xFF followed by the MAC 16 times.
Future<void> wake(String mac, {String broadcast = '255.255.255.255'}) async {
  final hex = mac.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
  if (hex.length != 12) throw FormatException('MAC inválido: $mac');
  final macBytes = [for (var i = 0; i < 12; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
  final packet = Uint8List.fromList([...List.filled(6, 0xFF), for (var i = 0; i < 16; i++) ...macBytes]);

  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  try {
    socket.broadcastEnabled = true;
    final targets = {InternetAddress(broadcast), InternetAddress('255.255.255.255')};
    // UDP pode perder pacotes; repetir é barato.
    for (var i = 0; i < 3; i++) {
      for (final addr in targets) {
        socket.send(packet, addr, 9);
        socket.send(packet, addr, 7);
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  } finally {
    socket.close();
  }
}
