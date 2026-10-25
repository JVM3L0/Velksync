import 'package:dynamic_color/dynamic_color.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../services/settings.dart';
import '../ui/palettes.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

class SettingsScreen extends StatelessWidget {
  final AppSettings settings;
  const SettingsScreen({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      // Lê as cores do papel de parede mesmo com outro tema ativo, para a prévia.
      body: DynamicColorBuilder(
        builder: (wallLight, wallDark) => ListenableBuilder(
          listenable: settings,
          builder: (context, _) {
            final scheme = Theme.of(context).colorScheme;
            final dark = Theme.of(context).brightness == Brightness.dark;
            final wall = schemeFrom(dark ? wallDark : wallLight, dark ? Brightness.dark : Brightness.light);
            List<Color> swatches(ThemeFamily f) => switch (f) {
              ThemeFamily.dynamic => [wall.surface, wall.primary, wall.secondary, wall.tertiary, wall.error],
              ThemeFamily.gruvbox => (dark ? Palettes.gruvboxDark : Palettes.gruvboxLight).swatches,
              ThemeFamily.catppuccin => (dark ? Palettes.catppuccinMocha : Palettes.catppuccinLatte).swatches,
            };
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              children: [
                const SectionLabel('Tema'),
                ExpressiveGroup(
                  children: [
                    for (final f in ThemeFamily.values)
                      _ThemeTile(
                        family: f,
                        swatches: swatches(f),
                        selected: settings.family == f,
                        onTap: () => settings.setFamily(f),
                      ),
                  ],
                ),
                const SectionLabel('Modo'),
                SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Symbols.brightness_auto_rounded),
                      label: Text('Sistema'),
                    ),
                    ButtonSegment(value: ThemeMode.light, icon: Icon(Symbols.light_mode_rounded), label: Text('Claro')),
                    ButtonSegment(value: ThemeMode.dark, icon: Icon(Symbols.dark_mode_rounded), label: Text('Escuro')),
                  ],
                  selected: {settings.mode},
                  onSelectionChanged: (s) => settings.setMode(s.first),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
                  child: Text(
                    'Gruvbox usa as variantes Dark/Light e Catppuccin usa Mocha/Latte conforme o modo.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  final ThemeFamily family;
  final List<Color> swatches;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeTile({required this.family, required this.swatches, required this.selected, required this.onTap});

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
            // Prévia: fundo da paleta com as cores de destaque em pílulas.
            AnimatedContainer(
              duration: Motion.effectsDuration,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: swatches.first,
                borderRadius: BorderRadius.circular(Radii.lg),
                border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2 : 1),
              ),
              child: Row(
                children: [
                  for (final c in swatches.skip(1))
                    Container(
                      width: 12,
                      height: 28,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(family.label, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  Text(family.description, style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            AnimatedSwitcher(
              duration: Motion.spatialFastDuration,
              switchInCurve: Motion.spatialFast,
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: selected
                  ? Icon(Symbols.check_circle_rounded, key: const ValueKey(true), fill: 1, color: scheme.primary)
                  : const SizedBox(key: ValueKey(false), width: 24),
            ),
          ],
        ),
      ),
    );
  }
}
