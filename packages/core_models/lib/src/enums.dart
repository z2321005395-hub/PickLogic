enum PickLogicPlatform { windows, android, synthetic, unknown }

enum SourceKind {
  fileSystem,
  mediaStore,
  storageAccessFramework,
  downloads,
  appOwned,
  synthetic,
  unknown,
}

enum VirtualCategory {
  documents,
  spreadsheets,
  presentations,
  pdf,
  images,
  videos,
  audio,
  archives,
  installers,
  code,
  academicPapers,
  screenshots,
  downloads,
  duplicates,
  largeFiles,
  unknown,
}

enum HashState { notRequested, queued, hashing, complete, failed }

enum OcrState {
  notRequested,
  queued,
  processing,
  complete,
  failed,
  unavailable,
}

enum RiskLevel { safe, review, protected, unknown }

enum EvidenceKind {
  fact,
  ruleInference,
  lowConfidenceGuess,
  platformRestriction,
}

enum OperationType { rename, move, deleteToTrash }

enum OperationStatus {
  planned,
  previewed,
  confirmed,
  executing,
  completed,
  undone,
  cancelled,
  failed,
}

enum ScreenshotReviewState { unreviewed, keep, deleteReview, later, protected }

enum SafeCapability {
  scan,
  indexFiles,
  hash,
  thumbnail,
  classify,
  explain,
  benchmark,
  deleteRealData,
  moveRealData,
  renameRealData,
  systemChanges,
}
