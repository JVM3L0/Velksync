import 'package:dynamic_color/dynamic_color.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/device.dart';
import '../services/device_store.dart';

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
            Palette pick((Palette, Palette) p) => dark ? p.$2 : p.$1;
            List<Color> swatches(ThemeFamily f) => switch (f) {
              ThemeFamily.dynamic => [wall.surface, wall.primary, wall.secondary, wall.tertiary, wall.error],
              ThemeFamily.gruvbox => pick(Palettes.gruvbox(settings.gruvbox)).swatches,
              ThemeFamily.catppuccin => pick(Palettes.catppuccin(settings.catppuccin)).swatches,
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
                // Variante só para as famílias que têm (Gruvbox e Catppuccin).
                AnimatedSize(
                  duration: Motion.spatialDuration,
                  curve: Motion.effects,
                  alignment: Alignment.topCenter,
                  child: switch (settings.family) {
                    ThemeFamily.gruvbox => _Variant(
                      label: 'Variante',
                      hint: settings.gruvbox.description,
                      child: SegmentedButton<GruvboxVariant>(
                        showSelectedIcon: false,
                        segments: [
                          for (final v in GruvboxVariant.values) ButtonSegment(value: v, label: Text(v.label)),
                        ],
                        selected: {settings.gruvbox},
                        onSelectionChanged: (s) => settings.setGruvbox(s.first),
                      ),
                    ),
                    ThemeFamily.catppuccin => _Variant(
                      label: 'Sabor escuro',
                      hint: 'Do mais suave ao mais contrastado; o modo claro usa o Latte.',
                      child: SegmentedButton<CatppuccinFlavor>(
                        showSelectedIcon: false,
                        segments: [
                          for (final f in CatppuccinFlavor.values) ButtonSegment(value: f, label: Text(f.label)),
                        ],
                        selected: {settings.catppuccin},
                        onSelectionChanged: (s) => settings.setCatppuccin(s.first),
                      ),
                    ),
                    ThemeFamily.dynamic => const SizedBox(width: double.infinity),
                  },
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
                    'Os temas acompanham o modo: Gruvbox nas versões clara e escura, Catppuccin no Latte '
                    'quando claro e no sabor escolhido quando escuro.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                const _TilePicker(),
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

/// Qual PC o bloco "Ligar PC" das Configurações rápidas liga. O bloco
/// (WakeTileService.kt) lê esta escolha e a lista de PCs; sem escolha, usa o
/// primeiro com MAC.
class _TilePicker extends StatefulWidget {
  const _TilePicker();

  static const prefsKey = 'tile_device';

  @override
  State<_TilePicker> createState() => _TilePickerState();
}

class _TilePickerState extends State<_TilePicker> {
  List<Device> _devices = [];
  String? _chosen;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final devices = (await DeviceStore().load()).where((d) => d.mac.isNotEmpty).toList();
    final chosen = (await SharedPreferences.getInstance()).getString(_TilePicker.prefsKey);
    if (!mounted) return;
    setState(() {
      _devices = devices;
      _chosen = devices.any((d) => d.id == chosen) ? chosen : devices.firstOrNull?.id;
    });
  }

  Future<void> _choose(Device d) async {
    setState(() => _chosen = d.id);
    await (await SharedPreferences.getInstance()).setString(_TilePicker.prefsKey, d.id);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Bloco "Ligar PC"'),
        if (_devices.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Cadastre um PC com MAC para usar o bloco das Configurações rápidas.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          )
        else
          ExpressiveGroup(
            children: [
              for (final d in _devices)
                GroupTile(
                  icon: Symbols.power_settings_new_rounded,
                  title: d.name,
                  subtitle: d.mac,
                  highlighted: d.id == _chosen,
                  trailing: d.id == _chosen
                      ? Icon(Symbols.check_circle_rounded, fill: 1, color: scheme.primary)
                      : const SizedBox(width: 24),
                  onTap: () => _choose(d),
                ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
          child: Text(
            'Adicione o bloco puxando as Configurações rápidas e tocando no lápis. Ele só liga o PC; '
            'desligar e comandos continuam só dentro do app.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _Variant extends StatelessWidget {
  final String label, hint;
  final Widget child;
  const _Variant({required this.label, required this.hint, required this.child});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SectionLabel(label),
      child,
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: Text(
          hint,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    ],
  );
}
