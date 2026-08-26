# ADR 0006: Authorized workspace operations

Status: Accepted

## Context

Global read-only mode prevented testing PickLogic's core organization workflow. Disabling safety globally would expose unrelated files and violate the OperationPlan contract.

## Decision

- Browsed locations remain read-only by default.
- A system folder picker may authorize one exact managed root; the built-in PickLogic Test Workspace is a separately visible authorized root.
- A workspace `FileOperator` resolves links, canonicalizes source and destination, rejects root escape and overwrite, and executes only a previewed and confirmed `OperationPlan`.
- Rename and move use an atomic filesystem rename where supported. Test Workspace delete is a reversible move to `Test-Trash`; Undo moves the same test copy back only when the original path is free.
- Managed Folder delete uses Windows `IFileOperation` with recycle and undo-record flags. When Windows returns the created Recycle Bin shell item, PickLogic keeps an in-session handle for safe restore; otherwise Explorer remains the restore path.
- Developer Safe Mode accepts an additive `userAuthorizedManagedTarget` signal only after the operator has completed these root checks. Its default remains false, preserving existing behavior.

## Compatibility

No serialized model, enum, locator, or database schema changes. Existing Safe Mode and `SafeOperationGate` call sites keep their previous deny-by-default semantics.

## Consequences

Test and explicitly managed roots can exercise real organization behavior without granting app-wide mutation authority. Windows Recycle Bin and Android system trash remain platform-confirmed paths; the test workspace keeps its own reversible trash so PickLogic can provide deterministic Undo without touching originals.
