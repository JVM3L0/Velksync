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
}
