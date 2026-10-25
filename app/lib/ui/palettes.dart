import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Paletas fixas (Velksync, Gruvbox e Catppuccin) mapeadas para os papéis do Material 3.
/// Cores oficiais: github.com/morhetz/gruvbox, github.com/sainnhe/gruvbox-material
/// e github.com/catppuccin/palette.

/// Gruvbox: o original saturado ou o Gruvbox Material suave (tons pastéis).
enum GruvboxVariant {
  soft('Suave', 'Gruvbox Material, tons pastéis'),
  classic('Original', 'Cores fortes do Gruvbox');

  final String label, description;
  const GruvboxVariant(this.label, this.description);
}

/// Sabor escuro do Catppuccin; o claro é sempre o Latte. Do mais suave ao
/// mais contrastado.
enum CatppuccinFlavor {
  frappe('Frappé'),
  macchiato('Macchiato'),
  mocha('Mocha');

  final String label;
  const CatppuccinFlavor(this.label);
}

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
    // Puxado para a cor de texto e, se ainda faltar contraste (paletas suaves),
    // clareado/escurecido até o mínimo AA.
    Color onContainer(Color c) => readable(dark ? Color.lerp(c, text, 0.5)! : Color.lerp(c, text, 0.6)!, container(c));
    final onAccent = dark ? lowest : background;
    // Botão cheio: quem cede é o fundo do botão, para o texto continuar claro/escuro.
    Color accent(Color c) => readable(c, onAccent);
    final primary = accent(this.primary), secondary = accent(this.secondary);
    final tertiary = accent(this.tertiary), error = accent(this.error);
    final subtext = readable(this.subtext, containers[1]);
    return ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onAccent,
      primaryContainer: container(primary),
      onPrimaryContainer: onContainer(primary),
      secondary: secondary,
      onSecondary: onAccent,
      secondaryContainer: container(secondary),
      onSecondaryContainer: onContainer(secondary),
      tertiary: tertiary,
      onTertiary: onAccent,
      tertiaryContainer: container(tertiary),
      onTertiaryContainer: onContainer(tertiary),
      error: error,
      onError: onAccent,
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

/// Contraste WCAG 2.x entre duas cores (1 a 21).
double contrastRatio(Color a, Color b) {
  double lum(Color c) {
    double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  final l1 = lum(a), l2 = lum(b);
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

/// [fg] com contraste AA (4.5:1) sobre [bg]: se já tem, volta igual; senão vai
/// em direção ao preto ou ao branco (o que se afasta de [bg]) só o necessário.
Color readable(Color fg, Color bg, {double min = 4.5}) {
  if (contrastRatio(fg, bg) >= min) return fg;
  final target = contrastRatio(Colors.black, bg) > contrastRatio(Colors.white, bg) ? Colors.black : Colors.white;
  for (var t = 0.05; t < 1; t += 0.05) {
    final c = Color.lerp(fg, target, t)!;
    if (contrastRatio(c, bg) >= min) return c;
  }
  return target;
}

abstract final class Palettes {
  // Velksync: as cores do ícone (marinho do fundo, gelo das asas) com um toque
  // lilás da Velkhana. Ver tools/icon/generate.py.
  static const velksyncDark = Palette(
    name: 'Velksync Dark',
    brightness: Brightness.dark,
    background: Color(0xFF0B1A33),
    lowest: Color(0xFF060F22), // fundo do ícone
    containers: [Color(0xFF0F2140), Color(0xFF16345F), Color(0xFF1D3F6E), Color(0xFF264B7E)],
    text: Color(0xFFE6F4FF),
    subtext: Color(0xFFA9C2DB),
    outline: Color(0xFF6F8BAA),
    primary: Color(0xFFA8DDFF), // gelo
    secondary: Color(0xFF7FE3FF), // brilho
    tertiary: Color(0xFFC3B5FF), // lilás
    error: Color(0xFFFF8A8A),
  );

  static const velksyncLight = Palette(
    name: 'Velksync Light',
    brightness: Brightness.light,
    background: Color(0xFFF4F9FF),
    lowest: Color(0xFFFFFFFF),
    containers: [Color(0xFFEAF3FD), Color(0xFFDFEBF8), Color(0xFFD2E2F3), Color(0xFFC4D7EC)],
    text: Color(0xFF0B1A33),
    subtext: Color(0xFF3D5674),
    outline: Color(0xFF7189A6),
    primary: Color(0xFF1F6FB5), // gelo profundo
    secondary: Color(0xFF1C7A96),
    tertiary: Color(0xFF6650B8),
    error: Color(0xFFB3261E),
  );

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

  // Gruvbox Material, fundo "soft" e frente "material": a versão pastel.
  // bg2/bg4 do soft repetem bg1/bg3; os níveis intermediários vêm do medium.
  static const gruvboxSoftDark = Palette(
    name: 'Gruvbox Suave Dark',
    brightness: Brightness.dark,
    background: Color(0xFF32302F), // bg0
    lowest: Color(0xFF252423), // bg_dim
    containers: [Color(0xFF3C3836), Color(0xFF45403D), Color(0xFF504945), Color(0xFF5A524C)],
    text: Color(0xFFD4BE98), // fg0
    subtext: Color(0xFFA89984), // grey2
    outline: Color(0xFF928374), // grey1
    primary: Color(0xFFD8A657), // yellow
    secondary: Color(0xFF7DAEA3), // blue
    tertiary: Color(0xFFD3869B), // purple
    error: Color(0xFFEA6962), // red
  );

  static const gruvboxSoftLight = Palette(
    name: 'Gruvbox Suave Light',
    brightness: Brightness.light,
    background: Color(0xFFF2E5BC), // bg0
    lowest: Color(0xFFF9F5D7), // bg0 do hard: o nível mais claro
    containers: [Color(0xFFEDDEB5), Color(0xFFEBDBB2), Color(0xFFE6D5AE), Color(0xFFDAC9A5)], // bg1-4
    text: Color(0xFF654735), // fg0
    subtext: Color(0xFF7C6F64), // grey2
    outline: Color(0xFF928374), // grey1
    primary: Color(0xFFC35E0A), // orange
    secondary: Color(0xFF45707A), // blue
    tertiary: Color(0xFF945E80), // purple
    error: Color(0xFFC14A4A), // red
  );

  static const catppuccinFrappe = Palette(
    name: 'Catppuccin Frappé',
    brightness: Brightness.dark,
    background: Color(0xFF303446), // base
    lowest: Color(0xFF232634), // crust
    containers: [Color(0xFF292C3C), Color(0xFF414559), Color(0xFF51576D), Color(0xFF626880)], // mantle, surface0-2
    text: Color(0xFFC6D0F5), // text
    subtext: Color(0xFFA5ADCE), // subtext0
    outline: Color(0xFF838BA7), // overlay1
    primary: Color(0xFFCA9EE6), // mauve
    secondary: Color(0xFF8CAAEE), // blue
    tertiary: Color(0xFFF4B8E4), // pink
    error: Color(0xFFE78284), // red
  );

  static const catppuccinMacchiato = Palette(
    name: 'Catppuccin Macchiato',
    brightness: Brightness.dark,
    background: Color(0xFF24273A), // base
    lowest: Color(0xFF181926), // crust
    containers: [Color(0xFF1E2030), Color(0xFF363A4F), Color(0xFF494D64), Color(0xFF5B6078)], // mantle, surface0-2
    text: Color(0xFFCAD3F5), // text
    subtext: Color(0xFFA5ADCB), // subtext0
    outline: Color(0xFF8087A2), // overlay1
    primary: Color(0xFFC6A0F6), // mauve
    secondary: Color(0xFF8AADF4), // blue
    tertiary: Color(0xFFF5BDE6), // pink
    error: Color(0xFFED8796), // red
  );

  static const all = [
    velksyncDark,
    velksyncLight,
    gruvboxDark,
    gruvboxLight,
    gruvboxSoftDark,
    gruvboxSoftLight,
    catppuccinMocha,
    catppuccinMacchiato,
    catppuccinFrappe,
    catppuccinLatte,
  ];

  static const velksync = (velksyncLight, velksyncDark);

  static (Palette light, Palette dark) gruvbox(GruvboxVariant v) => switch (v) {
    GruvboxVariant.soft => (gruvboxSoftLight, gruvboxSoftDark),
    GruvboxVariant.classic => (gruvboxLight, gruvboxDark),
  };

  static (Palette light, Palette dark) catppuccin(CatppuccinFlavor f) => (
    catppuccinLatte,
    switch (f) {
      CatppuccinFlavor.frappe => catppuccinFrappe,
      CatppuccinFlavor.macchiato => catppuccinMacchiato,
      CatppuccinFlavor.mocha => catppuccinMocha,
    },
  );
}
