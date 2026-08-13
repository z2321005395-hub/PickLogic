import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_file_index/picklogic_file_index.dart';
import 'package:picklogic_desktop/src/desktop_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'selected temp directory drives scoped read-only Standard features',
    () async {
      final firstRoot = await Directory.systemTemp.createTemp(
        'picklogic-standard-first-',
      );
      final secondRoot = await Directory.systemTemp.createTemp(
        'picklogic-standard-second-',
      );
      final index = SqliteFileIndex.inMemory();
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('picklogic_windows_bridge'),
              null,
            );
        index.close();
        await firstRoot.delete(recursive: true);
        await secondRoot.delete(recursive: true);
      });

      await File(
        '${firstRoot.path}${Platform.pathSeparator}old.pdf',
      ).writeAsBytes(const [1, 2, 3]);
      await File(
        '${secondRoot.path}${Platform.pathSeparator}report.pdf',
      ).writeAsBytes(const [7, 8, 9]);
      await File(
        '${secondRoot.path}${Platform.pathSeparator}figure.png',
      ).writeAsBytes(const [4, 5, 6, 7]);
      await File(
        '${secondRoot.path}${Platform.pathSeparator}duplicate-a.txt',
      ).writeAsString('same synthetic bytes');
      await File(
        '${secondRoot.path}${Platform.pathSeparator}duplicate-b.txt',
      ).writeAsString('same synthetic bytes');

      final selectedRoots = <String>[firstRoot.path, secondRoot.path].iterator;
      final shellCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('picklogic_windows_bridge'),
            (call) async {
              if (call.method == 'pickDirectory') {
                expect(selectedRoots.moveNext(), isTrue);
                return selectedRoots.current;
              }
              shellCalls.add(call);
              return true;
            },
          );

      final repository = WindowsDesktopRepository(indexFactory: () => index);
      await repository.chooseAndScan().toList();
      final batches = await repository.chooseAndScan().toList();
      final records = batches.expand((batch) => batch.records).toList();

      expect(records, hasLength(4));
      expect(
        records
            .singleWhere((record) => record.displayName == 'report.pdf')
            .category,
        VirtualCategory.pdf,
      );
      expect(
        records
            .singleWhere((record) => record.displayName == 'figure.png')
            .category,
        VirtualCategory.images,
      );
      expect(await repository.search('old'), isEmpty);
      expect(
        (await repository.search('report')).single.displayName,
        'report.pdf',
      );

      final duplicates = await repository.findExactDuplicates(records);
      expect(duplicates.groups, hasLength(1));
      expect(
        duplicates.groups.single.map((record) => record.displayName).toSet(),
        {'duplicate-a.txt', 'duplicate-b.txt'},
      );

      final report = records.singleWhere(
        (record) => record.displayName == 'report.pdf',
      );
      expect(await repository.open(report), isTrue);
      expect(await repository.reveal(report), isTrue);
      expect(shellCalls.map((call) => call.method), ['openItem', 'revealItem']);
      expect(
        shellCalls.every(
          (call) =>
              (call.arguments as Map<Object?, Object?>)['path'] ==
              report.locator.value,
        ),
        isTrue,
      );
    },
  );
}
