import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
