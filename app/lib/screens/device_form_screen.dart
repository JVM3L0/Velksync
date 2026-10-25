import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../models/device.dart';
import '../services/agent_client.dart';
import '../services/discovery.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'scan_screen.dart';

class DeviceFormScreen extends StatefulWidget {
  static const deleted = 'deleted';
  final Device? device;
  const DeviceFormScreen({super.key, this.device});

  @override
  State<DeviceFormScreen> createState() => _DeviceFormScreenState();
}

class _DeviceFormScreenState extends State<DeviceFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.device?.name);
  late final _host = TextEditingController(text: widget.device?.host);
  late final _port = TextEditingController(text: '${widget.device?.port ?? 41100}');
  late final _mac = TextEditingController(text: widget.device?.mac);
  late final _broadcast = TextEditingController(text: widget.device?.broadcast ?? '255.255.255.255');
  // Credencial vem só do QR (pin do certificado + credencial deste celular).
  late String _pin = widget.device?.pin ?? '';
  late String _deviceId = widget.device?.deviceId ?? '';
  late String _deviceToken = widget.device?.token ?? '';
  List<DiscoveredPc>? _found;
  bool _searching = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    if (widget.device == null) _search();
  }

  Future<void> _search() async {
    setState(() => _searching = true);
    final found = await discover();
    if (mounted) {
      setState(() {
        _found = found;
        _searching = false;
      });
    }
  }

  void _pick(DiscoveredPc pc) {
    _name.text = pc.name;
    _host.text = pc.host;
    _port.text = '${pc.port}';
    if (pc.mac.isNotEmpty) _mac.text = pc.mac;
    // Broadcast da sub-rede /24, que é o caso típico de rede doméstica.
    final parts = pc.host.split('.');
    if (parts.length == 4) _broadcast.text = '${parts.take(3).join('.')}.255';
  }

  static Future<String> _phoneName() async {
    try {
      if (Platform.isAndroid) {
        final a = await DeviceInfoPlugin().androidInfo;
        return '${a.manufacturer} ${a.model}';
      }
    } catch (_) {}
    return 'celular';
  }

  Future<void> _scan() async {
    final link = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (link == null || !mounted) return;
    final q = Uri.parse(link).queryParameters;
    final code = q['code'] ?? '', pin = q['fp'] ?? '';
    if (code.isEmpty || pin.length != 64) {
      _snack('QR de uma versão antiga do agente: atualize o agente no PC');
      return;
    }
    setState(() => _testing = true);
    try {
      final cred = await AgentClient.claimPairing(
        host: q['host'] ?? _host.text,
        port: int.tryParse(q['port'] ?? '') ?? 41100,
        code: code,
        pin: pin,
        deviceName: await _phoneName(),
      );
      _pin = pin;
      _deviceId = cred.deviceId;
      _deviceToken = cred.token;
    } on AgentException catch (e) {
      _snack(e.message);
      return;
    } finally {
      if (mounted) setState(() => _testing = false);
    }
    if (!mounted) return;
    _name.text = q['name'] ?? _name.text;
    _host.text = q['host'] ?? _host.text;
    _port.text = q['port'] ?? _port.text;
    if ((q['mac'] ?? '').isNotEmpty) _mac.text = q['mac']!;
    if ((q['broadcast'] ?? '').isNotEmpty) _broadcast.text = q['broadcast']!;
    await _submit();
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Device _build() => Device(
    id: widget.device?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
    name: _name.text.trim(),
    host: _host.text.trim(),
    port: int.parse(_port.text.trim()),
    mac: _mac.text.trim(),
    broadcast: _broadcast.text.trim(),
    pin: _pin,
    deviceId: _deviceId,
    token: _deviceToken,
  );

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final device = _build();
    if (!device.paired) {
      // Sem QR: cadastro só para ligar pela rede, que precisa do MAC.
      if (device.mac.isEmpty) {
        _snack('Sem parear pelo QR, informe o MAC para pelo menos poder ligar o PC');
        return;
      }
      Navigator.pop(context, device);
      return;
    }
    setState(() => _testing = true);
    final client = AgentClient(device);
    String? error;
    var mac = device.mac;
    try {
      final info = await client.info();
      if (mac.isEmpty) mac = info.mac;
    } on AgentException catch (e) {
      error = e.message;
    } finally {
      client.close();
    }
    if (!mounted) return;
    setState(() => _testing = false);
    if (error != null) {
      final saveAnyway = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Não consegui falar com o PC'),
          content: Text('$error\n\nSalvar mesmo assim? (normal se o PC estiver desligado)'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Corrigir')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
          ],
        ),
      );
      if (saveAnyway != true || !mounted) return;
    }
    Navigator.pop(context, device.copyWith(mac: mac));
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Obrigatório' : null;

  @override
  Widget build(BuildContext context) {
    final editing = widget.device != null;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    const gap = SizedBox(height: 12);
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Editar PC' : 'Adicionar PC'),
        actions: [
          if (editing)
            IconButton(
              tooltip: 'Remover',
              icon: Icon(Symbols.delete_rounded, color: scheme.error),
              onPressed: () => Navigator.pop(context, DeviceFormScreen.deleted),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _scanCard(scheme, text),
            if (!editing) ...[
              SectionLabel(
                'Na rede',
                action: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 3)),
                      )
                    : IconButton(
                        tooltip: 'Procurar de novo',
                        onPressed: _search,
                        icon: const Icon(Symbols.wifi_find_rounded),
                      ),
              ),
              _found == null || (_found!.isEmpty && _searching)
                  ? const SizedBox(height: 8)
                  : _found!.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'Nenhum agente encontrado. Confira se o PC está ligado e na mesma rede.',
                        style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : ExpressiveGroup(
                      children: [
                        for (final pc in _found!)
                          GroupTile(
                            icon: osIcon(pc.os),
                            title: pc.name,
                            subtitle: pc.host,
                            trailing: const Icon(Symbols.keyboard_arrow_right_rounded),
                            onTap: () => _pick(pc),
                          ),
                      ],
                    ),
            ],
            SectionLabel(editing ? 'Dados' : 'Manual (só para ligar)'),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nome', prefixIcon: Icon(Symbols.label_rounded)),
              validator: _required,
            ),
            gap,
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _host,
                    decoration: const InputDecoration(labelText: 'IP do PC', hintText: '192.168.0.10'),
                    validator: _required,
                    keyboardType: TextInputType.url,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _port,
                    decoration: const InputDecoration(labelText: 'Porta'),
                    keyboardType: TextInputType.number,
                    validator: (v) => int.tryParse(v ?? '') == null ? 'Inválida' : null,
                  ),
                ),
              ],
            ),
            gap,
            if (_pin.isNotEmpty) ...[
              // Para conferir com `velksync-agent fingerprint` no PC.
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: Icon(Symbols.verified_user_rounded, color: scheme.primary),
                title: const Text('Pareado com certificado'),
                subtitle: Text(_build().shortPin, style: monoStyle(color: scheme.onSurfaceVariant)),
              ),
              gap,
            ],
            TextFormField(
              controller: _mac,
              decoration: const InputDecoration(
                labelText: 'MAC (para ligar)',
                prefixIcon: Icon(Symbols.router_rounded),
                helperText: 'Preenchido sozinho quando o PC responde',
              ),
              validator: (v) {
                final hex = (v ?? '').replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
                return v!.trim().isEmpty || hex.length == 12 ? null : 'MAC inválido';
              },
            ),
            gap,
            TextFormField(
              controller: _broadcast,
              decoration: const InputDecoration(labelText: 'Endereço de broadcast'),
              validator: _required,
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _testing ? null : _submit,
              icon: _testing
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 3))
                  : const Icon(Symbols.check_rounded, weight: 600),
              label: Text(_testing ? 'Testando conexão…' : 'Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scanCard(ColorScheme scheme, TextTheme text) {
    return Material(
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(Radii.xlPlus),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _testing ? null : _scan,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(Radii.lgPlus)),
                child: Icon(Symbols.qr_code_scanner_rounded, size: 32, color: scheme.onPrimary),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Escanear QR do PC',
                      style: text.titleLarge?.copyWith(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Rode "velksync-agent pair" no PC',
                      style: text.bodyMedium?.copyWith(color: scheme.onPrimaryContainer.withValues(alpha: 0.8)),
                    ),
                  ],
                ),
              ),
              Icon(Symbols.keyboard_arrow_right_rounded, color: scheme.onPrimaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}
