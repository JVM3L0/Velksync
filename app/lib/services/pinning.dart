import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Extrai o SubjectPublicKeyInfo (DER) de um certificado X.509 em DER.
/// Certificate ::= SEQUENCE { tbsCertificate SEQUENCE { [0] version?, serial,
/// signature, issuer, validity, subject, subjectPublicKeyInfo, ... }, ... }
Uint8List spkiOf(Uint8List der) {
  (int, int, int) tlv(int i) {
    var len = der[i + 1];
    var p = i + 2;
    if (len & 0x80 != 0) {
      final n = len & 0x7f;
      len = 0;
      for (var k = 0; k < n; k++) {
        len = (len << 8) | der[p++];
      }
    }
    return (der[i], p, p + len); // tag, início do conteúdo, fim
  }

  final (_, certStart, _) = tlv(0);
  final (_, tbsStart, _) = tlv(certStart);
  var i = tbsStart;
  if (der[i] == 0xA0) i = tlv(i).$3; // versão explícita
  for (var skip = 0; skip < 5; skip++) {
    i = tlv(i).$3; // serial, signature, issuer, validity, subject
  }
  return Uint8List.sublistView(der, i, tlv(i).$3);
}

String pinOf(Uint8List certDer) => sha256.convert(spkiOf(certDer)).toString();

/// Cliente HTTP que só aceita o servidor cuja chave pública tem esse pin.
/// Sem raízes confiáveis, todo certificado passa pelo callback.
http.Client pinnedClient(String pin) {
  final io = HttpClient(context: SecurityContext(withTrustedRoots: false))
    ..connectionTimeout = const Duration(seconds: 5)
    ..badCertificateCallback = (cert, host, port) {
      try {
        return pin.isNotEmpty && pinOf(cert.der) == pin;
      } catch (_) {
        return false;
      }
    };
  return IOClient(io);
}
