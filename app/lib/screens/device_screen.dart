import 'dart:async';

import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../models/device.dart';
import '../services/agent_client.dart';
import '../services/wol.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'terminal_screen.dart';

class DeviceScreen extends StatefulWidget {
  final Device device;
  final VoidCallback onEdit;
  const DeviceScreen({super.key, required this.device, required this.onEdit});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  late final _client = AgentClient(widget.device);
  AgentInfo? _info;
  bool _checked = false;
  List<PresetCommand> _commands = [];
  String? _running;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    if (!widget.device.paired) return; // sem credencial: só dá para ligar
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _client.close();
    super.dispose();
  }

  Future<void> _refresh() async {
    AgentInfo? info;
    var commands = _commands;
    try {
      info = await _client.info();
      if (_info == null) commands = await _client.commands();
    } on AgentException {
      info = null;
    }
    if (!mounted) return;
    setState(() {
      _info = info;
      _commands = info == null ? [] : commands;
      _checked = true;
    });
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _wake() async {
    try {
      await wake(widget.device.mac, broadcast: widget.device.broadcast);
      _snack('Sinal enviado. O PC deve ligar em alguns segundos.');
    } catch (e) {
      _snack('Falha: $e');
    }
  }

  Future<void> _power(String action, String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$label ${widget.device.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(label)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _client.power(action);
      _snack('$label: comando enviado');
    } on AgentException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _run(PresetCommand c) async {
    setState(() => _running = c.id);
    try {
      final r = await _client.run(c.id);
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => ResultSheet(title: c.name, result: r),
      );
    } on AgentException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _running = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.device;
    final online = _info != null;
    final status = !d.paired
        ? PcStatus.unpaired
        : !_checked
        ? PcStatus.checking
        : (online ? PcStatus.online : PcStatus.offline);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(d.name),
        actions: [
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Symbols.edit_rounded),
            onPressed: () {
              Navigator.pop(context);
              widget.onEdit();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _hero(status),
            const SectionLabel('Energia'),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.35,
              children: [
                MorphTile(
                  icon: Symbols.power_settings_new_rounded,
                  label: 'Ligar',
                  color: scheme.primary,
                  onColor: scheme.onPrimary,
                  onTap: !online && d.mac.isNotEmpty ? _wake : null,
                ),
                MorphTile(
                  icon: Symbols.power_off_rounded,
                  label: 'Desligar',
                  color: Color.alphaBlend(scheme.error.withValues(alpha: 0.16), scheme.surfaceContainer),
                  onColor: scheme.error,
                  onTap: online ? () => _power('shutdown', 'Desligar') : null,
                ),
                MorphTile(
                  icon: Symbols.restart_alt_rounded,
                  label: 'Reiniciar',
                  color: scheme.secondaryContainer,
                  onColor: scheme.onSecondaryContainer,
                  onTap: online ? () => _power('reboot', 'Reiniciar') : null,
                ),
                MorphTile(
                  icon: Symbols.bedtime_rounded,
                  label: 'Suspender',
                  color: scheme.tertiaryContainer,
                  onColor: scheme.onTertiaryContainer,
                  onTap: online ? () => _power('sleep', 'Suspender') : null,
                ),
              ],
            ),
            if (d.mac.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
                child: Text(
                  'Sem MAC salvo: abra o app com o PC ligado uma vez para habilitar "Ligar".',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            AnimatedSize(
              duration: Motion.spatialDuration,
              curve: Motion.spatial,
              alignment: Alignment.topCenter,
              child: online ? _commandsSection() : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero(PcStatus status) {
    final online = status == PcStatus.online;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final fg = online ? scheme.onPrimaryContainer : scheme.onSurface;
    final sub = online ? '${_info!.osLabel} · ${_info!.hostname} · ${widget.device.host}' : widget.device.host;
    return AnimatedContainer(
      duration: Motion.spatialDuration,
      curve: Motion.effects,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: online ? scheme.primaryContainer : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(Radii.xlPlus),
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: Motion.spatialDuration,
            curve: Motion.spatial,
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: online ? scheme.primary : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(online ? Radii.xxl : Radii.lgPlus),
            ),
            child: Icon(
              online ? osIcon(_info!.os) : Symbols.computer_rounded,
              size: 36,
              fill: online ? 1 : 0,
              color: online ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedSwitcher(
                  duration: Motion.effectsDuration,
                  child: Text(
                    switch (status) {
                      PcStatus.online => 'Ligado',
                      PcStatus.offline => 'Desligado',
                      PcStatus.checking => 'Verificando…',
                      PcStatus.unpaired => 'Não pareado',
                    },
                    key: ValueKey(status),
                    style: text.headlineMedium?.copyWith(color: fg, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 4),
                Text(switch (status) {
                  PcStatus.offline => '$sub · ou fora da rede',
                  PcStatus.unpaired => 'Edite e escaneie o QR do PC para controlar. Ligar já funciona.',
                  _ => sub,
                }, style: text.bodyMedium?.copyWith(color: fg.withValues(alpha: 0.8))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _commandsSection() {
    final tiles = <Widget>[
      if (_info!.allowShell)
        GroupTile(
          icon: Symbols.terminal_rounded,
          title: 'Terminal',
          subtitle: 'Comandos livres',
          highlighted: true,
          trailing: const Icon(Symbols.keyboard_arrow_right_rounded),
          onTap: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => TerminalScreen(device: widget.device))),
        ),
      for (final c in _commands)
        GroupTile(
          icon: Symbols.play_arrow_rounded,
          title: c.name,
          trailing: _running == c.id
              ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 3))
              : null,
          onTap: _running == null ? () => _run(c) : null,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Comandos'),
        if (tiles.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('Nenhum comando para ${_info!.osLabel}. Adicione em "commands" na config do agente.'),
          )
        else
          ExpressiveGroup(children: tiles),
      ],
    );
  }
}

class ResultSheet extends StatelessWidget {
  final String title;
  final RunResult result;
  const ResultSheet({super.key, required this.title, required this.result});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final status = result.timedOut ? 'tempo esgotado' : 'código ${result.exitCode}';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  result.ok ? Symbols.check_circle_rounded : Symbols.error_rounded,
                  fill: 1,
                  size: 28,
                  color: result.ok ? scheme.primary : scheme.error,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 40),
              child: Text(
                '$status · ${result.durationMs} ms',
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.55),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(Radii.lgPlus),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  result.output.isEmpty ? '(sem saída)' : result.output,
                  style: monoStyle(color: scheme.onSurface),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
