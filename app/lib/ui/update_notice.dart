import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/versions.dart';
import 'theme.dart';

/// Aviso na aba Controle quando app e agente estão em versões diferentes.
class UpdateBanner extends StatelessWidget {
  final VersionGap gap;
  final String agentVersion;
  final String appVersion;
  final VoidCallback onDismiss;
  final VoidCallback onHowTo;

  const UpdateBanner({
    super.key,
    required this.gap,
    required this.agentVersion,
    required this.appVersion,
    required this.onDismiss,
    required this.onHowTo,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final fg = scheme.onTertiaryContainer;
    final agent = agentVersion.isEmpty ? 'versão antiga' : agentVersion;
    final (title, body) = switch (gap) {
      VersionGap.appOld => (
        'App desatualizado ($appVersion)',
        'O agente do PC está na $agent. Atualize o app para ter tudo funcionando.',
      ),
      _ => ('Agente desatualizado ($agent)', 'O app está na $appVersion. Atualize o agente para ter tudo funcionando.'),
    };
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(Radii.xl)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Symbols.upgrade_rounded, color: fg, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.titleMedium?.copyWith(color: fg, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(body, style: text.bodyMedium?.copyWith(color: fg)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              TextButton(
                onPressed: onDismiss,
                style: TextButton.styleFrom(foregroundColor: fg),
                child: const Text('Agora não'),
              ),
              FilledButton.tonal(onPressed: onHowTo, child: const Text('Como atualizar')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Passo a passo para atualizar o lado que está atrás, no sistema do PC.
Future<void> showUpdateSheet(BuildContext context, {required VersionGap gap, required String os}) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => UpdateSheet(gap: gap, os: os),
    );

class UpdateSheet extends StatelessWidget {
  final VersionGap gap;
  final String os;
  const UpdateSheet({super.key, required this.gap, required this.os});

  List<(String, String?)> get _steps => switch ((gap, os)) {
    (VersionGap.appOld, _) => [
      ('Na página de versões, baixe o velksync-…-arm64.apk (aparelhos antigos: -armv7.apk).', null),
      ('Abra o arquivo e confirme a instalação por cima do app atual. Os PCs pareados continuam.', null),
    ],
    (_, 'linux') => [
      ('Na página de versões, baixe o velksync-agent-…-linux-amd64.tar.gz e o SHA256SUMS.', null),
      (
        'Confira o arquivo e extraia:',
        'sha256sum -c --ignore-missing SHA256SUMS\nmkdir velksync && tar -xzf velksync-agent-*-linux-amd64.tar.gz -C velksync',
      ),
      ('Rode o instalador (pede sudo para o sinal de presença):', 'cd velksync && ./install-linux.sh'),
    ],
    _ => [
      ('Na página de versões, baixe o velksync-agent-…-windows-amd64.zip e o SHA256SUMS.', null),
      (
        'No PowerShell, confira se os dois códigos batem:',
        r'(Get-FileHash .\velksync-agent-*-windows-amd64.zip).Hash.ToLower()'
            '\n'
            r'Select-String "windows-amd64.zip" .\SHA256SUMS',
      ),
      (
        'Extraia e, no PowerShell como administrador, rode o instalador. A configuração e os celulares pareados continuam.',
        r'Expand-Archive .\velksync-agent-*-windows-amd64.zip .\velksync -Force'
            '\n'
            r'cd .\velksync; Unblock-File .\*'
            '\n'
            r'powershell -ExecutionPolicy Bypass -File .\install-windows.ps1',
      ),
    ],
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final title = gap == VersionGap.appOld
        ? 'Atualizar o app'
        : 'Atualizar o agente no ${os == 'linux' ? 'Linux' : 'Windows'}';
    final steps = _steps;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          for (var i = 0; i < steps.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: scheme.secondaryContainer,
                  child: Text('${i + 1}', style: text.labelMedium?.copyWith(color: scheme.onSecondaryContainer)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(steps[i].$1, style: text.bodyMedium)),
              ],
            ),
            if (steps[i].$2 case final code?) _Code(code),
            const SizedBox(height: 16),
          ],
          FilledButton.icon(
            onPressed: () => launchUrl(Uri.parse(releasesUrl), mode: LaunchMode.externalApplication),
            icon: const Icon(Symbols.open_in_new_rounded),
            label: const Text('Abrir a página de versões'),
          ),
        ],
      ),
    );
  }
}

/// Comando para copiar (o celular não roda nada no PC daqui).
class _Code extends StatelessWidget {
  final String code;
  const _Code(this.code);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(left: 36, top: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(Radii.md)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(
              code,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ),
          IconButton(
            tooltip: 'Copiar',
            icon: const Icon(Symbols.content_copy_rounded, size: 20),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Copiado')));
            },
          ),
        ],
      ),
    );
  }
}
