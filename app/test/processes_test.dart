import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:velksync/services/agent_client.dart';
import 'package:velksync/ui/processes.dart';

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
    expect(ProcessList.fromJson({}).byCpu, isEmpty);
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
}
