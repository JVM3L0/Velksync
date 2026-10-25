import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:velksync/services/pinning.dart';

// Certificados de teste gerados com openssl; os pins esperados vêm de
//   openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | sha256sum
// Se o leitor de DER errar um campo, o pin não bate e o app recusaria o PC.

const _ec =
    'MIIBjDCCATGgAwIBAgIUCoKHqlf+TH9qaOrR4OHy2AkA3EEwCgYIKoZIzj0EAwIwGzEZMBcGA1UE'
    'AwwQdmVsa3N5bmMtdGVzdC1lYzAeFw0yNjEwMjUwNjIyMTdaFw0zNjEwMjIwNjIyMTdaMBsxGTAX'
    'BgNVBAMMEHZlbGtzeW5jLXRlc3QtZWMwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAAQW71EXbsYV'
    'jGgGRmBYYtsuoouPv0MYta+1iijYJUd4NXssVbAr49XCrf4QiWhPIQGgM15CSbCIlECSkn7IiO0v'
    'o1MwUTAdBgNVHQ4EFgQUNag+z+q2bVBwCVgh93NnhQvpu64wHwYDVR0jBBgwFoAUNag+z+q2bVBw'
    'CVgh93NnhQvpu64wDwYDVR0TAQH/BAUwAwEB/zAKBggqhkjOPQQDAgNJADBGAiEAjOXsvxoOOWyZ'
    'mggzkH6f+eWHGw5IDQNOm5e4obARgC8CIQCzsrWxm6OpkUe/0KygMU0U/auIFlXDgGJ9t1ZkSAM0'
    'wg==';
const _ecPin = 'cb39de73805c9768b13889e6e2ce3d4a7dac9708a08a0b82bea15dfbce047f85';

const _rsa =
    'MIIDGTCCAgGgAwIBAgIUBohyXygByTBUuJvemdMLv21G3o4wDQYJKoZIhvcNAQELBQAwHDEaMBgG'
    'A1UEAwwRdmVsa3N5bmMtdGVzdC1yc2EwHhcNMjYxMDI1MDYyMjE3WhcNMzYxMDIyMDYyMjE3WjAc'
    'MRowGAYDVQQDDBF2ZWxrc3luYy10ZXN0LXJzYTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoC'
    'ggEBAK58Da1/IiANa96qQtNaYclN0vcG/jYnmG8VL5LKDFUf2eceud72LX/WfnVj7CTFU8//UnEl'
    'NYmWxTDx/tsbORB11CIeQTffQqrKoEIiIrLZyMeenhWmUQk2c52MR0IsmA5u/C0XwdFEW384kS2B'
    'biqVX4k/J/NFAd7cyTmf6hLLI9EP+tbJOFkknEnyX7asF8vVkPBEfGaQl6X5r/5tJx/uMTNnH80h'
    'JCRSHlMzVGDQ3QKMIl9PkuCwOgspgIpld4QfnCjWgGB3YOlMbm/+mDRuDOri0DKKD2Th7gxatTLf'
    '2jm4vimkd88P1dBysi07kQ2ZZ+sS/JkBS2QdXWo+030CAwEAAaNTMFEwHQYDVR0OBBYEFJuqDK1F'
    'FYEGRpFYCbX1LJChkDw1MB8GA1UdIwQYMBaAFJuqDK1FFYEGRpFYCbX1LJChkDw1MA8GA1UdEwEB'
    '/wQFMAMBAf8wDQYJKoZIhvcNAQELBQADggEBAIgNFPAZRBeYqLzdQfOsFnCtYXxCbg4cmwZYzGJZ'
    '1swevYs5gAUDgtQWJ/t6KJnoEtfyhYFeVsJXC9indEvKyA4uI7eo2WgBTm+bJeNPA8MYLElQYXXx'
    'W/DHH3NklzFJZxaIObkAYzkA2vR53Go9Mn8W1j7Kl1m2xFHvPubd9bUWswDLmPSZ0482ZwwEvFi/'
    'XdOxDtkuBBdDlI8ID2ms/yFoR2fEVPUVura98oKnSpuHdsw3a/cFFng5iau3xIOOacBOoLHCmbcf'
    '2WYvVsfETp+XaThIHNfn7ZBVIBzjVBouGKPCzHWVDGvVXiFyBbypvS1KMqGz6N132ATlRPu7dSo=';
const _rsaPin = '80be19b758937a34190ff9e47e74d395570ae3cdaa710f32fd1c60db85852c63';

void main() {
  test('pin de certificado EC (o tipo que o agente usa) bate com o openssl', () {
    expect(pinOf(base64.decode(_ec)), _ecPin);
  });

  test('pin de certificado RSA bate com o openssl', () {
    expect(pinOf(base64.decode(_rsa)), _rsaPin);
  });

  test('certificados diferentes têm pins diferentes', () {
    expect(pinOf(base64.decode(_ec)), isNot(pinOf(base64.decode(_rsa))));
  });
}
