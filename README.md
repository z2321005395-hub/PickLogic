# PickLogic

**Small. Local. Useful.**

Find files by what they are, not where they are.

PickLogic is a local-first file understanding and organization project. One Flutter/Dart monorepo produces PickLogic Desktop, PickLogic Pro, and PickLogic Mobile. **Insight** explains selected files, screenshots, literature, and storage using evidence and confidence rather than acting as a chatbot home screen.

> Status: v0.1.0-alpha user-testing prerelease.

## Product targets

- **PickLogic Desktop** — Windows Standard: local scan, virtual categories, search, preview, exact duplicates, planned organization, and Insight.
- **PickLogic Pro** — the same Windows codebase plus Literature Manager Lite, local PDF reading and source-preserving text/image/page editing, Research Workspace, and read-only System Insight.
- **PickLogic Mobile** — Android: files, screenshots, photos, storage insight, fast review, and Insight.

## Safety and privacy

- No forced account, ads, default telemetry, or cloud backend.
- Debug builds enforce visible Developer Safe Mode.
- Virtual categories do not move files.
- Mutations require a plan, preview, confirmation, and undo/trash path.
- Unknown or protected content is never presented as safe to delete.

## Repository

See [Architecture](ARCHITECTURE.md), [Product Principles](PRODUCT_PRINCIPLES.md), [Security and Privacy](SECURITY_AND_PRIVACY.md), [Installation](docs/INSTALLATION.md), [Known Issues](docs/KNOWN_ISSUES.md), and the [Roadmap](ROADMAP.md). Contributors should start with [CONTRIBUTING.md](CONTRIBUTING.md).

Chinese documentation: [README_CN.md](README_CN.md).

## Development

The development baseline is Flutter stable and Dart with local SQLite plus narrow Windows and Android bridges. On the reference machine, use `tools\picklogic.cmd env` and `tools\picklogic.cmd quick`; this launcher prefers the existing TTDT Android toolchain and does not require changing PowerShell execution policy. Target-specific commands are documented in `docs/PROJECT_SNAPSHOT.md`.

## License

PickLogic is released under the [BSD 3-Clause License](LICENSE), Copyright (c) 2026 Dawei Zhou. Bundled third-party components retain their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
