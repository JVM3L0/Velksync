import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'widgets.dart';

/// Tempo decorrido como "0:23".
String formatElapsed(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// Causas mais comuns de o Wake-on-LAN não funcionar, na ordem em que vale
/// a pena conferir.
Future<void> showWakeHelp(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    Widget tip(IconData icon, String title, String body) => GroupTile(icon: icon, title: title, subtitle: body);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: Text('O PC não respondeu', style: text.headlineSmall),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
              child: Text(
                'O sinal foi enviado, mas o PC não deu notícia em 2 minutos. Confira:',
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            ExpressiveGroup(
              children: [
                tip(
                  Symbols.bolt_rounded,
                  'Inicialização rápida do Windows',
                  'Desative em Painel de Controle → Opções de Energia → Escolher a função dos botões. '
                      'Com ela, o Windows "desliga" hibernando e a placa ignora o sinal.',
                ),
                tip(
                  Symbols.memory_rounded,
                  'BIOS',
                  'ErP Ready desativado e "Power On By PCI-E" ativado (Asus: Advanced → APM Configuration).',
                ),
                tip(
                  Symbols.cable_rounded,
                  'Cabo de rede',
                  'O Wake-on-LAN quase sempre exige cabo; pelo Wi-Fi a placa não escuta desligada.',
                ),
                tip(
                  Symbols.power_rounded,
                  'Faltou energia?',
                  'Depois de uma queda, muitas placas só voltam a aceitar o sinal após ligar uma vez pelo botão.',
                ),
                tip(
                  Symbols.lan_rounded,
                  'Mesma rede',
                  'O celular precisa estar no Wi-Fi de casa, não na rede de convidados nem nos dados móveis.',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  },
);
