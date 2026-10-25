import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velksync/models/device.dart';
import 'package:velksync/services/presence.dart';

// Mesmo vetor de agent/presence_test.go: prova gerada pelo agente em Go.
const secret = '120d7cc7d299ac345c70dfb3195c33ab097e96c84334a88b894f08e6a0cafaa9';
const nonce = '00112233445566778899aabbccddeeff';
const proof = '3c090eea3b8640c738fe38f842e98be8b0304923be5e015147caaac3049fd3b2';

void main() {
  test('aceita a prova gerada pelo agente', () {
    expect(verifyPresence(secret, nonce, {'os': 'windows', 'nonce': nonce, 'proof': proof}), 'windows');
  });

  test('recusa respostas que não provam ser o PC', () {
    final other = secret.replaceRange(0, 2, 'ff');
    final cases = <Object?>[
      {'os': 'windows', 'nonce': nonce, 'proof': proof.replaceRange(0, 1, '0')}, // prova adulterada
      {'os': 'linux', 'nonce': nonce, 'proof': proof}, // trocou o sistema
      {'os': 'windows', 'nonce': 'ffeeddccbbaa99887766554433221100', 'proof': proof}, // desafio antigo
      {'os': 'windows', 'nonce': nonce}, // sem prova
      'texto',
      null,
    ];
    for (final c in cases) {
      expect(verifyPresence(secret, nonce, c), isNull, reason: '$c');
    }
    expect(verifyPresence(other, nonce, {'os': 'windows', 'nonce': nonce, 'proof': proof}), isNull);
    expect(verifyPresence('nao-e-hex', nonce, {'os': 'windows', 'nonce': nonce, 'proof': proof}), isNull);
  });

  test('desafios são aleatórios e têm 128 bits', () {
    final a = newNonce(), b = newNonce();
    expect(a, hasLength(32));
    expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(a), isTrue);
    expect(a, isNot(b));
  });

  test('pergunta pela rede e confere a resposta', () async {
    // "PC" falso na porta de presença do loopback.
    final pc = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(pc.close);
    var forge = false;
    pc.listen((e) {
      final dg = pc.receive();
      if (dg == null) return;
      final n = utf8.decode(dg.data).split(' ').last;
      // Sem o segredo, só dá para mandar uma prova inventada.
      final reply = forge
          ? {'os': 'windows', 'nonce': n, 'proof': '00' * 32}
          : {'os': 'windows', 'nonce': n, 'proof': _proofFor(n)};
      pc.send(utf8.encode(jsonEncode(reply)), dg.address, dg.port);
    });
    final d = const Device(id: 'x', name: 'pc', host: '127.0.0.1', presenceKey: secret);
    expect(await probePresence(d, port: pc.port), 'windows');
    forge = true;
    expect(await probePresence(d, port: pc.port, timeout: const Duration(milliseconds: 300)), isNull);
    expect(
      await probePresence(const Device(id: 'x', name: 'pc', host: '127.0.0.1')),
      isNull,
      reason: 'sem segredo',
    );
  });
}

String _proofFor(String n) {
  final key = [for (var i = 0; i < secret.length; i += 2) int.parse(secret.substring(i, i + 2), radix: 16)];
  return Hmac(sha256, key).convert(utf8.encode('presence|$n|windows')).toString();
}
