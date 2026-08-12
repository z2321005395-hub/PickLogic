import 'package:picklogic_core_models/picklogic_core_models.dart';

final class LiteratureNaming {
  const LiteratureNaming();

  String previewFileName(LiteratureRecord record) {
    final author = record.authors.isEmpty
        ? 'Unknown author'
        : record.authors.first;
    final year = record.year?.toString() ?? 'n.d.';
    final title = record.title.trim().isEmpty
        ? 'Untitled paper'
        : record.title.trim();
    final raw = '$author ($year) - $title.pdf';
    final sanitized = raw.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    return sanitized.length <= 180
        ? sanitized
        : '${sanitized.substring(0, 176)}.pdf';
  }
}
