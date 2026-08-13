import 'package:flutter_test/flutter_test.dart';
import 'package:picklogic_mobile/src/paged_media.dart';

void main() {
  test(
    '145 items paginate without truncation, duplicates, or boundary reordering',
    () async {
      final base = DateTime.utc(2026, 8, 13, 12);
      final bridgeSorted =
          List<_SyntheticMedia>.generate(145, (rank) {
            final displayedDate = base.subtract(
              Duration(minutes: rank == 120 ? 119 : rank),
            );
            return _SyntheticMedia(
              id: 'images:${1000 - rank}',
              dateTaken: rank.isEven ? displayedDate : null,
              modifiedAt: displayedDate,
            );
          }).reversed.toList(growable: false)..sort((left, right) {
            final byDisplayedDate = right.displayedDate.compareTo(
              left.displayedDate,
            );
            if (byDisplayedDate != 0) return byDisplayedDate;
            return compareMediaIdsDescending(left.id, right.id);
          });

      expect(bridgeSorted[119].displayedDate, bridgeSorted[120].displayedDate);
      expect(bridgeSorted[119].id, 'images:881');
      expect(bridgeSorted[120].id, 'images:880');

      final transport = <_SyntheticMedia>[
        ...bridgeSorted.take(120),
        bridgeSorted[119],
        ...bridgeSorted.skip(120),
      ];
      final offsets = <int>[];
      final pager = PagedMediaController<_SyntheticMedia>(
        pageSize: 120,
        counter: () async => bridgeSorted.length,
        loader: (offset, limit) async {
          offsets.add(offset);
          return transport.skip(offset).take(limit).toList(growable: false);
        },
        idOf: (item) => item.id,
        dateOf: (item) => item.displayedDate,
      );

      while (pager.hasMore) {
        await pager.loadNext();
      }

      expect(offsets, <int>[0, 120]);
      expect(pager.totalCount, 145);
      expect(pager.loadedCount, 145);
      expect(
        pager.items.map((item) => item.id),
        bridgeSorted.map((item) => item.id),
      );
      expect(pager.items.map((item) => item.id).toSet(), hasLength(145));
      expect(pager.hasMore, isFalse);

      await pager.loadNext();
      expect(offsets, <int>[0, 120]);
    },
  );
}

final class _SyntheticMedia {
  const _SyntheticMedia({
    required this.id,
    required this.dateTaken,
    required this.modifiedAt,
  });

  final String id;
  final DateTime? dateTaken;
  final DateTime modifiedAt;

  DateTime get displayedDate => dateTaken ?? modifiedAt;
}
