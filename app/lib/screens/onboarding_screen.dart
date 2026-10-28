import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/device.dart';
import '../services/versions.dart';
import '../services/wake_tracker.dart';
import '../ui/theme.dart';
import '../ui/wake_help.dart';

/// Primeira vez: o que é, instalar o agente, parear e testar o "Ligar".
/// Aparece só sem PC cadastrado; dá para pular em qualquer passo.
class OnboardingScreen extends StatefulWidget {
  /// Abre o cadastro (QR ou busca na rede) e devolve o PC salvo, ou null.
  final Future<Device?> Function() addPc;
  final WakeTracker wakes;
  const OnboardingScreen({super.key, required this.addPc, required this.wakes});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _Test { idle, waking, ok, failed }

class _OnboardingScreenState extends State<OnboardingScreen> {
  var _step = 0;
  Device? _pc;
  var _test = _Test.idle;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.wakes.addListener(_onWake);
  }

  @override
  void dispose() {
    widget.wakes.removeListener(_onWake);
    super.dispose();
  }

  void _onWake() {
    final pc = _pc;
    if (pc == null || _test != _Test.waking) return;
    final phase = widget.wakes.of(pc.id)?.phase;
    if (phase == WakePhase.online || phase == WakePhase.awaitingLogin) {
      setState(() => _test = _Test.ok);
    } else if (phase == WakePhase.failed) {
      setState(() => _test = _Test.failed);
    }
  }

  void _done() => Navigator.pop(context);

  Future<void> _add() async {
    final d = await widget.addPc();
    if (d != null && mounted) {
      setState(() {
        _pc = d;
        _step = 3;
      });
    }
  }

  Future<void> _wake() async {
    final pc = _pc;
    if (pc == null) return;
    setState(() {
      _test = _Test.waking;
      _error = null;
    });
    try {
      await widget.wakes.start(pc);
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _test = _Test.failed;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final page = switch (_step) {
      0 => _Page(
        icon: Symbols.devices_rounded,
        title: 'Bem-vindo ao Velksync',
        body:
            'Ligue, desligue e acompanhe o seu PC pelo celular, na rede de casa.\n\n'
            'Ele precisa de um programa pequeno no PC, o agente. Leva uns 2 minutos.',
        actions: [FilledButton(onPressed: () => setState(() => _step = 1), child: const Text('Começar'))],
      ),
      1 => _Page(
        icon: Symbols.download_rounded,
        title: 'Instale o agente no PC',
        body:
            'No Windows: abra a página de versões no PC, baixe o velksync-setup e siga as telas. '
            'Ele já confere o Wake-on-LAN.\n\n'
            'No Linux: siga o guia do README na mesma página.',
        extra: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Symbols.content_copy_rounded),
              label: const Text('Copiar o link'),
              onPressed: () async {
                await Clipboard.setData(const ClipboardData(text: releasesUrl));
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Link copiado: mande para o PC ou digite lá')));
                }
              },
            ),
            OutlinedButton.icon(
              icon: const Icon(Symbols.open_in_new_rounded),
              label: const Text('Abrir aqui'),
              onPressed: () => launchUrl(Uri.parse(releasesUrl), mode: LaunchMode.externalApplication),
            ),
          ],
        ),
        actions: [FilledButton(onPressed: () => setState(() => _step = 2), child: const Text('Já instalei'))],
      ),
      2 => _Page(
        icon: Symbols.qr_code_scanner_rounded,
        title: 'Pareie o celular',
        body:
            'No PC, clique no ícone do Velksync perto do relógio e escolha "Parear um celular…". '
            'Depois toque abaixo e escaneie o QR (ou procure o PC na rede).',
        actions: [
          FilledButton.icon(onPressed: _add, icon: const Icon(Symbols.add_rounded), label: const Text('Adicionar PC')),
        ],
      ),
      _ => _Page(
        icon: switch (_test) {
          _Test.ok => Symbols.check_circle_rounded,
          _Test.failed => Symbols.error_rounded,
          _ => Symbols.power_settings_new_rounded,
        },
        title: switch (_test) {
          _Test.ok => 'Funcionou!',
          _Test.failed => 'O PC não ligou',
          _Test.waking => 'Ligando ${_pc?.name ?? 'o PC'}…',
          _Test.idle => 'Teste: ligar pelo celular',
        },
        body: switch (_test) {
          _Test.ok => 'O ${_pc?.name ?? 'PC'} ligou pelo celular. Está tudo pronto.',
          _Test.failed =>
            '${_error ?? 'O sinal saiu, mas o PC não respondeu.'}\n\n'
                'Quase sempre é a BIOS, o cabo de rede ou a Inicialização Rápida do Windows.',
          _Test.waking => 'Mandando o sinal e esperando o PC responder. Isso pode levar até 2 minutos.',
          _Test.idle => 'Desligue o PC (pelo menu Iniciar) e toque em Ligar. Se ele já estiver desligado, é só tocar.',
        },
        extra: _test == _Test.waking ? const LinearProgressIndicator() : null,
        actions: [
          if (_test == _Test.failed)
            OutlinedButton(onPressed: () => showWakeHelp(context), child: const Text('Ver dicas')),
          switch (_test) {
            _Test.ok => FilledButton(onPressed: _done, child: const Text('Concluir')),
            _Test.waking => const SizedBox.shrink(),
            _Test.failed => FilledButton(onPressed: _wake, child: const Text('Tentar de novo')),
            _Test.idle => FilledButton.icon(
              onPressed: _pc?.mac.isNotEmpty ?? false ? _wake : null,
              icon: const Icon(Symbols.power_settings_new_rounded),
              label: const Text('Ligar'),
            ),
          },
        ],
      ),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text('${_step + 1} de 4', style: text.titleMedium?.copyWith(color: scheme.onSurfaceVariant)),
        automaticallyImplyLeading: false,
        actions: [
          if (_test != _Test.ok) TextButton(onPressed: _done, child: Text(_step == 3 ? 'Pular o teste' : 'Pular')),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: Motion.spatialDuration,
          switchInCurve: Motion.effects,
          child: KeyedSubtree(key: ValueKey('$_step-$_test'), child: page),
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  final IconData icon;
  final String title, body;
  final Widget? extra;
  final List<Widget> actions;
  const _Page({required this.icon, required this.title, required this.body, this.extra, required this.actions});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(Radii.xxl)),
            child: Icon(icon, size: 44, fill: 1, color: scheme.onPrimaryContainer),
          ),
        ),
        const SizedBox(height: 28),
        Text(title, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Text(body, style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
        if (extra case final e?) ...[const SizedBox(height: 20), e],
        const SizedBox(height: 28),
        Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: actions),
      ],
    );
  }
}
