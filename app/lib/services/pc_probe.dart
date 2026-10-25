import '../models/device.dart';
import 'agent_client.dart';
import 'presence.dart';

enum PcPower { online, awaitingLogin, offline }

/// O que se sabe do PC agora: o agente completo respondeu (online), só o
/// sinal de presença respondeu (ligado, sem ninguém logado) ou nada.
class PcState {
  final PcPower power;
  final AgentInfo? info;

  /// Sistema que respondeu ('windows'/'linux'), também antes do login.
  final String os;

  /// Segredo de presença recém-aprendido do agente; quem chamou salva.
  final String? learnedPresenceKey;

  const PcState._(this.power, {this.info, this.os = '', this.learnedPresenceKey});
  const PcState.offline() : this._(PcPower.offline);
  PcState.online(AgentInfo i, {String? learnedPresenceKey})
    : this._(PcPower.online, info: i, os: i.os, learnedPresenceKey: learnedPresenceKey);
  const PcState.awaitingLogin(String os) : this._(PcPower.awaitingLogin, os: os);
}

/// Consulta o agente e, se ele não responder, o sinal de presença.
Future<PcState> probePc(Device d) async {
  if (!d.paired) return const PcState.offline();
  final client = AgentClient(d);
  try {
    final info = await client.info();
    String? key;
    if (d.presenceKey.isEmpty) {
      try {
        key = await client.presenceKey();
      } on AgentException {
        // agente anterior à v0.3: sem sinal de presença
      }
    }
    return PcState.online(info, learnedPresenceKey: key);
  } on AgentException {
    // agente fora do ar: pode ser que ninguém tenha logado ainda
  } finally {
    client.close();
  }
  final os = await probePresence(d);
  return os == null ? const PcState.offline() : PcState.awaitingLogin(os);
}
