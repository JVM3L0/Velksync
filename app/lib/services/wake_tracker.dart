import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/device.dart';
import 'pc_probe.dart';
import 'wol.dart' as wol;

enum WakePhase { waiting, awaitingLogin, online, failed }

class WakeProgress {
  final WakePhase phase;
  final Duration elapsed;
  final int sends;
  final String os;
  const WakeProgress(this.phase, this.elapsed, {this.sends = 1, this.os = ''});
  bool get active => phase == WakePhase.waiting;
}

/// Acompanha o "ligar" depois do Wake-on-LAN: reenvia o sinal, pergunta ao
/// PC com mais frequência e avisa quando ele respondeu ou desistiu. Global
/// para a tela inicial e a do PC mostrarem o mesmo progresso.
class WakeTracker extends ChangeNotifier {
  WakeTracker({
    this.send = _send,
    this.probe = probePc,
    this.resendAt = const [Duration(seconds: 10), Duration(seconds: 30)],
    this.probeEvery = const Duration(seconds: 2),
    this.giveUpAfter = const Duration(minutes: 2),
    this.keepResult = const Duration(seconds: 4),
  });

  static final instance = WakeTracker();

  static Future<void> _send(Device d) => wol.wake(d.mac, broadcast: d.broadcast);

  final Future<void> Function(Device) send;
  final Future<PcState> Function(Device) probe;
  final List<Duration> resendAt;
  final Duration probeEvery, giveUpAfter, keepResult;

  final _progress = <String, WakeProgress>{};
  final _timers = <String, Timer>{};

  WakeProgress? of(String deviceId) => _progress[deviceId];

  /// Manda o sinal e começa a acompanhar. Erros do primeiro envio (MAC
  /// inválido, sem rede) sobem para quem chamou mostrar.
  Future<void> start(Device d) async {
    stop(d.id);
    await send(d);
    var elapsed = Duration.zero, sends = 1;
    var probing = false;
    _set(d.id, const WakeProgress(WakePhase.waiting, Duration.zero));
    const tick = Duration(seconds: 1);
    _timers[d.id] = Timer.periodic(tick, (t) async {
      elapsed += tick;
      if (resendAt.contains(elapsed)) {
        sends++;
        unawaited(send(d).catchError((_) {}));
      }
      if (elapsed >= giveUpAfter) {
        t.cancel();
        _finish(d.id, WakeProgress(WakePhase.failed, elapsed, sends: sends), autoDismiss: false);
        return;
      }
      _set(d.id, WakeProgress(WakePhase.waiting, elapsed, sends: sends));
      if (probing || elapsed.inMilliseconds % probeEvery.inMilliseconds != 0) return;
      probing = true;
      final state = await probe(d);
      probing = false;
      if (!t.isActive) return; // cancelado enquanto perguntava
      final phase = switch (state.power) {
        PcPower.online => WakePhase.online,
        PcPower.awaitingLogin => WakePhase.awaitingLogin,
        PcPower.offline => null,
      };
      if (phase == null) return;
      t.cancel();
      _finish(d.id, WakeProgress(phase, elapsed, sends: sends, os: state.os));
    });
  }

  /// Mostra o resultado; sucesso some sozinho, falha fica até [dismiss].
  void _finish(String id, WakeProgress p, {bool autoDismiss = true}) {
    _set(id, p);
    if (autoDismiss) _timers[id] = Timer(keepResult, () => dismiss(id));
  }

  void dismiss(String id) => stop(id);

  void stop(String id) {
    _timers.remove(id)?.cancel();
    if (_progress.remove(id) != null) notifyListeners();
  }

  void _set(String id, WakeProgress p) {
    _progress[id] = p;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    super.dispose();
  }
}
