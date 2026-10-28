import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Paletas fixas (Velksync, Gruvbox e Catppuccin) mapeadas para os papéis do Material 3.
/// Cores oficiais: github.com/morhetz/gruvbox, github.com/sainnhe/gruvbox-material
/// e github.com/catppuccin/palette. Uso das cores: guia de estilo do Catppuccin
/// (github.com/catppuccin/catppuccin/blob/main/docs/style-guide.md) e, como
/// referência de app, o tema Catppuccin do Mihon e o Gruvbox do Zed.

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

/// Cor de destaque que a pessoa escolhe; o id fica salvo nas preferências.
class Accent {
  final String id, label;
  const Accent(this.id, this.label);
}

class Palette {
  final String name;
  final Brightness brightness;
  final Color background; // surface: o fundo da tela
  final Color lowest; // surfaceContainerLowest; nas paletas sólidas, também o texto sobre o destaque
  final List<Color> containers; // low, base (cartões), high (chips, ícones), highest
  final Color text, subtext, outline;
  final Color primary, secondary, tertiary, error;

  /// Destaques da paleta por id (vazio: sem seletor). [accent] diz qual é o primary.
  final Map<String, Color> accents;
  final String accent;

  /// Tonal: contêineres misturam o destaque ao fundo (como o Material You).
  /// Sólido: destaque puro com texto escuro e o resto em superfícies da
  /// própria paleta, como os ports oficiais do Catppuccin e o Mihon.
  final bool solid;

  /// Snackbar e afins: a superfície do tema oposto (Latte no escuro, Mocha no claro).
  final Color? inverseBackground, inverseText;

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
    this.accents = const {},
    this.accent = '',
    this.solid = false,
    this.inverseBackground,
    this.inverseText,
  });

  /// Amostras para a prévia na tela de configurações.
  List<Color> get swatches => [background, primary, secondary, tertiary, error];

  /// A mesma paleta com outro destaque. A secundária e a terciária nunca
  /// repetem o destaque: quem coincide herda o destaque antigo.
  Palette withAccent(String? id) {
    final c = accents[id];
    if (id == null || c == null || id == accent) return this;
    var sec = secondary, ter = tertiary;
    if (sec == c) {
      sec = primary;
    } else if (ter == c) {
      ter = primary;
    }
    return Palette(
      name: name,
      brightness: brightness,
      background: background,
      lowest: lowest,
      containers: containers,
      text: text,
      subtext: subtext,
      outline: outline,
      primary: c,
      secondary: sec,
      tertiary: ter,
      error: error,
      accents: accents,
      accent: id,
      solid: solid,
      inverseBackground: inverseBackground,
      inverseText: inverseText,
    );
  }

  ColorScheme toScheme() {
    final dark = brightness == Brightness.dark;
    final onAccent = solid || dark ? lowest : background;
    // Botão cheio: quem cede é o fundo do botão, para o texto continuar claro/escuro.
    Color accent(Color c) => readable(c, onAccent);
    final primary = accent(this.primary), secondary = accent(this.secondary);
    final tertiary = accent(this.tertiary), error = accent(this.error);
    // Legível no cartão e no fundo da tela (que nas paletas sólidas é outro tom).
    final subtext = readable(readable(this.subtext, containers[1]), background);
    final inverseSurface = inverseBackground ?? text;
    final inverseOn = inverseText ?? background;

    final Color primaryContainer, onPrimaryContainer, secondaryContainer, onSecondaryContainer;
    final Color tertiaryContainer, onTertiaryContainer, errorContainer, onErrorContainer;
    if (solid) {
      // Destaque cheio só no que é principal; o resto fica numa superfície
      // neutra da paleta, com o ícone ou o texto na cor de destaque.
      final neutral = containers[2];
      primaryContainer = primary;
      onPrimaryContainer = onAccent;
      secondaryContainer = neutral;
      onSecondaryContainer = readable(this.primary, neutral);
      tertiaryContainer = neutral;
      onTertiaryContainer = readable(text, neutral);
      errorContainer = neutral;
      onErrorContainer = readable(this.error, neutral);
    } else {
      // Contêineres "tonais": a cor de destaque misturada ao fundo, como no M3.
      Color container(Color c) => Color.alphaBlend(c.withValues(alpha: dark ? 0.24 : 0.20), background);
      // Puxado para a cor de texto e, se ainda faltar contraste (paletas suaves),
      // clareado/escurecido até o mínimo AA.
      Color onContainer(Color c) =>
          readable(dark ? Color.lerp(c, text, 0.5)! : Color.lerp(c, text, 0.6)!, container(c));
      primaryContainer = container(primary);
      onPrimaryContainer = onContainer(primary);
      secondaryContainer = container(secondary);
      onSecondaryContainer = onContainer(secondary);
      tertiaryContainer = container(tertiary);
      onTertiaryContainer = onContainer(tertiary);
      errorContainer = container(error);
      onErrorContainer = onContainer(error);
    }
    return ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onAccent,
      primaryContainer: primaryContainer,
      onPrimaryContainer: onPrimaryContainer,
      secondary: secondary,
      onSecondary: onAccent,
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: onSecondaryContainer,
      tertiary: tertiary,
      onTertiary: onAccent,
      tertiaryContainer: tertiaryContainer,
      onTertiaryContainer: onTertiaryContainer,
      error: error,
      onError: onAccent,
      errorContainer: errorContainer,
      onErrorContainer: onErrorContainer,
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
      inverseSurface: inverseSurface,
      onInverseSurface: inverseOn,
      // A ação do snackbar fica sobre a superfície invertida: o destaque
      // escurecido/clareado até ter contraste lá.
      inversePrimary: readable(this.primary, inverseSurface),
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

  // Gruvbox e Catppuccin no estilo sólido: fundo da tela no tom mais
  // escuro, cartões no fundo padrão e o destaque puro (referências: guia de
  // estilo do Catppuccin, Mihon, Zed e Gruvbox Material para VS Code).

  static const gruvboxAccents = [
    Accent('orange', 'Laranja'),
    Accent('yellow', 'Amarelo'),
    Accent('green', 'Verde'),
    Accent('aqua', 'Aqua'),
    Accent('blue', 'Azul'),
  ];

  static const gruvboxDark = Palette(
    name: 'Gruvbox Dark',
    brightness: Brightness.dark,
    solid: true,
    background: Color(0xFF1D2021), // bg0_h
    lowest: Color(0xFF1D2021),
    containers: [Color(0xFF282828), Color(0xFF282828), Color(0xFF3C3836), Color(0xFF504945)], // bg0, bg0, bg1, bg2
    text: Color(0xFFEBDBB2), // fg1
    subtext: Color(0xFFBDAE93), // fg3
    outline: Color(0xFF928374), // gray
    primary: Color(0xFFFE8019), // orange
    secondary: Color(0xFFFABD2F), // yellow
    tertiary: Color(0xFF8EC07C), // aqua
    error: Color(0xFFFB4934), // red
    accent: 'orange',
    accents: {
      'orange': Color(0xFFFE8019),
      'yellow': Color(0xFFFABD2F),
      'green': Color(0xFFB8BB26),
      'aqua': Color(0xFF8EC07C),
      'blue': Color(0xFF83A598),
    },
    inverseBackground: Color(0xFFFBF1C7),
    inverseText: Color(0xFF3C3836),
  );

  static const gruvboxLight = Palette(
    name: 'Gruvbox Light',
    brightness: Brightness.light,
    solid: true,
    background: Color(0xFFF2E5BC), // bg0_s
    lowest: Color(0xFFF9F5D7), // bg0_h
    containers: [Color(0xFFFBF1C7), Color(0xFFFBF1C7), Color(0xFFEBDBB2), Color(0xFFD5C4A1)], // bg0, bg0, bg1, bg2
    text: Color(0xFF3C3836), // fg1
    subtext: Color(0xFF665C54), // fg3
    outline: Color(0xFF928374), // gray
    primary: Color(0xFFAF3A03), // orange
    secondary: Color(0xFFB57614), // yellow
    tertiary: Color(0xFF427B58), // aqua
    error: Color(0xFF9D0006), // red
    accent: 'orange',
    accents: {
      'orange': Color(0xFFAF3A03),
      'yellow': Color(0xFFB57614),
      'green': Color(0xFF79740E),
      'aqua': Color(0xFF427B58),
      'blue': Color(0xFF076678),
    },
    inverseBackground: Color(0xFF282828),
    inverseText: Color(0xFFEBDBB2),
  );

  // Gruvbox Material (fundo medium/soft, frente "material"): a versão
  // pastel. O padrão é o verde, como no Gruvbox Material do VS Code.
  static const gruvboxSoftDark = Palette(
    name: 'Gruvbox Suave Dark',
    brightness: Brightness.dark,
    solid: true,
    background: Color(0xFF282828), // bg0 medium
    lowest: Color(0xFF1B1B1B), // bg_dim
    containers: [Color(0xFF32302F), Color(0xFF32302F), Color(0xFF45403D), Color(0xFF5A524C)], // bg0 soft, bg3, bg5
    text: Color(0xFFD4BE98), // fg0
    subtext: Color(0xFFA89984), // grey2
    outline: Color(0xFF928374), // grey1
    primary: Color(0xFFA9B665), // green
    secondary: Color(0xFFD8A657), // yellow
    tertiary: Color(0xFF7DAEA3), // blue
    error: Color(0xFFEA6962), // red
    accent: 'green',
    accents: {
      'orange': Color(0xFFE78A4E),
      'yellow': Color(0xFFD8A657),
      'green': Color(0xFFA9B665),
      'aqua': Color(0xFF89B482),
      'blue': Color(0xFF7DAEA3),
    },
    inverseBackground: Color(0xFFFBF1C7),
    inverseText: Color(0xFF654735),
  );

  static const gruvboxSoftLight = Palette(
    name: 'Gruvbox Suave Light',
    brightness: Brightness.light,
    solid: true,
    background: Color(0xFFF2E5BC), // bg0 soft
    lowest: Color(0xFFF9F5D7), // bg0 hard
    containers: [Color(0xFFFBF1C7), Color(0xFFFBF1C7), Color(0xFFEDDEB5), Color(0xFFE6D5AE)], // bg0 medium, bg1, bg3
    text: Color(0xFF654735), // fg0
    subtext: Color(0xFF7C6F64), // grey2
    outline: Color(0xFF928374), // grey1
    primary: Color(0xFF6C782E), // green
    secondary: Color(0xFFB47109), // yellow
    tertiary: Color(0xFF45707A), // blue
    error: Color(0xFFC14A4A), // red
    accent: 'green',
    accents: {
      'orange': Color(0xFFC35E0A),
      'yellow': Color(0xFFB47109),
      'green': Color(0xFF6C782E),
      'aqua': Color(0xFF4C7A5D),
      'blue': Color(0xFF45707A),
    },
    inverseBackground: Color(0xFF32302F),
    inverseText: Color(0xFFD4BE98),
  );

  static const catppuccinAccents = [
    Accent('mauve', 'Mauve'),
    Accent('lavender', 'Lavanda'),
    Accent('blue', 'Azul'),
    Accent('sapphire', 'Safira'),
    Accent('teal', 'Verde-água'),
    Accent('green', 'Verde'),
    Accent('peach', 'Pêssego'),
    Accent('pink', 'Rosa'),
    Accent('red', 'Vermelho'),
  ];

  static const catppuccinMocha = Palette(
    name: 'Catppuccin Mocha',
    brightness: Brightness.dark,
    solid: true,
    background: Color(0xFF181825), // mantle
    lowest: Color(0xFF11111B), // crust
    containers: [Color(0xFF1E1E2E), Color(0xFF1E1E2E), Color(0xFF313244), Color(0xFF45475A)], // base, base, surface0-1
    text: Color(0xFFCDD6F4), // text
    subtext: Color(0xFFA6ADC8), // subtext0
    outline: Color(0xFF7F849C), // overlay1
    primary: Color(0xFFCBA6F7), // mauve
    secondary: Color(0xFFB4BEFE), // lavender
    tertiary: Color(0xFFA6E3A1), // green
    error: Color(0xFFF38BA8), // red
    accent: 'mauve',
    accents: {
      'mauve': Color(0xFFCBA6F7),
      'lavender': Color(0xFFB4BEFE),
      'blue': Color(0xFF89B4FA),
      'sapphire': Color(0xFF74C7EC),
      'teal': Color(0xFF94E2D5),
      'green': Color(0xFFA6E3A1),
      'peach': Color(0xFFFAB387),
      'pink': Color(0xFFF5C2E7),
      'red': Color(0xFFF38BA8),
    },
    inverseBackground: Color(0xFFEFF1F5), // Latte base
    inverseText: Color(0xFF4C4F69),
  );

  static const catppuccinMacchiato = Palette(
    name: 'Catppuccin Macchiato',
    brightness: Brightness.dark,
    solid: true,
    background: Color(0xFF1E2030), // mantle
    lowest: Color(0xFF181926), // crust
    containers: [Color(0xFF24273A), Color(0xFF24273A), Color(0xFF363A4F), Color(0xFF494D64)], // base, base, surface0-1
    text: Color(0xFFCAD3F5),
    subtext: Color(0xFFA5ADCB), // subtext0
    outline: Color(0xFF8087A2), // overlay1
    primary: Color(0xFFC6A0F6), // mauve
    secondary: Color(0xFFB7BDF8), // lavender
    tertiary: Color(0xFFA6DA95), // green
    error: Color(0xFFED8796), // red
    accent: 'mauve',
    accents: {
      'mauve': Color(0xFFC6A0F6),
      'lavender': Color(0xFFB7BDF8),
      'blue': Color(0xFF8AADF4),
      'sapphire': Color(0xFF7DC4E4),
      'teal': Color(0xFF8BD5CA),
      'green': Color(0xFFA6DA95),
      'peach': Color(0xFFF5A97F),
      'pink': Color(0xFFF5BDE6),
      'red': Color(0xFFED8796),
    },
    inverseBackground: Color(0xFFEFF1F5),
    inverseText: Color(0xFF4C4F69),
  );

  static const catppuccinFrappe = Palette(
    name: 'Catppuccin Frappé',
    brightness: Brightness.dark,
    solid: true,
    background: Color(0xFF292C3C), // mantle
    lowest: Color(0xFF232634), // crust
    containers: [Color(0xFF303446), Color(0xFF303446), Color(0xFF414559), Color(0xFF51576D)], // base, base, surface0-1
    text: Color(0xFFC6D0F5),
    subtext: Color(0xFFA5ADCE), // subtext0
    outline: Color(0xFF838BA7), // overlay1
    primary: Color(0xFFCA9EE6), // mauve
    secondary: Color(0xFFBABBF1), // lavender
    tertiary: Color(0xFFA6D189), // green
    error: Color(0xFFE78284), // red
    accent: 'mauve',
    accents: {
      'mauve': Color(0xFFCA9EE6),
      'lavender': Color(0xFFBABBF1),
      'blue': Color(0xFF8CAAEE),
      'sapphire': Color(0xFF85C1DC),
      'teal': Color(0xFF81C8BE),
      'green': Color(0xFFA6D189),
      'peach': Color(0xFFEF9F76),
      'pink': Color(0xFFF4B8E4),
      'red': Color(0xFFE78284),
    },
    inverseBackground: Color(0xFFEFF1F5),
    inverseText: Color(0xFF4C4F69),
  );

  static const catppuccinLatte = Palette(
    name: 'Catppuccin Latte',
    brightness: Brightness.light,
    solid: true,
    background: Color(0xFFE6E9EF), // mantle
    lowest: Color(0xFFEFF1F5), // base: o mais claro, também texto sobre o destaque
    containers: [Color(0xFFEFF1F5), Color(0xFFEFF1F5), Color(0xFFCCD0DA), Color(0xFFBCC0CC)], // base, base, surface0-1
    text: Color(0xFF4C4F69),
    subtext: Color(0xFF5C5F77), // subtext1 (subtext0 fica abaixo de 4.5:1)
    outline: Color(0xFF8C8FA1), // overlay1
    primary: Color(0xFF8839EF), // mauve
    secondary: Color(0xFF7287FD), // lavender
    tertiary: Color(0xFF40A02B), // green
    error: Color(0xFFD20F39), // red
    accent: 'mauve',
    accents: {
      'mauve': Color(0xFF8839EF),
      'lavender': Color(0xFF7287FD),
      'blue': Color(0xFF1E66F5),
      'sapphire': Color(0xFF209FB5),
      'teal': Color(0xFF179299),
      'green': Color(0xFF40A02B),
      'peach': Color(0xFFFE640B),
      'pink': Color(0xFFEA76CB),
      'red': Color(0xFFD20F39),
    },
    inverseBackground: Color(0xFF1E1E2E), // Mocha base
    inverseText: Color(0xFFCDD6F4),
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

  /// [accent]: id escolhido em Configurações; null usa o padrão da variante.
  static (Palette light, Palette dark) gruvbox(GruvboxVariant v, [String? accent]) {
    final (l, d) = switch (v) {
      GruvboxVariant.soft => (gruvboxSoftLight, gruvboxSoftDark),
      GruvboxVariant.classic => (gruvboxLight, gruvboxDark),
    };
    return (l.withAccent(accent), d.withAccent(accent));
  }

  static (Palette light, Palette dark) catppuccin(CatppuccinFlavor f, [String? accent]) => (
    catppuccinLatte.withAccent(accent),
    switch (f) {
      CatppuccinFlavor.frappe => catppuccinFrappe,
      CatppuccinFlavor.macchiato => catppuccinMacchiato,
      CatppuccinFlavor.mocha => catppuccinMocha,
    }.withAccent(accent),
  );
}
