import 'package:picklogic_core_models/picklogic_core_models.dart';

final class OperationBatchPreview {
  OperationBatchPreview({
    required this.batchId,
    required Iterable<OperationPlan> plans,
    required Iterable<String> warnings,
  }) : plans = List<OperationPlan>.unmodifiable(plans),
       warnings = List<String>.unmodifiable(warnings);

  final String batchId;
  final List<OperationPlan> plans;
  final List<String> warnings;

  int count(OperationType type) =>
      plans.where((plan) => plan.operationType == type).length;

  String get summary =>
      '${plans.length} operations: '
      '${count(OperationType.rename)} rename, '
      '${count(OperationType.move)} move, '
      '${count(OperationType.deleteToTrash)} trash';
}

final class OperationBatchPreviewer {
  const OperationBatchPreviewer();

  Future<OperationBatchPreview> preview({
    required String batchId,
    required Iterable<OperationPlan> plans,
    required FileOperator operator,
  }) async {
    if (batchId.trim().isEmpty) {
      throw ArgumentError.value(batchId, 'batchId', 'A batch id is required.');
    }
    final pending = plans.toList(growable: false);
    if (pending.isEmpty) {
      throw ArgumentError.value(
        pending,
        'plans',
        'At least one operation plan is required.',
      );
    }

    final operationIds = <String>{};
    final sourceKeys = <String>{};
    final destinationKeys = <String>{};
    for (final plan in pending) {
      if (plan.status != OperationStatus.planned) {
        throw StateError('Every batch operation must start in planned state.');
      }
      if (!operationIds.add(plan.operationId)) {
        throw StateError('Batch operation ids must be unique.');
      }
      if (!sourceKeys.add(_locatorKey(plan.source))) {
        throw StateError('A batch source can be changed only once.');
      }
      final destination = plan.destination;
      if (destination != null) {
        final destinationKey = _locatorKey(destination);
        if (destinationKey == _locatorKey(plan.source)) {
          throw StateError('A batch destination must differ from its source.');
        }
        if (!destinationKeys.add(destinationKey)) {
          throw StateError('Batch destinations must be unique.');
        }
      }
    }

    final warnings = <String>{for (final plan in pending) ...plan.warnings};
    if (destinationKeys.any(sourceKeys.contains)) {
      warnings.add(
        'A destination overlaps another batch source; execution order requires review.',
      );
    }

    final previewed = <OperationPlan>[];
    for (final plan in pending) {
      final preview = await operator.preview(plan);
      if (preview.status != OperationStatus.previewed) {
        throw StateError(
          'The file operator returned an invalid preview state.',
        );
      }
      previewed.add(preview);
    }
    return OperationBatchPreview(
      batchId: batchId,
      plans: previewed,
      warnings: warnings,
    );
  }
}

String _locatorKey(FileLocator locator) {
  final normalized = locator.value.replaceAll('\\', '/');
  final value = locator.platform == PickLogicPlatform.windows
      ? normalized.toLowerCase()
      : normalized;
  return '${locator.platform.name}:${locator.sourceKind.name}:$value';
}
