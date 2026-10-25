import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../services/stats_history.dart';
import 'perf.dart';

/// Cor de cada métrica, a mesma dos cartões do desempenho.
Color metricColor(Metric m, ColorScheme scheme) => switch (m) {
  Metric.cpu => scheme.primary,
  Metric.gpu || Metric.vram => scheme.secondary,
  Metric.mem => scheme.tertiary,
};

/// Folha com o gráfico dos últimos minutos; abre já com o que foi guardado
/// e segue ao vivo enquanto aberta.
Future<void> showStatsSheet(BuildContext context, StatsHistory history, Metric initial) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => StatsSheet(history: history, initial: initial),
);

class StatsSheet extends StatefulWidget {
  final StatsHistory history;
  final Metric initial;
  const StatsSheet({super.key, required this.history, required this.initial});

  @override
  State<StatsSheet> createState() => _StatsSheetState();
}

class _StatsSheetState extends State<StatsSheet> {
  late Metric _metric = widget.initial;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final h = widget.history;
    return ListenableBuilder(
      listenable: h,
      builder: (context, _) {
        final color = metricColor(_metric, scheme);
        final points = h.series(_metric);
        final sum = h.summary(_metric);
        final muted = text.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
        final minutes = h.window.inMinutes;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_metric.label, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                        Text('últimos $minutes min', style: muted),
                      ],
                    ),
                  ),
                  Text(
                    points.isEmpty ? '--' : percentText(points.last.$2),
                    style: text.headlineMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontFeatures: tabular,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 180,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('100%', style: muted),
                        Text('50%', style: muted),
                        Text('0%', style: muted),
                      ],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: points.isEmpty
                          ? Center(child: Text('Coletando dados…', style: muted))
                          : Semantics(
                              label:
                                  'Gráfico de ${_metric.label} dos últimos $minutes minutos'
                                  '${sum == null ? '' : ': mínimo ${percentText(sum.min)}, média ${percentText(sum.avg)}, máximo ${percentText(sum.max)}'}',
                              child: HistoryChart(history: h, metric: _metric, color: color),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 44),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('-$minutes min', style: muted),
                    Text('agora', style: muted),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  for (final (label, v) in [('mín', sum?.min), ('média', sum?.avg), ('máx', sum?.max)])
                    Expanded(
                      child: Column(
                        children: [
                          Text(label, style: muted),
                          const SizedBox(height: 2),
                          Text(
                            v == null ? '--' : percentText(v),
                            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600, fontFeatures: tabular),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final m in h.available)
                    ChoiceChip(
                      label: Text(m.label),
                      selected: m == _metric,
                      onSelected: (_) => setState(() => _metric = m),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Linha com área preenchida, de 0 a 100%. Desliza suavemente para a
/// esquerda com o tempo (parada com "remover animações").
class HistoryChart extends StatefulWidget {
  final StatsHistory history;
  final Metric metric;
  final Color color;
  const HistoryChart({super.key, required this.history, required this.metric, required this.color});

  @override
  State<HistoryChart> createState() => _HistoryChartState();
}

class _HistoryChartState extends State<HistoryChart> with SingleTickerProviderStateMixin {
  late final _clock = ValueNotifier(widget.history.now);
  late final Ticker _ticker = createTicker((_) => _clock.value = widget.history.now);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    if (still && _ticker.isActive) _ticker.stop();
    if (!still && !_ticker.isActive) _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _ChartPainter(
        history: widget.history,
        metric: widget.metric,
        clock: _clock,
        color: widget.color,
        grid: scheme.outlineVariant,
        animate: _ticker.isActive,
      ),
      size: Size.infinite,
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.history,
    required this.metric,
    required this.clock,
    required this.color,
    required this.grid,
    required this.animate,
  }) : super(repaint: Listenable.merge([history, clock]));

  final StatsHistory history;
  final Metric metric;
  final ValueNotifier<DateTime> clock;
  final Color color, grid;
  final bool animate;

  /// Mais que isso entre duas leituras é um buraco (o usuário saiu da tela).
  static const _gap = Duration(seconds: 7);

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final f in [0.0, 0.5, 1.0]) {
      final y = size.height * (1 - f);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final points = history.series(metric);
    if (points.isEmpty) return;
    // Sem animação, o "agora" é a última leitura: o gráfico só anda quando chega dado.
    final now = animate ? clock.value : points.last.$1;
    final window = history.window.inMilliseconds;
    Offset at((DateTime, double) p) {
      final age = now.difference(p.$1).inMilliseconds.clamp(0, window);
      return Offset(size.width * (1 - age / window), size.height * (1 - p.$2));
    }

    // Trechos contínuos; cada um vira uma linha e uma área.
    final runs = <List<Offset>>[];
    DateTime? prev;
    for (final p in points) {
      if (prev == null || p.$1.difference(prev) > _gap) runs.add([]);
      runs.last.add(at(p));
      prev = p.$1;
    }
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0.02)],
      ).createShader(Offset.zero & size);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final run in runs) {
      if (run.length == 1) {
        canvas.drawCircle(run.first, 2.5, Paint()..color = color);
        continue;
      }
      final path = Path()..moveTo(run.first.dx, run.first.dy);
      for (final o in run.skip(1)) {
        path.lineTo(o.dx, o.dy);
      }
      final area = Path.from(path)
        ..lineTo(run.last.dx, size.height)
        ..lineTo(run.first.dx, size.height)
        ..close();
      canvas.drawPath(area, fill);
      canvas.drawPath(path, line);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ChartPainter o) =>
      o.history != history || o.metric != metric || o.color != color || o.grid != grid || o.animate != animate;
}
