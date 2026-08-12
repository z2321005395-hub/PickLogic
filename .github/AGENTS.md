# CI Rules

- CI uses synthetic data only and does not require secrets for pull requests.
- Pin third-party actions to immutable commits and audit their licenses.
- Run format, analysis, unit/integration tests, Android debug build, Windows build, dependency/license, and secret/privacy checks.
- Preserve concise success summaries; inspect full logs only for failures.
