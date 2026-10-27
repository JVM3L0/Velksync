import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/device.dart';
import 'pinning.dart';

class AgentException implements Exception {
  final String message;
  AgentException(this.message);
  @override
  String toString() => message;
}

/// Talks to velksync-agent running on the PC over HTTPS pinned to the key from
/// the pairing QR. Unpaired devices (Wake-on-LAN only) can't make requests.
class AgentClient {
  final Device device;
  late final http.Client _http = pinnedClient(device.pin);

  AgentClient(this.device);

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri(scheme: 'https', host: device.host, port: device.port, path: path, queryParameters: query);

  Map<String, String> get _headers => {
    if (device.deviceId.isNotEmpty) 'Authorization': 'Bearer ${device.deviceId}:${device.token}',
    'Content-Type': 'application/json',
  };

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final req = http.Request(method, _uri(path))..headers.addAll(_headers);
    if (body != null) req.body = jsonEncode(body);
    final http.Response res;
    if (device.pin.isEmpty) throw AgentException('PC não pareado: escaneie o QR');
    try {
      res = await http.Response.fromStream(await _http.send(req).timeout(timeout));
    } on TimeoutException {
      throw AgentException('PC não respondeu');
    } on HandshakeException {
      throw AgentException('Certificado do PC não confere: pareie de novo pelo QR');
    } on Exception catch (e) {
      throw AgentException('Sem conexão com o PC ($e)');
    }
    final data = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode >= 400) {
      throw AgentException(data is Map && data['error'] != null ? data['error'] as String : 'Erro ${res.statusCode}');
    }
    return data;
  }

  /// Exchanges the one-time code from the pairing QR for this phone's own
  /// credential. The only call without credentials; the pin comes from the QR.
  static Future<({String deviceId, String token})> claimPairing({
    required String host,
    required int port,
    required String code,
    required String pin,
    required String deviceName,
  }) async {
    final client = AgentClient(Device(id: '', name: '', host: host, port: port, pin: pin));
    try {
      final data = await client._send(
        'POST',
        '/api/pair/claim',
        body: {'code': code, 'device': deviceName},
      ) as Map<String, dynamic>;
      return (deviceId: data['device_id'] as String, token: data['token'] as String);
    } finally {
      client.close();
    }
  }

  Future<AgentInfo> info() async =>
      AgentInfo.fromJson(await _send('GET', '/api/info', timeout: const Duration(seconds: 3)) as Map<String, dynamic>);

  /// Segredo do sinal de presença (agentes a partir da v0.3).
  Future<String> presenceKey() async {
    final data = await _send('GET', '/api/presence', timeout: const Duration(seconds: 3));
    final secret = data is Map ? data['secret'] : null;
    if (secret is! String || secret.isEmpty) throw AgentException('Resposta inválida do PC');
    return secret;
  }

  Future<PcStats> stats() async =>
      PcStats.fromJson(await _send('GET', '/api/stats', timeout: const Duration(seconds: 3)) as Map<String, dynamic>);

  Future<MediaState> media() async => MediaState.fromJson(
    await _send('GET', '/api/media', timeout: const Duration(seconds: 4)) as Map<String, dynamic>,
  );

  /// Capa do que está tocando, pela mesma conexão fixada (por isso não usa
  /// Image.network, que não teria o pin).
  Future<Uint8List?> mediaArt() async {
    if (device.pin.isEmpty) return null;
    final req = http.Request('GET', _uri('/api/media/art'))..headers.addAll(_headers);
    try {
      final res = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 6)));
      return res.statusCode == 200 && res.bodyBytes.length <= 5 << 20 ? res.bodyBytes : null;
    } on Exception {
      return null;
    }
  }

  /// action: play_pause, next ou previous.
  Future<void> mediaCommand(String action) => _send('POST', '/api/media/$action');

  Future<void> mediaSeek(int positionMs) => _send('POST', '/api/media/seek', body: {'position_ms': positionMs});

  Future<void> mediaVolume({double? volume, bool? muted}) =>
      _send('POST', '/api/media/volume', body: {'volume': ?volume?.clamp(0.0, 1.0), 'muted': ?muted});

  /// action: shutdown, reboot ou sleep. Devolve a contagem em segundos que o
  /// PC mostra antes de executar (0: na hora; agentes antigos não mandam).
  Future<int> power(String action) async => graceOf(await _send('POST', '/api/power', body: {'action': action}));

  static int graceOf(Object? response) =>
      response is Map && response['grace_s'] is num ? max(0, (response['grace_s'] as num).toInt()) : 0;

  /// Agenda shutdown ou sleep: daqui a [delay] ou quando a mídia parar.
  Future<void> schedulePower(String action, {Duration? delay, bool whenMediaStops = false}) => _send(
    'POST',
    '/api/power',
    body: {'action': action, 'delay_s': ?delay?.inSeconds, if (whenMediaStops) 'when': 'media_stopped'},
  );

  Future<void> cancelSchedule() => _send('DELETE', '/api/power/schedule');

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
  Stream<PcEvent> events() => _decoded(_sse('/api/events'), PcEvent.fromJson);

  /// Stats do PC empurrados pelo agente (feature "live"), em vez de polling.
  Stream<PcStats> liveStats() => _live('stats', PcStats.fromJson);

  /// Mídia empurrada pelo agente só quando muda (feature "live").
  Stream<MediaState> liveMedia() => _live('media', MediaState.fromJson);

  Stream<T> _live<T>(String topic, T Function(Map<String, dynamic>) parse) =>
      _decoded(_sse('/api/live', {'topics': topic}).where((m) => m.event == topic), parse);

  static Stream<T> _decoded<T>(Stream<({String event, String data})> s, T Function(Map<String, dynamic>) parse) =>
      s.expand((m) {
        try {
          return [parse(jsonDecode(m.data) as Map<String, dynamic>)];
        } on FormatException {
          return const []; // evento malformado, ignora
        }
      });

  /// Lê um fluxo SSE pela conexão fixada. O agente manda um ping a cada 20 s;
  /// sem nada por 45 s a conexão morreu e o fluxo termina com erro.
  Stream<({String event, String data})> _sse(String path, [Map<String, String>? query]) {
    final client = pinnedClient(device.pin);
    StreamSubscription<String>? lines;
    late final StreamController<({String event, String data})> out;
    void finish([Object? error]) {
      client.close();
      if (out.isClosed) return;
      if (error != null) out.addError(error);
      out.close();
    }

    out = StreamController(
      onListen: () async {
        try {
          final req = http.Request('GET', _uri(path, query))..headers.addAll(_headers);
          final res = await client.send(req).timeout(const Duration(seconds: 5));
          if (res.statusCode != 200) throw AgentException('Erro ${res.statusCode}');
          var event = 'message';
          lines = res.stream
              .timeout(const Duration(seconds: 45))
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen(
                (line) {
                  if (line.isEmpty) {
                    event = 'message';
                  } else if (line.startsWith('event: ')) {
                    event = line.substring(7);
                  } else if (line.startsWith('data: ')) {
                    out.add((event: event, data: line.substring(6)));
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
