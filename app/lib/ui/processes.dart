import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../services/agent_client.dart';
import 'perf.dart';
import 'role_colors.dart';
import 'theme.dart';
import 'widgets.dart';

enum ProcessSort { cpu, mem }

/// Seção "Processos" da aba Desempenho: os 10 que mais usam CPU ou memória.
/// Só existe com a aba aberta, e só então o PC é consultado (a cada 3 s).
class ProcessesSection extends StatefulWidget {
  final Future<ProcessList> Function() load;
  final Duration every;
  final ProcessSort initialSort;

  /// Com título "Processos" (seção solta) ou só a ordenação (dentro da janela do gráfico).
  final bool showTitle;
  const ProcessesSection({
    super.key,
    required this.load,
    this.every = const Duration(seconds: 3),
    this.initialSort = ProcessSort.cpu,
    this.showTitle = true,
  });

  @override
  State<ProcessesSection> createState() => _ProcessesSectionState();
}

class _ProcessesSectionState extends State<ProcessesSection> {
  ProcessList? _list;
  String? _error;
  late var _sort = widget.initialSort;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(widget.every, (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final l = await widget.load();
      if (mounted) {
        setState(() {
          _list = l;
          _error = null;
        });
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final roles = RoleColors.of(context);
    final list = _list;
    final sortButton = SegmentedButton<ProcessSort>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: const [
        ButtonSegment(value: ProcessSort.cpu, label: Text('CPU')),
        ButtonSegment(value: ProcessSort.mem, label: Text('Memória')),
      ],
      selected: {_sort},
      onSelectionChanged: (s) => setState(() => _sort = s.first),
    );
    final items = list == null ? const <ProcessInfo>[] : (_sort == ProcessSort.cpu ? list.byCpu : list.byMem);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showTitle)
          SectionLabel('Processos', action: sortButton)
        else
          // Na janela do gráfico: o seletor na largura toda (cabe em tela estreita).
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(width: double.infinity, child: sortButton),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: scheme.surfaceContainer, borderRadius: BorderRadius.circular(Radii.xl)),
          child: switch ((list, _error)) {
            (null, null) => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            (null, final e?) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Não deu para ler os processos: $e', style: text.bodyMedium),
            ),
            _ => Column(
              children: [
                for (final p in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: p.name),
                                if (p.count > 1)
                                  TextSpan(
                                    text: '  ×${p.count}',
                                    style: TextStyle(color: scheme.onSurfaceVariant),
                                  ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodyMedium,
                          ),
                        ),
                        SizedBox(
                          width: 56,
                          child: Text(
                            '${p.cpu < 10 ? p.cpu.toStringAsFixed(1) : p.cpu.round()}%',
                            textAlign: TextAlign.end,
                            style: text.bodyMedium?.copyWith(
                              fontFeatures: tabular,
                              color: _sort == ProcessSort.cpu ? roles.cpu : scheme.onSurfaceVariant,
                              fontWeight: _sort == ProcessSort.cpu ? FontWeight.w600 : null,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 76,
                          child: Text(
                            formatBytes(p.mem),
                            textAlign: TextAlign.end,
                            style: text.bodyMedium?.copyWith(
                              fontFeatures: tabular,
                              color: _sort == ProcessSort.mem ? roles.mem : scheme.onSurfaceVariant,
                              fontWeight: _sort == ProcessSort.mem ? FontWeight.w600 : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (list != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 4),
                    child: Text(
                      '${list.total} processos no PC · só leitura',
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          },
        ),
      ],
    );
  }
}
