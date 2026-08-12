import 'dart:io';

typedef _TestCommand = ({
  String label,
  String executable,
  List<String> args,
  String cwd,
});

void main(List<String> arguments) {
  if (arguments.length != 1 ||
      !const {'quick', 'remaining'}.contains(arguments.single)) {
    stderr.writeln(
      'Usage: dart run tools/run_module_tests.dart <quick|remaining>',
    );
    exitCode = 2;
    return;
  }

  final repoRoot = File.fromUri(Platform.script).absolute.parent.parent.path;
  final flutterRoot = Platform.environment['PICKLOGIC_FLUTTER_ROOT'];
  if (flutterRoot == null || flutterRoot.isEmpty) {
    stderr.writeln('TEST_RUNNER_FAILED flutter_root_missing=true');
    exitCode = 1;
    return;
  }
  final suffix = Platform.isWindows ? '.bat' : '';
  final dart =
      '$flutterRoot${Platform.pathSeparator}bin${Platform.pathSeparator}dart$suffix';
  final flutter =
      '$flutterRoot${Platform.pathSeparator}bin${Platform.pathSeparator}flutter$suffix';
  final commands = arguments.single == 'quick'
      ? _quickCommands(repoRoot, dart)
      : _remainingCommands(repoRoot, dart, flutter);
  final stopwatch = Stopwatch()..start();

  for (final command in commands) {
    final result = Process.runSync(
      command.executable,
      command.args,
      workingDirectory: command.cwd,
      runInShell: Platform.isWindows,
    );
    if (result.exitCode != 0) {
      stderr.writeln(
        'TEST_MODULE_FAILED label=${command.label} exit=${result.exitCode}',
      );
      if ((result.stdout as String).isNotEmpty) stderr.write(result.stdout);
      if ((result.stderr as String).isNotEmpty) stderr.write(result.stderr);
      exitCode = result.exitCode;
      return;
    }
  }

  stdout.writeln(
    'TEST_MODULES_OK scope=${arguments.single} modules=${commands.length} '
    'elapsed_ms=${stopwatch.elapsedMilliseconds}',
  );
}

List<_TestCommand> _quickCommands(String root, String dart) {
  const packages = <String>[
    'core_models',
    'classification_rules',
    'search_index',
    'duplicate_engine',
    'insight_engine',
    'operation_planner',
    'preview_core',
    'literature_core',
    'research_core',
    'system_insight_core',
  ];
  return <_TestCommand>[
    for (final package in packages)
      (
        label: package,
        executable: dart,
        args: const ['test', '--reporter', 'compact'],
        cwd:
            '$root${Platform.pathSeparator}packages${Platform.pathSeparator}$package',
      ),
    (
      label: 'test_fixtures',
      executable: dart,
      args: const ['test', '--reporter', 'compact'],
      cwd: '$root${Platform.pathSeparator}test_fixtures',
    ),
  ];
}

List<_TestCommand> _remainingCommands(
  String root,
  String dart,
  String flutter,
) => <_TestCommand>[
  (
    label: 'file_index',
    executable: dart,
    args: const ['test', '--reporter', 'compact'],
    cwd:
        '$root${Platform.pathSeparator}packages${Platform.pathSeparator}file_index',
  ),
  for (final path in const <String>[
    'packages/shared_ui',
    'platform/windows_bridge',
    'platform/android_bridge',
    'apps/desktop',
    'apps/mobile',
  ])
    (
      label: path.replaceAll('/', '_'),
      executable: flutter,
      args: const ['test', '--no-pub', '--reporter', 'compact'],
      cwd:
          '$root${Platform.pathSeparator}${path.replaceAll('/', Platform.pathSeparator)}',
    ),
];
