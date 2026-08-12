import 'dart:io';

import 'package:crypto/crypto.dart';

Future<File> resolvePinnedDownload({
  required Uri uri,
  required String cacheFileName,
  required String expectedSha256,
  required String label,
  required String retryEvent,
  String? sourcePath,
}) async {
  if (sourcePath != null) {
    final source = File(sourcePath).absolute;
    await verifyFileSha256(source, expectedSha256, label: label);
    return source;
  }

  final cacheRoot =
      Platform.environment['RUNNER_TEMP'] ?? Directory.systemTemp.path;
  final cached = File(joinPath(cacheRoot, cacheFileName));
  if (cached.existsSync()) {
    await verifyFileSha256(cached, expectedSha256, label: label);
    return cached;
  }

  Object? lastError;
  const maxAttempts = 6;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    final partial = File('${cached.path}.partial');
    if (partial.existsSync()) partial.deleteSync();
    try {
      await _download(uri, partial, label: label);
      await verifyFileSha256(partial, expectedSha256, label: label);
      partial.renameSync(cached.path);
      return cached;
    } on Object catch (error) {
      lastError = error;
      if (partial.existsSync()) partial.deleteSync();
      if (attempt < maxAttempts) {
        stderr.writeln('$retryEvent attempt=$attempt');
        await Future<void>.delayed(Duration(seconds: attempt * 10));
      }
    }
  }
  throw StateError(
    '$label download failed after $maxAttempts attempts: $lastError',
  );
}

Future<void> verifyFileSha256(
  File file,
  String expected, {
  required String label,
}) async {
  if (!file.existsSync()) {
    throw FileSystemException('$label does not exist.', file.path);
  }
  final actual = await sha256File(file);
  if (actual != expected) {
    throw StateError('Unexpected $label SHA-256: $actual');
  }
}

Future<String> sha256File(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Future<void> _download(
  Uri uri,
  File destination, {
  required String label,
}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 30)
    ..findProxy = HttpClient.findProxyFromEnvironment;
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        '$label download returned HTTP ${response.statusCode}.',
        uri: uri,
      );
    }
    destination.parent.createSync(recursive: true);
    await response.pipe(destination.openWrite());
  } finally {
    client.close(force: true);
  }
}

String joinPath(String first, String second, [String? third]) =>
    [first, second, ?third].join(Platform.pathSeparator);

String fileBaseName(String path) =>
    path.split(RegExp(r'[/\\]')).where((part) => part.isNotEmpty).last;
