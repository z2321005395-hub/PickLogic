import 'dart:io';

import 'pdfium_artifact.dart';

Future<void> main(List<String> arguments) async {
  try {
    final buildArgument = _argumentValue(arguments, '--build-directory');
    if (buildArgument == null) {
      throw const FormatException('Missing --build-directory.');
    }

    final buildDirectory = Directory(buildArgument).absolute;
    if (!buildDirectory.existsSync()) {
      throw FileSystemException(
        'Build directory does not exist.',
        buildDirectory.path,
      );
    }

    final pdfiumLibraries = buildDirectory
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((file) => fileBaseName(file.path).toLowerCase() == 'pdfium.dll')
        .toList(growable: false);
    if (pdfiumLibraries.isEmpty) {
      stdout.writeln('PDFIUM_NOTICE_PACKAGE_SKIPPED reason=no_pdfium_dll');
      return;
    }
    if (pdfiumLibraries.length != 1) {
      throw StateError(
        'Expected exactly one pdfium.dll; found ${pdfiumLibraries.length}.',
      );
    }

    await verifyFileSha256(
      pdfiumLibraries.single,
      windowsPdfium.librarySha256,
      label: windowsPdfium.libraryName,
    );
    final archive = await resolvePdfiumArchive(
      windowsPdfium,
      archivePath: _argumentValue(arguments, '--archive'),
    );

    final noticeRoot = Directory(
      joinPath(buildDirectory.path, 'third_party', 'pdfium'),
    )..createSync(recursive: true);
    final extraction = await Process.run('tar', [
      '-xzf',
      archive.path,
      '-C',
      noticeRoot.path,
      'LICENSE',
      'VERSION',
      'licenses',
    ], runInShell: Platform.isWindows);
    if (extraction.exitCode != 0) {
      throw ProcessException(
        'tar',
        const ['-xzf', '<archive>', '-C', '<notice-root>'],
        '${extraction.stdout}${extraction.stderr}',
        extraction.exitCode,
      );
    }

    final rootLicense = File(joinPath(noticeRoot.path, 'LICENSE'));
    final licenseDirectory = Directory(joinPath(noticeRoot.path, 'licenses'));
    final licenseFiles = <File>[
      rootLicense,
      ...licenseDirectory.listSync().whereType<File>(),
    ];
    if (licenseFiles.length != 16) {
      throw StateError(
        'Expected 16 PDFium license files; found ${licenseFiles.length}.',
      );
    }

    final provenance = File(
      joinPath(noticeRoot.path, 'PICKLOGIC_PDFIUM_PROVENANCE.txt'),
    );
    provenance.writeAsStringSync(
      [
        'PickLogic PDFium binary provenance',
        'Source release: bblanchon/pdfium-binaries chromium/7811',
        'Source archive: ${windowsPdfium.downloadUri}',
        'Archive SHA-256: ${windowsPdfium.archiveSha256}',
        'pdfium.dll SHA-256: ${windowsPdfium.librarySha256}',
        'PDFium version: 149.0.7811.0',
        'The LICENSE file and licenses directory are copied unchanged from '
            'the pinned source archive.',
        '',
      ].join('\n'),
    );

    final noticeBytes = noticeRoot
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .fold<int>(0, (total, file) => total + file.lengthSync());
    stdout.writeln(
      'PDFIUM_NOTICE_PACKAGE_OK '
      'dll_sha256=${windowsPdfium.librarySha256} '
      'license_files=${licenseFiles.length} '
      'notice_bytes=$noticeBytes',
    );
  } on Object catch (error) {
    stderr.writeln('PDFIUM_NOTICE_PACKAGE_FAILED error=$error');
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
