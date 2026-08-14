import 'dart:convert';
import 'dart:io';

import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_operation_planner/picklogic_operation_planner.dart';
import 'package:picklogic_windows_bridge/picklogic_windows_bridge.dart';

enum WorkspaceAccessLevel { browseOnly, managedFolder, testWorkspace }

final class WindowsWorkspaceController {
  WindowsWorkspaceController({
    this.bridge = const PicklogicWindowsBridge(),
    this._planner = const OperationPlanner(),
  });

  static const _folders = <String>[
    'Inbox',
    'Documents',
    'Images',
    'Videos',
    'Audio',
    'PDFs',
    'Archives',
    'Test-Trash',
    'Restore',
  ];

  final PicklogicWindowsBridge bridge;
  final OperationPlanner _planner;
  final Set<String> _managedRoots = <String>{};

  Directory get testRoot {
    final profile = Platform.environment['USERPROFILE'];
    if (profile == null || profile.trim().isEmpty) {
      throw StateError('Windows did not expose the current user profile.');
    }
    return Directory(
      '$profile${Platform.pathSeparator}PickLogic-TestWorkspace',
    );
  }

  File get _managedRootsFile {
    final base =
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
    return File(
      '$base${Platform.pathSeparator}PickLogic${Platform.pathSeparator}managed-roots-v1.json',
    );
  }

  Future<WindowsBrowseRoot> initialize() async {
    await testRoot.create(recursive: true);
    for (final name in _folders) {
      await Directory(_join(testRoot.path, name)).create(recursive: true);
    }
    await _loadManagedRoots();
    return WindowsBrowseRoot(
      id: 'picklogic-test-workspace',
      path: testRoot.path,
      kind: WindowsBrowseRootKind.folder,
    );
  }

  Future<String?> authorizeManagedFolder({required bool chinese}) async {
    final selected = await bridge.pickDirectory(
      title: chinese
          ? '授权一个可整理目录（仅此目录）'
          : 'Authorize one managed folder (this folder only)',
    );
    if (selected == null) return null;
    final directory = Directory(selected);
    if (!await directory.exists()) return null;
    _managedRoots.add(_normalized(directory.absolute.path));
    await _saveManagedRoots();
    return directory.absolute.path;
  }

  WorkspaceAccessLevel accessFor(String? path) {
    if (path == null || path.startsWith('synthetic:')) {
      return WorkspaceAccessLevel.browseOnly;
    }
    final normalized = _normalized(path);
    if (_isWithin(_normalized(testRoot.path), normalized)) {
      return WorkspaceAccessLevel.testWorkspace;
    }
    if (_managedRoots.any((root) => _isWithin(root, normalized))) {
      return WorkspaceAccessLevel.managedFolder;
    }
    return WorkspaceAccessLevel.browseOnly;
  }

  Future<List<String>> importTestCopies({required bool chinese}) async {
    final selected = await bridge.pickFiles(
      title: chinese
          ? '选择少量文件，复制到 PickLogic 测试工作区'
          : 'Choose a few files to copy into the PickLogic Test Workspace',
    );
    if (selected.isEmpty) return const <String>[];
    final inbox = Directory(_join(testRoot.path, 'Inbox'));
    await inbox.create(recursive: true);
    final copied = <String>[];
    final mappings = await _readMappings();
    for (final sourcePath in selected.take(24)) {
      final source = File(sourcePath);
      if (!await source.exists()) continue;
      final destination = await _uniquePath(inbox.path, _basename(source.path));
      await source.copy(destination);
      copied.add(destination);
      mappings.add(<String, String>{
        'source': source.absolute.path,
        'copy': File(destination).absolute.path,
        'importedAt': DateTime.now().toUtc().toIso8601String(),
      });
    }
    await _writeMappings(mappings);
    return List<String>.unmodifiable(copied);
  }

  Future<void> createFolder(String parentPath, String name) async {
    final root = _authorizedRootFor(parentPath);
    if (root == null) {
      throw FileSystemException('This location is browse-only.', parentPath);
    }
    final safeName = name.trim();
    if (safeName.isEmpty ||
        safeName == '.' ||
        safeName == '..' ||
        safeName.contains('/') ||
        safeName.contains('\\')) {
      throw const FileSystemException(
        'A single valid folder name is required.',
      );
    }
    final destination = _join(parentPath, safeName);
    if (!_isWithin(root, _normalized(destination))) {
      throw FileSystemException('The folder would escape its authorized root.');
    }
    if (await FileSystemEntity.type(destination) !=
        FileSystemEntityType.notFound) {
      throw FileSystemException('An item with this name already exists.');
    }
    await Directory(destination).create();
  }

  Future<OperationPlan> previewRename(String sourcePath, String newName) async {
    final safeName = newName.trim();
    if (safeName.isEmpty || safeName.contains('/') || safeName.contains('\\')) {
      throw const FileSystemException('A single valid name is required.');
    }
    final destination = _join(File(sourcePath).parent.path, safeName);
    final plan = _planner.planRename(
      operationId: _operationId('rename'),
      source: _locator(sourcePath),
      destination: _locator(destination),
    );
    return _operatorFor(sourcePath).preview(plan);
  }

  Future<OperationPlan> previewMove(
    String sourcePath,
    String destinationDirectory,
  ) async {
    final plan = _planner.planMove(
      operationId: _operationId('move'),
      source: _locator(sourcePath),
      destination: _locator(_join(destinationDirectory, _basename(sourcePath))),
    );
    return _operatorFor(sourcePath).preview(plan);
  }

  Future<OperationPlan> previewDelete(String sourcePath) async {
    if (accessFor(sourcePath) == WorkspaceAccessLevel.testWorkspace) {
      return _operatorFor(sourcePath).preview(
        _planner.planDeleteToTrash(
          operationId: _operationId('trash'),
          source: _locator(sourcePath),
          warnings: const <String>[
            'The test copy will move to reversible Test-Trash.',
          ],
        ),
      );
    }
    final root = _authorizedRootFor(sourcePath);
    if (root == null ||
        accessFor(sourcePath) != WorkspaceAccessLevel.managedFolder) {
      throw FileSystemException('This location is browse-only.', sourcePath);
    }
    final resolvedRoot = await Directory(root).resolveSymbolicLinks();
    final type = await FileSystemEntity.type(sourcePath, followLinks: false);
    final resolvedSource = switch (type) {
      FileSystemEntityType.file => await File(
        sourcePath,
      ).resolveSymbolicLinks(),
      FileSystemEntityType.directory => await Directory(
        sourcePath,
      ).resolveSymbolicLinks(),
      _ => throw FileSystemException(
        'Links and special filesystem items are not mutable.',
        sourcePath,
      ),
    };
    if (!_isWithin(_normalized(resolvedRoot), _normalized(resolvedSource)) ||
        _samePath(resolvedRoot, resolvedSource)) {
      throw FileSystemException(
        'The operation is outside the authorized folder or targets its root.',
        sourcePath,
      );
    }
    final planned = _planner.planDeleteToTrash(
      operationId: _operationId('trash'),
      source: _locator(resolvedSource),
      warnings: const <String>[
        'Windows will move this item to the system Recycle Bin.',
        'In-app Undo is available during this session when Windows returns a recycle record.',
      ],
    );
    return OperationPlan(
      operationId: planned.operationId,
      operationType: planned.operationType,
      source: planned.source,
      destination: planned.destination,
      preview: planned.preview,
      warnings: planned.warnings,
      rollbackMetadata: <String, String>{
        'strategy': 'windows-recycle-bin',
        'originalPath': resolvedSource,
        'authorizedRoot': resolvedRoot,
      },
      status: OperationStatus.previewed,
    );
  }

  Future<OperationResult> execute(OperationPlan confirmedPlan) async {
    if (confirmedPlan.rollbackMetadata['strategy'] != 'windows-recycle-bin') {
      return _operatorFromPlan(confirmedPlan).execute(confirmedPlan);
    }
    if (confirmedPlan.status != OperationStatus.confirmed ||
        accessFor(confirmedPlan.source.value) !=
            WorkspaceAccessLevel.managedFolder) {
      return OperationResult(
        plan: confirmedPlan,
        success: false,
        message: 'The managed-folder authorization is no longer active.',
      );
    }
    final executing = confirmedPlan.transitionTo(OperationStatus.executing);
    try {
      final recycled = await bridge.recycleItem(
        confirmedPlan.source.value,
        operationId: confirmedPlan.operationId,
      );
      final metadata = <String, String>{
        ...confirmedPlan.rollbackMetadata,
        'nativeUndoAvailable': recycled.undoAvailable.toString(),
      };
      return OperationResult(
        plan: _copyOperationPlan(
          executing,
          status: recycled.recycled
              ? OperationStatus.completed
              : OperationStatus.failed,
          rollbackMetadata: metadata,
        ),
        success: recycled.recycled,
        message: recycled.recycled
            ? recycled.undoAvailable
                  ? 'Moved to the Windows Recycle Bin; in-app Undo is available this session.'
                  : 'Moved to the Windows Recycle Bin; restore it with Windows Explorer.'
            : 'Windows did not move the item to the Recycle Bin.',
      );
    } on Object {
      return OperationResult(
        plan: _copyOperationPlan(
          executing,
          status: OperationStatus.failed,
          rollbackMetadata: confirmedPlan.rollbackMetadata,
        ),
        success: false,
        message: 'Windows did not move the item to the Recycle Bin.',
      );
    }
  }

  Future<OperationResult> undo(OperationPlan completedPlan) async {
    if (completedPlan.rollbackMetadata['strategy'] != 'windows-recycle-bin') {
      return _operatorFromPlan(completedPlan).undo(completedPlan);
    }
    if (completedPlan.status != OperationStatus.completed ||
        completedPlan.rollbackMetadata['nativeUndoAvailable'] != 'true') {
      return OperationResult(
        plan: completedPlan,
        success: false,
        message: 'Restore this item from the Windows Recycle Bin.',
      );
    }
    final restored = await bridge.restoreRecycledItem(
      completedPlan.operationId,
    );
    return OperationResult(
      plan: restored
          ? completedPlan.transitionTo(OperationStatus.undone)
          : completedPlan,
      success: restored,
      message: restored
          ? 'The recycled item was restored.'
          : 'Undo stopped because Windows could not safely restore the item.',
    );
  }

  AuthorizedWorkspaceFileOperator _operatorFor(String path) {
    final root = _authorizedRootFor(path);
    if (root == null) {
      throw FileSystemException('This location is browse-only.', path);
    }
    final test = _samePath(root, _normalized(testRoot.path));
    return AuthorizedWorkspaceFileOperator(
      authorizedRoot: Directory(root),
      trashDirectory: Directory(
        _join(root, test ? 'Test-Trash' : '.PickLogic-Trash'),
      ),
    );
  }

  AuthorizedWorkspaceFileOperator _operatorFromPlan(OperationPlan plan) {
    final root = plan.rollbackMetadata['authorizedRoot'];
    if (root == null || _authorizedRootFor(root) == null) {
      throw FileSystemException(
        'The operation authorization is no longer active.',
      );
    }
    final test = _samePath(root, _normalized(testRoot.path));
    return AuthorizedWorkspaceFileOperator(
      authorizedRoot: Directory(root),
      trashDirectory: Directory(
        _join(root, test ? 'Test-Trash' : '.PickLogic-Trash'),
      ),
    );
  }

  String? _authorizedRootFor(String path) {
    final normalized = _normalized(path);
    final test = _normalized(testRoot.path);
    if (_isWithin(test, normalized)) return test;
    return _managedRoots
        .where((root) => _isWithin(root, normalized))
        .toList(growable: false)
        .firstOrNull;
  }

  Future<void> _loadManagedRoots() async {
    try {
      if (!await _managedRootsFile.exists()) return;
      final raw = jsonDecode(await _managedRootsFile.readAsString());
      for (final path in (raw as List<Object?>).whereType<String>()) {
        if (await Directory(path).exists()) {
          _managedRoots.add(_normalized(path));
        }
      }
    } on Object {
      _managedRoots.clear();
    }
  }

  Future<void> _saveManagedRoots() async {
    await _managedRootsFile.parent.create(recursive: true);
    await _managedRootsFile.writeAsString(jsonEncode(_managedRoots.toList()));
  }

  File get _mappingFile =>
      File(_join(testRoot.path, '.picklogic-import-map.json'));

  Future<List<Map<String, String>>> _readMappings() async {
    try {
      if (!await _mappingFile.exists()) return <Map<String, String>>[];
      final raw =
          jsonDecode(await _mappingFile.readAsString()) as List<Object?>;
      return raw
          .whereType<Map<String, Object?>>()
          .map(
            (value) =>
                value.map((key, item) => MapEntry(key, item?.toString() ?? '')),
          )
          .toList();
    } on Object {
      return <Map<String, String>>[];
    }
  }

  Future<void> _writeMappings(List<Map<String, String>> mappings) async {
    await _mappingFile.writeAsString(jsonEncode(mappings), flush: true);
  }

  Future<String> _uniquePath(String directory, String name) async {
    var candidate = _join(directory, name);
    final dot = name.lastIndexOf('.');
    final stem = dot <= 0 ? name : name.substring(0, dot);
    final suffix = dot <= 0 ? '' : name.substring(dot);
    var counter = 2;
    while (await FileSystemEntity.type(candidate) !=
        FileSystemEntityType.notFound) {
      candidate = _join(directory, '$stem ($counter)$suffix');
      counter++;
    }
    return candidate;
  }
}

FileLocator _locator(String path) => FileLocator(
  value: path,
  sourceKind: SourceKind.fileSystem,
  platform: PickLogicPlatform.windows,
);

String _operationId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}';

String _normalized(String path) {
  final value = File(
    path,
  ).absolute.path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
  return value.toLowerCase();
}

bool _samePath(String left, String right) =>
    _normalized(left) == _normalized(right);

bool _isWithin(String root, String candidate) =>
    candidate == root || candidate.startsWith('$root/');

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}

String _join(String parent, String name) =>
    '$parent${Platform.pathSeparator}$name';

OperationPlan _copyOperationPlan(
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
