/// Cache pequeno na memória que descarta o item usado há mais tempo.
class LruCache<K, V> {
  LruCache(this.capacity) : assert(capacity > 0);

  final int capacity;
  final _items = <K, V>{}; // mantém a ordem de inserção

  int get length => _items.length;

  V? get(K key) {
    final v = _items.remove(key);
    if (v != null) _items[key] = v; // vai para o fim: usado agora
    return v;
  }

  void put(K key, V value) {
    _items.remove(key);
    _items[key] = value;
    while (_items.length > capacity) {
      _items.remove(_items.keys.first);
    }
  }
}
