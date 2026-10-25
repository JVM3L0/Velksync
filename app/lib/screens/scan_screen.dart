import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../ui/theme.dart';

/// Reads the QR shown by `velksync-agent pair` and returns its link.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw != null && raw.startsWith('velksync://pair?')) {
        _done = true;
        Navigator.pop(context, raw);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final window = MediaQuery.sizeOf(context).width * 0.7;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Escanear QR'),
        actions: [
          IconButton(
            tooltip: 'Lanterna',
            onPressed: _controller.toggleTorch,
            icon: const Icon(Symbols.flashlight_on_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // Escurece tudo fora da janela de leitura.
          ColorFiltered(
            colorFilter: const ColorFilter.mode(Colors.black54, BlendMode.srcOut),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const DecoratedBox(decoration: BoxDecoration(color: Colors.transparent)),
                Center(
                  child: Container(
                    width: window,
                    height: window,
                    decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(Radii.xxl)),
                  ),
                ),
              ],
            ),
          ),
          Center(
            child: Container(
              width: window,
              height: window,
              decoration: BoxDecoration(
                border: Border.all(color: scheme.primary, width: 4),
                borderRadius: BorderRadius.circular(Radii.xxl),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: ShapeDecoration(color: scheme.surfaceContainerHigh, shape: const StadiumBorder()),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Symbols.qr_code_rounded, color: scheme.primary),
                    const SizedBox(width: 12),
                    Flexible(child: Text('Rode "velksync-agent pair" no PC', style: text.bodyMedium)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
