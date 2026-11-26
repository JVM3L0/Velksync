import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'versions.dart';

/// Versão publicada no GitHub (a última que não é rascunho nem pré-versão).
class AppRelease {
  final String version;
  final String page;
  final String notes;
  final Map<String, ({String url, int size})> assets;

  const AppRelease({required this.version, required this.page, this.notes = '', this.assets = const {}});

  factory AppRelease.fromGitHub(Map<String, dynamic> j) => AppRelease(
    version: (j['tag_name'] as String? ?? '').replaceFirst(RegExp('^v'), ''),
    page: j['html_url'] as String? ?? releasesUrl,
    notes: j['body'] as String? ?? '',
    assets: {
      for (final a in j['assets'] as List? ?? const [])
        if (a is Map && a['name'] is String && a['browser_download_url'] is String)
          a['name'] as String: (url: a['browser_download_url'] as String, size: (a['size'] as num?)?.toInt() ?? 0),
    },
  );

  Map<String, dynamic> toJson() => {
    'tag_name': 'v$version',
    'html_url': page,
    'body': notes,
    'assets': [
      for (final e in assets.entries) {'name': e.key, 'browser_download_url': e.value.url, 'size': e.value.size},
    ],
  };
}

/// "0.6.0" > "0.5.1"? Aceita "v" na frente e "+build"; pré-versão ("-beta") nunca é mais nova.
bool isNewerVersion(String candidate, String current) {
  List<int>? parse(String v) {
    final m = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(\+\d+)?$').firstMatch(v.trim());
    return m == null ? null : [for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)];
  }

  final c = parse(candidate), r = parse(current);
  if (c == null || r == null) return false;
  for (var i = 0; i < 3; i++) {
    if (c[i] != r[i]) return c[i] > r[i];
  }
  return false;
}

/// Só HTTPS e só do GitHub (o download redireciona para o servidor de arquivos dele).
bool downloadUrlOk(Uri u) =>
    u.scheme == 'https' &&
    u.userInfo.isEmpty &&
    (u.host == 'github.com' || u.host == 'api.github.com' || u.host.endsWith('.githubusercontent.com'));

/// APK da release para o processador do celular, na ordem de preferência do Android.
String? apkAssetFor(String version, List<String> abis) {
  const names = {'arm64-v8a': 'arm64', 'armeabi-v7a': 'armv7', 'x86_64': 'x86_64'};
  for (final abi in abis) {
    if (names[abi] case final suffix?) return 'velksync-v$version-$suffix.apk';
  }
  return null;
}

/// SHA256SUMS (`<hash>  <arquivo>`) em arquivo → hash.
Map<String, String> parseSums(String text) => {
  for (final line in const LineSplitter().convert(text))
    if (RegExp(r'^([0-9a-fA-F]{64})\s+\*?(\S+)$').firstMatch(line.trim()) case final m?)
      m.group(2)!: m.group(1)!.toLowerCase(),
};

class UpdateException implements Exception {
  final String message;

  /// Falha passageira (rede, servidor): vale tentar de novo.
  final bool transient;
  UpdateException(this.message, {this.transient = false});
  @override
  String toString() => message;
}

/// Procura versão nova do app uma vez por dia e baixa o APK conferido.
/// A garantia final é do Android: ele só instala por cima um APK assinado
/// com a mesma chave do app instalado.
class AppUpdater {
  AppUpdater({
    http.Client? client,
    DateTime Function()? now,
    this.current = appVersion,
    this.backoff = const Duration(seconds: 2),
    this.stall = const Duration(seconds: 30),
  }) : _http = client ?? http.Client(),
       _now = now ?? DateTime.now;

  final http.Client _http;
  final DateTime Function() _now;
  final String current;

  /// Espera antes de tentar de novo, e quanto o download pode ficar parado.
  final Duration backoff, stall;

  static const enabledKey = 'update_check';
  static const _checkedKey = 'update_checked_at', _releaseKey = 'update_release', _dismissedKey = 'update_dismissed';
  static const _fromKey = 'update_installing_from';
  static const _api = 'https://api.github.com/repos/JVM3L0/Velksync/releases/latest';
  static const _channel = MethodChannel('velksync/update');

  /// Builds de desenvolvimento (outro pacote, outra assinatura) não se atualizam.
  static bool get supported => kReleaseMode && Platform.isAndroid;

  /// Versão nova ainda não dispensada; null sem novidade ou com a checagem desligada.
  /// [force] é o "Procurar agora": consulta na hora (mesmo desligada ou já
  /// feita hoje), avisa se não conseguiu e traz de volta uma versão dispensada.
  Future<AppRelease?> check({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    if (current.isEmpty || (!force && !(prefs.getBool(enabledKey) ?? true))) return null;
    var release = _cached(prefs);
    final checked = DateTime.fromMillisecondsSinceEpoch(prefs.getInt(_checkedKey) ?? 0);
    if (force || _now().difference(checked) >= const Duration(days: 1)) {
      try {
        final res = await _http
            .get(Uri.parse(_api), headers: {'Accept': 'application/vnd.github+json'})
            .timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          final j = jsonDecode(res.body) as Map<String, dynamic>;
          if (j['draft'] != true && j['prerelease'] != true) {
            release = AppRelease.fromGitHub(j);
            await prefs.setString(_releaseKey, jsonEncode(release.toJson()));
          }
          await prefs.setInt(_checkedKey, _now().millisecondsSinceEpoch);
        } else if (force) {
          throw _statusError(res.statusCode, res.headers);
        }
      } on UpdateException {
        rethrow;
      } on FormatException {
        if (force) throw UpdateException('Resposta inesperada do GitHub');
      } on TypeError {
        // JSON válido com outro formato (portal de Wi-Fi, proxy).
        if (force) throw UpdateException('Resposta inesperada do GitHub');
      } on Exception {
        // Sem internet: tenta na próxima vez que abrir (ou avisa, no manual).
        if (force) throw UpdateException('Sem conexão com o GitHub');
      }
    }
    if (release == null || !isNewerVersion(release.version, current)) return null;
    if (prefs.getString(_dismissedKey) == release.version) {
      if (!force) return null;
      await prefs.remove(_dismissedKey);
    }
    return release;
  }

  AppRelease? _cached(SharedPreferences prefs) {
    final raw = prefs.getString(_releaseKey);
    if (raw == null) return null;
    try {
      return AppRelease.fromGitHub(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  /// "Agora não": some até sair uma versão mais nova que esta.
  Future<void> dismiss(String version) async =>
      (await SharedPreferences.getInstance()).setString(_dismissedKey, version);

  /// Baixa o APK do processador do celular e confere com o SHA256SUMS. Um APK
  /// já baixado e íntegro é reaproveitado (depois de liberar a permissão de
  /// instalar, por exemplo). Falha sempre como [UpdateException].
  Future<File> download(
    AppRelease r, {
    required List<String> abis,
    required Directory dir,
    void Function(int received, int total)? onProgress,
  }) async {
    final name = apkAssetFor(r.version, abis);
    final apk = name == null ? null : r.assets[name];
    final sumsAsset = r.assets['SHA256SUMS'];
    if (apk == null || sumsAsset == null) throw UpdateException('Esta versão não tem APK para este celular');
    try {
      final sumsBytes = await _retry(() => _get(sumsAsset.url, maxBytes: 64 << 10));
      final want = parseSums(utf8.decode(sumsBytes, allowMalformed: true))[name];
      if (want == null) throw UpdateException('$name não está no SHA256SUMS');

      await dir.create(recursive: true);
      final file = File('${dir.path}/$name');
      for (final old in dir.listSync().whereType<File>()) {
        if (old.uri.pathSegments.last != name) old.deleteSync();
      }
      if (file.existsSync()) {
        if ((await sha256.bind(file.openRead()).first).toString() == want) return file;
        file.deleteSync();
      }

      // Só ganha o nome final depois de conferido.
      final part = File('${file.path}.part');
      try {
        final digest = await _retry(() => _stream(apk.url, part, total: apk.size, onProgress: onProgress));
        if (digest != want) throw UpdateException('O arquivo baixado não confere com o SHA256SUMS');
        return await part.rename(file.path);
      } finally {
        if (part.existsSync()) part.deleteSync();
      }
    } on FileSystemException {
      throw UpdateException('Não deu para gravar o arquivo. Veja se há espaço livre no celular');
    }
  }

  /// Repete só as falhas passageiras, esperando um pouco mais a cada vez, e
  /// traduz os erros de rede.
  Future<T> _retry<T>(Future<T> Function() f) async {
    for (var attempt = 1; ; attempt++) {
      UpdateException error;
      try {
        return await f();
      } on UpdateException catch (e) {
        error = e;
      } on TimeoutException {
        error = UpdateException('A conexão ficou parada. Tente de novo', transient: true);
      } on SocketException {
        error = UpdateException('Sem conexão com o GitHub', transient: true);
      } on HttpException {
        error = UpdateException('A conexão caiu no meio do download', transient: true);
      } on http.ClientException {
        error = UpdateException('A conexão caiu no meio do download', transient: true);
      } on TlsException {
        error = UpdateException('Conexão segura recusada. Confira a data do celular e o Wi-Fi');
      }
      if (!error.transient || attempt == 3) throw error;
      await Future<void>.delayed(backoff * attempt);
    }
  }

  static UpdateException _statusError(int status, Map<String, String> headers) {
    if (status == 429 || (status == 403 && headers['x-ratelimit-remaining'] == '0')) {
      return UpdateException('O GitHub limitou as consultas. Tente de novo em uma hora');
    }
    if (status >= 500) return UpdateException('O GitHub está fora do ar ($status)', transient: true);
    return UpdateException('O GitHub respondeu $status');
  }

  Future<List<int>> _get(String url, {required int maxBytes}) async {
    final res = await _send(url);
    final bytes = <int>[];
    await for (final chunk in res.stream.timeout(stall)) {
      bytes.addAll(chunk);
      if (bytes.length > maxBytes) throw UpdateException('Resposta grande demais');
    }
    return bytes;
  }

  Future<String> _stream(
    String url,
    File file, {
    required int total,
    void Function(int received, int total)? onProgress,
  }) async {
    final res = await _send(url);
    final out = file.openWrite();
    final hash = _DigestSink();
    final hasher = sha256.startChunkedConversion(hash);
    var received = 0;
    try {
      // addStream respeita a velocidade do disco e entrega os erros de gravação.
      await out.addStream(
        res.stream.timeout(stall).map((chunk) {
          received += chunk.length;
          if (received > 200 << 20) throw UpdateException('APK grande demais');
          hasher.add(chunk);
          onProgress?.call(received, total);
          return chunk;
        }),
      );
      await out.flush();
    } finally {
      hasher.close();
      await out.close();
    }
    if (total > 0 && received < total) throw UpdateException('O download veio incompleto', transient: true);
    return hash.value.toString();
  }

  /// Larga o corpo sem esperar por ele: um proxy pode nunca terminar de mandar.
  static void _discard(http.StreamedResponse res) => unawaited(res.stream.listen(null).cancel());

  /// GET seguindo redirecionamentos só dentro do GitHub.
  Future<http.StreamedResponse> _send(String url) async {
    var uri = Uri.parse(url);
    for (var hop = 0; hop < 5; hop++) {
      if (!downloadUrlOk(uri)) throw UpdateException('Endereço de download fora do GitHub');
      final req = http.Request('GET', uri)..followRedirects = false;
      final res = await _http.send(req).timeout(stall);
      if (res.isRedirect || (res.statusCode >= 300 && res.statusCode < 400)) {
        final loc = res.headers['location'];
        _discard(res);
        if (loc == null) break;
        uri = uri.resolve(loc);
        continue;
      }
      if (res.statusCode != 200) {
        _discard(res);
        throw _statusError(res.statusCode, res.headers);
      }
      return res;
    }
    throw UpdateException('Redirecionamentos demais');
  }

  /// Processadores do celular, do preferido ao menos.
  static Future<List<String>> abis() async => (await _channel.invokeListMethod<String>('abis')) ?? const <String>[];

  /// Pasta própria para o APK (a única que o instalador do Android pode ler).
  static Future<Directory> downloadDir() async => Directory((await _channel.invokeMethod<String>('dir'))!);

  /// Entrega o APK ao Android. false: falta liberar "instalar apps desta
  /// fonte" (o app abre essa tela; depois é só tocar de novo). Dando certo, o
  /// Android encerra o app; o resto chega em [onInstallStatus].
  static Future<bool> install(File apk) async => (await _channel.invokeMethod<bool>('install', {'path': apk.path}))!;

  /// [onConfirm]: o Android abriu a tela de confirmação. [onFailed]: não
  /// instalou, com o motivo. null nos dois para parar de ouvir.
  static void onInstallStatus({void Function()? onConfirm, void Function(String why)? onFailed}) {
    _channel.setMethodCallHandler(
      onConfirm == null && onFailed == null
          ? null
          : (call) async {
              if (call.method != 'status') return;
              final args = call.arguments as Map;
              if (args['status'] == 'confirm') {
                onConfirm?.call();
              } else {
                onFailed?.call(args['message'] as String? ?? 'O Android não conseguiu instalar');
              }
            },
    );
  }

  /// Marca que uma instalação começou a partir desta versão.
  Future<void> markInstalling() async => (await SharedPreferences.getInstance()).setString(_fromKey, current);

  /// true uma única vez, ao abrir já na versão nova instalada pelo app.
  Future<bool> takeUpdated() async {
    final prefs = await SharedPreferences.getInstance();
    final from = prefs.getString(_fromKey);
    if (from == null || !isNewerVersion(current, from)) return false;
    await prefs.remove(_fromKey);
    return true;
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
