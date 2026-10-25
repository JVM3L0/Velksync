import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:velksync/ui/media_panel.dart';

/// PNG 120x120, o tamanho que o Windows costuma mandar.
Future<Uint8List> smallPng() async {
  final rec = ui.PictureRecorder();
  Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 120, 120), Paint()..color = const Color(0xFFAA3366));
  final img = await rec.endRecording().toImage(120, 120);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  testWidgets('capa pequena ocupa o quadrado inteiro', (tester) async {
    final png = (await tester.runAsync(smallPng))!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 400, child: MediaCover(art: png, artId: 'a')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final cover = tester.getSize(find.byType(Image));
    expect(cover.width, 360, reason: 'antes ficava em 120, minúscula no meio');
    expect(cover.height, 360);
  });
}
