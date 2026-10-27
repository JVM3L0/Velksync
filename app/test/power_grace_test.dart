import 'package:flutter_test/flutter_test.dart';
import 'package:velksync/services/agent_client.dart';

void main() {
  test('contagem do PC vem do grace_s; agentes antigos e respostas estranhas viram 0', () {
    expect(AgentClient.graceOf({'status': 'ok', 'grace_s': 10}), 10);
    expect(AgentClient.graceOf({'status': 'ok', 'grace_s': 0}), 0);
    expect(AgentClient.graceOf({'status': 'ok'}), 0);
    expect(AgentClient.graceOf({'grace_s': -3}), 0);
    expect(AgentClient.graceOf({'grace_s': '10'}), 0);
    expect(AgentClient.graceOf(null), 0);
  });
}
