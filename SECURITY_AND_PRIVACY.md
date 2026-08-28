# Security and Privacy

## Defaults

- No account, telemetry, ads, cloud backend, or file upload.
- Index, OCR output, preferences, thumbnails, and Insight records remain local.
- API keys, if a future provider needs one, use OS secure storage and are never logged or committed.
- Online translation is off until the user selects an engine in the result sidebar. Choosing `Fast aggregate` once enables and remembers local terminology/cache plus the no-key MyMemory source; each selection sends at most 500 selected characters to MyMemory and never sends PDF bytes, images, paths, filenames, library metadata, or unrelated text. If the user has separately configured the optional AI provider, aggregate mode may query it concurrently with the same selected text.
- The reader exposes its engine selector beside every selection result. OpenAI-compatible translation remains optional and keeps endpoint/model preferences local while protecting its API key with Windows DPAPI.
- Current-page and document translation remain explicit menu actions. They send bounded extracted text only, never the PDF file, and may be limited by the selected service's public quota.
- Page translations and terminology are stored in the app-owned local SQLite catalog. A bounded terminology list accompanies only an explicit translation request.

## Developer Safe Mode

Debug builds visibly show `Developer Safe Mode: ON` and permit scan, index, hash, thumbnail, classify, explain, and benchmark only. Real delete, move, rename, and system changes are blocked below the UI layer.

Mutation tests operate only on an application-created synthetic root after explicit approval. Release mode still requires a plan, preview, confirmation, and platform Trash/recycle mechanism.

## Platform boundaries

- Windows: real directories are read-only during development. Registry, services, startup entries, tasks, uninstallers, and protected paths are inspection-only.
- Android: obey scoped storage, MediaStore, and SAF. Never root, inspect another app's private data, or claim visibility into inaccessible storage.
- `REQUEST_INSTALL_PACKAGES` is used only after the user selects `System install` from an APK detail page; Android's per-source authorization and installer confirmation remain mandatory, and PickLogic never installs silently.
- Android MediaStore metadata and resume checkpoints use a fixed SQLite file under the application's `noBackupFilesDir`; neither file contents nor the database are cloud-backed by PickLogic.
- For inaccessible Android data show: `当前Android权限不允许第三方应用直接检查该部分。`

## Data minimization

- Public fixtures are synthetic. Device validation records only aggregate counts, durations, memory, temperature observations, and coarse environment metadata.
- Never commit real paths, filenames, paper titles, experiment names, device serials, screenshots, full logs, tokens, cookies, or credentials.
- Diagnostic logs use generated IDs and redact locator values by default.
- Android Release signing credentials are never committed; final signing is a maintainer-controlled release gate. CI device validation uses Debug APKs.

## Vulnerability reporting

See `SECURITY.md`. Do not disclose a suspected vulnerability in a public issue before maintainers can assess it.
