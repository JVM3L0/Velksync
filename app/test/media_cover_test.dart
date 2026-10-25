import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:velksync/ui/media_panel.dart';

/// PNG 120x120, o tamanho que o Windows costuma mandar.
Future<Uint8List> smallPng({int w = 120, int h = 120}) async {
  final rec = ui.PictureRecorder();
  Canvas(rec).drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = const Color(0xFFAA3366));
  final img = await rec.endRecording().toImage(w, h);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  testWidgets('capa pequena ocupa o quadrado inteiro', (tester) async {
    final png = (await tester.runAsync(smallPng))!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: MediaCover(art: png, artId: 'a'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final cover = tester.getSize(find.byType(Image));
    expect(cover.width, 360, reason: 'antes ficava em 120, minúscula no meio');
    expect(cover.height, 360);
  });

  testWidgets('miniatura de vídeo fica em 16:9, sem cortar', (tester) async {
    final png = (await tester.runAsync(() => smallPng(w: 160, h: 90)))!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: MediaCover(art: png, artId: 'v', side: 360, aspect: 16 / 9),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final size = tester.getSize(find.byType(Image));
    expect(size.width, 400);
    expect(size.height, closeTo(225, 0.5));
    expect(tester.getSize(find.byType(MediaCover)).height, 360, reason: 'a área da capa não muda de altura');
  });
}
