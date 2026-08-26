import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'native_asset_io.dart';

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
}) => resolvePinnedDownload(
  uri: spec.downloadUri,
  cacheFileName: 'picklogic-${spec.archiveName}',
  expectedSha256: spec.archiveSha256,
  label: spec.archiveName,
  retryEvent: 'PDFIUM_DOWNLOAD_RETRY platform=${spec.platform}',
  sourcePath: archivePath,
);

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
