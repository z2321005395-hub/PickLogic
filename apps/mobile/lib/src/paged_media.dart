typedef PagedMediaLoader<T> = Future<List<T>> Function(int offset, int limit);
typedef PagedMediaCounter = Future<int> Function();
typedef PagedMediaId<T> = String Function(T item);
typedef PagedMediaDate<T> = DateTime Function(T item);

int compareMediaIdsDescending(String left, String right) {
  final leftNativeId = int.tryParse(left.substring(left.lastIndexOf(':') + 1));
  final rightNativeId = int.tryParse(
    right.substring(right.lastIndexOf(':') + 1),
  );
  if (leftNativeId != null && rightNativeId != null) {
    return rightNativeId.compareTo(leftNativeId);
  }
  return right.compareTo(left);
}

final class PagedMediaController<T> {
  PagedMediaController({
    required this.loader,
    required this.counter,
    required this.idOf,
    required this.dateOf,
    this.pageSize = 120,
  }) : assert(pageSize > 0 && pageSize <= 250);

  final PagedMediaLoader<T> loader;
  final PagedMediaCounter counter;
  final PagedMediaId<T> idOf;
  final PagedMediaDate<T> dateOf;
  final int pageSize;

  final Map<String, T> _items = <String, T>{};
  var _offset = 0;
  var _hasMore = true;
  var _isLoading = false;
  int? _totalCount;
  Object? _error;

  List<T> get items {
    final sorted = _items.values.toList(growable: false);
    sorted.sort((left, right) {
      final byDate = dateOf(right).compareTo(dateOf(left));
      if (byDate != 0) return byDate;
      return compareMediaIdsDescending(idOf(left), idOf(right));
    });
    return sorted;
  }

  int get loadedCount => _items.length;
  int? get totalCount => _totalCount;
  int get nextOffset => _offset;
  bool get hasMore => _hasMore;
  bool get isLoading => _isLoading;
  Object? get error => _error;

  Future<void> loadNext() async {
    if (_isLoading || !_hasMore) return;
    _isLoading = true;
    _error = null;
    try {
      final totalFuture = _totalCount == null
          ? counter().then<void>((value) => _totalCount = value)
          : Future<void>.value();
      final page = await loader(_offset, pageSize);
      await totalFuture;
      _offset += page.length;
      for (final item in page) {
        _items[idOf(item)] = item;
      }
      final total = _totalCount;
      _hasMore =
          page.isNotEmpty &&
          page.length >= pageSize &&
          (total == null || _offset < total);
    } catch (error) {
      _error = error;
      rethrow;
    } finally {
      _isLoading = false;
    }
  }
}
