import 'package:material_ui/material_ui.dart';

/// Paletas fixas (Gruvbox e Catppuccin) mapeadas para os papéis do Material 3.
/// Cores oficiais: github.com/morhetz/gruvbox e github.com/catppuccin/palette.
class Palette {
  final String name;
  final Brightness brightness;
  final Color background; // surface
  final Color lowest; // surfaceContainerLowest (o fundo mais fundo)
  final List<Color> containers; // low, base, high, highest
  final Color text, subtext, outline;
  final Color primary, secondary, tertiary, error;

  const Palette({
    required this.name,
    required this.brightness,
    required this.background,
    required this.lowest,
    required this.containers,
    required this.text,
    required this.subtext,
    required this.outline,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.error,
  });

  /// Amostras para a prévia na tela de configurações.
  List<Color> get swatches => [background, primary, secondary, tertiary, error];

  ColorScheme toScheme() {
    final dark = brightness == Brightness.dark;
    // Contêineres "tonais": a cor de destaque misturada ao fundo, como no M3.
    Color container(Color c) => Color.alphaBlend(c.withValues(alpha: dark ? 0.24 : 0.20), background);
    // Puxado para a cor de texto o bastante para passar no contraste AA (teste).
    Color onContainer(Color c) => dark ? Color.lerp(c, text, 0.5)! : Color.lerp(c, text, 0.6)!;
    return ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: dark ? lowest : background,
      primaryContainer: container(primary),
      onPrimaryContainer: onContainer(primary),
      secondary: secondary,
      onSecondary: dark ? lowest : background,
      secondaryContainer: container(secondary),
      onSecondaryContainer: onContainer(secondary),
      tertiary: tertiary,
      onTertiary: dark ? lowest : background,
      tertiaryContainer: container(tertiary),
      onTertiaryContainer: onContainer(tertiary),
      error: error,
      onError: dark ? lowest : background,
      errorContainer: container(error),
      onErrorContainer: onContainer(error),
      surface: background,
      onSurface: text,
      onSurfaceVariant: subtext,
      surfaceContainerLowest: lowest,
      surfaceContainerLow: containers[0],
      surfaceContainer: containers[1],
      surfaceContainerHigh: containers[2],
      surfaceContainerHighest: containers[3],
      surfaceTint: Colors.transparent,
      outline: outline,
      outlineVariant: containers[3],
      inverseSurface: text,
      onInverseSurface: background,
      inversePrimary: primary,
      shadow: Colors.black,
      scrim: Colors.black,
    );
  }
}

abstract final class Palettes {
  static const gruvboxDark = Palette(
    name: 'Gruvbox Dark',
    brightness: Brightness.dark,
    background: Color(0xFF282828), // bg0
    lowest: Color(0xFF1D2021), // bg0_h
    containers: [Color(0xFF32302F), Color(0xFF3C3836), Color(0xFF504945), Color(0xFF665C54)], // bg0_s, bg1-3
    text: Color(0xFFEBDBB2), // fg
    subtext: Color(0xFFBDAE93), // fg3
    outline: Color(0xFF928374), // gray
    primary: Color(0xFFFABD2F), // yellow
    secondary: Color(0xFF83A598), // blue
    tertiary: Color(0xFF8EC07C), // aqua
    error: Color(0xFFFB4934), // red
  );

  static const gruvboxLight = Palette(
    name: 'Gruvbox Light',
    brightness: Brightness.light,
    background: Color(0xFFFBF1C7), // bg0
    lowest: Color(0xFFF9F5D7), // bg0_h
    containers: [Color(0xFFF2E5BC), Color(0xFFEBDBB2), Color(0xFFD5C4A1), Color(0xFFBDAE93)], // bg0_s, bg1-3
    text: Color(0xFF3C3836), // fg
    subtext: Color(0xFF665C54), // fg3
    outline: Color(0xFF928374), // gray
    primary: Color(0xFFAF3A03), // orange (o yellow claro não tem contraste com o fundo)
    secondary: Color(0xFF076678), // blue
    tertiary: Color(0xFF427B58), // aqua
    error: Color(0xFF9D0006), // red
  );

  static const catppuccinMocha = Palette(
    name: 'Catppuccin Mocha',
    brightness: Brightness.dark,
    background: Color(0xFF1E1E2E), // base
    lowest: Color(0xFF11111B), // crust
    containers: [Color(0xFF181825), Color(0xFF313244), Color(0xFF45475A), Color(0xFF585B70)], // mantle, surface0-2
    text: Color(0xFFCDD6F4), // text
    subtext: Color(0xFFA6ADC8), // subtext0
    outline: Color(0xFF7F849C), // overlay1
    primary: Color(0xFFCBA6F7), // mauve
    secondary: Color(0xFF89B4FA), // blue
    tertiary: Color(0xFFF5C2E7), // pink
    error: Color(0xFFF38BA8), // red
  );

  static const catppuccinLatte = Palette(
    name: 'Catppuccin Latte',
    brightness: Brightness.light,
    background: Color(0xFFEFF1F5), // base
    lowest: Color(0xFFDCE0E8), // crust
    containers: [Color(0xFFE6E9EF), Color(0xFFCCD0DA), Color(0xFFBCC0CC), Color(0xFFACB0BE)], // mantle, surface0-2
    text: Color(0xFF4C4F69), // text
    subtext: Color(0xFF5C5F77), // subtext1 (subtext0 fica abaixo de 4.5:1)
    outline: Color(0xFF8C8FA1), // overlay1
    primary: Color(0xFF8839EF), // mauve
    secondary: Color(0xFF1E66F5), // blue
    tertiary: Color(0xFFEA76CB), // pink
    error: Color(0xFFD20F39), // red
  );
}
