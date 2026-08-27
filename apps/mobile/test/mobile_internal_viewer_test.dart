import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_mobile/src/mobile_internal_viewer.dart';
import 'package:picklogic_mobile/src/mobile_repository.dart';
import 'package:picklogic_mobile/src/mobile_test_workspace.dart';

void main() {
  test('internal viewer routing covers the promised lightweight formats', () {
    expect(
      mobileViewerKind(syntheticMobileRecord('image.webp')),
      MobileInternalViewerKind.image,
    );
    expect(
      mobileViewerKind(syntheticMobileRecord('clip.mp4')),
      MobileInternalViewerKind.video,
    );
    expect(
      mobileViewerKind(syntheticMobileRecord('sound.mp3')),
      MobileInternalViewerKind.audio,
    );
    expect(
      mobileViewerKind(syntheticMobileRecord('paper.pdf')),
      MobileInternalViewerKind.pdf,
    );
    expect(
      mobileViewerKind(syntheticMobileRecord('notes.md')),
      MobileInternalViewerKind.text,
    );
    expect(
      mobileViewerKind(syntheticMobileRecord('bundle.zip')),
      MobileInternalViewerKind.archive,
    );
    expect(
      mobileViewerKind(syntheticMobileRecord('installer.apk')),
      MobileInternalViewerKind.apk,
    );
    expect(
      mobileViewerKind(syntheticMobileRecord('slides.pptx')),
      MobileInternalViewerKind.office,
    );
  });

  testWidgets('text viewer is internal and bounded', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MobileInternalViewer(
            record: syntheticMobileRecord('notes.txt'),
            repository: const SyntheticMobileRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mobile-text-viewer')), findsOneWidget);
    expect(find.textContaining('Synthetic read-only preview'), findsOneWidget);
  });

  testWidgets('test workspace stays unauthorized until SAF selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MobileTestWorkspacePage(repository: SyntheticMobileRepository()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('choose-test-workspace')), findsOneWidget);
    expect(find.byKey(const Key('import-test-copies')), findsNothing);
  });

  testWidgets('MediaStore trash requires PickLogic preview before Android', (
    tester,
  ) async {
    final record = _androidRecord();
    await tester.pumpWidget(
      MaterialApp(
        home: MobileViewerPage(
          records: <FileRecord>[record],
          initialRecord: record,
          repository: const SyntheticMobileRepository(systemTrashResult: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('mobile-viewer-trash')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('mobile-trash-operation-preview')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('confirm-mobile-system-trash')));
    await tester.pumpAndSettle();
    expect(
      find.text('Android moved the item to system trash.'),
      findsOneWidget,
    );
  });
}

FileRecord _androidRecord() => FileRecord(
  id: 'android-photo-42',
  locator: const FileLocator(
    value: 'content://media/external/images/media/42',
    sourceKind: SourceKind.mediaStore,
    platform: PickLogicPlatform.android,
  ),
  displayName: 'photo.jpg',
  extension: 'jpg',
  mimeType: 'image/jpeg',
  sizeBytes: 2048,
  createdAt: DateTime.utc(2026, 8, 27),
  modifiedAt: DateTime.utc(2026, 8, 27),
  parentLocator: null,
  sourceKind: SourceKind.mediaStore,
  platform: PickLogicPlatform.android,
  isHidden: false,
  isSystem: false,
  isAccessible: true,
  isProtected: false,
  category: VirtualCategory.images,
  hashState: HashState.notRequested,
  ocrState: OcrState.notRequested,
);
