# PickLogic Mobile

Android target for files, screenshots, photos, storage, and contextual Insight. See the repository root documentation and this directory's `AGENTS.md`.

- The first screen waits only for permission and aggregate storage state, not a complete media scan.
- Screenshot groups use bounded MediaStore pages plus time and source clues; they do not imply OCR or verified app ownership.
- Thumbnails load only for visible widgets, with a native 512 px / 512 KiB ceiling and an 8 MiB in-process LRU cache.
- The incremental metadata queue is a bounded process-local skeleton. It handles one page per collection request, does not auto-page, and never schedules OCR.
- Storage Insight separates system aggregate usage, accessible MediaStore/SAF data, and Android-restricted data.
