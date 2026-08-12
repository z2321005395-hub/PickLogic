import 'dart:io';

import 'native_asset_io.dart';
import 'sqlite_native_asset.dart';

Future<void> main(List<String> arguments) async {
  try {
    final spec = hostSqlite;
    final repoRoot = File.fromUri(Platform.script).absolute.parent.parent.path;
    final target = File(
      joinPath(
        joinPath(repoRoot, '.dart_tool', 'hooks_runner'),
        'shared${Platform.pathSeparator}sqlite3${Platform.pathSeparator}'
        'build${Platform.pathSeparator}${spec.hookCacheSubdirectory}',
        spec.bundledName,
      ),
    );

    if (target.existsSync()) {
      await verifyFileSha256(target, spec.sha256, label: spec.bundledName);
      stdout.writeln(
        'SQLITE_NATIVE_ASSET_READY platform=${spec.platform} source=verified-cache',
      );
      return;
    }

    final source = await resolvePinnedDownload(
      uri: spec.downloadUri,
      cacheFileName: 'picklogic-${spec.sourceName}',
      expectedSha256: spec.sha256,
      label: spec.sourceName,
      retryEvent: 'SQLITE_DOWNLOAD_RETRY platform=${spec.platform}',
      sourcePath: _argumentValue(arguments, '--asset'),
    );
    target.parent.createSync(recursive: true);
    source.copySync(target.path);
    await verifyFileSha256(target, spec.sha256, label: spec.bundledName);
    stdout.writeln(
      'SQLITE_NATIVE_ASSET_READY platform=${spec.platform} '
      'source_sha256=${spec.sha256}',
    );
  } on Object catch (error) {
    stderr.writeln('SQLITE_NATIVE_ASSET_FAILED error=$error');
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
