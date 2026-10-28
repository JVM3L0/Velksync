import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:velksync/models/device.dart';
import 'package:velksync/services/agent_client.dart';
import 'package:velksync/ui/history.dart';
import 'package:velksync/ui/send_sheet.dart';

void main() {
  test('quando aconteceu', () {
    final now = DateTime(2026, 11, 2, 23, 30);
    expect(historyWhen(now.subtract(const Duration(seconds: 20)), now), 'agora');
    expect(historyWhen(now.subtract(const Duration(minutes: 5)), now), 'há 5 min');
    expect(historyWhen(DateTime(2026, 11, 2, 9, 7), now), '09:07');
    expect(historyWhen(DateTime(2026, 11, 1, 21, 5), now), 'ontem 21:05');
    expect(historyWhen(DateTime(2026, 10, 25, 18, 0), now), '25/10 18:00');
  });

  test('histórico vindo do agente', () {
    final e = HistoryEntry.fromJson({
      'at': 1793000000000,
      'device': 'Pixel 9',
      'kind': 'power',
      'text': 'desligou o PC',
    });
    expect((e.device, e.kind, e.text, e.failed), ('Pixel 9', 'power', 'desligou o PC', false));
    expect(HistoryEntry.fromJson({}).device, '');
  });

  test('link sozinho abre no PC; o resto vai como texto', () {
    expect(isShareLink(' https://youtu.be/x '), isTrue);
    expect(isShareLink('olha https://youtu.be/x'), isFalse);
    expect(isShareLink('javascript:alert(1)'), isFalse);
    expect(isShareLink('Rua das Flores, 12'), isFalse);
  });

  testWidgets('atividade recente mostra as 3 últimas e "Ver tudo" abre o resto', (tester) async {
    final now = DateTime.now();
    final entries = [
      for (var i = 0; i < 5; i++)
        HistoryEntry(
          at: now.subtract(Duration(minutes: i)),
          device: 'Pixel',
          kind: 'command',
          text: 'rodou "$i"',
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: RecentActivity(entries: entries)),
        ),
      ),
    );
    expect(find.textContaining('rodou "2"'), findsOneWidget);
    expect(find.textContaining('rodou "3"'), findsNothing);
    await tester.tap(find.text('Ver tudo'));
    await tester.pumpAndSettle();
    expect(find.textContaining('rodou "4"'), findsOneWidget);
  });

  testWidgets('envio: só PCs pareados e ligados podem ser escolhidos', (tester) async {
    final on = Device(id: 'a', name: 'Velkhyro', host: '1', mac: 'aa', pin: 'p', deviceId: 'd', token: 't');
    final off = Device(id: 'b', name: 'Notebook', host: '2', mac: 'bb', pin: 'p', deviceId: 'd', token: 't');
    Device? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () async => picked = await showSendSheet(
                c,
                text: 'https://x.com',
                devices: [on, off],
                online: (d) => d.id == 'a',
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('O link abre no navegador do PC.'), findsOneWidget);
    await tester.tap(find.text('Notebook'));
    await tester.pumpAndSettle();
    expect(picked, isNull, reason: 'desligado não pode ser escolhido');
    await tester.tap(find.text('Velkhyro'));
    await tester.pumpAndSettle();
    expect(picked?.id, 'a');
  });
}
