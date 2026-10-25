import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:velksync/models/device.dart';
import 'package:velksync/services/stats_history.dart';
import 'package:velksync/ui/stats_chart.dart';

PcStats stats(double cpu, {double? gpu}) => PcStats.fromJson({
  'cpu_percent': cpu,
  'mem_used': 4,
  'mem_total': 16,
  'gpu': gpu == null ? null : {'name': 'RTX', 'percent': gpu, 'vram_used': 0, 'vram_total': 0},
});

void main() {
  late DateTime clock;
  StatsHistory history() => StatsHistory(now: () => clock);
  setUp(() => clock = DateTime(2026, 10, 25, 12));

  test('guarda só a janela de 2 minutos', () {
    final h = history();
    for (var i = 0; i < 100; i++) {
      h.add(stats(i.toDouble()));
      clock = clock.add(const Duration(seconds: 2));
    }
    expect(h.length, lessThanOrEqualTo(h.capacity));
    expect(h.series(Metric.cpu).first.$1.isBefore(clock.subtract(const Duration(minutes: 2))), isFalse);
    expect(h.series(Metric.cpu).last.$2, closeTo(0.99, 1e-9));
  });

  test('mínimo, média e máximo', () {
    final h = history();
    for (final v in [10.0, 50.0, 90.0]) {
      h.add(stats(v));
      clock = clock.add(const Duration(seconds: 2));
    }
    final s = h.summary(Metric.cpu)!;
    expect(s.min, closeTo(0.1, 1e-9));
    expect(s.avg, closeTo(0.5, 1e-9));
    expect(s.max, closeTo(0.9, 1e-9));
    expect(h.summary(Metric.gpu), isNull);
  });

  test('GPU e VRAM só aparecem se o PC informar', () {
    final h = history()..add(stats(5));
    expect(h.available, [Metric.cpu, Metric.mem]);
    h.add(stats(5, gpu: 30));
    expect(h.available, [Metric.cpu, Metric.gpu, Metric.mem], reason: 'VRAM total 0: sem VRAM');
  });

  test('um histórico por PC, que sobrevive a sair da tela', () {
    StatsHistory.resetAll();
    StatsHistory.of('a').add(stats(1));
    expect(StatsHistory.of('a').length, 1);
    expect(StatsHistory.of('b').length, 0);
  });

  group('folha do gráfico', () {
    Future<StatsHistory> open(WidgetTester tester, {double textScale = 1}) async {
      final h = StatsHistory();
      for (var i = 0; i < 30; i++) {
        h.add(stats(20 + i.toDouble(), gpu: 60));
      }
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: const Size(320, 640), textScaler: TextScaler.linear(textScale)),
            child: Scaffold(
              body: Builder(
                builder: (context) =>
                    TextButton(onPressed: () => showStatsSheet(context, h, Metric.cpu), child: const Text('abrir')),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      return h;
    }

    testWidgets('abre já com os pontos guardados e segue ao vivo', (tester) async {
      final h = await open(tester);
      expect(find.byType(HistoryChart), findsOneWidget);
      expect(find.text('Coletando dados…'), findsNothing);
      expect(find.text('49%'), findsWidgets, reason: 'valor atual');
      expect(find.text('20%'), findsOneWidget, reason: 'mínimo');
      h.add(stats(80, gpu: 60));
      await tester.pump();
      expect(find.text('80%'), findsWidgets);
    });

    testWidgets('troca de métrica sem fechar', (tester) async {
      await open(tester);
      expect(find.widgetWithText(ChoiceChip, 'VRAM'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'GPU'));
      await tester.pump();
      expect(find.text('60%'), findsWidgets);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Memória'));
      await tester.pump();
      expect(find.text('25%'), findsWidgets);
    });

    testWidgets('cabe em tela pequena com fonte grande', (tester) async {
      tester.view.physicalSize = const Size(960, 1600);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await open(tester, textScale: 2);
      expect(tester.takeException(), isNull);
    });
  });
}
