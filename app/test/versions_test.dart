import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:velksync/services/versions.dart';
import 'package:velksync/ui/update_notice.dart';

void main() {
  group('comparação de versões', () {
    test('agente atrás, na frente ou igual', () {
      expect(versionGap(agent: '0.3.0', app: '0.4.0'), VersionGap.agentOld);
      expect(versionGap(agent: '0.5.0', app: '0.4.0'), VersionGap.appOld);
      expect(versionGap(agent: '0.4.0', app: '0.4.0'), VersionGap.none);
      expect(versionGap(agent: '1.0.0', app: '0.9.3'), VersionGap.appOld);
    });

    test('correção (patch) não gera aviso', () {
      expect(versionGap(agent: '0.4.0', app: '0.4.1'), VersionGap.none);
      expect(versionGap(agent: 'v0.4.2', app: '0.4.0+5'), VersionGap.none);
    });

    test('agente sem versão conta como antigo; app sem versão não avisa', () {
      expect(versionGap(agent: '', app: '0.4.0'), VersionGap.agentOld);
      expect(versionGap(agent: null, app: '0.4.0'), VersionGap.agentOld);
      expect(versionGap(agent: 'lixo', app: '0.4.0'), VersionGap.agentOld);
      expect(versionGap(agent: '0.3.0', app: ''), VersionGap.none);
    });
  });

  group('aviso', () {
    Widget banner(VersionGap gap, {VoidCallback? onDismiss, VoidCallback? onHowTo}) => MaterialApp(
      home: Scaffold(
        body: UpdateBanner(
          gap: gap,
          agentVersion: '0.3.0',
          appVersion: '0.4.0',
          onDismiss: onDismiss ?? () {},
          onHowTo: onHowTo ?? () {},
        ),
      ),
    );

    testWidgets('agente desatualizado e botões', (tester) async {
      var dismissed = 0, howTo = 0;
      await tester.pumpWidget(banner(VersionGap.agentOld, onDismiss: () => dismissed++, onHowTo: () => howTo++));
      expect(find.text('Agente desatualizado (0.3.0)'), findsOneWidget);
      await tester.tap(find.text('Agora não'));
      await tester.tap(find.text('Como atualizar'));
      expect((dismissed, howTo), (1, 1));
      final card = tester.getRect(find.byType(UpdateBanner));
      expect(tester.getRect(find.text('Como atualizar')).right, greaterThan(card.right - 80), reason: 'botões à direita');
    });

    testWidgets('app desatualizado', (tester) async {
      await tester.pumpWidget(banner(VersionGap.appOld));
      expect(find.text('App desatualizado (0.4.0)'), findsOneWidget);
    });
  });

  group('passo a passo', () {
    Future<void> open(WidgetTester tester, VersionGap gap, String os, {double scale = 1}) async {
      tester.view.physicalSize = const Size(960, 1600);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: const Size(320, 533), textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Builder(
                builder: (c) => TextButton(
                  onPressed: () => showUpdateSheet(c, gap: gap, os: os),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('Windows mostra o instalador do PowerShell', (tester) async {
      await open(tester, VersionGap.agentOld, 'windows');
      expect(find.text('Atualizar o agente no Windows'), findsOneWidget);
      expect(find.textContaining('install-windows.ps1'), findsOneWidget);
    });

    testWidgets('Linux mostra o install-linux.sh', (tester) async {
      await open(tester, VersionGap.agentOld, 'linux');
      expect(find.text('Atualizar o agente no Linux'), findsOneWidget);
      expect(find.textContaining('install-linux.sh'), findsWidgets);
    });

    testWidgets('app atrás mostra o APK', (tester) async {
      await open(tester, VersionGap.appOld, 'windows');
      expect(find.text('Atualizar o app'), findsOneWidget);
      expect(find.textContaining('arm64.apk'), findsOneWidget);
    });

    testWidgets('cabe em tela pequena com fonte 2×', (tester) async {
      await open(tester, VersionGap.agentOld, 'windows', scale: 2);
      expect(tester.takeException(), isNull);
    });
  });
}
