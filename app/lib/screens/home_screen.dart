import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/device.dart';
import '../services/device_store.dart';
import '../services/pc_events.dart';
import '../services/pc_probe.dart';
import '../services/settings.dart';
import '../services/wake_tracker.dart';
import '../services/widget_bridge.dart';
import '../ui/theme.dart';
import '../ui/transitions.dart';
import '../ui/wake_help.dart';
import '../ui/widgets.dart';
import 'device_form_screen.dart';
import 'device_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final GlobalKey<ScaffoldMessengerState> messenger;
  final AppSettings settings;
  const HomeScreen({super.key, required this.messenger, required this.settings});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _store = DeviceStore();
  late final _events = PcEventListener(widget.messenger);
  List<Device> _devices = [];
  final Map<String, PcState> _status = {}; // ausente = verificando
  final _wakes = WakeTracker.instance;
  Timer? _poll;
  final _celebrated = <String>{}; // PCs cujo "ligou" já foi comemorado
  final _widget = WidgetBridge();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _wakes.addListener(_onWake);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wakes.removeListener(_onWake);
    _poll?.cancel();
    _events.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _start();
    } else if (state == AppLifecycleState.paused) {
      _poll?.cancel();
      _events.dispose();
    }
  }

  void _onWake() {
    if (!mounted) return;
    for (final d in _devices) {
      final p = _wakes.of(d.id);
      final woke = p != null && (p.phase == WakePhase.online || p.phase == WakePhase.awaitingLogin);
      if (!woke) {
        _celebrated.remove(d.id);
      } else if (_celebrated.add(d.id)) {
        _celebrate(d, p);
      }
    }
    setState(() {});
  }

  /// O momento marcante do app: o PC respondeu ao "ligar". Vibração, o ícone
  /// dá um pulo e um aviso diz quanto demorou (vale em qualquer tela).
  void _celebrate(Device d, WakeProgress p) {
    HapticFeedback.mediumImpact();
    final login = p.phase == WakePhase.awaitingLogin ? ' · faça login para controlar' : '';
    widget.messenger.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('${d.name} ligou em ${humanElapsed(p.elapsed)}$login')));
  }

  Future<void> _load() async {
    _devices = await _store.load();
    if (mounted) setState(() {});
    _start();
    // Toque no widget: abre direto a tela daquele PC.
    WidgetBridge.onOpen(_openFromWidget);
    if (await WidgetBridge.takeLaunch() case final launch?) _openFromWidget(launch);
  }

  /// Abre a tela do PC tocado no widget; o botão de desligar abre já
  /// perguntando "Desligar?" (a tela confere antes se o PC está ligado).
  void _openFromWidget(WidgetLaunch launch) {
    if (!mounted) return;
    final d = _devices.where((x) => x.id == launch.device).firstOrNull;
    if (d == null) return; // id que não é nosso (outro app pode abrir a activity)
    Navigator.of(context).popUntil((r) => r.isFirst);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DeviceScreen(device: d, onEdit: () => _edit(d), confirmShutdown: launch.action == 'shutdown'),
      ),
    ).then((_) => _refresh());
  }

  void _start() {
    _events.update(_devices);
    _poll?.cancel();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  Future<void> _refresh() async {
    await Future.wait(
      _devices.where((d) => d.paired).map((d) async {
        final state = await probePc(d);
        if (!mounted) return;
        setState(() => _status[d.id] = state);
        _widget.report(d.id, state.power);
        // Aprende sozinho, na primeira vez que o PC responde, o MAC para o
        // Wake-on-LAN e o segredo do sinal de presença.
        final mac = state.info?.mac ?? '';
        final learnMac = mac.isNotEmpty && d.mac.isEmpty;
        if (learnMac || state.learnedPresenceKey != null) {
          await _save(d.copyWith(mac: learnMac ? mac : null, presenceKey: state.learnedPresenceKey));
        }
      }),
    );
  }

  Future<void> _save(Device d) async {
    var i = _devices.indexWhere((x) => x.id == d.id);
    // Parear de novo um PC já cadastrado (mesmo MAC) atualiza o cadastro em
    // vez de duplicar; no dual boot é o mesmo PC.
    if (i < 0 && d.mac.isNotEmpty) {
      i = _devices.indexWhere((x) => x.mac.toLowerCase() == d.mac.toLowerCase());
      if (i >= 0) {
        await _store.forget(_devices[i]);
        _status.remove(_devices[i].id);
      }
    }
    setState(() => i < 0 ? _devices.add(d) : _devices[i] = d);
    await _store.save(_devices);
    _events.update(_devices);
  }

  Future<void> _delete(Device d) async {
    setState(() {
      _devices.removeWhere((x) => x.id == d.id);
      _status.remove(d.id);
    });
    await _store.forget(d);
    await _store.save(_devices);
    await _widget.forget(d.id);
    _events.update(_devices);
  }

  Future<void> _edit([Device? d]) async {
    final result = await Navigator.push<Object>(
      context,
      MaterialPageRoute(builder: (_) => DeviceFormScreen(device: d)),
    );
    if (result is Device) {
      await _save(result);
      _refresh();
    } else if (result == DeviceFormScreen.deleted && d != null) {
      await _delete(d);
    }
  }

  Future<void> _wake(Device d) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _wakes.start(d);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Falha: $e')));
    }
  }

  PcStatus _statusOf(Device d) {
    switch (_wakes.of(d.id)?.phase) {
      case WakePhase.waiting:
        return PcStatus.waking;
      case WakePhase.failed:
        return PcStatus.wakeFailed;
      default:
    }
    if (!d.paired) return PcStatus.unpaired;
    return switch (_status[d.id]?.power) {
      null => PcStatus.checking,
      PcPower.online => PcStatus.online,
      PcPower.awaitingLogin => PcStatus.awaitingLogin,
      PcPower.offline => PcStatus.offline,
    };
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final online = _devices.where((d) => _status[d.id]?.power == PcPower.online).length;
    return Scaffold(
      floatingActionButton: _devices.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _edit,
              icon: const Icon(Symbols.add_rounded, weight: 600),
              label: const Text('Adicionar PC'),
            ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar.large(
              title: const Text('Velksync'),
              actions: [
                IconButton(tooltip: 'Atualizar', onPressed: _refresh, icon: const Icon(Symbols.refresh_rounded)),
                IconButton(
                  tooltip: 'Configurações',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => SettingsScreen(settings: widget.settings)),
                  ),
                  icon: const Icon(Symbols.settings_rounded),
                ),
                const SizedBox(width: 8),
              ],
            ),
            if (_devices.isEmpty)
              SliverFillRemaining(hasScrollBody: false, child: _empty(context))
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  child: Text(
                    online == 0 ? 'Nenhum PC ligado' : '$online de ${_devices.length} ligado${online > 1 ? 's' : ''}',
                    style: text.titleMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 112),
                sliver: SliverList.separated(
                  itemCount: _devices.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _card(_devices[i]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 96),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(Radii.xxl)),
            child: Icon(Symbols.devices_rounded, size: 56, fill: 1, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: 28),
          Text('Nenhum PC ainda', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            'Instale o agente no PC e pareie pelo QR code ou pela busca na rede.',
            textAlign: TextAlign.center,
            style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _edit,
            icon: const Icon(Symbols.add_rounded, weight: 600),
            label: const Text('Adicionar PC'),
          ),
        ],
      ),
    );
  }

  Widget _card(Device d) {
    final status = _statusOf(d);
    final os = _status[d.id]?.os ?? '';
    final on = status == PcStatus.online || status == PcStatus.awaitingLogin;
    final wake = _wakes.of(d.id);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      child: Builder(
        builder: (card) => InkWell(
          onTap: () async {
            await Navigator.push(
              context,
              ContainerTransformRoute(
                origin: card,
                builder: (_) => DeviceScreen(device: d, onEdit: () => _edit(d)),
              ),
            );
            _refresh();
          },
          onLongPress: () => _edit(d),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                WakePop(
                  active: _celebrated.contains(d.id),
                  child: IconBadge(icon: on ? osIcon(os) : Symbols.computer_rounded, highlighted: on, size: 60),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.name, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      StatusPill(
                        status: status,
                        detail: switch (status) {
                          PcStatus.waking => formatElapsed(wake!.elapsed),
                          _ when on => osLabelOf(os),
                          _ => null,
                        },
                      ),
                    ],
                  ),
                ),
                AnimatedSwitcher(
                  duration: Motion.spatialFastDuration,
                  switchInCurve: Motion.spatialFast,
                  transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                  child: switch (status) {
                    PcStatus.waking => const SizedBox.square(
                      key: ValueKey('waking'),
                      dimension: 56,
                      child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()),
                    ),
                    PcStatus.wakeFailed => IconButton.filledTonal(
                      key: const ValueKey('help'),
                      tooltip: 'Por que não ligou?',
                      iconSize: 28,
                      style: IconButton.styleFrom(minimumSize: const Size(56, 56)),
                      onPressed: () async {
                        await showWakeHelp(context);
                        _wakes.dismiss(d.id);
                      },
                      icon: const Icon(Symbols.help_rounded, weight: 600),
                    ),
                    _ when (status == PcStatus.offline || status == PcStatus.unpaired) && d.mac.isNotEmpty =>
                      IconButton.filled(
                        key: const ValueKey('wake'),
                        tooltip: 'Ligar',
                        iconSize: 28,
                        style: IconButton.styleFrom(minimumSize: const Size(56, 56)),
                        onPressed: () => _wake(d),
                        icon: const Icon(Symbols.power_settings_new_rounded, weight: 600),
                      ),
                    _ => Icon(
                      Symbols.keyboard_arrow_right_rounded,
                      key: const ValueKey('open'),
                      color: scheme.onSurfaceVariant,
                    ),
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
