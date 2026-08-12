# Privacy Report — v0.1.0-alpha Draft

## Default data flow

- No account, backend, ads, default telemetry, or cloud upload.
- SQLite indexes, thumbnail cache entries, classifications, review state, and Insight evidence remain local.
- File and MediaStore scanning reads metadata in bounded batches; SHA-256 reads file streams only when explicitly requested.
- Online translation, OCR, and intelligence providers are replaceable interfaces and are disabled/unconfigured in this build.

## Platform limits

- Windows development uses synthetic roots for Move/Rename/Undo; no real path has been mutated.
- Android uses MediaStore and SAF and does not request root or other applications' private directories.
- Mobile persists only the metadata returned by authorized MediaStore queries plus bounded resume checkpoints in the app-private, no-backup SQLite index.
- Storage totals that Android cannot attribute are labeled as system aggregates, not explained as inspectable files.

## Public-data gate

Synthetic fixtures contain no real filename, path, paper title, experiment name, screenshot, or device serial. The committed-source privacy scan currently reports zero findings. Future reference-device results may include aggregate counts/timings only.
