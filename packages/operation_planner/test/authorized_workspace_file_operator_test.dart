import 'dart:io';

import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_operation_planner/picklogic_operation_planner.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Directory trash;
  late AuthorizedWorkspaceFileOperator operator;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('picklogic-workspace-');
    trash = Directory('${root.path}${Platform.pathSeparator}Test-Trash');
    await trash.create();
    operator = AuthorizedWorkspaceFileOperator(
      authorizedRoot: root,
      trashDirectory: trash,
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('rename follows preview confirm execute and undo', () async {
    final source = File('${root.path}${Platform.pathSeparator}before.txt');
    await source.writeAsString('synthetic');
    final destination = '${root.path}${Platform.pathSeparator}after.txt';
    final plan = const OperationPlanner().planRename(
      operationId: 'rename-1',
      source: _locator(source.path),
      destination: _locator(destination),
    );

    final preview = await operator.preview(plan);
    expect(preview.status, OperationStatus.previewed);
    final result = await operator.execute(
      preview.transitionTo(OperationStatus.confirmed),
    );

    expect(result.success, isTrue);
    expect(await File(destination).readAsString(), 'synthetic');
    final undo = await operator.undo(result.plan);
    expect(undo.success, isTrue);
    expect(await source.readAsString(), 'synthetic');
  });

  test('delete moves into reversible workspace trash', () async {
    final source = File('${root.path}${Platform.pathSeparator}review.txt');
    await source.writeAsString('review');
    final plan = const OperationPlanner().planDeleteToTrash(
      operationId: 'trash-1',
      source: _locator(source.path),
    );

    final preview = await operator.preview(plan);
    expect(preview.destination!.value, startsWith(trash.path));
    final result = await operator.execute(
      preview.transitionTo(OperationStatus.confirmed),
    );
    expect(result.success, isTrue);
    expect(await source.exists(), isFalse);
    expect(await File(result.plan.destination!.value).exists(), isTrue);

    final undo = await operator.undo(result.plan);
    expect(undo.success, isTrue);
    expect(await source.readAsString(), 'review');
  });

  test('preview rejects destinations outside the authorized root', () async {
    final source = File('${root.path}${Platform.pathSeparator}inside.txt');
    await source.writeAsString('inside');
    final outside = await Directory.systemTemp.createTemp('picklogic-outside-');
    addTearDown(() => outside.delete(recursive: true));
    final plan = const OperationPlanner().planMove(
      operationId: 'escape-1',
      source: _locator(source.path),
      destination: _locator(
        '${outside.path}${Platform.pathSeparator}escaped.txt',
      ),
    );

    await expectLater(
      operator.preview(plan),
      throwsA(isA<FileSystemException>()),
    );
    expect(await source.readAsString(), 'inside');
  });
}

FileLocator _locator(String path) => FileLocator(
  value: path,
  sourceKind: SourceKind.fileSystem,
  platform: PickLogicPlatform.windows,
);
