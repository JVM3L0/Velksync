import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velksync/services/app_update.dart';
import 'package:velksync/services/versions.dart';
import 'package:velksync/ui/update_notice.dart';

const _gh = 'https://github.com/JVM3L0/Velksync/releases/download/v0.6.0';

Map<String, dynamic> _release({String tag = 'v0.6.0', bool pre = false}) => {
  'tag_name': tag,
  'html_url': 'https://github.com/JVM3L0/Velksync/releases/tag/$tag',
  'body': '### Adicionado\n- Atualização pelo app\n- Capas em alta no Pear\n- Terceira',
  'prerelease': pre,
  'assets': [
    {'name': 'SHA256SUMS', 'browser_download_url': '$_gh/SHA256SUMS', 'size': 100},
    {'name': 'velksync-v0.6.0-arm64.apk', 'browser_download_url': '$_gh/velksync-v0.6.0-arm64.apk', 'size': 3},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('compara versões', () {
    expect(isNewerVersion('0.6.0', '0.5.0'), isTrue);
    expect(isNewerVersion('v0.10.0', '0.9.9'), isTrue);
    expect(isNewerVersion('0.5.0', '0.5.0'), isFalse);
    expect(isNewerVersion('0.4.9', '0.5.0'), isFalse);
    expect(isNewerVersion('0.6.0-beta', '0.5.0'), isFalse);
    expect(isNewerVersion('0.6.0', ''), isFalse);
  });

  test('escolhe o APK pelo processador', () {
    expect(apkAssetFor('0.6.0', ['arm64-v8a', 'armeabi-v7a']), 'velksync-v0.6.0-arm64.apk');
    expect(apkAssetFor('0.6.0', ['armeabi-v7a', 'armeabi']), 'velksync-v0.6.0-armv7.apk');
    expect(apkAssetFor('0.6.0', ['x86_64']), 'velksync-v0.6.0-x86_64.apk');
    expect(apkAssetFor('0.6.0', ['mips']), isNull);
  });

  test('só baixa do GitHub por HTTPS', () {
    expect(downloadUrlOk(Uri.parse('$_gh/x.apk')), isTrue);
    expect(downloadUrlOk(Uri.parse('https://objects.githubusercontent.com/x')), isTrue);
    expect(downloadUrlOk(Uri.parse('http://github.com/x')), isFalse);
    expect(downloadUrlOk(Uri.parse('https://github.com.evil.com/x')), isFalse);
    expect(downloadUrlOk(Uri.parse('https://evilgithubusercontent.com/x')), isFalse);
  });

  test('lê o SHA256SUMS', () {
    final h = 'ab' * 32;
    expect(parseSums('$h  a.apk\n${h.toUpperCase()} *b.exe\nlixo'), {'a.apk': h, 'b.exe': h});
  });

  test('consulta no máximo uma vez por dia, respeita "Agora não" e o interruptor', () async {
    var now = DateTime(2026, 11, 1, 9);
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      return http.Response(jsonEncode(_release()), 200);
    });
    final u = AppUpdater(client: client, now: () => now, current: '0.5.0');

    expect((await u.check())?.version, '0.6.0');
    expect((await u.check())?.version, '0.6.0'); // do cache
    now = now.add(const Duration(hours: 23));
    await u.check();
    expect(calls, 1);
    now = now.add(const Duration(hours: 2));
    await u.check();
    expect(calls, 2);

    await u.dismiss('0.6.0');
    expect(await u.check(), isNull);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppUpdater.enabledKey, false);
    now = now.add(const Duration(days: 3));
    expect(await u.check(), isNull);
    expect(calls, 2, reason: 'desligado não vai à rede');
  });

  test('ignora pré-versão, versão igual e erro de rede', () async {
    var u = AppUpdater(
      client: MockClient((_) async => http.Response(jsonEncode(_release(pre: true)), 200)),
      current: '0.5.0',
    );
    expect(await u.check(), isNull);
    SharedPreferences.setMockInitialValues({});
    u = AppUpdater(client: MockClient((_) async => http.Response(jsonEncode(_release()), 200)), current: '0.6.0');
    expect(await u.check(), isNull);
    SharedPreferences.setMockInitialValues({});
    u = AppUpdater(client: MockClient((_) async => throw const SocketException('sem rede')), current: '0.5.0');
    expect(await u.check(), isNull);
  });

  group('download', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('velksync-update'));
    tearDown(() => dir.deleteSync(recursive: true));

    AppUpdater updater(List<int> apk, {String? sums, Map<String, String>? redirect}) => AppUpdater(
      current: '0.5.0',
      client: MockClient((req) async {
        final url = req.url.toString();
        if (redirect?[url] case final to?) return http.Response('', 302, headers: {'location': to});
        if (url.endsWith('SHA256SUMS')) {
          return http.Response(sums ?? '${sha256.convert(apk)}  velksync-v0.6.0-arm64.apk\n', 200);
        }
        return http.Response.bytes(apk, 200);
      }),
    );

    test('baixa e confere o APK', () async {
      final r = AppRelease.fromGitHub(_release());
      final progress = <int>[];
      final f = await updater([1, 2, 3])
          .download(r, abis: ['arm64-v8a'], dir: dir, onProgress: (got, _) => progress.add(got));
      expect(f.readAsBytesSync(), [1, 2, 3]);
      expect(progress.last, 3);
    });

    test('recusa APK que não bate com o SHA256SUMS e apaga', () async {
      final r = AppRelease.fromGitHub(_release());
      final u = updater([6, 6, 6], sums: '${sha256.convert([1, 2, 3])}  velksync-v0.6.0-arm64.apk\n');
      await expectLater(u.download(r, abis: ['arm64-v8a'], dir: dir), throwsA(isA<UpdateException>()));
      expect(dir.listSync(), isEmpty);
    });

    test('não segue redirecionamento para fora do GitHub', () async {
      final r = AppRelease.fromGitHub(_release());
      final u = updater([1], redirect: {'$_gh/SHA256SUMS': 'https://evil.example/SHA256SUMS'});
      await expectLater(u.download(r, abis: ['arm64-v8a'], dir: dir), throwsA(isA<UpdateException>()));
    });

    test('sem APK para o processador', () async {
      final r = AppRelease.fromGitHub(_release());
      await expectLater(updater([1]).download(r, abis: ['mips'], dir: dir), throwsA(isA<UpdateException>()));
    });
  });

  test('destaques do CHANGELOG', () {
    expect(AppUpdateCard.highlights('### Adicionado\n- Um\n- Dois\n- Três\n\n### Corrigido\n- Quatro'), 'Um · Dois');
  });

  testWidgets('cartão: Agora não, Atualizar e progresso', (tester) async {
    var dismissed = false, updated = false;
    Widget card({double? progress}) => MaterialApp(
      home: Scaffold(
        body: AppUpdateCard(
          release: AppRelease.fromGitHub(_release()),
          progress: progress,
          onDismiss: () => dismissed = true,
          onUpdate: () => updated = true,
        ),
      ),
    );
    await tester.pumpWidget(card());
    expect(find.text('Velksync 0.6.0 disponível'), findsOneWidget);
    expect(find.textContaining('Atualização pelo app · Capas em alta no Pear'), findsOneWidget);
    await tester.tap(find.text('Agora não'));
    await tester.tap(find.text('Atualizar'));
    expect((dismissed, updated), (true, true));

    await tester.pumpWidget(card(progress: 0.42));
    expect(find.text('Baixando… 42%'), findsOneWidget);
    expect(find.text('Atualizar'), findsNothing);
  });

  testWidgets('aviso do agente com versão nova: no Windows aponta para o ícone', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpdateBanner(
            gap: VersionGap.agentOld,
            agentVersion: '0.6.0',
            appVersion: '0.6.0',
            available: '0.6.1',
            os: 'windows',
            onDismiss: () {},
            onHowTo: null,
          ),
        ),
      ),
    );
    expect(find.text('Agente 0.6.1 disponível no PC'), findsOneWidget);
    expect(find.textContaining('ícone do Velksync no PC'), findsOneWidget);
    expect(find.text('Como atualizar'), findsNothing);
  });
}
