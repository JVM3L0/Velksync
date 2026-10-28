import 'dart:async';

import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/device.dart';
import '../services/agent_client.dart';
import '../services/pc_probe.dart';
import '../services/stats_history.dart';
import '../services/versions.dart';
import '../services/wake_tracker.dart';
import '../ui/media_panel.dart';
import '../ui/perf.dart';
import '../ui/schedule.dart';
import '../ui/stats_chart.dart';
import '../ui/theme.dart';
import '../ui/transitions.dart';
import '../ui/update_notice.dart';
import '../ui/wake_help.dart';
import '../ui/widgets.dart';
import 'terminal_screen.dart';

class DeviceScreen extends StatefulWidget {
  final Device device;
  final VoidCallback onEdit;

  /// Veio do botão "desligar" do widget: ao confirmar que o PC está ligado,
  /// pergunta "Desligar?" (o widget mostra um estado que pode estar velho).
  final bool confirmShutdown;
  const DeviceScreen({super.key, required this.device, required this.onEdit, this.confirmShutdown = false});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  late final _client = AgentClient(widget.device);
  AgentInfo? _info;
  bool _checked = false;
  String? _awaitingLoginOs; // só o sinal de presença respondeu
  final _wakes = WakeTracker.instance;
  List<PresetCommand> _commands = [];
  String? _running;
  PcStats? _stats;
  late final _history = StatsHistory.of(widget.device.id); // para o gráfico já abrir preenchido
  int _tab = 0; // 0 controle, 1 desempenho, 2 mídia
  Timer? _poll;
  Timer? _statsPoll;
  StreamSubscription<PcStats>? _liveStats; // agente com "live": ele empurra os stats
  late bool _pendingShutdown = widget.confirmShutdown;
  String? _dismissedVersion; // "Agora não" vale até a versão do agente mudar
  String get _dismissKey => 'update_dismissed_${widget.device.id}';

  @override
  void initState() {
    super.initState();
    _wakes.addListener(_onWake);
    if (!widget.device.paired) return; // sem credencial: só dá para ligar
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _dismissedVersion = p.getString(_dismissKey));
    });
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
    // Desempenho só enquanto esta tela está aberta e o PC responde (em
    // qualquer aba: o histórico do gráfico vai enchendo).
    _statsPoll = Timer.periodic(const Duration(seconds: 2), (_) => _refreshStats());
  }

  @override
  void dispose() {
    _wakes.removeListener(_onWake);
    _poll?.cancel();
    _statsPoll?.cancel();
    _liveStats?.cancel();
    _client.close();
    super.dispose();
  }

  Future<void> _refreshStats() async {
    if (_liveStats != null) return; // o canal ao vivo já entrega
    if (_info == null) {
      if (_stats != null) setState(() => _stats = null);
      return;
    }
    try {
      final stats = await _client.stats();
      if (mounted) _gotStats(stats);
    } on AgentException {
      // agente antigo sem /api/stats ou queda momentânea: mantém o último
    }
  }

  void _onWake() {
    if (!mounted) return;
    final p = _wakes.of(widget.device.id);
    // O PC acabou de responder ao "ligar": atualiza sem esperar o próximo ciclo.
    if (p != null && !p.active && p.phase != WakePhase.failed) _refresh();
    setState(() {});
  }

  Future<void> _refresh() async {
    final state = await probePc(widget.device);
    var commands = _commands;
    if (state.info != null && _info == null) {
      try {
        commands = await _client.commands();
      } on AgentException {
        commands = [];
      }
    }
    if (!mounted) return;
    setState(() {
      _info = state.info;
      _awaitingLoginOs = state.power == PcPower.awaitingLogin ? state.os : null;
      _commands = state.info == null ? [] : commands;
      _checked = true;
    });
    _syncLiveStats();
    if (_pendingShutdown) {
      _pendingShutdown = false;
      if (state.info != null) {
        _power('shutdown', 'Desligar');
      } else {
        _snack('${widget.device.name} já não está ligado');
      }
    }
  }

  void _gotStats(PcStats s) {
    _history.add(s);
    // Fora da aba Desempenho só guarda: não precisa redesenhar a tela.
    if (_tab == 1) {
      setState(() => _stats = s);
    } else {
      _stats = s;
    }
  }

  /// Abre o canal ao vivo enquanto o PC responde; se cair, o polling assume
  /// e o próximo _refresh tenta de novo.
  void _syncLiveStats() {
    final want = _info?.has('live') ?? false;
    if (want && _liveStats == null) {
      void lost([Object? _]) => _liveStats = null;
      _liveStats = _client.liveStats().listen(
        (s) {
          if (mounted) _gotStats(s);
        },
        onError: lost,
        onDone: lost,
      );
    } else if (!want && _liveStats != null) {
      _liveStats!.cancel();
      _liveStats = null;
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _wake() async {
    try {
      await _wakes.start(widget.device);
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
      final grace = await _client.power(action);
      _snack(grace > 0 ? '$label em $grace s, se ninguém cancelar no PC' : '$label: comando enviado');
    } on AgentException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _schedule() async {
    final choice = await showScheduleSheet(context);
    if (choice == null) return;
    try {
      await _client.schedulePower(choice.action, delay: choice.delay, whenMediaStops: choice.whenMediaStops);
    } on AgentException catch (e) {
      _snack(e.message);
    }
    await _refresh();
  }

  Future<void> _cancelSchedule() async {
    try {
      await _client.cancelSchedule();
      _snack('Agendamento cancelado');
    } on AgentException catch (e) {
      _snack(e.message);
    }
    await _refresh();
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
    final status = switch (_wakes.of(d.id)?.phase) {
      WakePhase.waiting => PcStatus.waking,
      WakePhase.failed => PcStatus.wakeFailed,
      _ when !d.paired => PcStatus.unpaired,
      _ when !_checked => PcStatus.checking,
      _ when online => PcStatus.online,
      _ when _awaitingLoginOs != null => PcStatus.awaitingLogin,
      _ => PcStatus.offline,
    };
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
      body: SharedAxisSwitcher(
        index: online ? _tab : 0,
        child: switch (online ? _tab : 0) {
          1 => _performanceTab(),
          2 => MediaPanel(client: _client, live: _info?.has('live') ?? false),
          _ => _controlTab(d, status, online, scheme),
        },
      ),
      // Abas só com o PC respondendo: desempenho e mídia dependem do agente.
      bottomNavigationBar: AnimatedSize(
        duration: Motion.spatialDuration,
        curve: Motion.effects,
        alignment: Alignment.topCenter,
        child: online
            ? NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: (i) {
                  setState(() => _tab = i);
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Symbols.power_settings_new_rounded),
                    selectedIcon: Icon(Symbols.power_settings_new_rounded, fill: 1),
                    label: 'Controle',
                  ),
                  NavigationDestination(
                    icon: Icon(Symbols.monitoring_rounded),
                    selectedIcon: Icon(Symbols.monitoring_rounded, fill: 1),
                    label: 'Desempenho',
                  ),
                  NavigationDestination(
                    icon: Icon(Symbols.music_note_rounded),
                    selectedIcon: Icon(Symbols.music_note_rounded, fill: 1),
                    label: 'Mídia',
                  ),
                ],
              )
            // Sem abas, mantém o respiro da barra de gestos.
            : SizedBox(width: double.infinity, height: MediaQuery.paddingOf(context).bottom),
      ),
    );
  }

  Widget _controlTab(Device d, PcStatus status, bool online, ColorScheme scheme) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _hero(status),
          ?_updateNotice(),
          ..._energy(d, status, online, scheme),
          AnimatedSize(
            duration: Motion.spatialDuration,
            curve: Motion.effects,
            alignment: Alignment.topCenter,
            child: _info?.schedule == null
                ? const SizedBox(width: double.infinity)
                : ScheduleBanner(schedule: _info!.schedule!, onCancel: _cancelSchedule),
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
    );
  }

  /// Só as ações que fazem sentido no estado do PC: desligado mostra um
  /// "Ligar" grande; ligado, desligar, reiniciar, suspender e agendar. Com
  /// número ímpar de botões, o primeiro ocupa a linha toda.
  List<Widget> _energy(Device d, PcStatus status, bool online, ColorScheme scheme) {
    final canWake = d.mac.isNotEmpty;
    final tiles = <Widget>[
      if (online) ...[
        MorphTile(
          icon: Symbols.power_off_rounded,
          label: 'Desligar',
          color: Color.alphaBlend(scheme.error.withValues(alpha: 0.16), scheme.surfaceContainer),
          onColor: scheme.error,
          onTap: () => _power('shutdown', 'Desligar'),
        ),
        MorphTile(
          icon: Symbols.restart_alt_rounded,
          label: 'Reiniciar',
          color: scheme.secondaryContainer,
          onColor: scheme.onSecondaryContainer,
          onTap: () => _power('reboot', 'Reiniciar'),
        ),
        MorphTile(
          icon: Symbols.bedtime_rounded,
          label: 'Suspender',
          color: scheme.tertiaryContainer,
          onColor: scheme.onTertiaryContainer,
          onTap: () => _power('sleep', 'Suspender'),
        ),
        if (_info!.has('schedule'))
          MorphTile(
            icon: Symbols.schedule_rounded,
            label: 'Agendar',
            color: scheme.surfaceContainerHigh,
            onColor: scheme.onSurface,
            onTap: _schedule,
          ),
      ] else if (canWake &&
          (status == PcStatus.offline || status == PcStatus.unpaired || status == PcStatus.wakeFailed))
        MorphTile(
          icon: Symbols.power_settings_new_rounded,
          label: status == PcStatus.wakeFailed ? 'Tentar de novo' : 'Ligar',
          color: scheme.primary,
          onColor: scheme.onPrimary,
          onTap: _wake,
        ),
    ];
    if (tiles.isEmpty) return const []; // ligando, aguardando login, verificando
    return [
      const SectionLabel('Energia'),
      LayoutBuilder(
        builder: (context, box) {
          const gap = 10.0;
          final height = (box.maxWidth - gap) / 2 / 1.35;
          final rows = <Widget>[
            if (tiles.length.isOdd) SizedBox(width: double.infinity, height: height, child: tiles.first),
            for (var i = tiles.length % 2; i < tiles.length; i += 2)
              SizedBox(
                height: height,
                child: Row(
                  children: [
                    Expanded(child: tiles[i]),
                    const SizedBox(width: gap),
                    Expanded(child: tiles[i + 1]),
                  ],
                ),
              ),
          ];
          return Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[if (i > 0) const SizedBox(height: gap), rows[i]],
            ],
          );
        },
      ),
    ];
  }

  /// Aviso de versão: só com o PC respondendo e se não foi dispensado para
  /// esta versão do agente.
  Widget? _updateNotice() {
    final info = _info;
    if (info == null) return null;
    final gap = versionGap(agent: info.version);
    // Sem diferença entre app e agente, ainda pode haver versão nova que o
    // agente achou; "Agora não" vale por versão (a do agente ou a nova).
    final available = gap == VersionGap.none ? info.update : null;
    final key = available ?? info.version;
    if ((gap == VersionGap.none && available == null) || _dismissedVersion == key) return null;
    return UpdateBanner(
      gap: available != null ? VersionGap.agentOld : gap,
      agentVersion: info.version,
      appVersion: appVersion,
      available: available,
      os: info.os,
      onDismiss: () async {
        setState(() => _dismissedVersion = key);
        await (await SharedPreferences.getInstance()).setString(_dismissKey, key);
      },
      // No Windows o caminho é o ícone do PC; o texto já diz.
      onHowTo: available != null && info.os == 'windows'
          ? null
          : () => showUpdateSheet(context, gap: available != null ? VersionGap.agentOld : gap, os: info.os),
    );
  }

  Widget _performanceTab() {
    final s = _stats;
    if (s == null) return const Center(child: CircularProgressIndicator());
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [_performanceSection(s)]);
  }

  Widget _hero(PcStatus status) {
    final online = status == PcStatus.online;
    final on = online || status == PcStatus.awaitingLogin;
    final wake = _wakes.of(widget.device.id);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final fg = switch (status) {
      PcStatus.online => scheme.onPrimaryContainer,
      PcStatus.awaitingLogin || PcStatus.waking => scheme.onSecondaryContainer,
      PcStatus.wakeFailed => scheme.onErrorContainer,
      _ => scheme.onSurface,
    };
    final host = widget.device.host;
    final sub = switch (status) {
      PcStatus.online => '${_info!.osLabel} · ${_info!.hostname} · $host',
      PcStatus.offline => '$host · ou fora da rede',
      PcStatus.unpaired => 'Edite e escaneie o QR do PC para controlar. Ligar já funciona.',
      PcStatus.awaitingLogin => '${osLabelOf(_awaitingLoginOs ?? '')} · faça login no PC para controlar',
      PcStatus.waking =>
        'Sinal enviado há ${formatElapsed(wake!.elapsed)}${wake.sends > 1 ? ' · reenviado ${wake.sends - 1}×' : ''}',
      PcStatus.wakeFailed => 'Sem resposta em 2 minutos. Toque para ver o que conferir.',
      PcStatus.checking => host,
    };
    final card = AnimatedContainer(
      duration: Motion.spatialDuration,
      curve: Motion.effects,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: switch (status) {
          PcStatus.online => scheme.primaryContainer,
          PcStatus.awaitingLogin || PcStatus.waking => scheme.secondaryContainer,
          PcStatus.wakeFailed => scheme.errorContainer,
          _ => scheme.surfaceContainerHigh,
        },
        borderRadius: BorderRadius.circular(Radii.xlPlus),
      ),
      child: Row(
        children: [
          WakePop(
            active: wake != null && (wake.phase == WakePhase.online || wake.phase == WakePhase.awaitingLogin),
            child: AnimatedContainer(
              duration: Motion.spatialDuration,
              curve: Motion.spatial,
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: online
                    ? scheme.primary
                    : on
                    ? scheme.secondary
                    : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(on ? Radii.xxl : Radii.lgPlus),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    on ? osIcon(_info?.os ?? _awaitingLoginOs ?? '') : Symbols.computer_rounded,
                    size: 36,
                    fill: on ? 1 : 0,
                    color: online
                        ? scheme.onPrimary
                        : on
                        ? scheme.onSecondary
                        : scheme.onSurfaceVariant,
                  ),
                  if (status == PcStatus.waking)
                    const SizedBox.square(dimension: 64, child: CircularProgressIndicator(strokeWidth: 4)),
                ],
              ),
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
                      PcStatus.awaitingLogin => 'Aguardando login',
                      PcStatus.waking => 'Ligando…',
                      PcStatus.wakeFailed => 'Não ligou',
                    },
                    key: ValueKey(status),
                    style: text.headlineMedium?.copyWith(color: fg, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 4),
                Text(sub, style: text.bodyMedium?.copyWith(color: fg.withValues(alpha: 0.8))),
              ],
            ),
          ),
        ],
      ),
    );
    if (status != PcStatus.wakeFailed) return card;
    return GestureDetector(
      onTap: () async {
        await showWakeHelp(context);
        _wakes.dismiss(widget.device.id);
      },
      child: card,
    );
  }

  /// Dashboard de desempenho no estilo do Caelestia.
  Widget _performanceSection(PcStats s) {
    final scheme = Theme.of(context).colorScheme;
    final gpu = s.gpu;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          'Desempenho',
          // Sem temperatura (Windows), o tempo ligado vai para o cartão da CPU.
          action: s.cpuTemp == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    'ligado há ${formatUptime(s.uptime)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
        ),
        HeroCard(
          icon: Symbols.memory_rounded,
          label: 'CPU',
          subLabel: s.cpuName.isNotEmpty ? shortCpuName(s.cpuName) : '${s.cpuThreads} threads',
          usage: s.cpuPercent / 100,
          accent: scheme.primary,
          temperature: s.cpuTemp,
          fallback: (icon: Symbols.timer_rounded, text: 'Ligado há ${formatUptime(s.uptime)}', fraction: null),
          onTap: () => showStatsSheet(context, _history, Metric.cpu),
        ),
        if (gpu != null) ...[
          const SizedBox(height: 10),
          HeroCard(
            icon: Symbols.desktop_windows_rounded,
            label: 'GPU',
            subLabel: gpu.name,
            usage: gpu.percent / 100,
            accent: scheme.secondary,
            onTap: () => showStatsSheet(context, _history, Metric.gpu),
            temperature: gpu.temp,
            fallback: gpu.vramTotal == 0
                ? null
                : (
                    icon: Symbols.memory_alt_rounded,
                    text: 'VRAM ${formatBytes(gpu.vramUsed)} / ${formatBytes(gpu.vramTotal)}',
                    fraction: gpu.vramFraction,
                  ),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: GaugeCard(
                icon: Symbols.memory_alt_rounded,
                title: 'Memória',
                used: s.memUsed,
                total: s.memTotal,
                accent: scheme.tertiary,
                onTap: () => showStatsSheet(context, _history, Metric.mem),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GaugeCard(
                icon: Symbols.hard_drive_rounded,
                title: 'Disco',
                used: s.diskUsed,
                total: s.diskTotal,
                accent: scheme.primary,
              ),
            ),
          ],
        ),
      ],
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
