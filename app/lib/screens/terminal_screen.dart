import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../models/device.dart';
import '../services/agent_client.dart';
import '../ui/theme.dart';

class _Entry {
  final String command;
  RunResult? result;
  String? error;
  _Entry(this.command);
}

/// Free-form commands, only offered when the agent has allow_shell enabled.
class TerminalScreen extends StatefulWidget {
  final Device device;
  const TerminalScreen({super.key, required this.device});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  late final _client = AgentClient(widget.device);
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _entries = <_Entry>[];
  bool _busy = false;

  @override
  void dispose() {
    _client.close();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final cmd = _input.text.trim();
    if (cmd.isEmpty || _busy) return;
    final entry = _Entry(cmd);
    setState(() {
      _entries.add(entry);
      _busy = true;
      _input.clear();
    });
    try {
      entry.result = await _client.shell(cmd);
    } on AgentException catch (e) {
      entry.error = e.message;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final mono = monoStyle(color: scheme.onSurface);
    return Scaffold(
      appBar: AppBar(title: Text('Terminal · ${widget.device.name}')),
      body: Column(
        children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(Radii.xl),
              ),
              clipBehavior: Clip.antiAlias,
              child: _entries.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Symbols.terminal_rounded, size: 48, color: scheme.outline),
                          const SizedBox(height: 12),
                          Text(
                            'Digite um comando abaixo',
                            style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(18),
                      itemCount: _entries.length,
                      itemBuilder: (_, i) {
                        final e = _entries[i];
                        final r = e.result;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: '❯ ',
                                      style: mono.copyWith(color: scheme.primary, fontWeight: FontWeight.bold),
                                    ),
                                    TextSpan(
                                      text: e.command,
                                      style: mono.copyWith(fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (r == null && e.error == null)
                                const Padding(padding: EdgeInsets.only(top: 6), child: LinearProgressIndicator()),
                              if (e.error != null) Text(e.error!, style: mono.copyWith(color: scheme.error)),
                              if (r != null && r.output.trim().isNotEmpty)
                                SelectableText(
                                  r.output.trimRight(),
                                  style: mono.copyWith(color: scheme.onSurfaceVariant),
                                ),
                              if (r != null && !r.ok)
                                Text(
                                  r.timedOut ? 'tempo esgotado' : 'saiu com código ${r.exitCode}',
                                  style: mono.copyWith(color: scheme.error),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      style: mono,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'comando',
                        prefixIcon: Icon(Symbols.chevron_right_rounded, color: scheme.primary),
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(Radii.xxl)),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(Radii.xxl)),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: const BorderRadius.all(Radius.circular(Radii.xxl)),
                          borderSide: BorderSide(color: scheme.primary, width: 2),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    style: IconButton.styleFrom(minimumSize: const Size(56, 56)),
                    onPressed: _busy ? null : _send,
                    icon: const Icon(Symbols.send_rounded, fill: 1),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
