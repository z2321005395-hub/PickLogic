import 'dart:io';

import 'pdfium_artifact.dart';

Future<void> main(List<String> arguments) async {
  try {
    final spec = hostPdfium;
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

String? _argumentValue(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  if (index == -1) return null;
  if (index + 1 >= arguments.length || arguments[index + 1].startsWith('--')) {
    throw FormatException('Missing value for $name.');
  }
  return arguments[index + 1];
}
