import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:velksync/models/device.dart';
import 'package:velksync/screens/onboarding_screen.dart';
import 'package:velksync/services/pc_probe.dart';
import 'package:velksync/services/wake_tracker.dart';

const _pc = Device(id: 'a', name: 'Velkhyro', host: '192.168.3.5', mac: 'aa:bb:cc:dd:ee:ff');

Future<void> _open(WidgetTester tester, WakeTracker wakes, {Device? added = _pc}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (c) => TextButton(
          onPressed: () => Navigator.push(
            c,
            MaterialPageRoute(
              builder: (_) => OnboardingScreen(wakes: wakes, addPc: () async => added),
            ),
          ),
          child: const Text('abrir'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

Future<void> _toTest(WidgetTester tester) async {
  await tester.tap(find.text('Começar'));
  await tester.pumpAndSettle();
  expect(find.text('Instale o agente no PC'), findsOneWidget);
  await tester.tap(find.text('Já instalei'));
  await tester.pumpAndSettle();
  expect(find.text('Pareie o celular'), findsOneWidget);
  await tester.tap(find.text('Adicionar PC'));
  await tester.pumpAndSettle();
  expect(find.text('Teste: ligar pelo celular'), findsOneWidget);
}

void main() {
  testWidgets('passo a passo até o PC ligar', (tester) async {
    var online = false;
    final wakes = WakeTracker(
      send: (_) async {},
      probe: (_) async => online ? const PcState.awaitingLogin('windows') : const PcState.offline(),
      probeEvery: const Duration(seconds: 1),
    );
    await _open(tester, wakes);
    expect(find.text('1 de 4'), findsOneWidget);
    await _toTest(tester);
    await tester.tap(find.text('Ligar'));
    await tester.pump();
    expect(find.text('Ligando Velkhyro…'), findsOneWidget);
    online = true;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Funcionou!'), findsOneWidget);
    await tester.tap(find.text('Concluir'));
    await tester.pumpAndSettle();
    expect(find.text('abrir'), findsOneWidget, reason: 'fechou o guia');
    wakes.dispose();
  });

  testWidgets('PC que não liga mostra as dicas e deixa tentar de novo', (tester) async {
    final wakes = WakeTracker(
      send: (_) async {},
      probe: (_) async => const PcState.offline(),
      probeEvery: const Duration(seconds: 1),
      giveUpAfter: const Duration(seconds: 3),
    );
    await _open(tester, wakes);
    await _toTest(tester);
    await tester.tap(find.text('Ligar'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pumpAndSettle();
    expect(find.text('O PC não ligou'), findsOneWidget);
    expect(find.text('Ver dicas'), findsOneWidget);
    expect(find.text('Tentar de novo'), findsOneWidget);
    await tester.tap(find.text('Pular o teste'));
    await tester.pumpAndSettle();
    expect(find.text('abrir'), findsOneWidget);
    wakes.dispose();
  });

  testWidgets('dá para pular logo no começo, e cancelar o cadastro não avança', (tester) async {
    final wakes = WakeTracker(send: (_) async {}, probe: (_) async => const PcState.offline());
    await _open(tester, wakes, added: null);
    await tester.tap(find.text('Começar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Já instalei'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar PC'));
    await tester.pumpAndSettle();
    expect(find.text('Pareie o celular'), findsOneWidget, reason: 'sem PC salvo, fica no passo 3');
    await tester.tap(find.text('Pular'));
    await tester.pumpAndSettle();
    expect(find.text('abrir'), findsOneWidget);
    wakes.dispose();
  });
}
