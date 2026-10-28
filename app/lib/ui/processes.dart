import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../services/agent_client.dart';
import 'perf.dart';
import 'role_colors.dart';
import 'theme.dart';
import 'widgets.dart';

enum ProcessSort {
  cpu('CPU'),
  gpu('GPU'),
  vram('VRAM'),
  mem('Memória');

  final String label;
  const ProcessSort(this.label);
}

/// Os 10 programas que mais usam CPU, GPU, VRAM ou memória, com os filtros
/// embaixo (como os do gráfico). Só consulta o PC enquanto está à mostra,
/// a cada [every].
class ProcessesSection extends StatefulWidget {
  final Future<ProcessList> Function() load;
  final Duration every;
  final ProcessSort initialSort;

  /// Com o título "Processos" (seção solta) ou sem (dentro da janela do gráfico).
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

  static List<ProcessSort> _available(ProcessList l) => [
    ProcessSort.cpu,
    if (l.byGpu != null) ProcessSort.gpu,
    if (l.byVram != null) ProcessSort.vram,
    ProcessSort.mem,
  ];

  static List<ProcessInfo> _items(ProcessList l, ProcessSort s) => switch (s) {
    ProcessSort.cpu => l.byCpu,
    ProcessSort.gpu => l.byGpu ?? l.byCpu,
    ProcessSort.vram => l.byVram ?? l.byMem,
    ProcessSort.mem => l.byMem,
  };

  static String _pct(double v) => '${v < 10 ? v.toStringAsFixed(1) : v.round()}%';

  /// Abaixo de 1 GB em MB: um programa costuma usar centenas de MB.
  static String _size(int bytes) => bytes >= 1 << 30 ? formatBytes(bytes) : '${(bytes / (1 << 20)).round()} MB';

  /// O valor do filtro (em destaque) e um vizinho de contexto: CPU com
  /// memória, GPU com VRAM.
  static (String, String) _values(ProcessInfo p, ProcessSort s) => switch (s) {
    ProcessSort.cpu => (_pct(p.cpu), _size(p.mem)),
    ProcessSort.mem => (_size(p.mem), _pct(p.cpu)),
    ProcessSort.gpu => (_pct(p.gpu), _size(p.vram)),
    ProcessSort.vram => (_size(p.vram), _pct(p.gpu)),
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final roles = RoleColors.of(context);
    final list = _list;
    final sorts = list == null ? const <ProcessSort>[] : _available(list);
    // Filtro escolhido que este PC não informa (ex.: GPU no Linux): volta à CPU.
    final sort = sorts.contains(_sort) ? _sort : ProcessSort.cpu;
    final accent = switch (sort) {
      ProcessSort.cpu => roles.cpu,
      ProcessSort.gpu || ProcessSort.vram => roles.gpu,
      ProcessSort.mem => roles.mem,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showTitle) const SectionLabel('Processos'),
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
            (final l?, _) => Column(
              children: [
                for (final p in _items(l, sort))
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
                          width: 76,
                          child: Text(
                            _values(p, sort).$1,
                            textAlign: TextAlign.end,
                            style: text.bodyMedium?.copyWith(
                              fontFeatures: tabular,
                              color: accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 76,
                          child: Text(
                            _values(p, sort).$2,
                            textAlign: TextAlign.end,
                            style: text.bodyMedium?.copyWith(fontFeatures: tabular, color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                    '${l.total} processos no PC · só leitura',
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          },
        ),
        if (sorts.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final s in sorts)
                ChoiceChip(label: Text(s.label), selected: s == sort, onSelected: (_) => setState(() => _sort = s)),
            ],
          ),
        ],
      ],
    );
  }
}
