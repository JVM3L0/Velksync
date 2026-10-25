import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../models/device.dart';

/// Sinal de presença: o PC responde já no boot, antes do login, provando com
/// HMAC que conhece o segredo entregue pelo agente. Sem o segredo certo, uma
/// resposta forjada por outro aparelho da rede é descartada.
const presencePort = 41101;
const _probe = 'VELKSYNC_PRESENCE ';

String newNonce([Random? random]) {
  final r = random ?? Random.secure();
  return [for (var i = 0; i < 16; i++) r.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
}

Uint8List? _hex(String s) {
  if (s.length.isOdd) return null;
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    final b = int.tryParse(s.substring(i * 2, i * 2 + 2), radix: 16);
    if (b == null) return null;
    out[i] = b;
  }
  return out;
}

/// Comparação em tempo constante: não revela quantos caracteres batem.
bool _sameText(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

/// Confere a resposta ao desafio [nonce]; devolve o sistema que respondeu
/// ('windows' ou 'linux') ou null se a prova não confere.
String? verifyPresence(String secretHex, String nonce, Object? reply) {
  final secret = _hex(secretHex);
  if (secret == null || secret.isEmpty || reply is! Map) return null;
  final os = reply['os'], proof = reply['proof'];
  if (reply['nonce'] != nonce || os is! String || proof is! String) return null;
  final expected = Hmac(sha256, secret).convert(utf8.encode('presence|$nonce|$os')).toString();
  return _sameText(expected, proof.toLowerCase()) ? os : null;
}

/// Pergunta ao PC se ele está ligado. Devolve o sistema ou null (desligado,
/// fora da rede, agente antigo ou resposta que não prova ser este PC).
Future<String?> probePresence(
  Device d, {
  Duration timeout = const Duration(milliseconds: 1500),
  int port = presencePort,
}) async {
  if (d.presenceKey.isEmpty) return null;
  InternetAddress target;
  RawDatagramSocket? socket;
  try {
    target = InternetAddress.tryParse(d.host) ?? (await InternetAddress.lookup(d.host)).first;
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  } on Exception {
    socket?.close();
    return null;
  }
  final nonce = newNonce();
  final msg = utf8.encode('$_probe$nonce');
  final done = Completer<String?>();
  socket.listen((event) {
    if (event != RawSocketEvent.read || done.isCompleted) return;
    final dg = socket!.receive();
    if (dg == null || dg.address != target) return;
    try {
      final os = verifyPresence(d.presenceKey, nonce, jsonDecode(utf8.decode(dg.data)));
      if (os != null) done.complete(os);
    } on FormatException {
      // resposta malformada: continua esperando até o tempo acabar
    }
  });
  // UDP pode perder pacote: manda de novo na metade do tempo.
  socket.send(msg, target, port);
  final resend = Timer(timeout ~/ 2, () => socket!.send(msg, target, port));
  try {
    return await done.future.timeout(timeout, onTimeout: () => null);
  } finally {
    resend.cancel();
    socket.close();
  }
}
