import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:velksync/services/agent_client.dart';
import 'package:velksync/services/stats_history.dart';
import 'package:velksync/ui/processes.dart';
import 'package:velksync/ui/stats_chart.dart';

void main() {
  test('lista de processos vinda do agente', () {
    final l = ProcessList.fromJson({
      'by_cpu': [
        {'name': 'chrome.exe', 'count': 24, 'cpu': 18.4, 'mem': 1288490188},
      ],
      'by_mem': [
        {'name': 'Code.exe', 'cpu': 2, 'mem': 900},
      ],
      'total': 231,
    });
    expect((l.byCpu.single.name, l.byCpu.single.count, l.total), ('chrome.exe', 24, 231));
    expect(l.byMem.single.count, 1);
    expect(l.byGpu, isNull, reason: 'sem by_gpu: o PC não informa GPU por processo');
    expect(ProcessList.fromJson({}).byCpu, isEmpty);
    final g = ProcessList.fromJson({
      'by_gpu': [
        {'name': 'game.exe', 'gpu': 70.5, 'vram': 3221225472},
      ],
      'by_vram': <Object>[],
    });
    expect((g.byGpu!.single.gpu, g.byGpu!.single.vram), (70.5, 3221225472));
    expect(g.byVram, isEmpty);
  });

  testWidgets('mostra por CPU, troca para memória e para de consultar ao sair', (tester) async {
    var calls = 0;
    Future<ProcessList> load() async {
      calls++;
      return const ProcessList(
        byCpu: [ProcessInfo(name: 'chrome.exe', count: 24, cpu: 18.4, mem: 1288490188)],
        byMem: [ProcessInfo(name: 'Code.exe', cpu: 2.5, mem: 838860800)],
        total: 231,
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProcessesSection(load: load, every: const Duration(seconds: 3)),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('chrome.exe'), findsOneWidget);
    expect(find.textContaining('×24'), findsOneWidget);
    expect(find.text('18%'), findsOneWidget);
    expect(find.textContaining('231 processos'), findsOneWidget);

    await tester.tap(find.text('Memória'));
    await tester.pump();
    expect(find.textContaining('Code.exe'), findsOneWidget);
    expect(find.text('2.5%'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    expect(calls, 2, reason: 'consulta de novo a cada 3 s com a seção aberta');
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(seconds: 10));
    expect(calls, 2, reason: 'fechada, não consulta mais');
  });

  Future<ProcessList> load() async => const ProcessList(
    byCpu: [ProcessInfo(name: 'chrome.exe', cpu: 18, mem: 100)],
    byMem: [ProcessInfo(name: 'Code.exe', cpu: 1, mem: 900)],
    total: 2,
  );

  Future<void> openSheet(WidgetTester tester, Metric m, {bool direct = false}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () => showStatsSheet(c, StatsHistory(), m, processes: load, showProcesses: direct),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('janela do gráfico alterna para os processos, na ordem da métrica tocada', (tester) async {
    await openSheet(tester, Metric.mem);
    expect(find.text('Gráfico'), findsOneWidget);
    expect(find.text('Coletando dados…'), findsOneWidget);
    await tester.tap(find.text('Processos'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Code.exe'), findsOneWidget, reason: 'aberto pela memória: ordena por memória');
  });

  testWidgets('"Ver processos" abre direto nos processos, por CPU, e volta ao gráfico', (tester) async {
    await openSheet(tester, Metric.cpu, direct: true);
    await tester.pump();
    expect(find.textContaining('chrome.exe'), findsOneWidget);
    await tester.tap(find.text('Gráfico'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Coletando dados…'), findsOneWidget);
  });

  testWidgets('sem processos (agente antigo) não mostra o seletor', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatsSheet(history: StatsHistory(), initial: Metric.cpu),
        ),
      ),
    );
    expect(find.text('Processos'), findsNothing);
  });

  testWidgets('filtros GPU e VRAM embaixo só quando o PC informa', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    Future<ProcessList> withGpu() async => const ProcessList(
      byCpu: [ProcessInfo(name: 'chrome.exe', cpu: 18)],
      byMem: [ProcessInfo(name: 'Code.exe', mem: 900)],
      byGpu: [ProcessInfo(name: 'game.exe', gpu: 70, vram: 3 << 30)],
      byVram: [ProcessInfo(name: 'game.exe', gpu: 70, vram: 3 << 30)],
      total: 3,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProcessesSection(load: withGpu, initialSort: ProcessSort.gpu),
          ),
        ),
      ),
    );
    await tester.pump();
    for (final f in ['CPU', 'GPU', 'VRAM', 'Memória']) {
      expect(find.widgetWithText(ChoiceChip, f), findsOneWidget, reason: f);
    }
    expect(find.text('70%'), findsOneWidget, reason: 'aberto pela GPU: ordena pela GPU');
    expect(find.text('3.0 GB'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'CPU'));
    await tester.pump();
    expect(find.textContaining('chrome.exe'), findsOneWidget);

    Future<ProcessList> noGpu() async => const ProcessList(byCpu: [ProcessInfo(name: 'bash', cpu: 1)], total: 1);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProcessesSection(key: const ValueKey('sem-gpu'), load: noGpu, initialSort: ProcessSort.gpu),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.widgetWithText(ChoiceChip, 'GPU'), findsNothing);
    expect(find.textContaining('bash'), findsOneWidget, reason: 'sem GPU, volta para CPU');
  });
}
