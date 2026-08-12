# ADR 0005: Mobile index resume

## Context

Mobile must show a usable first screen before indexing completes, process MediaStore in bounded pages, and resume incremental work without duplicating Shared Core in Kotlin. Real media remains permission-gated and was not used for this decision.

## Decision

- Android returns one fixed database path under the app-private `noBackupFilesDir`.
- Dart opens that path with the existing shared `SqliteFileIndex`.
- Each loaded MediaStore page is upserted before its offset and modification-time checkpoint is saved.
- A malformed or incompatible checkpoint restarts that collection's bounded pass; indexed records remain intact.
- Search uses SQLite and merges any newer in-memory records.
- First paint never awaits queue completion. The queue handles one bounded page at a time and requeues collections with more data at the back for fair continuation.
- A user pause finishes only the current page. OCR, hashing, media mutation, permission prompts, and OS-scheduled wakeups are not part of the queue.

## Dependency decision

No dependency is added. AndroidX WorkManager 2.11.2 is Apache-2.0 and is Android's recommended persistent-work scheduler, but it would add a scheduling runtime and transitive payload before reference-device evidence shows OS wakeups are necessary. The v0.1 checkpoint resumes when PickLogic next runs; WorkManager remains an evaluated follow-up.

## Compatibility

The bridge method is additive. Shared models and SQLite schema stay unchanged because checkpoint data uses the existing `scan_state` table with an isolated `android-mediastore:*` root key.

## Consequences

Index metadata and progress survive process restarts without delaying the first screen or adding package bytes. Work does not run while Android keeps the application stopped; that limitation remains explicit.
