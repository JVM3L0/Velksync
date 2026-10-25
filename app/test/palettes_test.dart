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

void main() {
  for (final p in Palettes.all) {
    group(p.name, () {
      final s = p.toScheme();
      final pairs = {
        'texto/fundo': (s.onSurface, s.surface),
        'texto secundário/fundo': (s.onSurfaceVariant, s.surface),
        'texto/cartão': (s.onSurface, s.surfaceContainer),
        'botão primário': (s.onPrimary, s.primary),
        'contêiner primário': (s.onPrimaryContainer, s.primaryContainer),
        'contêiner secundário': (s.onSecondaryContainer, s.secondaryContainer),
        'erro': (s.onErrorContainer, s.errorContainer),
      };
      for (final MapEntry(key: name, value: (fg, bg)) in pairs.entries) {
        test('$name ≥ 4.5:1', () {
          expect(contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: '$name em ${p.name}');
        });
      }
    });
  }
}
