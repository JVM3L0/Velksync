import 'package:material_ui/material_ui.dart';

/// Cores por função: desligar em vermelho, reiniciar em amarelo, suspender em
/// azul, CPU em azul, memória em verde. Gruvbox e Catppuccin trazem as suas
/// (Palette.toRoles); o tema dinâmico e o Velksync derivam do ColorScheme,
/// como sempre foi.
@immutable
class RoleColors extends ThemeExtension<RoleColors> {
  const RoleColors({
    required this.danger,
    required this.onDanger,
    required this.warn,
    required this.onWarn,
    required this.info,
    required this.onInfo,
    required this.ok,
    required this.onOk,
    required this.cpu,
    required this.gpu,
    required this.mem,
    required this.disk,
  });

  /// Blocos (fundo e frente): desligar, reiniciar, suspender, ação positiva.
  final Color danger, onDanger, warn, onWarn, info, onInfo, ok, onOk;

  /// Linhas, barras e números sobre os cartões de desempenho.
  final Color cpu, gpu, mem, disk;

  factory RoleColors.fromScheme(ColorScheme s) => RoleColors(
    danger: Color.alphaBlend(s.error.withValues(alpha: 0.16), s.surfaceContainer),
    onDanger: s.error,
    warn: s.secondaryContainer,
    onWarn: s.onSecondaryContainer,
    info: s.tertiaryContainer,
    onInfo: s.onTertiaryContainer,
    ok: s.secondaryContainer,
    onOk: s.onSecondaryContainer,
    cpu: s.primary,
    gpu: s.secondary,
    mem: s.tertiary,
    disk: s.primary,
  );

  static RoleColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<RoleColors>() ?? RoleColors.fromScheme(theme.colorScheme);
  }

  @override
  RoleColors copyWith({
    Color? danger,
    Color? onDanger,
    Color? warn,
    Color? onWarn,
    Color? info,
    Color? onInfo,
    Color? ok,
    Color? onOk,
    Color? cpu,
    Color? gpu,
    Color? mem,
    Color? disk,
  }) => RoleColors(
    danger: danger ?? this.danger,
    onDanger: onDanger ?? this.onDanger,
    warn: warn ?? this.warn,
    onWarn: onWarn ?? this.onWarn,
    info: info ?? this.info,
    onInfo: onInfo ?? this.onInfo,
    ok: ok ?? this.ok,
    onOk: onOk ?? this.onOk,
    cpu: cpu ?? this.cpu,
    gpu: gpu ?? this.gpu,
    mem: mem ?? this.mem,
    disk: disk ?? this.disk,
  );

  @override
  RoleColors lerp(RoleColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return RoleColors(
      danger: l(danger, other.danger),
      onDanger: l(onDanger, other.onDanger),
      warn: l(warn, other.warn),
      onWarn: l(onWarn, other.onWarn),
      info: l(info, other.info),
      onInfo: l(onInfo, other.onInfo),
      ok: l(ok, other.ok),
      onOk: l(onOk, other.onOk),
      cpu: l(cpu, other.cpu),
      gpu: l(gpu, other.gpu),
      mem: l(mem, other.mem),
      disk: l(disk, other.disk),
    );
  }
}
