import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/device.dart';
import '../services/agent_client.dart';
import '../services/device_store.dart';
import '../services/pc_events.dart';
import '../services/wol.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'device_form_screen.dart';
import 'device_screen.dart';

class HomeScreen extends StatefulWidget {
  final GlobalKey<ScaffoldMessengerState> messenger;
  const HomeScreen({super.key, required this.messenger});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _store = DeviceStore();
  late final _events = PcEventListener(widget.messenger);
  List<Device> _devices = [];
  final Map<String, AgentInfo?> _status = {}; // ausente = verificando, null = offline
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  Future<void> _load() async {
    _devices = await _store.load();
    if (mounted) setState(() {});
    _start();
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
        final client = AgentClient(d);
        AgentInfo? info;
        try {
          info = await client.info();
        } on AgentException {
          info = null;
        } finally {
          client.close();
        }
        if (!mounted) return;
        setState(() => _status[d.id] = info);
        // Aprende o MAC sozinho na primeira vez que o PC responde.
        if (info != null && info.mac.isNotEmpty && d.mac.isEmpty) {
          await _save(d.copyWith(mac: info.mac));
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
      await wake(d.mac, broadcast: d.broadcast);
      messenger.showSnackBar(SnackBar(content: Text('Sinal para ligar enviado a ${d.name}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Falha: $e')));
    }
  }

  PcStatus _statusOf(Device d) => !d.paired
      ? PcStatus.unpaired
      : !_status.containsKey(d.id)
      ? PcStatus.checking
      : _status[d.id] != null
      ? PcStatus.online
      : PcStatus.offline;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final online = _devices.where((d) => _status[d.id] != null).length;
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
    final info = _status[d.id];
    final online = status == PcStatus.online;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
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
              IconBadge(icon: online ? osIcon(info!.os) : Symbols.computer_rounded, highlighted: online, size: 60),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.name, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    StatusPill(status: status, detail: online ? info!.osLabel : null),
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration: Motion.spatialFastDuration,
                switchInCurve: Motion.spatialFast,
                transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                child: (status == PcStatus.offline || status == PcStatus.unpaired) && d.mac.isNotEmpty
                    ? IconButton.filled(
                        key: const ValueKey('wake'),
                        tooltip: 'Ligar',
                        iconSize: 28,
                        style: IconButton.styleFrom(minimumSize: const Size(56, 56)),
                        onPressed: () => _wake(d),
                        icon: const Icon(Symbols.power_settings_new_rounded, weight: 600),
                      )
                    : Icon(
                        Symbols.keyboard_arrow_right_rounded,
                        key: const ValueKey('open'),
                        color: scheme.onSurfaceVariant,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
