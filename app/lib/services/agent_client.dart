import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/device.dart';

class AgentException implements Exception {
  final String message;
  AgentException(this.message);
  @override
  String toString() => message;
}

/// Talks to velksync-agent running on the PC.
class AgentClient {
  final Device device;
  final http.Client _http = http.Client();

  AgentClient(this.device);

  Uri _uri(String path) => Uri(scheme: 'http', host: device.host, port: device.port, path: path);

  Map<String, String> get _headers => {'Authorization': 'Bearer ${device.token}', 'Content-Type': 'application/json'};

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final req = http.Request(method, _uri(path))..headers.addAll(_headers);
    if (body != null) req.body = jsonEncode(body);
    final http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(req).timeout(timeout));
    } on TimeoutException {
      throw AgentException('PC não respondeu');
    } on Exception catch (e) {
      throw AgentException('Sem conexão com o PC ($e)');
    }
    final data = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode >= 400) {
      throw AgentException(data is Map && data['error'] != null ? data['error'] as String : 'Erro ${res.statusCode}');
    }
    return data;
  }

  /// Exchanges the one-time code from the pairing QR for the token. The only
  /// call that doesn't need a token, so it lives outside an instance.
  static Future<String> claimPairing({required String host, required int port, required String code}) async {
    final client = AgentClient(Device(id: '', name: '', host: host, port: port, token: ''));
    try {
      final data = await client._send('POST', '/api/pair/claim', body: {'code': code, 'device': 'app Velksync'});
      return (data as Map<String, dynamic>)['token'] as String;
    } finally {
      client.close();
    }
  }

  Future<AgentInfo> info() async =>
      AgentInfo.fromJson(await _send('GET', '/api/info', timeout: const Duration(seconds: 3)) as Map<String, dynamic>);

  /// action: shutdown, reboot ou sleep.
  Future<void> power(String action) => _send('POST', '/api/power', body: {'action': action});

  Future<List<PresetCommand>> commands() async => [
    for (final c in await _send('GET', '/api/commands') as List) PresetCommand.fromJson(c as Map<String, dynamic>),
  ];

  Future<RunResult> run(String id) async => RunResult.fromJson(
    await _send('POST', '/api/commands/${Uri.encodeComponent(id)}', timeout: const Duration(minutes: 2))
        as Map<String, dynamic>,
  );

  Future<RunResult> shell(String command) async => RunResult.fromJson(
    await _send('POST', '/api/shell', body: {'command': command}, timeout: const Duration(minutes: 2))
        as Map<String, dynamic>,
  );

  /// Server-sent events from the PC. Completes when the connection drops;
  /// cancelling the subscription closes the connection right away.
  Stream<PcEvent> events() {
    final client = http.Client();
    StreamSubscription<String>? lines;
    late final StreamController<PcEvent> out;
    void finish([Object? error]) {
      client.close();
      if (out.isClosed) return;
      if (error != null) out.addError(error);
      out.close();
    }

    out = StreamController<PcEvent>(
      onListen: () async {
        try {
          final req = http.Request('GET', _uri('/api/events'))..headers.addAll(_headers);
          final res = await client.send(req).timeout(const Duration(seconds: 5));
          if (res.statusCode != 200) throw AgentException('Erro ${res.statusCode}');
          // O agente manda um ping a cada 20s; sem nada por 45s a conexão morreu.
          lines = res.stream
              .timeout(const Duration(seconds: 45))
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen(
                (line) {
                  if (!line.startsWith('data: ')) return;
                  try {
                    out.add(PcEvent.fromJson(jsonDecode(line.substring(6)) as Map<String, dynamic>));
                  } on FormatException {
                    // evento malformado, ignora
                  }
                },
                onError: finish,
                onDone: finish,
              );
        } catch (e) {
          finish(e);
        }
      },
      onCancel: () {
        lines?.cancel();
        client.close();
      },
    );
    return out.stream;
  }

  void close() => _http.close();
}
