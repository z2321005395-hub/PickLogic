import 'package:picklogic_preview_core/picklogic_preview_core.dart';
import 'package:test/test.dart';

void main() {
  test('evicts least-recently-used entries by count and weight', () {
    final cache = BoundedCache<String, String>(maxEntries: 2, maxWeight: 5);
    cache.put('a', 'A', weight: 2);
    cache.put('b', 'B', weight: 2);
    expect(cache.get('a'), 'A');
    cache.put('c', 'C', weight: 2);
    expect(cache.get('b'), isNull);
    expect(cache.length, 2);
    expect(cache.weight, 4);
  });

  test('does not cache an item larger than the whole budget', () {
    final cache = BoundedCache<String, String>(maxEntries: 2, maxWeight: 3);
    cache.put('large', 'L', weight: 4);
    expect(cache.length, 0);
  });
}
