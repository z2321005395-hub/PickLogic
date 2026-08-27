import 'dart:io';

import 'native_asset_io.dart';
import 'pdfium_artifact.dart';

Future<void> main(List<String> arguments) async {
  try {
    final spec = hostPdfium;
    final seedFlutterTestRuntime = arguments.contains('--flutter-test-runtime');
    final repoRoot = File.fromUri(Platform.script).absolute.parent.parent.path;
    final target = File(
      joinPath(
        joinPath(repoRoot, '.dart_tool', 'hooks_runner'),
        'shared${Platform.pathSeparator}pdfium_dart${Platform.pathSeparator}'
        'build${Platform.pathSeparator}chromium_7811${Platform.pathSeparator}'
        '${spec.hookCacheSubdirectory}',
        spec.libraryName,
      ),
    );

    if (target.existsSync()) {
      await verifyFileSha256(
        target,
        spec.librarySha256,
        label: spec.libraryName,
      );
      if (seedFlutterTestRuntime) {
        await _seedFlutterTestRuntime(target, spec);
      }
      stdout.writeln(
        'PDFIUM_NATIVE_ASSET_READY platform=${spec.platform} source=verified-cache',
      );
      return;
    }

    final archive = await resolvePdfiumArchive(
      spec,
      archivePath: _argumentValue(arguments, '--archive'),
    );
    final bytes = await extractPdfiumLibrary(archive, spec);
    target.parent.createSync(recursive: true);
    target.writeAsBytesSync(bytes, flush: true);
    await verifyFileSha256(target, spec.librarySha256, label: spec.libraryName);
    if (seedFlutterTestRuntime) {
      await _seedFlutterTestRuntime(target, spec);
    }
    stdout.writeln(
      'PDFIUM_NATIVE_ASSET_READY platform=${spec.platform} '
      'archive_sha256=${spec.archiveSha256} '
      'library_sha256=${spec.librarySha256}',
    );
  } on Object catch (error) {
    stderr.writeln('PDFIUM_NATIVE_ASSET_FAILED error=$error');
    exitCode = 1;
  }
}

Future<void> _seedFlutterTestRuntime(
  File source,
  PdfiumArtifactSpec spec,
) async {
  if (!Platform.isLinux || spec.platform != linuxPdfium.platform) {
    throw UnsupportedError(
      '--flutter-test-runtime is supported only for Linux Flutter tests.',
    );
  }
  final flutterRoot = _findFlutterRoot();
  final destination = File(
    joinPath(
      flutterRoot.path,
      'bin${Platform.pathSeparator}cache${Platform.pathSeparator}'
      'artifacts${Platform.pathSeparator}engine${Platform.pathSeparator}'
      'linux-x64${Platform.pathSeparator}lib',
      spec.libraryName,
    ),
  );
  destination.parent.createSync(recursive: true);
  if (!destination.existsSync()) {
    source.copySync(destination.path);
  }
  await verifyFileSha256(
    destination,
    spec.librarySha256,
    label: 'Flutter test ${spec.libraryName}',
  );
  stdout.writeln('PDFIUM_FLUTTER_TEST_RUNTIME_READY platform=${spec.platform}');
}

Directory _findFlutterRoot() {
  final configured = Platform.environment['FLUTTER_ROOT'];
  if (configured != null && configured.trim().isNotEmpty) {
    final directory = Directory(configured);
    if (File(joinPath(directory.path, 'bin', 'flutter')).existsSync()) {
      return directory;
    }
  }
  var directory = File(Platform.resolvedExecutable).absolute.parent;
  while (true) {
    if (File(joinPath(directory.path, 'bin', 'flutter')).existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  throw StateError('Flutter SDK root could not be resolved for test seeding.');
}

String? _argumentValue(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  if (index == -1) return null;
  if (index + 1 >= arguments.length || arguments[index + 1].startsWith('--')) {
    throw FormatException('Missing value for $name.');
  }
  return arguments[index + 1];
}
