import 'dart:math' as math;

import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'theme.dart';

// Medidores de desempenho no estilo do dashboard do Caelestia: cartões "hero"
// para CPU/GPU com o uso dentro de uma forma do M3 Expressive que muda com a
// carga, e arcos de 270° para memória e armazenamento.

String formatBytes(int bytes) {
  const gib = 1024 * 1024 * 1024;
  final g = bytes / gib;
  return g >= 100 ? '${g.round()} GB' : '${g.toStringAsFixed(1)} GB';
}

String formatUptime(Duration d) {
  if (d.inDays > 0) return '${d.inDays} d ${d.inHours % 24} h';
  if (d.inHours > 0) return '${d.inHours} h ${d.inMinutes % 60} min';
  return '${d.inMinutes} min';
}

/// "AMD Ryzen 7 5700X 8-Core Processor" → "AMD Ryzen 7 5700X";
/// "Intel(R) Core(TM) i7-9700K CPU @ 3.60GHz" → "Intel Core i7-9700K".
String shortCpuName(String name) => name
    .replaceAll(RegExp(r'\((R|TM|tm)\)'), '')
    .replaceAll(RegExp(r'\s+CPU\s+@.*$'), '')
    .replaceAll(RegExp(r'\s+\d+-Core( Processor)?$', caseSensitive: false), '')
    .replaceAll(RegExp(r'\s+Processor$', caseSensitive: false), '')
    .replaceAll(RegExp(r'\s{2,}'), ' ')
    .trim();

String percentText(double fraction) => '${(fraction * 100).round()}%';

/// Arco de progresso com espaço entre o preenchido e o trilho (M3 Expressive).
class ExpressiveArc extends StatelessWidget {
  final double value; // 0..1
  final double size;
  final double stroke;
  final double startAngle; // graus, 0 = 3 horas, sentido horário
  final double sweepAngle;
  final Color color;
  final Widget? child;

  const ExpressiveArc({
    super.key,
    required this.value,
    required this.color,
    this.size = 56,
    this.stroke = 5,
    this.startAngle = -90,
    this.sweepAngle = 360,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final track = Theme.of(context).colorScheme.surfaceContainerHighest;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.clamp(0, 1)),
      duration: Motion.spatialDuration,
      curve: Motion.effects,
      builder: (_, v, _) => SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _ArcPainter(v, stroke, startAngle, sweepAngle, color, track),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final double value, stroke, start, sweep;
  final Color color, track;
  _ArcPainter(this.value, this.stroke, this.start, this.sweep, this.color, this.track);

  @override
  void paint(Canvas canvas, Size size) {
    final r = (size.shortestSide - stroke) / 2;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: r);
    Paint p(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final total = sweep * math.pi / 180;
    final s = start * math.pi / 180;
    // Espaço entre preenchido e trilho, compensando as pontas arredondadas.
    final gap = (stroke * 1.6) / r;
    final filled = total * value;
    if (filled > 0.001) canvas.drawArc(rect, s, filled, false, p(color));
    final trackStart = filled > 0.001 ? s + filled + gap : s;
    final trackEnd = s + total - (sweep >= 360 && filled > 0.001 ? gap : 0);
    if (trackEnd - trackStart > 0.01) canvas.drawArc(rect, trackStart, trackEnd - trackStart, false, p(track));
  }

  @override
  bool shouldRepaint(_ArcPainter o) => o.value != value || o.color != color || o.track != track || o.stroke != stroke;
}

/// Formas do M3 Expressive usadas pelo Caelestia para o uso de CPU/GPU.
enum LoadShape {
  cookie4(4, 0.10),
  sunny(8, 0.08),
  softBurst(12, 0.11);

  final int lobes;
  final double depth;
  const LoadShape(this.lobes, this.depth);

  static LoadShape of(double fraction) => fraction >= 0.8
      ? LoadShape.softBurst
      : fraction >= 0.4
      ? LoadShape.sunny
      : LoadShape.cookie4;

  double radius(double theta) => 1 - depth + depth * math.cos(lobes * theta);
}

/// Forma que se transforma suavemente quando a faixa de uso muda.
class MorphingShape extends StatefulWidget {
  final LoadShape shape;
  final Color color;
  final double size;
  final Widget child;
  const MorphingShape({super.key, required this.shape, required this.color, required this.size, required this.child});

  @override
  State<MorphingShape> createState() => _MorphingShapeState();
}

class _MorphingShapeState extends State<MorphingShape> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: Motion.spatialDuration, value: 1);
  late LoadShape _from = widget.shape;

  @override
  void didUpdateWidget(MorphingShape old) {
    super.didUpdateWidget(old);
    if (old.shape != widget.shape) {
      _from = old.shape;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => CustomPaint(
        painter: _ShapePainter(_from, widget.shape, Motion.spatial.transform(_c.value), widget.color),
        child: child,
      ),
      child: SizedBox.square(
        dimension: widget.size,
        child: Center(child: widget.child),
      ),
    );
  }
}

class _ShapePainter extends CustomPainter {
  final LoadShape from, to;
  final double t;
  final Color color;
  _ShapePainter(this.from, this.to, this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final path = Path();
    const steps = 180;
    for (var i = 0; i <= steps; i++) {
      final th = 2 * math.pi * i / steps - math.pi / 2;
      // Interpola o raio das duas formas no mesmo ângulo: a transição é contínua.
      final k = from.radius(th) + (to.radius(th) - from.radius(th)) * t;
      final p = c + Offset(math.cos(th), math.sin(th)) * r * k;
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ShapePainter o) => o.t != t || o.from != from || o.to != to || o.color != color;
}

/// Cartão grande de CPU/GPU: anel com ícone, nome, rodapé (temperatura ou
/// outra métrica) e o uso dentro da forma que muda com a carga.
class HeroCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subLabel;
  final double usage; // 0..1
  final Color accent;
  final double? temperature;
  final ({String text, double fraction})? fallback; // quando não há temperatura

  const HeroCard({
    super.key,
    required this.icon,
    required this.label,
    required this.subLabel,
    required this.usage,
    required this.accent,
    this.temperature,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final hot = (temperature ?? 0) > 90;
    final footer = temperature != null
        ? (
            icon: hot ? Symbols.thermometer_alert_rounded : Symbols.thermometer_rounded,
            text: '${temperature!.round()} °C',
            fraction: temperature! / 100,
            color: hot ? scheme.error : accent,
          )
        : fallback == null
        ? null
        : (icon: Symbols.memory_alt_rounded, text: fallback!.text, fraction: fallback!.fraction, color: accent);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ExpressiveArc(
                        value: usage,
                        color: accent,
                        size: 52,
                        stroke: 4,
                        child: Icon(icon, color: accent, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: text.titleMedium?.copyWith(color: accent, fontWeight: FontWeight.w600),
                            ),
                            Text(
                              subLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (footer != null) ...[
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Icon(footer.icon, color: footer.color, fill: 1, size: 20),
                        const SizedBox(width: 6),
                        Text(footer.text, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TweenAnimationBuilder<double>(
                      tween: Tween(end: footer.fraction.clamp(0, 1)),
                      duration: Motion.spatialDuration,
                      curve: Motion.effects,
                      builder: (_, v, _) => LinearProgressIndicator(
                        value: v,
                        color: footer.color,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            Column(
              children: [
                Text('Uso', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 4),
                MorphingShape(
                  shape: LoadShape.of(usage),
                  color: scheme.secondaryContainer,
                  size: 96,
                  child: Text(
                    percentText(usage),
                    style: text.headlineSmall?.copyWith(color: accent, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Cartão de memória/armazenamento: título, arco de 270° e "usado / total".
class GaugeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final int used, total;
  final Color accent;

  const GaugeCard({
    super.key,
    required this.icon,
    required this.title,
    required this.used,
    required this.total,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final fraction = total == 0 ? 0.0 : used / total;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: accent, fill: 1, size: 22),
                const SizedBox(width: 8),
                Text(title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 14),
            ExpressiveArc(
              value: fraction,
              color: accent,
              size: 112,
              stroke: 8,
              startAngle: 135,
              sweepAngle: 270,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    percentText(fraction),
                    style: text.titleLarge?.copyWith(color: accent, fontWeight: FontWeight.w700),
                  ),
                  Text('Usado', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text('${formatBytes(used)} / ${formatBytes(total)}', style: text.bodyMedium),
          ],
        ),
      ),
    );
  }
}
