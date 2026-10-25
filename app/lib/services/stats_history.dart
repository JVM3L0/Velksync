import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/device.dart';

/// O que dá para ver no gráfico; cada uma vira uma fração de 0 a 1.
enum Metric {
  cpu('CPU'),
  gpu('GPU'),
  vram('VRAM'),
  mem('Memória');

  final String label;
  const Metric(this.label);

  double? of(PcStats s) => switch (this) {
    cpu => s.cpuPercent / 100,
    gpu => s.gpu?.percent == null ? null : s.gpu!.percent / 100,
    vram => (s.gpu?.vramTotal ?? 0) == 0 ? null : s.gpu!.vramFraction,
    mem => s.memTotal == 0 ? null : s.memFraction,
  };
}

/// Últimos minutos de desempenho de um PC, guardados só na memória enquanto
/// o app está aberto. Assim o gráfico já abre preenchido. Quem alimenta é a
/// tela do PC (em qualquer aba); fora dela fica um buraco no gráfico.
class StatsHistory extends ChangeNotifier {
  StatsHistory({this.window = const Duration(minutes: 2), DateTime Function()? now}) : _now = now ?? DateTime.now;

  final Duration window;
  final DateTime Function() _now;
  final _samples = ListQueue<(DateTime, PcStats)>();

  static final _byDevice = <String, StatsHistory>{};

  /// Um histórico por PC, que sobrevive a sair e voltar para a tela dele.
  static StatsHistory of(String deviceId) => _byDevice.putIfAbsent(deviceId, StatsHistory.new);

  /// Teto de pontos: uma leitura a cada 2 s cabe com folga.
  int get capacity => window.inSeconds;

  DateTime get now => _now();

  void add(PcStats s) {
    _samples.addLast((_now(), s));
    _prune();
    notifyListeners();
  }

  void _prune() {
    final oldest = _now().subtract(window);
    while (_samples.isNotEmpty && (_samples.first.$1.isBefore(oldest) || _samples.length > capacity)) {
      _samples.removeFirst();
    }
  }

  int get length => _samples.length;
  PcStats? get latest => _samples.isEmpty ? null : _samples.last.$2;

  /// Pontos da métrica dentro da janela (sem as leituras em que ela faltou).
  List<(DateTime, double)> series(Metric m) {
    _prune();
    return [
      for (final (at, s) in _samples)
        if (m.of(s) case final v?) (at, v.clamp(0.0, 1.0)),
    ];
  }

  /// Métricas que este PC informa (GPU e VRAM só se houver placa detectada).
  List<Metric> get available => [
    for (final m in Metric.values)
      if (_samples.any((e) => m.of(e.$2) != null)) m,
  ];

  ({double min, double avg, double max})? summary(Metric m) {
    final v = series(m).map((e) => e.$2).toList();
    if (v.isEmpty) return null;
    var lo = v.first, hi = v.first, sum = 0.0;
    for (final x in v) {
      if (x < lo) lo = x;
      if (x > hi) hi = x;
      sum += x;
    }
    return (min: lo, avg: sum / v.length, max: hi);
  }

  @visibleForTesting
  static void resetAll() => _byDevice.clear();
}
