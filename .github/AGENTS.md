# CI Rules

- CI uses synthetic data only and does not require secrets for pull requests.
- Pin third-party actions to immutable commits and audit their licenses.
- Run format, analysis, unit/integration tests, Android debug build, Windows build, dependency/license, and secret/privacy checks.
- Preserve concise success summaries; inspect full logs only for failures.
- Routine push and pull-request workflows must not upload installable packages or whole build directories.
- Failure diagnostics, when genuinely necessary, contain only the minimum logs/screenshots and use `retention-days: 1`.
- Candidate packages upload only for an explicit manual candidate run or version tag and use `retention-days: 3` by default, never more than 7 without maintainer approval.
