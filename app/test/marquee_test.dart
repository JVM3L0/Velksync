import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:velksync/ui/marquee.dart';

Widget box(String text, {bool reduceMotion = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Center(child: SizedBox(width: 200, child: MarqueeText(text))),
  ),
);

void main() {
  const long = 'Rap do Feedback (Ben 10) - Cês Sentiram Saudade, versão estendida ao vivo';

  testWidgets('título longo rola sem quebrar linha', (tester) async {
    await tester.pumpWidget(box(long));
    await tester.pump();
    final start = tester.getTopLeft(find.text(long)).dx;
    final h = tester.getSize(find.byType(MarqueeText)).height;
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getTopLeft(find.text(long)).dx, lessThan(start), reason: 'rolou para a esquerda');
    expect(tester.getSize(find.byType(MarqueeText)).height, h, reason: 'continua em uma linha');
    await tester.pumpWidget(const SizedBox()); // desmonta: nenhum temporizador fica pendente
  });

  testWidgets('título curto fica parado', (tester) async {
    await tester.pumpWidget(box('Numb'));
    await tester.pump(const Duration(seconds: 5));
    expect(find.byType(ShaderMask), findsNothing);
  });

  testWidgets('sem animações no sistema, usa reticências', (tester) async {
    await tester.pumpWidget(box(long, reduceMotion: true));
    await tester.pump(const Duration(seconds: 5));
    expect(find.byType(ShaderMask), findsNothing);
    expect(tester.widget<Text>(find.text(long)).overflow, TextOverflow.ellipsis);
  });
}
