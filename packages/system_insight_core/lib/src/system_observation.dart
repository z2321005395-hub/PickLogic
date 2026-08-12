import 'package:picklogic_core_models/picklogic_core_models.dart';

enum SystemObservationKind {
  userDirectory,
  appData,
  programData,
  hiddenItem,
  systemItem,
  softwareCache,
  temporaryFile,
  installer,
  startupEntry,
  service,
  scheduledTask,
  unknown,
}

final class SystemObservation {
  const SystemObservation({
    required this.kind,
    required this.label,
    required this.sizeBytes,
    required this.isWindowsCore,
    required this.isRunning,
    required this.isSigned,
    this.ownerApplication,
    this.evidence = const <String>[],
  });

  final SystemObservationKind kind;
  final String label;
  final int sizeBytes;
  final bool isWindowsCore;
  final bool isRunning;
  final bool isSigned;
  final String? ownerApplication;
  final List<String> evidence;
}

final class SystemObservationExplainer {
  const SystemObservationExplainer();

  InsightRecord explain(SystemObservation observation) {
    final protected =
        observation.isWindowsCore ||
        observation.kind == SystemObservationKind.systemItem ||
        observation.kind == SystemObservationKind.service;
    final unknown = observation.kind == SystemObservationKind.unknown;
    return InsightRecord(
      summary: protected
          ? 'This item is system-related and is protected from direct changes.'
          : unknown
          ? 'Available evidence is insufficient to identify this item.'
          : 'This is a read-only system observation.',
      fileType: observation.kind.name,
      probableOwner: observation.ownerApplication,
      whyItExists: _why(observation.kind),
      relatedApplication: observation.ownerApplication,
      spaceUsageBytes: observation.sizeBytes,
      runningOrActiveState: observation.isRunning
          ? 'running'
          : 'not observed running',
      riskLevel: protected
          ? RiskLevel.protected
          : unknown
          ? RiskLevel.unknown
          : RiskLevel.review,
      confidence: unknown ? 0.2 : 0.85,
      evidence: [
        ...observation.evidence.map(
          (statement) => InsightEvidence(
            kind: EvidenceKind.fact,
            statement: statement,
            source: 'read-only Windows observation',
          ),
        ),
        InsightEvidence(
          kind: EvidenceKind.fact,
          statement: observation.isSigned
              ? 'A digital signature was observed.'
              : 'No verified digital signature was observed.',
          source: 'signature inspection',
        ),
      ],
      recommendedActions: protected || unknown
          ? const ['View details', 'Add to review list']
          : const [
              'Open related settings',
              'View details',
              'Add to review list',
            ],
      limitations: const [
        'No registry, service, task, startup, uninstall, or file change was performed.',
      ],
    );
  }

  String _why(SystemObservationKind kind) => switch (kind) {
    SystemObservationKind.softwareCache =>
      'Applications may recreate cache data.',
    SystemObservationKind.temporaryFile =>
      'Temporary data may support active work.',
    SystemObservationKind.installer =>
      'An installer may support setup or repair.',
    SystemObservationKind.startupEntry =>
      'A registered item may launch at sign-in.',
    SystemObservationKind.service =>
      'A Windows service may support system or application features.',
    SystemObservationKind.scheduledTask =>
      'A scheduled task may perform maintenance or updates.',
    _ => 'The item exists in an inspected Windows scope.',
  };
}
