import 'dart:collection';

final class BoundedCache<K, V> {
  BoundedCache({required this.maxEntries, required this.maxWeight})
    : assert(maxEntries > 0),
      assert(maxWeight > 0);

  final int maxEntries;
  final int maxWeight;
  final LinkedHashMap<K, ({V value, int weight})> _entries = LinkedHashMap();
  int _weight = 0;

  int get length => _entries.length;
  int get weight => _weight;

  V? get(K key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    _entries[key] = entry;
    return entry.value;
  }

  void put(K key, V value, {required int weight}) {
    if (weight <= 0) throw ArgumentError.value(weight, 'weight');
    final previous = _entries.remove(key);
    if (previous != null) _weight -= previous.weight;
    if (weight > maxWeight) return;
    _entries[key] = (value: value, weight: weight);
    _weight += weight;
    _trim();
  }

  bool remove(K key) {
    final entry = _entries.remove(key);
    if (entry == null) return false;
    _weight -= entry.weight;
    return true;
  }

  void clear() {
    _entries.clear();
    _weight = 0;
  }

  void _trim() {
    while (_entries.length > maxEntries || _weight > maxWeight) {
      final oldestKey = _entries.keys.first;
      final oldest = _entries.remove(oldestKey)!;
      _weight -= oldest.weight;
    }
  }
}
