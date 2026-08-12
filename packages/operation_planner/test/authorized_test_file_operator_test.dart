import 'dart:io';

import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_operation_planner/picklogic_operation_planner.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late File source;
  late File destination;

  FileLocator locator(String path) => FileLocator(
    value: path,
    sourceKind: SourceKind.synthetic,
    platform: PickLogicPlatform.synthetic,
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('picklogic-operation-test-');
    source = File('${root.path}${Platform.pathSeparator}before.txt');
    destination = File('${root.path}${Platform.pathSeparator}after.txt');
    await source.writeAsString('synthetic');
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
}
