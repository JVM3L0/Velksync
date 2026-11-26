import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_update.dart';
import '../services/versions.dart';
import 'theme.dart';

/// Aviso na aba Controle quando app e agente estão em versões diferentes.
class UpdateBanner extends StatelessWidget {
  final VersionGap gap;
  final String agentVersion;
  final String appVersion;
  final VoidCallback onDismiss;
  final VoidCallback? onHowTo;

  /// Versão nova que o próprio agente achou (com app e agente em dia entre si).
  final String? available;
  final String os;

  const UpdateBanner({
    super.key,
    required this.gap,
    required this.agentVersion,
    required this.appVersion,
    required this.onDismiss,
    required this.onHowTo,
    this.available,
    this.os = '',
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final fg = scheme.onTertiaryContainer;
    final agent = agentVersion.isEmpty ? 'versão antiga' : agentVersion;
    final (title, body) = switch (gap) {
      _ when available != null => (
        'Agente $available disponível no PC',
        os == 'windows'
            ? 'Atualize pelo ícone do Velksync no PC, perto do relógio: Atualizar para $available.'
            : os == 'linux' && agentUpdatesItself(agentVersion)
            ? 'Atualize pelo ícone do Velksync na bandeja do PC: Atualizar para $available.'
            : 'O PC está na $agent. Atualize o agente para ter as novidades.',
      ),
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
          // Largura toda: sem ela o Wrap encolhe e os botões ficam à esquerda.
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              TextButton(
                onPressed: onDismiss,
                style: TextButton.styleFrom(foregroundColor: fg),
                child: const Text('Agora não'),
              ),
              if (onHowTo != null) FilledButton.tonal(onPressed: onHowTo, child: const Text('Como atualizar')),
            ],
          ),
        ],
      ),
    );
  }
}

/// No Linux, só os agentes depois da 0.9.1 se instalam pelo menu do ícone.
bool agentUpdatesItself(String agentVersion) => isNewerVersion(agentVersion, '0.9.1');

/// Passo a passo para atualizar o lado que está atrás, no sistema do PC.
Future<void> showUpdateSheet(
  BuildContext context, {
  required VersionGap gap,
  required String os,
  String agentVersion = '',
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => UpdateSheet(gap: gap, os: os, agentVersion: agentVersion),
);

class UpdateSheet extends StatelessWidget {
  final VersionGap gap;
  final String os;
  final String agentVersion;
  const UpdateSheet({super.key, required this.gap, required this.os, this.agentVersion = ''});

  static const _linuxByHand = <(String, String?)>[
    ('Na página de versões, baixe o velksync-agent-…-linux-amd64.tar.gz e o SHA256SUMS.', null),
    (
      'Confira o arquivo e extraia:',
      'sha256sum -c --ignore-missing SHA256SUMS\nmkdir velksync && tar -xzf velksync-agent-*-linux-amd64.tar.gz -C velksync',
    ),
    ('Rode o instalador (pede sudo para o sinal de presença):', 'cd velksync && ./install-linux.sh'),
  ];

  /// Reserva para quando o menu do ícone não serve (sem bandeja, por exemplo).
  List<(String, String?)> get _fallback =>
      gap != VersionGap.appOld && os == 'linux' && agentUpdatesItself(agentVersion) ? _linuxByHand : const [];

  List<(String, String?)> get _steps => switch ((gap, os)) {
    (VersionGap.appOld, _) => [
      ('Na página de versões, baixe o velksync-…-arm64.apk (aparelhos antigos: -armv7.apk).', null),
      ('Abra o arquivo e confirme a instalação por cima do app atual. Os PCs pareados continuam.', null),
    ],
    (_, 'linux') when agentUpdatesItself(agentVersion) => [
      ('No PC, abra o ícone do Velksync na bandeja e toque em Procurar atualizações agora.', null),
      ('Escolha Atualizar para… no mesmo menu e confirme na notificação.', null),
      ('Se o sistema pedir sua senha, é para atualizar o sinal de presença.', null),
    ],
    (_, 'linux') => _linuxByHand,
    _ => [
      ('Na página de versões, baixe o velksync-setup-…-windows-amd64.exe e o SHA256SUMS.', null),
      (
        'No PowerShell, confira se os dois códigos batem:',
        r'(Get-FileHash .\velksync-setup-*.exe).Hash.ToLower()'
            '\n'
            r'Select-String "velksync-setup" .\SHA256SUMS',
      ),
      (
        'Abra o instalador e siga as telas. A configuração e os celulares pareados continuam. '
            'Se o Windows avisar que o app não é reconhecido: Mais informações → Executar assim mesmo.',
        null,
      ),
    ],
  };

  List<Widget> _numbered(BuildContext context, List<(String, String?)> list) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return [
      for (var i = 0; i < list.length; i++) ...[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 12,
              backgroundColor: scheme.secondaryContainer,
              child: Text('${i + 1}', style: text.labelMedium?.copyWith(color: scheme.onSecondaryContainer)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(list[i].$1, style: text.bodyMedium)),
          ],
        ),
        if (list[i].$2 case final code?) _Code(code),
        const SizedBox(height: 16),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
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
          ..._numbered(context, steps),
          if (_fallback.isNotEmpty) ...[
            Text('Sem o ícone na bandeja? Instale à mão:', style: text.titleSmall),
            const SizedBox(height: 12),
            ..._numbered(context, _fallback),
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

/// Versão nova do app: no topo da lista de PCs. Baixando, mostra o progresso.
class AppUpdateCard extends StatelessWidget {
  final AppRelease release;

  /// 0 a 1 enquanto baixa; null parado.
  final double? progress;
  final String? error;

  /// Entregue ao Android, que encerra o app ao terminar.
  final bool installing;
  final VoidCallback onDismiss;
  final VoidCallback onUpdate;

  const AppUpdateCard({
    super.key,
    required this.release,
    required this.onDismiss,
    required this.onUpdate,
    this.progress,
    this.error,
    this.installing = false,
  });

  /// As primeiras novidades do CHANGELOG, sem os títulos das seções.
  static String highlights(String notes) {
    final items = [
      for (final line in const LineSplitter().convert(notes))
        if (line.trimLeft().startsWith('- ')) line.trimLeft().substring(2).trim(),
    ];
    return items.take(2).join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final fg = scheme.onPrimaryContainer;
    final p = progress;
    final news = highlights(release.notes);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(Radii.xl)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Symbols.system_update_rounded, color: fg, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      installing ? 'Velksync ${release.version}' : 'Velksync ${release.version} disponível',
                      style: text.titleMedium?.copyWith(color: fg, fontWeight: FontWeight.w600),
                    ),
                    if (news.isNotEmpty && !installing) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Novidades: $news',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium?.copyWith(color: fg),
                      ),
                    ],
                    if (error case final e?) ...[
                      const SizedBox(height: 4),
                      Text(e, style: text.bodyMedium?.copyWith(color: scheme.error)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (p != null || installing)
            Padding(
              padding: const EdgeInsets.fromLTRB(36, 4, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(value: installing ? null : p),
                  const SizedBox(height: 6),
                  Text(
                    installing ? 'Instalando… o app vai fechar' : 'Baixando… ${(p! * 100).round()}%',
                    style: text.bodySmall?.copyWith(color: fg),
                  ),
                ],
              ),
            )
          else
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: onDismiss,
                  style: TextButton.styleFrom(foregroundColor: fg),
                  child: const Text('Agora não'),
                ),
                FilledButton(onPressed: onUpdate, child: Text(error == null ? 'Atualizar' : 'Tentar de novo')),
              ],
            ),
        ],
      ),
    );
  }
}
