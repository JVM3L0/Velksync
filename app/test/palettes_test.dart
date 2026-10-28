import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:velksync/ui/palettes.dart';

// Contraste WCAG 2.x: texto normal precisa de 4.5:1 (AA).
double contrast(Color a, Color b) {
  double lum(Color c) {
    double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  final l1 = lum(a), l2 = lum(b);
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

/// Cada paleta com cada destaque que ela oferece (ou só ela, sem seletor).
Iterable<Palette> get _variants sync* {
  for (final p in Palettes.all) {
    if (p.accents.isEmpty) {
      yield p;
      continue;
    }
    for (final id in p.accents.keys) {
      yield p.withAccent(id);
    }
  }
}

void main() {
  for (final p in _variants) {
    group('${p.name} (${p.accent.isEmpty ? 'padrão' : p.accent})', () {
      final s = p.toScheme();
      final pairs = {
        'texto/fundo': (s.onSurface, s.surface),
        'texto secundário/fundo': (s.onSurfaceVariant, s.surface),
        'texto/cartão': (s.onSurface, s.surfaceContainer),
        'texto secundário/cartão': (s.onSurfaceVariant, s.surfaceContainer),
        'botão primário': (s.onPrimary, s.primary),
        'botão secundário': (s.onSecondary, s.secondary),
        'contêiner primário': (s.onPrimaryContainer, s.primaryContainer),
        'contêiner secundário': (s.onSecondaryContainer, s.secondaryContainer),
        'contêiner terciário': (s.onTertiaryContainer, s.tertiaryContainer),
        'erro': (s.onErrorContainer, s.errorContainer),
        'snackbar': (s.onInverseSurface, s.inverseSurface),
        'ação do snackbar': (s.inversePrimary, s.inverseSurface),
      };
      for (final MapEntry(key: name, value: (fg, bg)) in pairs.entries) {
        test('$name ≥ 4.5:1', () {
          expect(contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: '$name em ${p.name}');
        });
      }
    });
  }

  test('o destaque escolhido vira o primary e nunca se repete na secundária ou terciária', () {
    for (final p in Palettes.all.where((p) => p.accents.isNotEmpty)) {
      for (final MapEntry(key: id, value: color) in p.accents.entries) {
        final a = p.withAccent(id);
        expect(a.primary, color, reason: '${p.name} $id');
        expect(a.secondary, isNot(color), reason: '${p.name} $id');
        expect(a.tertiary, isNot(color), reason: '${p.name} $id');
        expect(a.accent, id);
      }
      expect(p.withAccent('inexistente'), same(p));
      expect(p.withAccent(null), same(p));
    }
  });

  test('Gruvbox e Catppuccin oferecem os mesmos destaques no claro e no escuro', () {
    for (final v in GruvboxVariant.values) {
      final (l, d) = Palettes.gruvbox(v);
      expect(l.accents.keys, Palettes.gruvboxAccents.map((a) => a.id));
      expect(d.accents.keys, Palettes.gruvboxAccents.map((a) => a.id));
    }
    for (final f in CatppuccinFlavor.values) {
      final (l, d) = Palettes.catppuccin(f, 'peach');
      expect((l.accent, d.accent), ('peach', 'peach'));
      expect(d.accents.keys, Palettes.catppuccinAccents.map((a) => a.id));
    }
    expect(Palettes.gruvbox(GruvboxVariant.soft).$2.accent, 'green');
    expect(Palettes.gruvbox(GruvboxVariant.classic).$2.accent, 'orange');
  });
}
