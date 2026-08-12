import 'package:picklogic_core_models/picklogic_core_models.dart';

final class RuleClassificationEngine implements ClassificationEngine {
  RuleClassificationEngine({Map<String, VirtualCategory>? rememberedExtensions})
    : _rememberedExtensions = <String, VirtualCategory>{
        for (final entry
            in rememberedExtensions?.entries ??
                const <MapEntry<String, VirtualCategory>>[])
          _normalizeExtension(entry.key): entry.value,
      };

  final Map<String, VirtualCategory> _rememberedExtensions;

  static const Map<VirtualCategory, Set<String>> _extensions = {
    VirtualCategory.documents: {'doc', 'docx', 'odt', 'rtf', 'txt', 'md'},
    VirtualCategory.spreadsheets: {'xls', 'xlsx', 'ods', 'csv', 'tsv'},
    VirtualCategory.presentations: {'ppt', 'pptx', 'odp'},
    VirtualCategory.pdf: {'pdf'},
    VirtualCategory.images: {
      'jpg',
      'jpeg',
      'png',
      'gif',
      'webp',
      'bmp',
      'tif',
      'tiff',
      'heic',
    },
    VirtualCategory.videos: {'mp4', 'mkv', 'mov', 'avi', 'webm', 'm4v'},
    VirtualCategory.audio: {'mp3', 'm4a', 'flac', 'wav', 'ogg', 'aac'},
    VirtualCategory.archives: {'zip', '7z', 'rar', 'tar', 'gz', 'bz2', 'xz'},
    VirtualCategory.installers: {'exe', 'msi', 'msix', 'apk', 'aab'},
    VirtualCategory.code: {
      'dart',
      'kt',
      'java',
      'c',
      'cc',
      'cpp',
      'h',
      'py',
      'js',
      'ts',
      'json',
      'yaml',
      'yml',
      'xml',
    },
  };

  void rememberExtension(String extension, VirtualCategory category) {
    _rememberedExtensions[_normalizeExtension(extension)] = category;
  }

  Map<String, VirtualCategory> get rememberedExtensions =>
      Map<String, VirtualCategory>.unmodifiable(_rememberedExtensions);

  @override
  FileRecord classify(FileRecord record) {
    final extension = _normalizeExtension(record.extension);
    final name = record.displayName.toLowerCase();
    final tags = record.tags.map((tag) => tag.toLowerCase()).toSet();

    final category =
        _rememberedExtensions[extension] ??
        _specialCategory(record, name, tags) ??
        _extensionCategory(extension) ??
        _mimeCategory(record.mimeType) ??
        VirtualCategory.unknown;
    return record.copyWith(category: category);
  }

  VirtualCategory? _specialCategory(
    FileRecord record,
    String name,
    Set<String> tags,
  ) {
    if (tags.contains('screenshot') ||
        name.startsWith('screenshot') ||
        name.startsWith('屏幕截图')) {
      return VirtualCategory.screenshots;
    }
    if (tags.contains('academic-paper') || tags.contains('doi')) {
      return VirtualCategory.academicPapers;
    }
    if (record.sourceKind == SourceKind.downloads) {
      return VirtualCategory.downloads;
    }
    return null;
  }

  VirtualCategory? _extensionCategory(String extension) {
    for (final entry in _extensions.entries) {
      if (entry.value.contains(extension)) return entry.key;
    }
    return null;
  }

  VirtualCategory? _mimeCategory(String mimeType) {
    final mime = mimeType.toLowerCase();
    if (mime.startsWith('image/')) return VirtualCategory.images;
    if (mime.startsWith('video/')) return VirtualCategory.videos;
    if (mime.startsWith('audio/')) return VirtualCategory.audio;
    if (mime == 'application/pdf') return VirtualCategory.pdf;
    return null;
  }

  static String _normalizeExtension(String extension) =>
      extension.toLowerCase().replaceFirst(RegExp(r'^\.'), '');
}
