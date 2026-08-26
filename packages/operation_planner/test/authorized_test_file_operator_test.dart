import 'dart:io';

import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_operation_planner/picklogic_operation_planner.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late File source;
  late File destination;
  late File moveSource;
  late File moveDestination;

  FileLocator locator(String path) => FileLocator(
    value: path,
    sourceKind: SourceKind.synthetic,
    platform: PickLogicPlatform.synthetic,
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('picklogic-operation-test-');
    source = File('${root.path}${Platform.pathSeparator}before.txt');
    destination = File('${root.path}${Platform.pathSeparator}after.txt');
    moveSource = File('${root.path}${Platform.pathSeparator}move-before.txt');
    final moveDirectory = await Directory(
      '${root.path}${Platform.pathSeparator}moved',
    ).create();
    moveDestination = File(
      '${moveDirectory.path}${Platform.pathSeparator}move-after.txt',
    );
    await source.writeAsString('synthetic');
    await moveSource.writeAsString('move-synthetic');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'preview, confirm, execute, and undo stay inside the test root',
    () async {
      final operator = AuthorizedTestFileOperator(
        authorizedRoot: root,
        testMutationAuthorized: true,
      );
      final planned = const OperationPlanner().planRename(
        operationId: 'synthetic-rename',
        source: locator(source.path),
        destination: locator(destination.path),
      );
      final previewed = await operator.preview(planned);
      final confirmed = previewed.transitionTo(OperationStatus.confirmed);
      final executed = await operator.execute(confirmed);

      expect(executed.success, isTrue);
      expect(await destination.readAsString(), 'synthetic');
      expect(await source.exists(), isFalse);

      final undone = await operator.undo(executed.plan);
      expect(undone.success, isTrue);
      expect(await source.readAsString(), 'synthetic');
      expect(await destination.exists(), isFalse);
    },
  );

  test('Developer Safe Mode blocks unapproved mutation', () async {
    final operator = AuthorizedTestFileOperator(
      authorizedRoot: root,
      testMutationAuthorized: false,
    );
    final planned = const OperationPlanner().planMove(
      operationId: 'blocked-move',
      source: locator(source.path),
      destination: locator(destination.path),
    );

    await expectLater(
      operator.preview(planned),
      throwsA(isA<FileSystemException>()),
    );
    expect(await source.exists(), isTrue);
  });

  test('batch preview keeps files unchanged before move and rename', () async {
    final operator = AuthorizedTestFileOperator(
      authorizedRoot: root,
      testMutationAuthorized: true,
    );
    final preview = await const OperationBatchPreviewer().preview(
      batchId: 'synthetic-batch',
      plans: [
        const OperationPlanner().planRename(
          operationId: 'batch-rename',
          source: locator(source.path),
          destination: locator(destination.path),
        ),
        const OperationPlanner().planMove(
          operationId: 'batch-move',
          source: locator(moveSource.path),
          destination: locator(moveDestination.path),
        ),
      ],
      operator: operator,
    );

    expect(preview.summary, '2 operations: 1 rename, 1 move, 0 trash');
    expect(
      preview.plans.map((plan) => plan.status),
      everyElement(OperationStatus.previewed),
    );
    expect(await source.readAsString(), 'synthetic');
    expect(await moveSource.readAsString(), 'move-synthetic');
    expect(await destination.exists(), isFalse);
    expect(await moveDestination.exists(), isFalse);

    final completed = <OperationPlan>[];
    for (final plan in preview.plans) {
      final result = await operator.execute(
        plan.transitionTo(OperationStatus.confirmed),
      );
      expect(result.success, isTrue);
      completed.add(result.plan);
    }
    expect(await destination.readAsString(), 'synthetic');
    expect(await moveDestination.readAsString(), 'move-synthetic');

    for (final plan in completed.reversed) {
      final result = await operator.undo(plan);
      expect(result.success, isTrue);
    }
    expect(await source.readAsString(), 'synthetic');
    expect(await moveSource.readAsString(), 'move-synthetic');
    expect(await destination.exists(), isFalse);
    expect(await moveDestination.exists(), isFalse);
  });

  test('Developer Safe Mode rejects a confirmed real-path plan', () async {
    final operator = AuthorizedTestFileOperator(
      authorizedRoot: root,
      testMutationAuthorized: true,
    );
    FileLocator realLocator(String path) => FileLocator(
      value: path,
      sourceKind: SourceKind.fileSystem,
      platform: PickLogicPlatform.windows,
    );
    final planned = const OperationPlanner().planRename(
      operationId: 'blocked-real-path',
      source: realLocator(source.path),
      destination: realLocator(destination.path),
    );
    final confirmed = planned
        .transitionTo(OperationStatus.previewed)
        .transitionTo(OperationStatus.confirmed);

    final result = await operator.execute(confirmed);

    expect(result.success, isFalse);
    expect(result.message, contains('Developer Safe Mode blocked'));
    expect(await source.readAsString(), 'synthetic');
    expect(await destination.exists(), isFalse);
  });
}
