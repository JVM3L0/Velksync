import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../models/device.dart';
import 'theme.dart';
import 'widgets.dart';

typedef ScheduleChoice = ({String action, Duration? delay, bool whenMediaStops});

String _verb(String action) => action == 'sleep' ? 'Suspende' : 'Desliga';

String _clock(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// "em 12 min", "em 1 h 05".
String _inTime(Duration d) {
  if (d.inMinutes < 1) return 'em menos de 1 min';
  if (d.inHours < 1) return 'em ${d.inMinutes} min';
  return 'em ${d.inHours} h ${(d.inMinutes % 60).toString().padLeft(2, '0')}';
}

String describeSchedule(PowerSchedule s, DateTime now) {
  final at = s.at;
  if (at == null) return '${_verb(s.action)} quando a mídia parar';
  final when = '${_verb(s.action)} às ${_clock(at)} · ${_inTime(at.difference(now))}';
  return s.whenMediaStops ? 'A mídia parou: $when' : when;
}

/// Aviso do agendamento ativo, com Cancelar.
class ScheduleBanner extends StatelessWidget {
  final PowerSchedule schedule;
  final VoidCallback onCancel;
  const ScheduleBanner({super.key, required this.schedule, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(Radii.xl)),
      child: Row(
        children: [
          Icon(Symbols.schedule_rounded, color: scheme.onTertiaryContainer, fill: 1),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              describeSchedule(schedule, DateTime.now()),
              style: text.titleSmall?.copyWith(color: scheme.onTertiaryContainer, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(foregroundColor: scheme.onTertiaryContainer),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }
}

/// Escolha do agendamento: o que fazer e quando.
Future<ScheduleChoice?> showScheduleSheet(BuildContext context) => showModalBottomSheet<ScheduleChoice>(
  context: context,
  // Sem isso o painel para em ~56% da tela e a última opção fica cortada.
  isScrollControlled: true,
  builder: (context) {
    var action = 'shutdown';
    return StatefulBuilder(
      builder: (context, setState) {
        Widget option(IconData icon, String label, {Duration? delay, bool media = false}) => GroupTile(
          icon: icon,
          title: label,
          onTap: () => Navigator.pop(context, (action: action, delay: delay, whenMediaStops: media)),
        );
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'shutdown', label: Text('Desligar'), icon: Icon(Symbols.power_off_rounded)),
                    ButtonSegment(value: 'sleep', label: Text('Suspender'), icon: Icon(Symbols.bedtime_rounded)),
                  ],
                  selected: {action},
                  onSelectionChanged: (s) => setState(() => action = s.first),
                ),
                const SizedBox(height: 16),
                ExpressiveGroup(
                  children: [
                    option(Symbols.timer_rounded, 'Em 15 minutos', delay: const Duration(minutes: 15)),
                    option(Symbols.timer_rounded, 'Em 30 minutos', delay: const Duration(minutes: 30)),
                    option(Symbols.timer_rounded, 'Em 1 hora', delay: const Duration(hours: 1)),
                    option(Symbols.timer_rounded, 'Em 2 horas', delay: const Duration(hours: 2)),
                    option(Symbols.music_off_rounded, 'Quando a mídia parar', media: true),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  },
);
