import 'dart:ui' show lerpDouble;

import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// Container transform do Material: a tela nova cresce a partir do cartão que
/// foi tocado e, ao voltar, encolhe de novo para dentro dele.
class ContainerTransformRoute<T> extends PageRoute<T> {
  ContainerTransformRoute({required this.origin, required this.builder, this.radius = Radii.xl});

  /// Contexto do cartão de origem; a posição é lida a cada quadro, então o
  /// retorno acerta o cartão mesmo que a lista tenha mudado.
  final BuildContext origin;
  final WidgetBuilder builder;
  final double radius;
  Rect? _lastRect;

  @override
  Duration get transitionDuration => Motion.spatialDuration;

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 380);

  @override
  bool get maintainState => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  Rect? _originRect() {
    if (origin.mounted) {
      final box = origin.findRenderObject();
      if (box is RenderBox && box.attached && box.hasSize) {
        _lastRect = box.localToGlobal(Offset.zero) & box.size;
      }
    }
    return _lastRect;
  }

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) =>
      builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final bounds = CurvedAnimation(
      parent: animation,
      curve: Easing.emphasizedDecelerate,
      reverseCurve: Easing.emphasizedAccelerate,
    );
    // Conteúdo aparece depois que o contêiner já cresceu um pouco e some
    // logo no começo da volta, como no container transform do M3.
    final fade = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.15, 0.55, curve: Curves.easeOut),
      reverseCurve: const Interval(0.45, 1, curve: Curves.easeIn),
    );
    return LayoutBuilder(
      builder: (context, box) {
        final full = Offset.zero & box.biggest;
        return AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (context, page) {
            if (animation.isCompleted) return page!;
            final from = _originRect() ?? Rect.fromCenter(center: full.center, width: 0, height: 0);
            final t = bounds.value;
            final rect = Rect.lerp(from, full, t)!;
            return Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(color: scheme.scrim.withValues(alpha: 0.25 * animation.value)),
                  ),
                ),
                Positioned.fromRect(
                  rect: rect,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(lerpDouble(radius, 0, t)!.clamp(0, radius)),
                    child: ColoredBox(
                      color: Color.lerp(scheme.surfaceContainer, scheme.surface, t)!,
                      // A página é montada no tamanho da tela e escalada para
                      // caber no contêiner, sem relayout a cada quadro.
                      child: FittedBox(
                        fit: BoxFit.fitWidth,
                        alignment: Alignment.topCenter,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox.fromSize(
                          size: full.size,
                          child: FadeTransition(opacity: fade, child: page),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Troca de abas com o eixo compartilhado (shared axis X) do Material: a aba
/// nova entra pelo lado para onde o usuário foi e a antiga sai pelo outro.
class SharedAxisSwitcher extends StatefulWidget {
  final int index;
  final Widget child;

  /// Quanto o conteúdo desliza; maior para elementos grandes (capa do álbum).
  final double distance;
  const SharedAxisSwitcher({super.key, required this.index, required this.child, this.distance = 36});

  @override
  State<SharedAxisSwitcher> createState() => _SharedAxisSwitcherState();
}

class _SharedAxisSwitcherState extends State<SharedAxisSwitcher> {
  double _direction = 1;

  @override
  void didUpdateWidget(SharedAxisSwitcher old) {
    super.didUpdateWidget(old);
    if (widget.index != old.index) _direction = widget.index > old.index ? 1 : -1;
  }

  @override
  Widget build(BuildContext context) {
    final key = ValueKey(widget.index);
    return AnimatedSwitcher(
      duration: Motion.spatialDuration,
      reverseDuration: Motion.spatialFastDuration,
      layoutBuilder: (current, previous) => Stack(children: [...previous, ?current]),
      transitionBuilder: (child, animation) {
        final incoming = child.key == key;
        final slide = CurvedAnimation(parent: animation, curve: Motion.spatial, reverseCurve: Motion.effects);
        // A que entra espera a outra sair; a que sai some no primeiro terço.
        final opacity = CurvedAnimation(
          parent: animation,
          curve: const Interval(0.3, 1, curve: Curves.easeOut),
          reverseCurve: const Interval(0.6, 1, curve: Curves.easeIn),
        );
        return AnimatedBuilder(
          animation: slide,
          child: FadeTransition(opacity: opacity, child: child),
          builder: (context, c) => Transform.translate(
            offset: Offset((incoming ? 1 : -1) * _direction * widget.distance * (1 - slide.value), 0),
            child: c,
          ),
        );
      },
      child: KeyedSubtree(key: key, child: widget.child),
    );
  }
}
