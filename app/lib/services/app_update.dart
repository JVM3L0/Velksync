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
  UpdateException(this.message);
  @override
  String toString() => message;
}

/// Procura versão nova do app uma vez por dia e baixa o APK conferido.
/// A garantia final é do Android: ele só instala por cima um APK assinado
/// com a mesma chave do app instalado.
class AppUpdater {
  AppUpdater({http.Client? client, DateTime Function()? now, this.current = appVersion})
    : _http = client ?? http.Client(),
      _now = now ?? DateTime.now;

  final http.Client _http;
  final DateTime Function() _now;
  final String current;

  static const enabledKey = 'update_check';
  static const _checkedKey = 'update_checked_at', _releaseKey = 'update_release', _dismissedKey = 'update_dismissed';
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
          throw UpdateException('O GitHub respondeu ${res.statusCode}');
        }
      } on UpdateException {
        rethrow;
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
    }
  }

  /// "Agora não": some até sair uma versão mais nova que esta.
  Future<void> dismiss(String version) async =>
      (await SharedPreferences.getInstance()).setString(_dismissedKey, version);

  /// Baixa o APK do processador do celular e confere com o SHA256SUMS.
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
    final sums = parseSums(utf8.decode(await _get(sumsAsset.url, maxBytes: 64 << 10)));
    final want = sums[name];
    if (want == null) throw UpdateException('$name não está no SHA256SUMS');

    await dir.create(recursive: true);
    for (final old in dir.listSync().whereType<File>()) {
      old.deleteSync();
    }
    final file = File('${dir.path}/$name');
    final digest = await _stream(apk.url, file, total: apk.size, onProgress: onProgress);
    if (digest != want) {
      await file.delete();
      throw UpdateException('O arquivo baixado não confere com o SHA256SUMS');
    }
    return file;
  }

  Future<List<int>> _get(String url, {required int maxBytes}) async {
    final res = await _send(url);
    final bytes = <int>[];
    await for (final chunk in res.stream) {
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
      await for (final chunk in res.stream) {
        received += chunk.length;
        if (received > 200 << 20) throw UpdateException('APK grande demais');
        hasher.add(chunk);
        out.add(chunk);
        onProgress?.call(received, total);
      }
    } finally {
      hasher.close();
      await out.close();
    }
    return hash.value.toString();
  }

  /// GET seguindo redirecionamentos só dentro do GitHub.
  Future<http.StreamedResponse> _send(String url) async {
    var uri = Uri.parse(url);
    for (var hop = 0; hop < 5; hop++) {
      if (!downloadUrlOk(uri)) throw UpdateException('Endereço de download fora do GitHub');
      final req = http.Request('GET', uri)..followRedirects = false;
      final res = await _http.send(req).timeout(const Duration(seconds: 30));
      if (res.isRedirect || (res.statusCode >= 300 && res.statusCode < 400)) {
        final loc = res.headers['location'];
        await res.stream.drain<void>();
        if (loc == null) break;
        uri = uri.resolve(loc);
        continue;
      }
      if (res.statusCode != 200) throw UpdateException('Download falhou (${res.statusCode})');
      return res;
    }
    throw UpdateException('Redirecionamentos demais');
  }

  /// Processadores do celular, do preferido ao menos.
  static Future<List<String>> abis() async => (await _channel.invokeListMethod<String>('abis')) ?? const <String>[];

  /// Pasta própria para o APK (a única que o instalador do Android pode ler).
  static Future<Directory> downloadDir() async => Directory((await _channel.invokeMethod<String>('dir'))!);

  /// Abre o instalador do Android. false: falta liberar "instalar apps
  /// desta fonte" (o app abre essa tela; depois é só tocar de novo).
  static Future<bool> install(File apk) async => (await _channel.invokeMethod<bool>('install', {'path': apk.path}))!;
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
