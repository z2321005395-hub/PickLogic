# PickLogic Mobile

Android target for files, screenshots, photos, storage, and contextual Insight. See the repository root documentation and this directory's `AGENTS.md`.

- The first screen waits only for permission and aggregate storage state, not a complete media scan.
- Screenshot groups use bounded MediaStore pages plus time and source clues; they do not imply OCR or verified app ownership.
- Thumbnails load only for visible widgets, with a native 512 px / 512 KiB ceiling and an 8 MiB in-process LRU cache.
- The incremental metadata queue handles one bounded page at a time, fairly continues authorized collections while the app runs, writes metadata through the shared SQLite index, and saves a per-collection checkpoint for restart recovery. Pause takes effect after the current page; the queue never schedules OCR.
- Android OS-scheduled wakeups are not part of v0.1; indexing resumes when PickLogic next runs and media access is already authorized.
- Storage Insight separates system aggregate usage, accessible MediaStore/SAF data, and Android-restricted data.
