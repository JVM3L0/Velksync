import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/device.dart';
import 'agent_client.dart';

/// Keeps an event stream open to every saved PC while the app is running and
/// carries out what the PC asks for (PC -> celular).
class PcEventListener {
  final GlobalKey<ScaffoldMessengerState> messenger;
  final Map<String, StreamSubscription<PcEvent>> _subs = {};
  final Map<String, Timer> _retries = {};
  Map<String, Device> _devices = {};

  PcEventListener(this.messenger);

  void update(List<Device> devices) {
    // Só PCs pareados: sem credencial e pin não há com quem falar.
    final next = {for (final d in devices.where((d) => d.paired)) d.id: d};
    for (final id in _devices.keys.toList()) {
      final old = _devices[id]!, now = next[id];
      if (now == null || now.host != old.host || now.port != old.port || now.token != old.token || now.pin != old.pin) {
        _stop(id);
      }
    }
    _devices = next;
    for (final d in next.values) {
      if (!_subs.containsKey(d.id) && !_retries.containsKey(d.id)) _connect(d);
    }
  }

  void _connect(Device d) {
    _retries.remove(d.id);
    _subs[d.id] = AgentClient(d).events().listen(
      (e) => _handle(d, e),
      onError: (_) {},
      onDone: () {
        _subs.remove(d.id);
        if (_devices.containsKey(d.id)) {
          _retries[d.id] = Timer(const Duration(seconds: 5), () => _connect(_devices[d.id] ?? d));
        }
      },
      cancelOnError: false,
    );
  }

  void _stop(String id) {
    _subs.remove(id)?.cancel();
    _retries.remove(id)?.cancel();
  }

  void dispose() {
    for (final id in {..._subs.keys, ..._retries.keys}) {
      _stop(id);
    }
    _devices = {};
  }

  Future<void> _handle(Device d, PcEvent e) async {
    void show(String msg) => messenger.currentState?.showSnackBar(SnackBar(content: Text('${d.name}: $msg')));
    switch (e.type) {
      case 'notify':
        HapticFeedback.mediumImpact();
        show(e.text);
      case 'vibrate':
        HapticFeedback.vibrate();
        if (e.text.isNotEmpty) show(e.text);
      case 'clipboard':
        await Clipboard.setData(ClipboardData(text: e.text));
        show('texto copiado para a área de transferência');
      case 'open_url':
        final uri = Uri.tryParse(e.url);
        if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
          show('URL recusada: ${e.url}');
        } else if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          show('não consegui abrir ${e.url}');
        }
    }
  }
}
