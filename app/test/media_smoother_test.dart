import 'package:flutter_test/flutter_test.dart';
import 'package:velksync/models/device.dart';
import 'package:velksync/services/media_smoother.dart';

MediaState track(String title, {bool available = true}) => MediaState.fromJson({
  'available': available,
  'status': available ? 'playing' : 'stopped',
  'title': title,
  'artist': 'Linkin Park',
});

final nothing = track('', available: false);

void main() {
  testWidgets('troca de faixa não pisca "nada tocando"', (tester) async {
    final m = MediaSmoother(onChange: () {});
    addTearDown(m.dispose);
    m.push(track('Heavy Is the Crown'));
    m.push(nothing); // o player some por um instante ao pular
    expect(m.switching, isTrue);
    expect(m.shown!.title, 'Heavy Is the Crown', reason: 'segura a faixa anterior');
    await tester.pump(const Duration(milliseconds: 800));
    m.push(track('The Emptiness Machine'));
    expect(m.switching, isFalse);
    expect(m.shown!.title, 'The Emptiness Machine');
    await tester.pump(const Duration(seconds: 5));
    expect(m.shown!.title, 'The Emptiness Machine', reason: 'o temporizador antigo não pode voltar atrás');
  });

  testWidgets('se o player sumiu de verdade, mostra depois do prazo', (tester) async {
    final m = MediaSmoother(onChange: () {});
    addTearDown(m.dispose);
    m.push(track('Numb'));
    m.push(nothing);
    await tester.pump(const Duration(seconds: 2));
    m.push(nothing);
    expect(m.shown!.available, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(m.switching, isFalse);
    expect(m.shown!.available, isFalse);
  });

  testWidgets('tocar em próxima mostra "trocando" até a faixa mudar', (tester) async {
    var changes = 0;
    final m = MediaSmoother(onChange: () => changes++);
    addTearDown(m.dispose);
    m.push(track('Numb'));
    m.expectChange();
    expect(m.switching, isTrue);
    m.push(track('Numb')); // o PC ainda não trocou
    expect(m.switching, isTrue);
    m.push(track('Faint'));
    expect(m.switching, isFalse);
    expect(m.shown!.title, 'Faint');
    expect(changes, greaterThanOrEqualTo(3));
  });

  testWidgets('pular sem efeito para de girar depois do prazo', (tester) async {
    final m = MediaSmoother(onChange: () {});
    addTearDown(m.dispose);
    m.push(track('Numb'));
    m.expectChange();
    await tester.pump(const Duration(seconds: 3));
    expect(m.switching, isFalse);
    expect(m.shown!.title, 'Numb');
  });

  test('sem nada tocando antes, "nada tocando" aparece na hora', () {
    final m = MediaSmoother(onChange: () {});
    m.push(nothing);
    expect(m.switching, isFalse);
    expect(m.shown!.available, isFalse);
    m.expectChange();
    expect(m.switching, isFalse);
    m.dispose();
  });
}
