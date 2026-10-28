import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../models/device.dart';
import 'theme.dart';

/// Link sozinho (http/https, sem espaços): no PC abre no navegador.
bool isShareLink(String text) {
  final t = text.trim();
  if (t.isEmpty || t.contains(RegExp(r'\s'))) return false;
  final u = Uri.tryParse(t);
  return u != null && (u.isScheme('http') || u.isScheme('https')) && u.host.isNotEmpty;
}

/// Escolha do PC para o texto que veio do menu Compartilhar. Só PCs pareados;
/// os desligados aparecem mas não dá para escolher.
Future<Device?> showSendSheet(
  BuildContext context, {
  required String text,
  required List<Device> devices,
  required bool Function(Device) online,
}) => showModalBottomSheet<Device>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme;
    final link = isShareLink(text);
    final paired = devices.where((d) => d.paired).toList();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Enviar para o PC', style: style.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              link ? 'O link abre no navegador do PC.' : 'O texto vai para a área de transferência do PC.',
              style: style.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(link ? Symbols.link_rounded : Symbols.content_paste_rounded, size: 20, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(text.trim(), maxLines: 3, overflow: TextOverflow.ellipsis, style: style.bodyMedium),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (paired.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Nenhum PC pareado. Pareie um PC pelo QR primeiro.', style: style.bodyMedium),
              ),
            for (final d in paired)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                enabled: online(d),
                leading: Icon(Symbols.computer_rounded, color: online(d) ? scheme.primary : null),
                title: Text(d.name),
                subtitle: Text(online(d) ? 'Ligado' : 'Desligado ou sem o agente'),
                onTap: () => Navigator.pop(context, d),
              ),
          ],
        ),
      ),
    );
  },
);
