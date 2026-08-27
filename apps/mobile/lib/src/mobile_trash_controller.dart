import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_operation_planner/picklogic_operation_planner.dart';

typedef AndroidSystemTrashRequester =
    Future<bool> Function(List<String> contentUris);

/// Safety gate for user-confirmed Android MediaStore trash requests.
///
/// PickLogic never deletes media directly. Eligible items first become an
/// [OperationPlan], then Android presents its own system confirmation UI.
final class MobileTrashController {
  const MobileTrashController({
    this.planner = const OperationPlanner(),
    this.gate = const SafeOperationGate(DeveloperSafeMode.on()),
  });

  final OperationPlanner planner;
  final SafeOperationGate gate;

  bool canMoveToSystemTrash(FileRecord record) {
    final uri = Uri.tryParse(record.locator.value);
    return record.platform == PickLogicPlatform.android &&
        record.isAccessible &&
        !record.isProtected &&
        !record.isSystem &&
        record.category != VirtualCategory.unknown &&
        (record.sourceKind == SourceKind.mediaStore ||
            record.sourceKind == SourceKind.downloads) &&
        uri != null &&
        uri.scheme == 'content';
  }

  OperationPlan preview(FileRecord record) {
    if (!canMoveToSystemTrash(record)) {
      throw StateError('This item is not eligible for Android system trash.');
    }
    final planned = planner.planDeleteToTrash(
      operationId: 'android-trash-${DateTime.now().microsecondsSinceEpoch}',
      source: record.locator,
      warnings: const <String>[
        'Android will show a separate system confirmation.',
        'The item can be restored from the Android system trash while retained.',
      ],
    );
    return OperationPlan(
      operationId: planned.operationId,
      operationType: planned.operationType,
      source: planned.source,
      destination: planned.destination,
      preview: planned.preview,
      warnings: planned.warnings,
      rollbackMetadata: const <String, String>{
        'strategy': 'android-system-trash',
      },
      status: OperationStatus.previewed,
    );
  }

  Future<OperationResult> execute({
    required OperationPlan confirmedPlan,
    required AndroidSystemTrashRequester requester,
  }) async {
    final eligible =
        confirmedPlan.operationType == OperationType.deleteToTrash &&
        confirmedPlan.rollbackMetadata['strategy'] == 'android-system-trash' &&
        gate.mayExecute(
          confirmedPlan,
          syntheticTarget: false,
          testMutationAuthorized: false,
          userAuthorizedManagedTarget: true,
        );
    if (!eligible) {
      return OperationResult(
        plan: confirmedPlan,
        success: false,
        message: 'The system trash request did not pass the safety gate.',
      );
    }

    final executing = confirmedPlan.transitionTo(OperationStatus.executing);
    try {
      final accepted = await requester(<String>[confirmedPlan.source.value]);
      return OperationResult(
        plan: executing.transitionTo(
          accepted ? OperationStatus.completed : OperationStatus.failed,
        ),
        success: accepted,
        message: accepted
            ? 'Android moved the item to system trash.'
            : 'The Android system trash request was cancelled or unavailable.',
      );
    } on Object {
      return OperationResult(
        plan: executing.transitionTo(OperationStatus.failed),
        success: false,
        message: 'The Android system trash request failed safely.',
      );
    }
  }
}
