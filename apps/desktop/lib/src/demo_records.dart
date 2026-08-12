import 'package:picklogic_core_models/picklogic_core_models.dart';

List<FileRecord> syntheticDesktopRecords() {
  FileRecord record(
    String id,
    String name,
    String extension,
    VirtualCategory category,
    int bytes,
  ) => FileRecord(
    id: id,
    locator: FileLocator(
      value: 'synthetic://desktop/$id',
      sourceKind: SourceKind.synthetic,
      platform: PickLogicPlatform.synthetic,
    ),
    displayName: name,
    extension: extension,
    mimeType: extension == 'pdf' ? 'application/pdf' : '',
    sizeBytes: bytes,
    createdAt: DateTime.utc(2026, 1, 1),
    modifiedAt: DateTime.utc(2026, 8, 12),
    parentLocator: null,
    sourceKind: SourceKind.synthetic,
    platform: PickLogicPlatform.synthetic,
    isHidden: false,
    isSystem: false,
    isAccessible: true,
    isProtected: false,
    category: category,
    tags: const ['synthetic'],
    hashState: HashState.notRequested,
    ocrState: OcrState.notRequested,
  );

  return [
    record(
      'paper',
      'Synthetic local-first paper.pdf',
      'pdf',
      VirtualCategory.academicPapers,
      184320,
    ),
    record(
      'table',
      'Synthetic measurements.csv',
      'csv',
      VirtualCategory.spreadsheets,
      8192,
    ),
    record(
      'image',
      'Synthetic figure.png',
      'png',
      VirtualCategory.images,
      32768,
    ),
    record(
      'archive',
      'Synthetic package.zip',
      'zip',
      VirtualCategory.archives,
      4096,
    ),
  ];
}
