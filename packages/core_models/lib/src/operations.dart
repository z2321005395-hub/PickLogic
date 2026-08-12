import 'enums.dart';
import 'locator.dart';

final class OperationPlan {
  const OperationPlan({
    required this.operationId,
    required this.operationType,
    required this.source,
    this.destination,
    required this.preview,
    this.warnings = const <String>[],
    this.rollbackMetadata = const <String, String>{},
    required this.status,
  }) : assert(operationId != '');

  final String operationId;
  final OperationType operationType;
  final FileLocator source;
  final FileLocator? destination;
  final String preview;
  final List<String> warnings;
  final Map<String, String> rollbackMetadata;
  final OperationStatus status;

  static const Map<OperationStatus, Set<OperationStatus>> _transitions = {
    OperationStatus.planned: {
      OperationStatus.previewed,
      OperationStatus.cancelled,
    },
    OperationStatus.previewed: {
      OperationStatus.confirmed,
      OperationStatus.cancelled,
    },
    OperationStatus.confirmed: {
      OperationStatus.executing,
      OperationStatus.cancelled,
    },
    OperationStatus.executing: {
      OperationStatus.completed,
      OperationStatus.failed,
    },
    OperationStatus.completed: {OperationStatus.undone},
  };

  bool canTransitionTo(OperationStatus next) =>
      _transitions[status]?.contains(next) ?? false;

  OperationPlan transitionTo(OperationStatus next) {
    if (!canTransitionTo(next)) {
      throw StateError('Invalid operation transition: $status -> $next');
    }
    return OperationPlan(
      operationId: operationId,
      operationType: operationType,
      source: source,
      destination: destination,
      preview: preview,
      warnings: warnings,
      rollbackMetadata: rollbackMetadata,
      status: next,
    );
  }
}

final class OperationResult {
  const OperationResult({
    required this.plan,
    required this.success,
    this.message = '',
  });

  final OperationPlan plan;
  final bool success;
  final String message;
}
