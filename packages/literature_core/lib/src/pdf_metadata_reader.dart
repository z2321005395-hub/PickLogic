import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'doi_extractor.dart';

/// A random-access byte source used by the bounded PDF metadata probe.
///
/// Implementations must return at most [length] bytes. The probe never asks
/// the source to load the complete document in one request.
abstract interface class PdfByteSource {
  Future<int> length();

  Future<List<int>> readRange({required int offset, required int length});
}

/// An explicitly constructed local-file source.
///
/// Merely constructing this object performs no I/O. Each requested range is
/// opened read-only and closed immediately after the bounded read.
final class FilePdfByteSource implements PdfByteSource {
  const FilePdfByteSource(this.path);

  final String path;

  @override
  Future<int> length() => File(path).length();

  @override
  Future<List<int>> readRange({
    required int offset,
    required int length,
  }) async {
    if (offset < 0 || length < 0) {
      throw RangeError('PDF byte ranges must be non-negative.');
    }
    if (length == 0) return const <int>[];

    final file = await File(path).open(mode: FileMode.read);
    try {
      await file.setPosition(offset);
      return file.read(length);
    } finally {
      await file.close();
    }
  }
}

final class PdfReadWindow {
  const PdfReadWindow({required this.offset, required this.length});

  final int offset;
  final int length;
}

/// Metadata found without rendering pages or extracting the full document.
final class PdfMetadataProbe {
  const PdfMetadataProbe({
    required this.hasPdfHeader,
    required this.totalBytes,
    required this.bytesRead,
    required this.wasTruncated,
    required this.readWindows,
    this.title,
    this.authors = const <String>[],
    this.subject,
    this.keywords = const <String>[],
    this.doiCandidates = const <String>[],
    this.year,
    this.limitations = const <String>[],
  });

  final bool hasPdfHeader;
  final int totalBytes;
  final int bytesRead;
  final bool wasTruncated;
  final List<PdfReadWindow> readWindows;
  final String? title;
  final List<String> authors;
  final String? subject;
  final List<String> keywords;
  final List<String> doiCandidates;
  final int? year;
  final List<String> limitations;
}

/// A deliberately small PDF metadata/DOI probe.
///
/// It reads bounded head and tail windows in small random-access requests.
/// This is not a PDF renderer or a full-text extractor. Compressed, encrypted,
/// or middle-of-file metadata may be unavailable until a PDF engine passes the
/// separate dependency audit.
final class BoundedPdfMetadataReader {
  const BoundedPdfMetadataReader({
    this.headWindowBytes = 32 * 1024,
    this.tailWindowBytes = 32 * 1024,
    this.maxReadBytes = 4 * 1024,
    this.maxTotalBytes = 64 * 1024,
  });

  final int headWindowBytes;
  final int tailWindowBytes;
  final int maxReadBytes;
  final int maxTotalBytes;

  Future<PdfMetadataProbe> read(PdfByteSource source) async {
    _validateConfiguration();
    final totalBytes = await source.length();
    if (totalBytes < 0) {
      throw StateError('A PDF byte source reported a negative length.');
    }
    final chunkLimit = totalBytes > 1 && totalBytes <= maxReadBytes
        ? math.max(1, totalBytes ~/ 2)
        : maxReadBytes;

    final windows = <PdfReadWindow>[];
    final headLength = math.min(
      totalBytes,
      math.min(headWindowBytes, maxTotalBytes),
    );
    final headBytes = await _readWindow(
      source,
      offset: 0,
      length: headLength,
      chunkLimit: chunkLimit,
      windows: windows,
    );

    final remainingBudget = maxTotalBytes - headBytes.length;
    final tailStart = math.max(headBytes.length, totalBytes - tailWindowBytes);
    final tailLength = math.min(
      math.max(0, totalBytes - tailStart),
      remainingBudget,
    );
    var tailWindowUnavailable = false;
    List<int> tailBytes;
    try {
      tailBytes = await _readWindow(
        source,
        offset: tailStart,
        length: tailLength,
        chunkLimit: chunkLimit,
        windows: windows,
      );
    } on Object {
      tailBytes = const <int>[];
      tailWindowUnavailable = true;
    }

    final bytesRead = headBytes.length + tailBytes.length;
    final headText = latin1.decode(headBytes, allowInvalid: true);
    final tailText = latin1.decode(tailBytes, allowInvalid: true);
    final boundedText = tailText.isEmpty ? headText : '$headText\n$tailText';
    final hasPdfHeader = _hasPdfHeader(headBytes);
    final limitations = <String>[
      'Only bounded byte windows were inspected; no page was rendered.',
      if (bytesRead < totalBytes)
        'The middle of the document was not inspected.',
      if (tailWindowUnavailable)
        'The tail metadata window could not be read; filename fallback remains available.',
      'Compressed or encrypted object streams may hide metadata and DOI text.',
      'A PDF rendering engine remains dependency-audit gated.',
    ];

    if (!hasPdfHeader) {
      return PdfMetadataProbe(
        hasPdfHeader: false,
        totalBytes: totalBytes,
        bytesRead: bytesRead,
        wasTruncated: bytesRead < totalBytes,
        readWindows: List<PdfReadWindow>.unmodifiable(windows),
        limitations: List<String>.unmodifiable([
          'The bounded header window did not contain a PDF signature.',
          ...limitations,
        ]),
      );
    }

    final authorText = _metadataValue(boundedText, 'Author', 'dc:creator');
    final keywordsText = _metadataValue(
      boundedText,
      'Keywords',
      'pdf:Keywords',
    );
    return PdfMetadataProbe(
      hasPdfHeader: true,
      totalBytes: totalBytes,
      bytesRead: bytesRead,
      wasTruncated: bytesRead < totalBytes,
      readWindows: List<PdfReadWindow>.unmodifiable(windows),
      title: _metadataValue(boundedText, 'Title', 'dc:title'),
      authors: List<String>.unmodifiable(_splitPeople(authorText)),
      subject: _metadataValue(boundedText, 'Subject', 'dc:description'),
      keywords: List<String>.unmodifiable(_splitKeywords(keywordsText)),
      doiCandidates: List<String>.unmodifiable(
        const DoiExtractor().candidates(boundedText),
      ),
      year: _publicationYear(boundedText),
      limitations: List<String>.unmodifiable(limitations),
    );
  }

  Future<List<int>> _readWindow(
    PdfByteSource source, {
    required int offset,
    required int length,
    required int chunkLimit,
    required List<PdfReadWindow> windows,
  }) async {
    if (length <= 0) return const <int>[];
    final bytes = <int>[];
    var nextOffset = offset;
    var remaining = length;
    while (remaining > 0) {
      final requested = math.min(remaining, chunkLimit);
      final chunk = await source.readRange(
        offset: nextOffset,
        length: requested,
      );
      if (chunk.length > requested) {
        throw StateError('A PDF byte source exceeded the requested range.');
      }
      if (chunk.isEmpty) break;
      bytes.addAll(chunk);
      windows.add(PdfReadWindow(offset: nextOffset, length: chunk.length));
      nextOffset += chunk.length;
      remaining -= chunk.length;
    }
    return bytes;
  }

  void _validateConfiguration() {
    if (headWindowBytes < 0 ||
        tailWindowBytes < 0 ||
        maxReadBytes <= 0 ||
        maxTotalBytes <= 0 ||
        headWindowBytes + tailWindowBytes > maxTotalBytes) {
      throw StateError('Invalid bounded PDF reader configuration.');
    }
  }

  String? _metadataValue(String text, String infoKey, String xmlTag) {
    final literal = _literalValue(text, infoKey);
    if (literal != null && literal.isNotEmpty) return literal;
    return _xmlValue(text, xmlTag);
  }

  String? _literalValue(String text, String key) {
    final marker = RegExp(
      '/$key\\s*\\(',
      caseSensitive: false,
    ).firstMatch(text);
    if (marker == null) return null;

    final value = StringBuffer();
    var depth = 1;
    var escaped = false;
    for (var index = marker.end; index < text.length; index++) {
      final character = text[index];
      if (escaped) {
        value.write(switch (character) {
          'n' => '\n',
          'r' => '\r',
          't' => '\t',
          'b' => '\b',
          'f' => '\f',
          _ => character,
        });
        escaped = false;
      } else if (character == r'\') {
        escaped = true;
      } else if (character == '(') {
        depth += 1;
        value.write(character);
      } else if (character == ')') {
        depth -= 1;
        if (depth == 0) return _cleanText(value.toString());
        value.write(character);
      } else {
        value.write(character);
      }
    }
    return null;
  }

  String? _xmlValue(String text, String tag) {
    final match = RegExp(
      '<$tag(?:\\s[^>]*)?>(.*?)</$tag>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(text);
    if (match == null) return null;
    final withoutTags = match.group(1)!.replaceAll(RegExp('<[^>]+>'), ' ');
    final cleaned = _cleanText(withoutTags);
    return cleaned.isEmpty ? null : cleaned;
  }

  String _cleanText(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  List<String> _splitPeople(String? value) {
    if (value == null || value.isEmpty) return const <String>[];
    final separator = value.contains(';') ? ';' : RegExp(r'\s+and\s+').pattern;
    return value
        .split(RegExp(separator, caseSensitive: false))
        .map(_cleanText)
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  List<String> _splitKeywords(String? value) {
    if (value == null || value.isEmpty) return const <String>[];
    return value
        .split(RegExp(r'[,;]'))
        .map(_cleanText)
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  int? _publicationYear(String text) {
    final date =
        _metadataValue(text, 'CreationDate', 'dc:date') ??
        _metadataValue(text, 'ModDate', 'xmp:ModifyDate');
    if (date == null) return null;
    final pdfDateMatch = RegExp(r'^D:((?:18|19|20|21)\d{2})').firstMatch(date);
    if (pdfDateMatch != null) return int.parse(pdfDateMatch.group(1)!);
    final match = RegExp(r'(?<!\d)(?:18|19|20|21)\d{2}(?!\d)').firstMatch(date);
    return match == null ? null : int.parse(match.group(0)!);
  }
}

bool _hasPdfHeader(List<int> bytes) {
  const signature = <int>[0x25, 0x50, 0x44, 0x46, 0x2D];
  final searchLength = math.min(bytes.length, 1024);
  for (var offset = 0; offset <= searchLength - signature.length; offset++) {
    var matches = true;
    for (var index = 0; index < signature.length; index++) {
      if (bytes[offset + index] != signature[index]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}
