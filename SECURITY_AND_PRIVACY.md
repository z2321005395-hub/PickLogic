# Security and Privacy

## Defaults

- No account, telemetry, ads, cloud backend, or file upload.
- Index, OCR output, preferences, thumbnails, and Insight records remain local.
- API keys, if a future provider needs one, use OS secure storage and are never logged or committed.
- Online translation receives only the selected text after explicit opt-in.

## Developer Safe Mode

Debug builds visibly show `Developer Safe Mode: ON` and permit scan, index, hash, thumbnail, classify, explain, and benchmark only. Real delete, move, rename, and system changes are blocked below the UI layer.

Mutation tests operate only on an application-created synthetic root after explicit approval. Release mode still requires a plan, preview, confirmation, and platform Trash/recycle mechanism.

## Platform boundaries

- Windows: real directories are read-only during development. Registry, services, startup entries, tasks, uninstallers, and protected paths are inspection-only.
- Android: obey scoped storage, MediaStore, and SAF. Never root, inspect another app's private data, or claim visibility into inaccessible storage.
- Android MediaStore metadata and resume checkpoints use a fixed SQLite file under the application's `noBackupFilesDir`; neither file contents nor the database are cloud-backed by PickLogic.
- For inaccessible Android data show: `当前Android权限不允许第三方应用直接检查该部分。`

## Data minimization

- Public fixtures are synthetic. Device validation records only aggregate counts, durations, memory, temperature observations, and coarse environment metadata.
- Never commit real paths, filenames, paper titles, experiment names, device serials, screenshots, full logs, tokens, cookies, or credentials.
- Diagnostic logs use generated IDs and redact locator values by default.
- Android Release signing credentials are never committed; final signing is a maintainer-controlled release gate. CI device validation uses Debug APKs.

## Vulnerability reporting

See `SECURITY.md`. Do not disclose a suspected vulnerability in a public issue before maintainers can assess it.
