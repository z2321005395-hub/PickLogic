# Desktop App Rules

- One app, two entrypoints: `main_standard.dart` and `main_pro.dart`.
- Standard owns Home, Files, Search, Duplicates, Storage; Pro adds contextual Literature, Research, and System Insight routes.
- Track A may change shared desktop shell/Standard. Track B adds Pro modules without copying the shell or core.
- File mutations go only through `OperationPlan` and the Windows bridge execution gate.
- Real Windows paths are read-only during development.
