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
  bool stuck = false; // o player demora a trocar de faixa
  final sent = <String>[];

  @override
  Future<MediaState> media() async => MediaState.fromJson({
    'available': true,
    'status': 'playing',
    'title': title,
    'artist': 'Linkin Park',
    'can_control': true,
    'duration_ms': 180000,
    'position_ms': 60000,
    'player': 'Helium',
    'volume': volume,
    'muted': false,
  });

  double volume = 0.5;

  @override
  Future<void> mediaVolume({double? volume, bool? muted}) async {
    if (volume != null) this.volume = volume;
  }

  @override
  Future<Uint8List?> mediaArt() async => null;

  @override
  Future<void> mediaCommand(String action) async {
    sent.add(action);
    if (stuck) return;
    if (action == 'next') title = 'Faint';
    if (action == 'previous') title = 'In the End';
  }
}

void main() {
  testWidgets('arrastar a capa para a esquerda pula para a próxima', (tester) async {
    final pc = FakePc();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MediaPanel(client: pc)),
      ),
    );
    await tester.pump();
    expect(find.text('Numb'), findsOneWidget);

    final center = tester.getCenter(find.text('Numb')).dx;
    await tester.drag(find.byType(MediaCover), const Offset(-250, 0));
    // O app relê o PC logo depois do comando: a faixa nova já está entrando.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    expect(pc.sent, ['next']);
    expect(tester.getCenter(find.text('Faint')).dx, greaterThan(center + 20), reason: 'entra pela direita');
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Faint'), findsOneWidget);
    expect(find.text('Numb'), findsNothing);
  });

  testWidgets('a barra para em 0:00 enquanto a faixa troca', (tester) async {
    final pc = FakePc()..stuck = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MediaPanel(client: pc)),
      ),
    );
    await tester.pump();
    expect(find.text('1:00'), findsOneWidget);
    await tester.tap(find.byTooltip('Próxima'));
    await tester.pump();
    expect(find.text('0:00'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('0:00'), findsOneWidget, reason: 'a faixa antiga não segue correndo');
    pc.stuck = false;
    pc.title = 'Faint';
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Faint'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('arrasto curto e lento não pula', (tester) async {
    final pc = FakePc();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MediaPanel(client: pc)),
      ),
    );
    await tester.pump();
    await tester.timedDrag(find.byType(MediaCover), const Offset(-40, 0), const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(pc.sent, isEmpty);
    expect(find.text('Numb'), findsOneWidget);
  });

  testWidgets('título longo não empurra os controles', (tester) async {
    Future<double> playY(String title) async {
      final pc = FakePc()..title = title;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MediaPanel(client: pc)),
        ),
      );
      await tester.pump();
      return tester.getCenter(find.byTooltip('Próxima')).dy;
    }

    final short = await playY('Numb');
    final long = await playY('Uma faixa com um título enorme que antes ocupava duas linhas inteiras e mais um pouco');
    expect(long, short);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('volume fica num botão e o slider some sozinho', (tester) async {
    tester.view.physicalSize = const Size(1220, 2712); // motorola edge 70
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final pc = FakePc();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MediaPanel(client: pc)),
      ),
    );
    await tester.pump();
    expect(find.byType(Slider), findsOneWidget, reason: 'só a barra de progresso');
    final next = tester.getCenter(find.byTooltip('Próxima')).dy;

    await tester.tap(find.byTooltip('Volume'));
    await tester.pump(); // a animação de abrir começa neste quadro
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(VerticalVolume), findsOneWidget);
    expect(tester.getCenter(find.byTooltip('Próxima')).dy, next, reason: 'abrir o volume não mexe nos controles');

    final volume = find.byKey(const ValueKey('volume'));
    expect(volume, findsOneWidget);
    final pill = find.ancestor(of: volume, matching: find.byType(Material)).first;
    expect(tester.getSize(pill).height, inInclusiveRange(200, 260), reason: 'pílula vertical, sem esticar pela tela');
    expect(tester.getSize(pill).width, lessThan(80));
    await tester.drag(volume, const Offset(0, 80)); // para baixo = mais baixo
    await tester.pump(const Duration(milliseconds: 300));
    expect(pc.volume, lessThan(0.5), reason: 'o volume chega ao PC');

    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(VerticalVolume), findsNothing, reason: 'fechou depois de 5 s parado');
    await tester.pumpWidget(const SizedBox());
  });

  group('proteção contra toque acidental (capa de 280 px: pula a partir de 112)', () {
    Future<FakePc> open(WidgetTester tester) async {
      final pc = FakePc();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MediaPanel(client: pc)),
        ),
      );
      await tester.pump();
      return pc;
    }

    testWidgets('arrastar menos de 40% e soltar devolve a capa', (tester) async {
      final pc = await open(tester);
      await tester.timedDrag(find.byType(MediaCover), const Offset(-100, 0), const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      expect(pc.sent, isEmpty);
      expect(find.text('Numb'), findsOneWidget);
    });

    testWidgets('passar do ponto e voltar o dedo cancela', (tester) async {
      final pc = await open(tester);
      final g = await tester.startGesture(tester.getCenter(find.byType(MediaCover)));
      for (var i = 0; i < 10; i++) {
        await g.moveBy(const Offset(-20, 0)); // 200 px: armado
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 200));
      for (var i = 0; i < 10; i++) {
        await g.moveBy(const Offset(18, 0)); // volta para 20 px
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 300));
      await g.up();
      await tester.pumpAndSettle();
      expect(pc.sent, isEmpty);
    });

    testWidgets('piparote rápido mas curto não pula', (tester) async {
      final pc = await open(tester);
      await tester.fling(find.byType(MediaCover), const Offset(-50, 0), 3000);
      await tester.pumpAndSettle();
      expect(pc.sent, isEmpty);
    });

    testWidgets('piparote rápido e longo pula', (tester) async {
      final pc = await open(tester);
      await tester.fling(find.byType(MediaCover), const Offset(-90, 0), 3000);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(pc.sent, ['next']);
      await tester.pumpAndSettle();
      expect(find.text('Faint'), findsOneWidget);
    });
  });
}
