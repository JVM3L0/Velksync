import 'package:flutter_test/flutter_test.dart';
import 'package:velksync/services/lru_cache.dart';

void main() {
  test('descarta o usado há mais tempo', () {
    final c = LruCache<String, int>(2)
      ..put('a', 1)
      ..put('b', 2);
    expect(c.get('a'), 1); // "a" passa a ser o mais recente
    c.put('c', 3);
    expect(c.get('b'), isNull);
    expect(c.get('a'), 1);
    expect(c.get('c'), 3);
    expect(c.length, 2);
  });

  test('respeita o tamanho total', () {
    final c = LruCache<String, List<int>>(10, sizeOf: (v) => v.length, maxSize: 10)
      ..put('a', List.filled(4, 0))
      ..put('b', List.filled(4, 0))
      ..put('c', List.filled(4, 0)); // 12 > 10: sai "a"
    expect(c.get('a'), isNull);
    expect(c.size, 8);
    c.put('grande', List.filled(11, 0)); // maior que o limite: não entra
    expect(c.get('grande'), isNull);
    expect(c.size, 8);
    c.put('b', List.filled(1, 0)); // substituir recalcula o tamanho
    expect(c.size, 5);
  });
}
