/// Cache pequeno na memória que descarta o item usado há mais tempo, por
/// quantidade e, com [sizeOf], também pelo tamanho total ([maxSize]).
class LruCache<K, V> {
  LruCache(this.capacity, {this.sizeOf, this.maxSize}) : assert(capacity > 0);

  final int capacity;
  final int Function(V value)? sizeOf;
  final int? maxSize;
  final _items = <K, V>{}; // mantém a ordem de inserção
  int _size = 0;

  int get length => _items.length;
  int get size => _size;

  V? get(K key) {
    final v = _items.remove(key);
    if (v != null) _items[key] = v; // vai para o fim: usado agora
    return v;
  }

  void put(K key, V value) {
    final old = _items.remove(key);
    if (old != null) _size -= sizeOf?.call(old) ?? 0;
    final size = sizeOf?.call(value) ?? 0;
    if (maxSize != null && size > maxSize!) return; // sozinho já não cabe
    _items[key] = value;
    _size += size;
    while (_items.length > capacity || (maxSize != null && _size > maxSize!)) {
      // Remove fora do `?.`: sem sizeOf ele pularia a chamada inteira.
      final evicted = _items.remove(_items.keys.first) as V;
      _size -= sizeOf?.call(evicted) ?? 0;
    }
  }
}
