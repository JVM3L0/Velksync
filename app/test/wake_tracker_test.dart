import 'package:flutter_test/flutter_test.dart';
import 'package:velksync/models/device.dart';
import 'package:velksync/services/agent_client.dart';
import 'package:velksync/services/pc_probe.dart';
import 'package:velksync/services/wake_tracker.dart';

const pc = Device(id: 'pc', name: 'PC', host: '192.168.3.21', mac: 'aa:bb:cc:dd:ee:ff');

/// Roda [seconds] ticks do relógio falso do testWidgets.
Future<void> advance(WidgetTester tester, int seconds) async {
  for (var i = 0; i < seconds; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

void main() {
  testWidgets('reenvia o sinal e para quando o PC aparece aguardando login', (tester) async {
    var sends = 0, probes = 0;
    var answer = const PcState.offline();
    final t = WakeTracker(
      send: (_) async => sends++,
      probe: (_) async {
        probes++;
        return answer;
      },
    );
    addTearDown(t.dispose);

    await t.start(pc);
    expect(t.of('pc')!.phase, WakePhase.waiting);
    expect(sends, 1);

    await advance(tester, 10);
    expect(sends, 2, reason: 'reenvio aos 10 s');
    expect(probes, 5, reason: 'pergunta a cada 2 s');
    expect(t.of('pc')!.elapsed, const Duration(seconds: 10));

    answer = const PcState.awaitingLogin('linux');
    await advance(tester, 2);
    final p = t.of('pc')!;
    expect(p.phase, WakePhase.awaitingLogin);
    expect(p.os, 'linux');

    await advance(tester, 30);
    expect(sends, 2, reason: 'depois de responder não reenvia mais');
    expect(t.of('pc'), isNull, reason: 'o resultado some sozinho');
  });

  testWidgets('desiste em 2 minutos e mantém a falha até dispensar', (tester) async {
    var sends = 0;
    final t = WakeTracker(send: (_) async => sends++, probe: (_) async => const PcState.offline());
    addTearDown(t.dispose);

    await t.start(pc);
    await advance(tester, 119);
    expect(t.of('pc')!.phase, WakePhase.waiting);
    await advance(tester, 1);
    expect(t.of('pc')!.phase, WakePhase.failed);
    expect(sends, 3, reason: 'envio + reenvios aos 10 s e 30 s');

    await advance(tester, 60);
    expect(t.of('pc')!.phase, WakePhase.failed, reason: 'a falha não some sozinha');
    t.dismiss('pc');
    expect(t.of('pc'), isNull);
  });

  testWidgets('erro no primeiro envio chega a quem chamou', (tester) async {
    final t = WakeTracker(
      send: (_) async => throw const FormatException('MAC inválido'),
      probe: (_) async {
        throw AgentException('não deveria perguntar');
      },
    );
    addTearDown(t.dispose);
    await expectLater(t.start(pc), throwsFormatException);
    expect(t.of('pc'), isNull);
  });
}
