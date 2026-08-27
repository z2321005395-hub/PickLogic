final class PdfPageEdit {
  const PdfPageEdit({
    required this.sourcePageNumber,
    this.clockwiseQuarterTurns = 0,
  }) : assert(sourcePageNumber > 0),
       assert(clockwiseQuarterTurns >= 0 && clockwiseQuarterTurns < 4);

  final int sourcePageNumber;
  final int clockwiseQuarterTurns;

  PdfPageEdit rotate(int delta) => PdfPageEdit(
    sourcePageNumber: sourcePageNumber,
    clockwiseQuarterTurns: (clockwiseQuarterTurns + delta) % 4,
  );
}

/// Immutable, source-preserving page arrangement for an edited PDF copy.
final class PdfEditPlan {
  PdfEditPlan({
    required this.originalPageCount,
    required List<PdfPageEdit> pages,
  }) : pages = List<PdfPageEdit>.unmodifiable(pages) {
    if (originalPageCount < 1 || pages.isEmpty) {
      throw ArgumentError('A PDF edit plan must keep at least one page.');
    }
    for (final page in pages) {
      if (page.sourcePageNumber > originalPageCount) {
        throw RangeError.range(
          page.sourcePageNumber,
          1,
          originalPageCount,
          'sourcePageNumber',
        );
      }
    }
  }

  factory PdfEditPlan.identity(int pageCount) => PdfEditPlan(
    originalPageCount: pageCount,
    pages: [
      for (var pageNumber = 1; pageNumber <= pageCount; pageNumber++)
        PdfPageEdit(sourcePageNumber: pageNumber),
    ],
  );

  final int originalPageCount;
  final List<PdfPageEdit> pages;

  bool get changed {
    if (pages.length != originalPageCount) return true;
    for (var index = 0; index < pages.length; index++) {
      final page = pages[index];
      if (page.sourcePageNumber != index + 1 ||
          page.clockwiseQuarterTurns != 0) {
        return true;
      }
    }
    return false;
  }

  int get removedPageCount {
    final retained = pages.map((page) => page.sourcePageNumber).toSet().length;
    return originalPageCount - retained;
  }

  int get duplicatedPageCount {
    final counts = <int, int>{};
    for (final page in pages) {
      counts.update(
        page.sourcePageNumber,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    return counts.values.fold(0, (total, count) => total + count - 1);
  }

  int get rotatedPageCount =>
      pages.where((page) => page.clockwiseQuarterTurns != 0).length;

  PdfEditPlan move(int oldIndex, int newIndex) {
    _checkIndex(oldIndex);
    if (newIndex < 0 || newIndex >= pages.length) {
      throw RangeError.index(newIndex, pages, 'newIndex');
    }
    if (oldIndex == newIndex) return this;
    final updated = pages.toList(growable: true);
    final page = updated.removeAt(oldIndex);
    updated.insert(newIndex, page);
    return _replace(updated);
  }

  PdfEditPlan rotate(int index, {required bool clockwise}) {
    _checkIndex(index);
    final updated = pages.toList(growable: true);
    updated[index] = updated[index].rotate(clockwise ? 1 : 3);
    return _replace(updated);
  }

  PdfEditPlan duplicate(int index) {
    _checkIndex(index);
    final updated = pages.toList(growable: true);
    updated.insert(index + 1, updated[index]);
    return _replace(updated);
  }

  PdfEditPlan remove(int index) {
    _checkIndex(index);
    if (pages.length == 1) {
      throw StateError('A PDF must keep at least one page.');
    }
    final updated = pages.toList(growable: true)..removeAt(index);
    return _replace(updated);
  }

  PdfEditPlan _replace(List<PdfPageEdit> updated) =>
      PdfEditPlan(originalPageCount: originalPageCount, pages: updated);

  void _checkIndex(int index) {
    if (index < 0 || index >= pages.length) {
      throw RangeError.index(index, pages, 'index');
    }
  }
}
