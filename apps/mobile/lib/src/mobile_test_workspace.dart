import 'dart:async';

import 'package:flutter/material.dart';
import 'package:picklogic_android_bridge/picklogic_android_bridge.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_operation_planner/picklogic_operation_planner.dart';

import 'mobile_localizations.dart';
import 'mobile_repository.dart';

final class MobileTestWorkspacePage extends StatefulWidget {
  const MobileTestWorkspacePage({super.key, required this.repository});

  final MobileRepository repository;

  @override
  State<MobileTestWorkspacePage> createState() =>
      _MobileTestWorkspacePageState();
}

final class _MobileTestWorkspacePageState
    extends State<MobileTestWorkspacePage> {
  late Future<AndroidWorkspaceState> _loading;
  AndroidWorkspaceState? _state;
  OperationPlan? _lastPlan;
  String? _lastNativeOperationId;

  bool get _zh => MobileLocalizations.of(context).locale.languageCode == 'zh';

  @override
  void initState() {
    super.initState();
    _loading = _refresh();
  }

  Future<AndroidWorkspaceState> _refresh() async {
    final value = await widget.repository.loadTestWorkspace();
    if (mounted) setState(() => _state = value);
    return value;
  }

  void _replace(AndroidWorkspaceState state) {
    setState(() {
      _state = state;
      _loading = Future<AndroidWorkspaceState>.value(state);
      _lastNativeOperationId = state.operationId ?? _lastNativeOperationId;
    });
  }

  Future<void> _run(Future<AndroidWorkspaceState?> Function() action) async {
    try {
      final next = await action();
      if (mounted && next != null) _replace(next);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<String?> _askName(String title, {String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 160,
          decoration: InputDecoration(labelText: _zh ? '名称' : 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_zh ? '取消' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(_zh ? '继续' : 'Continue'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value?.trim().isEmpty == true ? null : value;
  }

  Future<bool> _confirm(OperationPlan plan) async {
    final previewed = plan.transitionTo(OperationStatus.previewed);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_zh ? '操作预览' : 'Operation preview'),
        content: Text(previewed.preview),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_zh ? '取消' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_zh ? '确认' : 'Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    _lastPlan = previewed.transitionTo(OperationStatus.confirmed);
    return true;
  }

  FileLocator _locator(String value) => FileLocator(
    value: value,
    sourceKind: SourceKind.storageAccessFramework,
    platform: PickLogicPlatform.android,
  );

  Future<void> _createFolder() async {
    final name = await _askName(_zh ? '新建文件夹' : 'New folder');
    if (name == null) return;
    await _run(() => widget.repository.createTestFolder(name));
  }

  Future<void> _rename(AndroidWorkspaceEntry entry) async {
    final name = await _askName(
      _zh ? '重命名' : 'Rename',
      initial: entry.displayName,
    );
    if (name == null || name == entry.displayName) return;
    final plan = const OperationPlanner().planRename(
      operationId: 'android-rename-${DateTime.now().microsecondsSinceEpoch}',
      source: _locator(entry.documentUri),
      destination: _locator('${entry.parentUri}/$name'),
    );
    if (!await _confirm(plan)) return;
    await _execute(() => widget.repository.renameTestItem(entry, name));
  }

  Future<void> _move(AndroidWorkspaceEntry entry) async {
    final directories = (_state?.entries ?? const <AndroidWorkspaceEntry>[])
        .where(
          (candidate) =>
              candidate.directory &&
              candidate.documentUri != entry.documentUri &&
              candidate.displayName != 'Test-Trash',
        )
        .toList(growable: false);
    final target = await showDialog<AndroidWorkspaceEntry>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(_zh ? '移动到' : 'Move to'),
        children: [
          for (final directory in directories)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, directory),
              child: Text(directory.displayName),
            ),
        ],
      ),
    );
    if (target == null || target.documentUri == entry.parentUri) return;
    final plan = const OperationPlanner().planMove(
      operationId: 'android-move-${DateTime.now().microsecondsSinceEpoch}',
      source: _locator(entry.documentUri),
      destination: _locator(target.documentUri),
    );
    if (!await _confirm(plan)) return;
    await _execute(
      () => widget.repository.moveTestItem(entry, target.documentUri),
    );
  }

  Future<void> _trash(AndroidWorkspaceEntry entry) async {
    final plan = const OperationPlanner().planDeleteToTrash(
      operationId: 'android-trash-${DateTime.now().microsecondsSinceEpoch}',
      source: _locator(entry.documentUri),
      warnings: <String>['Moves only to PickLogic Test-Trash.'],
    );
    if (!await _confirm(plan)) return;
    await _execute(() => widget.repository.trashTestItem(entry));
  }

  Future<void> _execute(Future<AndroidWorkspaceState> Function() action) async {
    final confirmed = _lastPlan;
    if (confirmed == null || confirmed.status != OperationStatus.confirmed) {
      return;
    }
    setState(
      () => _lastPlan = confirmed.transitionTo(OperationStatus.executing),
    );
    try {
      final state = await action();
      if (!mounted) return;
      _replace(state);
      setState(
        () => _lastPlan = _lastPlan?.transitionTo(OperationStatus.completed),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(
        () => _lastPlan = _lastPlan?.transitionTo(OperationStatus.failed),
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _undo() async {
    await _run(
      () => widget.repository.undoTestOperation(_lastNativeOperationId),
    );
    final completed = _lastPlan;
    if (mounted && completed?.status == OperationStatus.completed) {
      setState(
        () => _lastPlan = completed!.transitionTo(OperationStatus.undone),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_zh ? '测试工作区' : 'Test Workspace'),
      actions: [
        IconButton(
          tooltip: _zh ? '刷新' : 'Refresh',
          onPressed: () => setState(() => _loading = _refresh()),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<AndroidWorkspaceState>(
      future: _loading,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final state = _state ?? snapshot.data!;
        if (!state.authorized) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.folder_special_outlined, size: 64),
                  const SizedBox(height: 16),
                  Text(
                    _zh
                        ? '请在 Android 系统选择器中选择或创建 PickLogic-TestWorkspace。只有该目录会获得读写权限。'
                        : 'Choose or create PickLogic-TestWorkspace in the Android system picker. Only that tree receives read/write access.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const Key('choose-test-workspace'),
                    onPressed: () =>
                        _run(widget.repository.chooseTestWorkspace),
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: Text(_zh ? '选择测试工作区' : 'Choose Test Workspace'),
                  ),
                ],
              ),
            ),
          );
        }
        return Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    FilledButton.tonalIcon(
                      key: const Key('import-test-copies'),
                      onPressed: () => _run(widget.repository.importTestCopies),
                      icon: const Icon(Icons.copy_all_outlined),
                      label: Text(_zh ? '导入测试副本' : 'Import test copies'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _createFolder,
                      icon: const Icon(Icons.create_new_folder_outlined),
                      label: Text(_zh ? '新建文件夹' : 'New folder'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: state.undoAvailable ? _undo : null,
                      icon: const Icon(Icons.undo),
                      label: Text(_zh ? '撤销' : 'Undo'),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: state.entries.length,
                itemBuilder: (context, index) {
                  final entry = state.entries[index];
                  final protectedDirectory =
                      entry.directory &&
                      const <String>{
                        'Inbox',
                        'Documents',
                        'Images',
                        'Videos',
                        'Audio',
                        'PDFs',
                        'Archives',
                        'Test-Trash',
                        'Restore',
                      }.contains(entry.displayName);
                  return Padding(
                    padding: EdgeInsets.only(left: entry.depth * 16.0),
                    child: ListTile(
                      leading: Icon(
                        entry.directory
                            ? Icons.folder_outlined
                            : Icons.insert_drive_file_outlined,
                      ),
                      title: Text(
                        entry.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        entry.directory
                            ? (_zh ? '测试工作区目录' : 'Workspace folder')
                            : '${entry.mimeType} · ${entry.sizeBytes} B',
                      ),
                      trailing: protectedDirectory
                          ? null
                          : PopupMenuButton<String>(
                              onSelected: (value) => switch (value) {
                                'rename' => _rename(entry),
                                'move' => _move(entry),
                                'trash' => _trash(entry),
                                _ => Future<void>.value(),
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'rename',
                                  child: Text(_zh ? '重命名' : 'Rename'),
                                ),
                                PopupMenuItem(
                                  value: 'move',
                                  child: Text(_zh ? '移动' : 'Move'),
                                ),
                                PopupMenuItem(
                                  value: 'trash',
                                  child: Text(
                                    _zh ? '移到测试回收站' : 'Move to Test-Trash',
                                  ),
                                ),
                              ],
                            ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    ),
  );
}
