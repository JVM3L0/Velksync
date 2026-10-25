import 'dart:async';

import 'package:material_ui/material_ui.dart';

/// Texto de uma linha que, se não couber, rola de um lado para o outro (como o
/// título nos players de música), com as bordas esmaecidas. Assim a altura não
/// muda com o tamanho do título. Com "remover animações" ligado, usa reticências.
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  /// Velocidade da rolagem, em pixels lógicos por segundo.
  final double speed;
  const MarqueeText(this.text, {super.key, this.style, this.speed = 36});

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> with SingleTickerProviderStateMixin {
  static const _pause = Duration(milliseconds: 1800);
  static const _fade = 24.0;
  late final _c = AnimationController(vsync: this);
  double _overflow = 0;
  Timer? _wait;

  @override
  void didUpdateWidget(MarqueeText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _c.value = 0; // faixa nova começa do início
  }

  @override
  void dispose() {
    _wait?.cancel();
    _c.dispose();
    super.dispose();
  }

  /// Ida e volta com pausas nas pontas; recalcula quando o texto ou a largura mudam.
  void _schedule(double overflow) {
    if (overflow == _overflow) return;
    _overflow = overflow;
    _wait?.cancel();
    _c.stop();
    if (overflow <= 0) return;
    _c.duration = Duration(milliseconds: (overflow / widget.speed * 1000).round());
    _leg(forward: true);
  }

  void _leg({required bool forward}) {
    _wait = Timer(_pause, () async {
      if (!mounted) return;
      try {
        await (forward ? _c.forward(from: 0) : _c.reverse()).orCancel;
      } on TickerCanceled {
        return; // texto ou largura mudaram: _schedule recomeça
      }
      if (mounted && _overflow > 0) _leg(forward: !forward);
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: scaler,
        )..layout();
        final overflow = painter.width - box.maxWidth;
        final still = overflow <= 0 || MediaQuery.disableAnimationsOf(context);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _schedule(still ? 0 : overflow + _fade);
        });
        if (still) {
          return Text(
            widget.text,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          );
        }
        final travel = overflow + _fade;
        return SizedBox(
          height: painter.height,
          child: ShaderMask(
            shaderCallback: (r) => LinearGradient(
              colors: const [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
              stops: [0, _fade / r.width, 1 - _fade / r.width, 1],
            ).createShader(r),
            blendMode: BlendMode.dstIn,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                maxWidth: double.infinity,
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(_fade / 2 - travel * Curves.easeInOut.transform(_c.value), 0),
                    child: child,
                  ),
                  child: Text(widget.text, style: style, maxLines: 1, softWrap: false),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
