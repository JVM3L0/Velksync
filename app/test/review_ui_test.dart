import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:velksync/models/device.dart';
import 'package:velksync/screens/device_screen.dart';
import 'package:velksync/ui/perf.dart';
import 'package:velksync/ui/wake_help.dart';
import 'package:velksync/ui/widgets.dart';

Widget app(Widget child) => MaterialApp(home: child);

void main() {
  group('energia mostra só o que faz sentido', () {
    testWidgets('PC sem pareamento, com MAC: só um "Ligar" grande', (tester) async {
      const d = Device(id: 'x', name: 'PC', host: '10.0.0.9', mac: 'aa:bb:cc:dd:ee:ff');
      await tester.pumpWidget(app(DeviceScreen(device: d, onEdit: () {})));
      await tester.pump();
      expect(find.text('Ligar'), findsOneWidget);
      for (final gone in ['Desligar', 'Reiniciar', 'Suspender', 'Agendar']) {
        expect(find.text(gone), findsNothing, reason: '$gone não serve com o PC desligado');
      }
      final tile = tester.getSize(find.byType(MorphTile));
      expect(tile.width, greaterThan(700), reason: 'ocupa a linha toda');
    });

    testWidgets('sem MAC não há botão desativado nem seção vazia', (tester) async {
      const d = Device(id: 'y', name: 'PC', host: '10.0.0.9');
      await tester.pumpWidget(app(DeviceScreen(device: d, onEdit: () {})));
      await tester.pump();
      expect(find.byType(MorphTile), findsNothing);
      expect(find.text('Energia'), findsNothing);
    });
  });

  test('tempo em linguagem natural', () {
    expect(humanElapsed(const Duration(seconds: 38)), '38 s');
    expect(humanElapsed(const Duration(seconds: 65)), '1 min 5 s');
    expect(humanElapsed(const Duration(minutes: 2)), '2 min');
  });

  testWidgets('o ícone dá um pulo quando o PC liga', (tester) async {
    Widget pop(bool active) => app(WakePop(active: active, child: const SizedBox.square(dimension: 60)));
    double scale() => tester.widget<ScaleTransition>(find.byType(ScaleTransition)).scale.value;
    await tester.pumpWidget(pop(false));
    expect(scale(), 1);
    await tester.pumpWidget(pop(true));
    await tester.pump(const Duration(milliseconds: 16));
    expect(scale(), lessThan(1));
    await tester.pump(const Duration(seconds: 1));
    expect(scale(), 1);
  });

  group('cartão de CPU', () {
    Widget card({double? temp}) => app(
      Scaffold(
        body: HeroCard(
          icon: Symbols.memory_rounded,
          label: 'CPU',
          subLabel: 'Ryzen',
          usage: 0.2,
          accent: Colors.orange,
          temperature: temp,
          fallback: (icon: Symbols.timer_rounded, text: 'Ligado há 1 h 52 min', fraction: null),
        ),
      ),
    );

    testWidgets('sem temperatura mostra o tempo ligado, sem barra', (tester) async {
      await tester.pumpWidget(card());
      expect(find.text('Ligado há 1 h 52 min'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('com temperatura mostra a temperatura e a barra', (tester) async {
      await tester.pumpWidget(card(temp: 61));
      expect(find.text('61 °C'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('porcentagem com algarismos de largura fixa', (tester) async {
      await tester.pumpWidget(card());
      final style = tester.widget<Text>(find.text('20%')).style!;
      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
    });
  });
}
