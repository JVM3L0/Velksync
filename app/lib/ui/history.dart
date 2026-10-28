import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../services/agent_client.dart';
import 'theme.dart';
import 'widgets.dart';

IconData historyIcon(String kind) => switch (kind) {
  'power' => Symbols.power_settings_new_rounded,
  'schedule' => Symbols.schedule_rounded,
  'command' => Symbols.play_arrow_rounded,
  'shell' => Symbols.terminal_rounded,
  'pair' => Symbols.qr_code_rounded,
  'revoke' => Symbols.block_rounded,
  'update' => Symbols.system_update_rounded,
  'send' => Symbols.phone_android_rounded,
  'receive' => Symbols.computer_rounded,
  _ => Symbols.history_rounded,
};

/// "agora", "há 5 min", "23:10", "ontem 21:05", "25/10 18:00".
String historyWhen(DateTime at, DateTime now) {
  final d = now.difference(at);
  String hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  if (d.inMinutes < 1) return 'agora';
  if (d.inMinutes < 60) return 'há ${d.inMinutes} min';
  final today = DateTime(now.year, now.month, now.day);
  if (!at.isBefore(today)) return hm(at);
  if (!at.isBefore(today.subtract(const Duration(days: 1)))) return 'ontem ${hm(at)}';
  return '${at.day.toString().padLeft(2, '0')}/${at.month.toString().padLeft(2, '0')} ${hm(at)}';
}

class HistoryTile extends StatelessWidget {
  final HistoryEntry entry;
  final DateTime now;
  const HistoryTile({super.key, required this.entry, required this.now});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(historyIcon(entry.kind), size: 20, color: entry.failed ? scheme.error : scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: entry.device,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: ' ${entry.text}${entry.failed ? ' (falhou)' : ''}'),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.bodyMedium,
            ),
          ),
          const SizedBox(width: 8),
          Text(historyWhen(entry.at, now), style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// Cartão "Atividade recente" da aba Controle: as 3 últimas e "Ver tudo".
class RecentActivity extends StatelessWidget {
  final List<HistoryEntry> entries;
  const RecentActivity({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          'Atividade recente',
          action: entries.length > 3
              ? TextButton(onPressed: () => showHistorySheet(context, entries), child: const Text('Ver tudo'))
              : null,
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(color: scheme.surfaceContainer, borderRadius: BorderRadius.circular(Radii.xl)),
          child: entries.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'Nada por enquanto.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                )
              : Column(
                  children: [for (final e in entries.take(3)) HistoryTile(entry: e, now: now)],
                ),
        ),
      ],
    );
  }
}

Future<void> showHistorySheet(BuildContext context, List<HistoryEntry> entries) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) {
    final now = DateTime.now();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        children: [
          Text('Histórico', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          for (final e in entries) HistoryTile(entry: e, now: now),
        ],
      ),
    );
  },
);
