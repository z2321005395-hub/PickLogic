import 'dart:async';
import 'dart:io';

import 'package:picklogic_core_models/picklogic_core_models.dart';

final class StreamingDirectoryScanner implements FileScanner {
  bool _cancelled = false;

  @override
  Stream<ScanBatch> scan(ScanRequest request) async* {
    if (request.root.sourceKind != SourceKind.fileSystem &&
        request.root.sourceKind != SourceKind.synthetic) {
      throw ArgumentError.value(
        request.root.sourceKind,
        'request.root.sourceKind',
        'Directory scanning requires a filesystem or synthetic locator.',
      );
    }
    final root = Directory(request.root.value);
    if (!await root.exists()) {
      throw FileSystemException('The selected scan root is unavailable.');
    }

    _cancelled = false;
    var scannedCount = 0;
    var resumeReached = request.resumeCursor == null;
    String? cursor = request.resumeCursor;
    final batch = <FileRecord>[];

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (_cancelled) {
        if (batch.isNotEmpty) {
          yield ScanBatch(
            records: List<FileRecord>.unmodifiable(batch),
            cursor: cursor,
            isComplete: false,
            scannedCount: scannedCount,
          );
        }
        return;
      }
      if (entity is! File) continue;
      if (!resumeReached) {
        if (_samePath(entity.path, request.resumeCursor!)) resumeReached = true;
        continue;
      }

      final record = await _recordFor(entity, request.root);
      if (record == null) continue;
      batch.add(record);
      scannedCount += 1;
      cursor = entity.path;
      if (batch.length >= request.batchSize) {
        yield ScanBatch(
          records: List<FileRecord>.unmodifiable(batch),
          cursor: cursor,
          isComplete: false,
          scannedCount: scannedCount,
        );
        batch.clear();
      }
    }

    if (!resumeReached && request.resumeCursor != null) {
      throw StateError('The scan resume cursor is no longer available.');
    }
    yield ScanBatch(
      records: List<FileRecord>.unmodifiable(batch),
      cursor: cursor,
      isComplete: true,
      scannedCount: scannedCount,
    );
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
  }

  Future<FileRecord?> _recordFor(File file, FileLocator root) async {
    try {
      final stat = await file.stat();
      final name = _basename(file.path);
      final extension = _extension(name);
      final sourceKind = root.sourceKind;
      return FileRecord(
        id: '${root.platform.name}:${_normalizedPath(file.path)}',
        locator: FileLocator(
          value: file.path,
          sourceKind: sourceKind,
          platform: root.platform,
        ),
        displayName: name,
        extension: extension,
        mimeType: _mimeType(extension),
        sizeBytes: stat.size,
        createdAt: stat.changed,
        modifiedAt: stat.modified,
        parentLocator: FileLocator(
          value: file.parent.path,
          sourceKind: sourceKind,
          platform: root.platform,
        ),
        sourceKind: sourceKind,
        platform: root.platform,
        isHidden: name.startsWith('.'),
        isSystem: false,
        isAccessible: true,
        isProtected: false,
        category: VirtualCategory.unknown,
        hashState: HashState.notRequested,
        ocrState: OcrState.notRequested,
      );
    } on FileSystemException {
      return null;
    }
  }
}

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}

String _extension(String name) {
  final index = name.lastIndexOf('.');
  return index <= 0 || index == name.length - 1
      ? ''
      : name.substring(index + 1).toLowerCase();
}

String _mimeType(String extension) => switch (extension) {
  'pdf' => 'application/pdf',
  'txt' || 'md' => 'text/plain',
  'csv' => 'text/csv',
  'doc' || 'docx' => 'application/msword',
  'xls' || 'xlsx' => 'application/vnd.ms-excel',
  'ppt' || 'pptx' => 'application/vnd.ms-powerpoint',
  'png' => 'image/png',
  'jpg' || 'jpeg' => 'image/jpeg',
  'gif' => 'image/gif',
  'mp4' => 'video/mp4',
  'mp3' => 'audio/mpeg',
  'zip' => 'application/zip',
  _ => 'application/octet-stream',
};

String _normalizedPath(String path) {
  final normalized = File(path).absolute.path.replaceAll('\\', '/');
  return Platform.isWindows ? normalized.toLowerCase() : normalized;
}

bool _samePath(String left, String right) =>
    _normalizedPath(left) == _normalizedPath(right);
