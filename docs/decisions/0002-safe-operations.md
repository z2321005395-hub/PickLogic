# ADR 0002: Safe operation pipeline

Status: Accepted for Bootstrap

## Context

File organization can cause irreversible data loss, and Windows/Android have different trash and permission behavior.

## Decision

All rename, move, and delete requests become immutable `OperationPlan` previews. Only `FileOperator` may execute a confirmed plan. Debug builds enforce Developer Safe Mode below the UI and reject real mutations. Release delete uses the platform recycle/trash mechanism when available.

## Consequences

- UI cannot directly mutate files.
- Plans and rollback metadata are testable with synthetic roots.
- `PROTECTED` and `UNKNOWN` content have no direct delete route.
- Platform restrictions are shown as limitations, not bypassed.
