import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

final class PdfiumArtifactSpec {
  const PdfiumArtifactSpec({
    required this.platform,
    required this.archiveName,
    required this.archiveSha256,
    required this.libraryName,
    required this.libraryArchivePath,
    required this.librarySha256,
    required this.hookCacheSubdirectory,
  });

  final String platform;
  final String archiveName;
  final String archiveSha256;
  final String libraryName;
  final String libraryArchivePath;
  final String librarySha256;
  final String hookCacheSubdirectory;

  Uri get downloadUri => Uri.parse(
    'https://github.com/bblanchon/pdfium-binaries/releases/download/'
    'chromium/7811/$archiveName',
  );
}

const windowsPdfium = PdfiumArtifactSpec(
  platform: 'windows-x64',
  archiveName: 'pdfium-win-x64.tgz',
  archiveSha256:
      '2e7af12674ac3716cb0e20369bb9fb269ceadfa2f0b0597097a520e6834175a0',
  libraryName: 'pdfium.dll',
  libraryArchivePath: 'bin/pdfium.dll',
  librarySha256:
      '019b6ee6e54e5508002e43c5199b00f6caca26d32dd23c7bb229ff6855cd5394',
  hookCacheSubdirectory: 'win-x64',
);

const linuxPdfium = PdfiumArtifactSpec(
  platform: 'linux-x64',
  archiveName: 'pdfium-linux-x64.tgz',
  archiveSha256:
      'e76e0a37aefb843d56f04657475ce612157021b1ebc53d801f2fbfcc537ccf64',
  libraryName: 'libpdfium.so',
  libraryArchivePath: 'lib/libpdfium.so',
  librarySha256:
      'd106072a29b3689a5d6739948f98a97fe3ec82f5a1c309dc44e86f6c549fb44e',
  hookCacheSubdirectory: 'linux-x64',
);

PdfiumArtifactSpec get hostPdfium =>
    switch ((Platform.isWindows, Platform.isLinux)) {
      (true, false) => windowsPdfium,
      (false, true) => linuxPdfium,
      _ => throw UnsupportedError(
        'The pinned PDFium prefetch supports Windows x64 and Linux x64.',
      ),
    };

Future<File> resolvePdfiumArchive(
  PdfiumArtifactSpec spec, {
  String? archivePath,
}) async {
  if (archivePath != null) {
    final archive = File(archivePath).absolute;
    await verifyFileSha256(
      archive,
      spec.archiveSha256,
      label: spec.archiveName,
    );
    return archive;
  }

  final cacheRoot =
      Platform.environment['RUNNER_TEMP'] ?? Directory.systemTemp.path;
  final archive = File(joinPath(cacheRoot, 'picklogic-${spec.archiveName}'));
  if (archive.existsSync()) {
    await verifyFileSha256(
      archive,
      spec.archiveSha256,
      label: spec.archiveName,
    );
    return archive;
  }

  Object? lastError;
  for (var attempt = 1; attempt <= 3; attempt++) {
    final partial = File('${archive.path}.partial');
    if (partial.existsSync()) partial.deleteSync();
    try {
      await _download(spec.downloadUri, partial);
      await verifyFileSha256(
        partial,
        spec.archiveSha256,
        label: spec.archiveName,
      );
      partial.renameSync(archive.path);
      return archive;
    } on Object catch (error) {
      lastError = error;
      if (partial.existsSync()) partial.deleteSync();
      if (attempt < 3) {
        stderr.writeln(
          'PDFIUM_DOWNLOAD_RETRY platform=${spec.platform} attempt=$attempt',
        );
        await Future<void>.delayed(Duration(seconds: attempt));
      }
    }
  }
  throw StateError(
    'Pinned PDFium download failed after 3 attempts: $lastError',
  );
}

Future<List<int>> extractPdfiumLibrary(
  File archive,
  PdfiumArtifactSpec spec,
) async {
  final result = await Process.run(
    'tar',
    ['-xOzf', archive.path, spec.libraryArchivePath],
    runInShell: Platform.isWindows,
    stdoutEncoding: null,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      'tar',
      ['-xOzf', '<archive>', spec.libraryArchivePath],
      '${result.stderr}',
      result.exitCode,
    );
  }
  final bytes = result.stdout as List<int>;
  final hash = sha256.convert(bytes).toString();
  if (hash != spec.librarySha256) {
    throw StateError('Unexpected ${spec.libraryName} SHA-256: $hash');
  }
  return bytes;
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

Future<void> _download(Uri uri, File destination) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'PDFium download returned HTTP ${response.statusCode}.',
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
