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

  test(
    'directory browsing is bounded, non-recursive, and metadata-only',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'picklogic-browser-root-',
      );
      final index = SqliteFileIndex.inMemory();
      final nested = await Directory(
        '${root.path}${Platform.pathSeparator}nested',
      ).create();
      await File(
        '${root.path}${Platform.pathSeparator}visible.pdf',
      ).writeAsBytes(const [1, 2, 3]);
      await File(
        '${nested.path}${Platform.pathSeparator}not-listed.txt',
      ).writeAsString('nested synthetic fixture');
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('picklogic_windows_bridge'),
              null,
            );
        index.close();
        await root.delete(recursive: true);
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('picklogic_windows_bridge'),
            (call) async => switch (call.method) {
              'getBrowseRoots' => <Object>[
                <String, Object>{
                  'id': 'drive:synthetic',
                  'path': root.path,
                  'kind': 'drive',
                },
                <String, Object>{
                  'id': 'documents',
                  'path': root.path,
                  'kind': 'documents',
                },
              ],
              _ => null,
            },
          );

      final repository = WindowsDesktopRepository(indexFactory: () => index);
      final roots = await repository.browseRoots();
      final snapshot = await repository.browseDirectory(root.path);

      expect(roots, hasLength(2));
      expect(roots.first.path, root.path);
      expect(snapshot.entries.map((entry) => entry.name), [
        'nested',
        'visible.pdf',
      ]);
      expect(snapshot.entries.first.isDirectory, isTrue);
      expect(snapshot.entries.last.category, VirtualCategory.pdf);
      expect(
        snapshot.entries.any((entry) => entry.name == 'not-listed.txt'),
        isFalse,
      );
      expect(snapshot.truncated, isFalse);

      final bounded = await repository.browseDirectory(
        root.path,
        maxEntries: 1,
      );
      expect(bounded.entries, hasLength(1));
      expect(bounded.truncated, isTrue);

      final progress = await repository.indexCommonFolders().toList();
      expect(progress, isNotEmpty);
      expect(
        (await repository.search('visible pdf')).single.displayName,
        'visible.pdf',
      );
    },
  );
}
