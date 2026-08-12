import 'package:picklogic_core_models/picklogic_core_models.dart';

final class LiteratureRenamePreview {
  const LiteratureRenamePreview({
    required this.originalFileName,
    required this.proposedFileName,
    required this.warnings,
  });

  final String originalFileName;
  final String proposedFileName;
  final List<String> warnings;

  bool get changed => originalFileName != proposedFileName;

  bool get isPreviewOnly => true;
}

final class LiteratureNaming {
  const LiteratureNaming();

  LiteratureRenamePreview previewRename({
    required LiteratureRecord record,
    required String originalFileName,
  }) {
    if (originalFileName.trim().isEmpty) {
      throw ArgumentError.value(
        originalFileName,
        'originalFileName',
        'Must not be empty.',
      );
    }
    final result = _buildFileName(record);
    return LiteratureRenamePreview(
      originalFileName: originalFileName,
      proposedFileName: result.fileName,
      warnings: List<String>.unmodifiable([
        if (record.authors.isEmpty) 'Author metadata is missing.',
        if (record.year == null) 'Publication year is missing.',
        if (record.title.trim().isEmpty) 'Title metadata is missing.',
        if (result.sanitized) 'Windows-invalid characters were replaced.',
        if (result.truncated) 'The preview was shortened to 180 characters.',
        'Preview only; no file operation has been planned or executed.',
      ]),
    );
  }

  String previewFileName(LiteratureRecord record) =>
      _buildFileName(record).fileName;

  ({String fileName, bool sanitized, bool truncated}) _buildFileName(
    LiteratureRecord record,
  ) {
    final author = record.authors.isEmpty
        ? 'Unknown author'
        : record.authors.first;
    final year = record.year?.toString() ?? 'n.d.';
    final title = record.title.trim().isEmpty
        ? 'Untitled paper'
        : record.title.trim();
    final rawStem = '$author ($year) - $title';
    var stem = rawStem
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'[ .]+$'), '');
    var sanitized = stem != rawStem;
    if (stem.isEmpty) {
      stem = 'Untitled paper';
      sanitized = true;
    }

    const reservedNames = {
      'CON',
      'PRN',
      'AUX',
      'NUL',
      'COM1',
      'COM2',
      'COM3',
      'COM4',
      'COM5',
      'COM6',
      'COM7',
      'COM8',
      'COM9',
      'LPT1',
      'LPT2',
      'LPT3',
      'LPT4',
      'LPT5',
      'LPT6',
      'LPT7',
      'LPT8',
      'LPT9',
    };
    if (reservedNames.contains(stem.split('.').first.toUpperCase())) {
      stem = '_$stem';
      sanitized = true;
    }

    const extension = '.pdf';
    const maximumLength = 180;
    final maximumStemLength = maximumLength - extension.length;
    final truncated = stem.length > maximumStemLength;
    if (truncated) {
      stem = _truncateUtf16(
        stem,
        maximumStemLength,
      ).replaceAll(RegExp(r'[ .]+$'), '');
    }
    return (
      fileName: '$stem$extension',
      sanitized: sanitized,
      truncated: truncated,
    );
  }

  String _truncateUtf16(String value, int maximumCodeUnits) {
    final result = StringBuffer();
    var codeUnits = 0;
    for (final rune in value.runes) {
      final width = rune > 0xFFFF ? 2 : 1;
      if (codeUnits + width > maximumCodeUnits) break;
      result.writeCharCode(rune);
      codeUnits += width;
    }
    return result.toString();
  }
}
