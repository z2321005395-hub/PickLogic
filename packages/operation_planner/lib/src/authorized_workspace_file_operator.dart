import 'dart:io';

import 'package:picklogic_core_models/picklogic_core_models.dart';

import 'operation_planner.dart';

/// Executes only pre-confirmed operations whose source and destination remain
/// inside one exact user-authorized root.
///
/// Delete is implemented as a reversible move into [trashDirectory]. Nothing
/// is overwritten, links cannot escape the root, and the original path is kept
/// as rollback metadata.
final class AuthorizedWorkspaceFileOperator implements FileOperator {
  AuthorizedWorkspaceFileOperator({
    required Directory authorizedRoot,
    required Directory trashDirectory,
  }) : _authorizedRoot = authorizedRoot.absolute,
       _trashDirectory = trashDirectory.absolute;

  final Directory _authorizedRoot;
  final Directory _trashDirectory;
  final SafeOperationGate _gate = const SafeOperationGate(
    DeveloperSafeMode.on(),
  );

  @override
  Future<OperationPlan> preview(OperationPlan plan) async {
    if (plan.status != OperationStatus.planned) {
      throw StateError('Only a newly planned operation can be previewed.');
    }
    final source = await _resolveExisting(plan.source.value);
    String destination;
    if (plan.operationType == OperationType.deleteToTrash) {
      await _ensureTrashDirectory();
      destination = await _uniqueTrashPath(_basename(source));
    } else {
      final locator = plan.destination;
      if (locator == null) throw StateError('A destination is required.');
      destination = await _resolveDestination(locator.value);
    }
    await _assertWithinRoot(source);
    await _assertWithinRoot(destination);
    if (_samePath(source, destination)) {
      throw FileSystemException('Source and destination are identical.');
    }
    if (await FileSystemEntity.type(destination) !=
        FileSystemEntityType.notFound) {
      throw FileSystemException('The destination already exists.');
    }
    return _copyPlan(
      plan,
      destination: FileLocator(
        value: destination,
        sourceKind: plan.source.sourceKind,
        platform: plan.source.platform,
      ),
      status: OperationStatus.previewed,
      rollbackMetadata: <String, String>{
        'strategy': 'rename-back',
        'originalPath': source,
        'authorizedRoot': _authorizedRoot.path,
      },
    );
  }

  @override
  Future<OperationResult> execute(OperationPlan confirmedPlan) async {
    if (!_gate.mayExecute(
      confirmedPlan,
      syntheticTarget: confirmedPlan.source.sourceKind == SourceKind.synthetic,
      testMutationAuthorized: true,
      userAuthorizedManagedTarget: true,
    )) {
      return OperationResult(
        plan: confirmedPlan,
        success: false,
        message: 'The confirmed plan did not pass the authorized-root gate.',
      );
    }
    final destination = confirmedPlan.destination;
    if (destination == null) {
      return OperationResult(
        plan: confirmedPlan,
        success: false,
        message: 'The confirmed plan has no destination.',
      );
    }
    final executing = confirmedPlan.transitionTo(OperationStatus.executing);
    try {
      final sourcePath = await _resolveExisting(confirmedPlan.source.value);
      final destinationPath = await _resolveDestination(destination.value);
      await _assertWithinRoot(sourcePath);
      await _assertWithinRoot(destinationPath);
      if (await FileSystemEntity.type(destinationPath) !=
          FileSystemEntityType.notFound) {
        throw FileSystemException('The destination already exists.');
      }
      await _renameEntity(sourcePath, destinationPath);
      return OperationResult(
        plan: executing.transitionTo(OperationStatus.completed),
        success: true,
        message: 'Authorized workspace operation completed.',
      );
    } on FileSystemException {
      return OperationResult(
        plan: executing.transitionTo(OperationStatus.failed),
        success: false,
        message: 'The operation stopped without overwriting another item.',
      );
    }
  }

  @override
  Future<OperationResult> undo(OperationPlan completedPlan) async {
    final destination = completedPlan.destination;
    final originalPath = completedPlan.rollbackMetadata['originalPath'];
    if (completedPlan.status != OperationStatus.completed ||
        destination == null ||
        originalPath == null ||
        completedPlan.rollbackMetadata['strategy'] != 'rename-back') {
      return OperationResult(
        plan: completedPlan,
        success: false,
        message: 'This operation has no reversible workspace record.',
      );
    }
    try {
      final sourcePath = await _resolveExisting(destination.value);
      final restorePath = await _resolveDestination(originalPath);
      await _assertWithinRoot(sourcePath);
      await _assertWithinRoot(restorePath);
      if (await FileSystemEntity.type(restorePath) !=
          FileSystemEntityType.notFound) {
        throw FileSystemException('The original path is occupied.');
      }
      await _renameEntity(sourcePath, restorePath);
      return OperationResult(
        plan: completedPlan.transitionTo(OperationStatus.undone),
        success: true,
        message: 'The workspace operation was undone.',
      );
    } on FileSystemException {
      return OperationResult(
        plan: completedPlan,
        success: false,
        message: 'Undo stopped without overwriting another item.',
      );
    }
  }

  Future<void> _ensureTrashDirectory() async {
    final root = await _resolvedRoot();
    final trash = _trashDirectory.absolute.path;
    if (!_isWithin(root, trash)) {
      throw FileSystemException('Trash directory escapes its authorized root.');
    }
    await _trashDirectory.create(recursive: true);
  }

  Future<String> _uniqueTrashPath(String name) async {
    final base = '${DateTime.now().microsecondsSinceEpoch}-$name';
    var candidate = _join(_trashDirectory.path, base);
    var suffix = 1;
    while (await FileSystemEntity.type(candidate) !=
        FileSystemEntityType.notFound) {
      candidate = _join(_trashDirectory.path, '$base-$suffix');
      suffix++;
    }
    return candidate;
  }

  Future<String> _resolvedRoot() async {
    if (!await _authorizedRoot.exists()) {
      throw FileSystemException('The authorized root is unavailable.');
    }
    return _authorizedRoot.resolveSymbolicLinks();
  }

  Future<String> _resolveExisting(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw FileSystemException('The source is unavailable.', path);
    }
    return File(path).resolveSymbolicLinks();
  }

  Future<String> _resolveDestination(String path) async {
    final absolute = File(path).absolute;
    final parent = absolute.parent;
    if (!await parent.exists()) {
      throw FileSystemException('The destination folder is unavailable.', path);
    }
    final resolvedParent = await parent.resolveSymbolicLinks();
    return _join(resolvedParent, _basename(absolute.path));
  }

  Future<void> _assertWithinRoot(String candidate) async {
    final root = await _resolvedRoot();
    if (!_isWithin(root, candidate)) {
      throw FileSystemException('The operation escapes its authorized root.');
    }
  }

  Future<void> _renameEntity(String source, String destination) async {
    final type = await FileSystemEntity.type(source, followLinks: false);
    switch (type) {
      case FileSystemEntityType.file:
        await File(source).rename(destination);
        return;
      case FileSystemEntityType.directory:
        await Directory(source).rename(destination);
        return;
      default:
        throw FileSystemException(
          'Links and special filesystem items are not mutable.',
        );
    }
  }
}

OperationPlan _copyPlan(
  OperationPlan plan, {
  required FileLocator destination,
  required OperationStatus status,
  required Map<String, String> rollbackMetadata,
}) => OperationPlan(
  operationId: plan.operationId,
  operationType: plan.operationType,
  source: plan.source,
  destination: destination,
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

bool _samePath(String left, String right) =>
    _normalized(left) == _normalized(right);

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
