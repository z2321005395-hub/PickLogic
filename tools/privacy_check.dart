import 'dart:convert';
import 'dart:io';

void main() {
  final repoRoot = File.fromUri(Platform.script).absolute.parent.parent;
  final listed = Process.runSync(
    'git',
    ['ls-files', '--cached', '--others', '--exclude-standard', '-z'],
    workingDirectory: repoRoot.path,
    stdoutEncoding: const Utf8Codec(allowMalformed: true),
  );
  if (listed.exitCode != 0) {
    stderr.writeln('PRIVACY_CHECK_FAILED git_inventory=true');
    exitCode = 1;
    return;
  }

  final patterns = <RegExp>[
    RegExp(
      r'C:'
      r'\\Users\\[^\\\r\n\t ]+',
    ),
    RegExp(
      r'C:'
      r'/Users/[^/\r\n\t ]+',
    ),
    RegExp(r'\bgithub_pat_[A-Za-z0-9_]{20,}\b'),
    RegExp(r'\bgh[pousr]_[A-Za-z0-9]{20,}\b'),
    RegExp(r'\bAIza[0-9A-Za-z_-]{30,}\b'),
    RegExp(r'\bsk-[A-Za-z0-9_-]{20,}\b'),
    RegExp(
      r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
      caseSensitive: false,
    ),
    RegExp(r'\badb(?:\.exe)?\s+-s\s+[A-Za-z0-9._:-]{6,}', caseSensitive: false),
    RegExp(
      r'''(?:api[_-]?key|access[_-]?token|client[_-]?secret)\s*[:=]\s*["'][A-Za-z0-9_./+=:-]{12,}["']''',
      caseSensitive: false,
    ),
  ];

  final paths = (listed.stdout as String)
      .split('\u0000')
      .where((path) => path.isNotEmpty);
  final findings = <String>[];

  for (final relativePath in paths) {
    final file = File('${repoRoot.path}${Platform.pathSeparator}$relativePath');
    if (!file.existsSync() || file.lengthSync() > 5 * 1024 * 1024) continue;
    final bytes = file.readAsBytesSync();
    if (bytes.contains(0)) continue;
    final text = utf8.decode(bytes, allowMalformed: true);
    if (patterns.any((pattern) => pattern.hasMatch(text))) {
      findings.add(relativePath.replaceAll('\\', '/'));
    }
  }

  if (findings.isNotEmpty) {
    findings.sort();
    stderr.writeln('PRIVACY_CHECK_FAILED files:');
    for (final path in findings.toSet()) {
      stderr.writeln('- $path');
    }
    stderr.writeln('Matching contents were intentionally not printed.');
    exitCode = 1;
    return;
  }

  stdout.writeln('PRIVACY_CHECK_OK findings=0');
}
