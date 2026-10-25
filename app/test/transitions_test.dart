import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:velksync/ui/transitions.dart';

void main() {
  testWidgets('container transform cresce do cartão e volta para ele', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: 200,
                height: 100,
                child: Builder(
                  builder: (card) => InkWell(
                    key: const Key('card'),
                    onTap: () => Navigator.push(
                      card,
                      ContainerTransformRoute(
                        origin: card,
                        builder: (_) => const Scaffold(body: Text('detalhe')),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    Rect container() => tester.getRect(find.byType(ClipRRect).last);

    await tester.tap(find.byKey(const Key('card')));
    await tester.pump();
    await tester.pump();
    expect(container(), const Rect.fromLTWH(16, 16, 200, 100), reason: 'começa no cartão');

    await tester.pump(const Duration(milliseconds: 150));
    final mid = container();
    expect(mid.width, greaterThan(200));
    expect(mid.width, lessThan(screen.width));

    await tester.pumpAndSettle();
    expect(find.byType(ClipRRect), findsNothing, reason: 'terminada, a página fica sem embrulho');
    expect(find.text('detalhe'), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 379));
    expect(container().width, closeTo(200, 2), reason: 'volta para dentro do cartão');
    await tester.pumpAndSettle();
    expect(find.text('detalhe'), findsNothing);
  });

  testWidgets('abas deslizam para o lado escolhido', (tester) async {
    Widget tabs(int i) => MaterialApp(
      home: SharedAxisSwitcher(
        index: i,
        child: Center(child: Text('aba $i')),
      ),
    );
    double dx(String text) => tester.getCenter(find.text(text)).dx;

    await tester.pumpWidget(tabs(0));
    final center = dx('aba 0');

    await tester.pumpWidget(tabs(2));
    await tester.pump(const Duration(milliseconds: 60));
    expect(dx('aba 2'), greaterThan(center), reason: 'para a direita, entra pela direita');
    expect(dx('aba 0'), lessThan(center), reason: 'e a antiga sai pela esquerda');
    await tester.pumpAndSettle();
    expect(find.text('aba 0'), findsNothing);
    expect(dx('aba 2'), center);

    await tester.pumpWidget(tabs(1));
    await tester.pump(const Duration(milliseconds: 60));
    expect(dx('aba 1'), lessThan(center), reason: 'para a esquerda, entra pela esquerda');
    await tester.pumpAndSettle();
  });

  testWidgets('capa do álbum desliza mais longe que as abas', (tester) async {
    Widget track(int i) => MaterialApp(
      home: SharedAxisSwitcher(
        index: i,
        distance: 160,
        child: Center(child: Text('faixa $i')),
      ),
    );
    await tester.pumpWidget(track(0));
    final center = tester.getCenter(find.text('faixa 0')).dx;
    await tester.pumpWidget(track(-1)); // anterior: entra pela esquerda
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.getCenter(find.text('faixa -1')).dx, lessThan(center - 100));
    await tester.pumpAndSettle();
  });
}
