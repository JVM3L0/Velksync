import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'theme.dart';

enum PcStatus { checking, online, offline }

/// Pill showing whether the PC answers; the dot breathes while online.
class StatusPill extends StatelessWidget {
  final PcStatus status;
  final String? detail;
  const StatusPill({super.key, required this.status, this.detail});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg, label) = switch (status) {
      PcStatus.online => (scheme.primaryContainer, scheme.onPrimaryContainer, 'Ligado'),
      PcStatus.offline => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant, 'Desligado'),
      PcStatus.checking => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant, 'Verificando'),
    };
    return AnimatedContainer(
      duration: Motion.effectsDuration,
      curve: Motion.effects,
      padding: const EdgeInsets.fromLTRB(10, 5, 12, 5),
      decoration: ShapeDecoration(color: bg, shape: const StadiumBorder()),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Dot(color: status == PcStatus.online ? scheme.primary : scheme.outline, pulse: status == PcStatus.online),
          const SizedBox(width: 8),
          Text(
            detail == null ? label : '$label · $detail',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  final Color color;
  final bool pulse;
  const _Dot({required this.color, required this.pulse});

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_Dot old) {
    super.didUpdateWidget(old);
    if (widget.pulse && !_c.isAnimating) _c.repeat(reverse: true);
    if (!widget.pulse) _c.value = 1;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: 0.35, end: 1.0).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
    child: Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    ),
  );
}

/// Material 3 Expressive list group: items stacked with small gaps, large
/// rounding on the outer corners and small rounding between items.
class ExpressiveGroup extends StatelessWidget {
  final List<Widget> children;
  const ExpressiveGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainer;
    final last = children.length - 1;
    return Column(
      children: [
        for (var i = 0; i < children.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == last ? 0 : 3),
            child: Material(
              color: color,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(i == 0 ? Radii.xl - 4 : Radii.xs + 2),
                  bottom: Radius.circular(i == last ? Radii.xl - 4 : Radii.xs + 2),
                ),
              ),
              child: children[i],
            ),
          ),
      ],
    );
  }
}

/// Row inside an [ExpressiveGroup].
class GroupTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool highlighted;
  const GroupTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            IconBadge(icon: icon, highlighted: highlighted),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  if (subtitle != null)
                    Text(subtitle!, style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );
  }
}

/// Rounded-square icon holder used by tiles and cards.
class IconBadge extends StatelessWidget {
  final IconData icon;
  final bool highlighted;
  final double size;
  const IconBadge({super.key, required this.icon, this.highlighted = false, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: Motion.effectsDuration,
      curve: Motion.effects,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: highlighted ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(size * 0.36),
      ),
      child: Icon(
        icon,
        size: size * 0.52,
        fill: highlighted ? 1 : 0,
        color: highlighted ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? action;
  const SectionLabel(this.text, {super.key, this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 24, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// Big square action whose corners tighten while pressed, with Caelestia's
/// springy spatial curve.
class MorphTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color onColor;
  final VoidCallback? onTap;
  const MorphTile({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onColor,
    this.onTap,
  });

  @override
  State<MorphTile> createState() => _MorphTileState();
}

class _MorphTileState extends State<MorphTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final scheme = Theme.of(context).colorScheme;
    final bg = enabled ? widget.color : scheme.surfaceContainer;
    final fg = enabled ? widget.onColor : scheme.onSurface.withValues(alpha: 0.38);
    final radius = BorderRadius.circular(_pressed ? Radii.lg : Radii.xl);
    return AnimatedScale(
      scale: _pressed ? 0.96 : 1,
      duration: Motion.spatialFastDuration,
      curve: Motion.spatialFast,
      child: AnimatedContainer(
        duration: Motion.spatialFastDuration,
        curve: Motion.spatialFast,
        decoration: BoxDecoration(color: bg, borderRadius: radius),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: widget.onTap,
            onHighlightChanged: (v) => setState(() => _pressed = v),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(widget.icon, size: 30, color: fg, fill: enabled ? 1 : 0),
                  const Spacer(),
                  Text(
                    widget.label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: fg, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

IconData osIcon(String os) => switch (os) {
  'windows' => Symbols.desktop_windows_rounded,
  'linux' => Symbols.terminal_rounded,
  _ => Symbols.computer_rounded,
};
