import 'package:flutter_test/flutter_test.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_mobile/src/mobile_trash_controller.dart';

void main() {
  const controller = MobileTrashController();

  test('eligible MediaStore item becomes a previewed OperationPlan', () {
    final preview = controller.preview(_record());

    expect(preview.operationType, OperationType.deleteToTrash);
    expect(preview.status, OperationStatus.previewed);
    expect(preview.rollbackMetadata['strategy'], 'android-system-trash');
  });

  test('protected and unknown items have no direct trash path', () {
    expect(
      controller.canMoveToSystemTrash(_record(isProtected: true)),
      isFalse,
    );
    expect(
      controller.canMoveToSystemTrash(
        _record(category: VirtualCategory.unknown),
      ),
      isFalse,
    );
  });

  test('confirmed plan executes only through the system requester', () async {
    final requested = <String>[];
    final result = await controller.execute(
      confirmedPlan: controller
          .preview(_record())
          .transitionTo(OperationStatus.confirmed),
      requester: (uris) async {
        requested.addAll(uris);
        return true;
      },
    );

    expect(requested, <String>['content://media/external/images/media/42']);
    expect(result.success, isTrue);
    expect(result.plan.status, OperationStatus.completed);
  });
}

FileRecord _record({
  bool isProtected = false,
  VirtualCategory category = VirtualCategory.images,
}) => FileRecord(
  id: '42',
  locator: const FileLocator(
    value: 'content://media/external/images/media/42',
    sourceKind: SourceKind.mediaStore,
    platform: PickLogicPlatform.android,
  ),
  displayName: 'photo.jpg',
  extension: 'jpg',
  mimeType: 'image/jpeg',
  sizeBytes: 1024,
  createdAt: DateTime.utc(2026, 8, 27),
  modifiedAt: DateTime.utc(2026, 8, 27),
  parentLocator: null,
  sourceKind: SourceKind.mediaStore,
  platform: PickLogicPlatform.android,
  isHidden: false,
  isSystem: false,
  isAccessible: true,
  isProtected: isProtected,
  category: category,
  hashState: HashState.notRequested,
  ocrState: OcrState.notRequested,
);
