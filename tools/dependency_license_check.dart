import 'dart:convert';
import 'dart:io';

const _licenseNames = <String>[
  'LICENSE',
  'LICENSE.txt',
  'LICENSE.md',
  'COPYING',
  'COPYING.txt',
  'NOTICE',
];

void main() {
  final scriptFile = File.fromUri(Platform.script).absolute;
  final repoRoot = scriptFile.parent.parent;
  final packageConfig = File(
    '${repoRoot.path}${Platform.pathSeparator}.dart_tool${Platform.pathSeparator}package_config.json',
  );
  if (!packageConfig.existsSync()) {
    stderr.writeln(
      'DEPENDENCY_LICENSE_CHECK_FAILED package_config_missing=true; run flutter pub get first',
    );
    exitCode = 1;
    return;
  }

  final configUri = packageConfig.uri;
  final json =
      jsonDecode(packageConfig.readAsStringSync()) as Map<String, Object?>;
  final packageEntries = json['packages']! as List<Object?>;
  final repoPrefix = _normalized(repoRoot.path);
  final reviewed = <String>[];
  final sdkReviewed = <String>[];
  final missing = <String>[];
  final restricted = <String>[];
  final unknown = <String>[];

  for (final rawEntry in packageEntries) {
    final entry = rawEntry! as Map<String, Object?>;
    final name = entry['name']! as String;
    final rawRootUri = Uri.parse(entry['rootUri']! as String);
    final rootUri = rawRootUri.hasScheme
        ? rawRootUri
        : configUri.resolveUri(rawRootUri);
    if (rootUri.scheme != 'file') {
      unknown.add(name);
      continue;
    }

    final packageRoot = Directory.fromUri(rootUri).absolute;
    if (_normalized(packageRoot.path).startsWith(repoPrefix)) {
      continue;
    }

    final flutterSdkLicense = _findFlutterSdkLicense(packageRoot);
    if (flutterSdkLicense != null) {
      final sdkText = flutterSdkLicense.readAsStringSync().trim();
      if (sdkText.isEmpty || !_isRecognizedLicense(sdkText)) {
        unknown.add(name);
      } else {
        sdkReviewed.add(name);
      }
      continue;
    }

    final licenseFile = _findLicense(packageRoot);
    if (licenseFile == null) {
      missing.add(name);
      continue;
    }

    final text = licenseFile.readAsStringSync().trim();
    if (text.isEmpty ||
        RegExp(r'\bTODO\b', caseSensitive: false).hasMatch(text)) {
      missing.add(name);
      continue;
    }

    if (_isStrongCopyleft(text)) {
      restricted.add(name);
      continue;
    }

    if (!_isRecognizedLicense(text)) {
      unknown.add(name);
      continue;
    }
    reviewed.add(name);
  }

  if (missing.isNotEmpty || restricted.isNotEmpty || unknown.isNotEmpty) {
    stderr.writeln(
      'DEPENDENCY_LICENSE_CHECK_FAILED reviewed=${reviewed.length} '
      'sdk=${sdkReviewed.length} '
      'missing=${missing.length} restricted=${restricted.length} unknown=${unknown.length}',
    );
    if (missing.isNotEmpty) stderr.writeln('missing: ${missing..sort()}');
    if (restricted.isNotEmpty) {
      stderr.writeln('restricted: ${restricted..sort()}');
    }
    if (unknown.isNotEmpty) stderr.writeln('unknown: ${unknown..sort()}');
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'DEPENDENCY_LICENSE_CHECK_OK external_packages=${reviewed.length} '
    'flutter_sdk_packages=${sdkReviewed.length} '
    'missing=0 restricted=0 unknown=0',
  );
}

File? _findLicense(Directory root) {
  for (final name in _licenseNames) {
    final candidate = File('${root.path}${Platform.pathSeparator}$name');
    if (candidate.existsSync()) return candidate;
  }
  return null;
}

File? _findFlutterSdkLicense(Directory packageRoot) {
  var current = packageRoot.absolute;
  for (var depth = 0; depth < 7; depth++) {
    final windowsLauncher = File(
      '${current.path}${Platform.pathSeparator}bin${Platform.pathSeparator}flutter.bat',
    );
    final posixLauncher = File(
      '${current.path}${Platform.pathSeparator}bin${Platform.pathSeparator}flutter',
    );
    final license = File('${current.path}${Platform.pathSeparator}LICENSE');
    if ((windowsLauncher.existsSync() || posixLauncher.existsSync()) &&
        license.existsSync()) {
      return license;
    }
    final parent = current.parent;
    if (parent.path == current.path) return null;
    current = parent;
  }
  return null;
}

bool _isStrongCopyleft(String text) {
  final lower = text.toLowerCase();
  return lower.contains('gnu affero general public license') ||
      lower.contains('gnu general public license') ||
      lower.contains('gnu lesser general public license');
}

bool _isRecognizedLicense(String text) {
  final lower = text.toLowerCase();
  return <String>[
    'apache license',
    'bsd license',
    'redistribution and use in source and binary forms',
    'mit license',
    'permission is hereby granted, free of charge',
    'mozilla public license',
    'isc license',
    'the unlicense',
    'public domain',
    'zlib',
    'eclipse public license',
  ].any(lower.contains);
}

String _normalized(String path) =>
    path.replaceAll('\\', '/').toLowerCase().replaceAll(RegExp(r'/+$'), '/');
