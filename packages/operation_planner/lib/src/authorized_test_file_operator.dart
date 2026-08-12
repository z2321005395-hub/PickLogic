import 'dart:io';

import 'package:picklogic_core_models/picklogic_core_models.dart';

import 'operation_planner.dart';

final class AuthorizedTestFileOperator implements FileOperator {
  AuthorizedTestFileOperator({
    required Directory authorizedRoot,
    required this.testMutationAuthorized,
  }) : _authorizedRoot = authorizedRoot.absolute;

  final Directory _authorizedRoot;
  final bool testMutationAuthorized;
  final SafeOperationGate _gate = const SafeOperationGate(
    DeveloperSafeMode.on(),
  );

  @override
  Future<OperationPlan> preview(OperationPlan plan) async {
    if (plan.status != OperationStatus.planned) {
      throw StateError('Only a newly planned operation can be previewed.');
    }
    if (plan.operationType == OperationType.deleteToTrash) {
      throw UnsupportedError(
        'Developer Safe Mode does not delete test data; use review queues.',
      );
    }
    final destination = plan.destination;
    if (destination == null) throw StateError('A destination is required.');
    await _validatedPaths(plan.source, destination, requireSource: true);
    return _copyPlan(
      plan,
      status: OperationStatus.previewed,
      rollbackMetadata: const {'strategy': 'rename-back'},
    );
  }

  @override
  Future<OperationResult> execute(OperationPlan confirmedPlan) async {
    final syntheticTarget =
        confirmedPlan.source.sourceKind == SourceKind.synthetic &&
        confirmedPlan.source.platform == PickLogicPlatform.synthetic;
    if (!_gate.mayExecute(
      confirmedPlan,
      syntheticTarget: syntheticTarget,
      testMutationAuthorized: testMutationAuthorized,
    )) {
      return OperationResult(
        plan: confirmedPlan,
        success: false,
        message: 'Developer Safe Mode blocked this operation.',
      );
    }
    final destination = confirmedPlan.destination;
    if (destination == null ||
        confirmedPlan.operationType == OperationType.deleteToTrash) {
      return OperationResult(
        plan: confirmedPlan,
        success: false,
        message: 'Only test-root move and rename are supported.',
      );
    }

    final executing = confirmedPlan.transitionTo(OperationStatus.executing);
    try {
      final paths = await _validatedPaths(
        confirmedPlan.source,
        destination,
        requireSource: true,
      );
      if (await FileSystemEntity.type(paths.destination) !=
          FileSystemEntityType.notFound) {
        throw FileSystemException('The destination already exists.');
      }
      await File(paths.source).rename(paths.destination);
      return OperationResult(
        plan: executing.transitionTo(OperationStatus.completed),
        success: true,
        message: 'Synthetic test operation completed.',
      );
    } on FileSystemException {
      return OperationResult(
        plan: executing.transitionTo(OperationStatus.failed),
        success: false,
        message: 'Synthetic test operation failed without overwriting data.',
      );
    }
  }

  @override
  Future<OperationResult> undo(OperationPlan completedPlan) async {
    if (completedPlan.status != OperationStatus.completed ||
        completedPlan.destination == null ||
        completedPlan.rollbackMetadata['strategy'] != 'rename-back') {
      return OperationResult(
        plan: completedPlan,
        success: false,
        message: 'This operation has no valid undo plan.',
      );
    }
    try {
      final paths = await _validatedPaths(
        completedPlan.destination!,
        completedPlan.source,
        requireSource: true,
      );
      if (await FileSystemEntity.type(paths.destination) !=
          FileSystemEntityType.notFound) {
        throw FileSystemException('The original location is occupied.');
      }
      await File(paths.source).rename(paths.destination);
      return OperationResult(
        plan: completedPlan.transitionTo(OperationStatus.undone),
        success: true,
        message: 'Synthetic test operation was undone.',
      );
    } on FileSystemException {
      return OperationResult(
        plan: completedPlan,
        success: false,
        message: 'Undo stopped without overwriting data.',
      );
    }
  }

  Future<({String source, String destination})> _validatedPaths(
    FileLocator source,
    FileLocator destination, {
    required bool requireSource,
  }) async {
    if (!testMutationAuthorized ||
        source.sourceKind != SourceKind.synthetic ||
        destination.sourceKind != SourceKind.synthetic ||
        source.platform != PickLogicPlatform.synthetic ||
        destination.platform != PickLogicPlatform.synthetic) {
      throw FileSystemException(
        'Only an authorized synthetic root is mutable.',
      );
    }
    final root = await _authorizedRoot.resolveSymbolicLinks();
    final sourceFile = File(source.value);
    if (requireSource && !await sourceFile.exists()) {
      throw FileSystemException('The synthetic source is unavailable.');
    }
    final resolvedSource = await sourceFile.resolveSymbolicLinks();
    final destinationFile = File(destination.value).absolute;
    final destinationParent = destinationFile.parent;
    final resolvedParent = await destinationParent.resolveSymbolicLinks();
    final resolvedDestination = _join(
      resolvedParent,
      _basename(destinationFile.path),
    );
    if (!_isWithin(root, resolvedSource) ||
        !_isWithin(root, resolvedDestination)) {
      throw FileSystemException('The operation escapes its authorized root.');
    }
    return (source: resolvedSource, destination: resolvedDestination);
  }
}

OperationPlan _copyPlan(
  OperationPlan plan, {
  required OperationStatus status,
  required Map<String, String> rollbackMetadata,
}) => OperationPlan(
  operationId: plan.operationId,
  operationType: plan.operationType,
  source: plan.source,
  destination: plan.destination,
  preview: plan.preview,
  warnings: plan.warnings,
  rollbackMetadata: Map<String, String>.unmodifiable(rollbackMetadata),
  status: status,
);

String _normalized(String path) {
  final value = File(
    path,
  ).absolute.path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
  return Platform.isWindows ? value.toLowerCase() : value;
}

bool _isWithin(String root, String candidate) {
  final normalizedRoot = _normalized(root);
  final normalizedCandidate = _normalized(candidate);
  return normalizedCandidate == normalizedRoot ||
      normalizedCandidate.startsWith('$normalizedRoot/');
}

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}

String _join(String parent, String name) =>
    '$parent${Platform.pathSeparator}$name';
