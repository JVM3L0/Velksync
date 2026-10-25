import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:velksync/models/device.dart';
import 'package:velksync/services/agent_client.dart';
import 'package:velksync/ui/media_panel.dart';

/// PC falso: responde à mídia sem rede e anota os comandos recebidos.
class FakePc extends AgentClient {
  FakePc() : super(const Device(id: 'pc', name: 'PC', host: '127.0.0.1'));

  String title = 'Numb';
  final sent = <String>[];

  @override
  Future<MediaState> media() async => MediaState.fromJson({
    'available': true,
    'status': 'playing',
    'title': title,
    'artist': 'Linkin Park',
    'can_control': true,
    'duration_ms': 180000,
  });

  @override
  Future<Uint8List?> mediaArt() async => null;

  @override
  Future<void> mediaCommand(String action) async {
    sent.add(action);
    if (action == 'next') title = 'Faint';
    if (action == 'previous') title = 'In the End';
  }
}

void main() {
  testWidgets('arrastar a capa para a esquerda pula para a próxima', (tester) async {
    final pc = FakePc();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MediaPanel(client: pc))));
    await tester.pump();
    expect(find.text('Numb'), findsOneWidget);

    final center = tester.getCenter(find.text('Numb')).dx;
    await tester.drag(find.text('Numb'), const Offset(-250, 0));
    // O app relê o PC logo depois do comando: a faixa nova já está entrando.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    expect(pc.sent, ['next']);
    expect(tester.getCenter(find.text('Faint')).dx, greaterThan(center + 20), reason: 'entra pela direita');
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Faint'), findsOneWidget);
    expect(find.text('Numb'), findsNothing);
  });

  testWidgets('arrasto curto e lento não pula', (tester) async {
    final pc = FakePc();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MediaPanel(client: pc))));
    await tester.pump();
    await tester.timedDrag(find.text('Numb'), const Offset(-40, 0), const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(pc.sent, isEmpty);
    expect(find.text('Numb'), findsOneWidget);
  });
}
