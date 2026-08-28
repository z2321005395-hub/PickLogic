# Known Issues — v0.1.0-alpha Draft

- Windows artifacts are portable unsigned ZIPs, not MSI/MSIX installers. Final signing and installer format are maintainer gates.
- Android's installable user-test artifact is test-signed, arm64-only Profile mode. Formal release signing and upgrade identity remain maintainer gates.
- The arm64 unsigned Release APK remains size evidence only and is not shipped as the user-test artifact.
- Office Open XML files use bounded structural summaries and Windows Shell thumbnails; PickLogic does not yet embed installed Office/WPS Shell Preview Handlers or bundle an Office runtime.
- Pro's accepted PDFium path supports local rendering, search, selection/copy, page/annotation export, and top-level text/image object editing into a new PDF. Scanned-page OCR reconstruction, paragraph reflow, outlined text, nested form objects, complex tables, forms, signing, certified redaction, and high-fidelity conversion remain out of scope.
- System Insight uses synthetic observations in the current vertical slice and performs no registry/service/task/startup inspection on the reference machine.
- No real Windows directory or Android media collection has been indexed or benchmarked.
- OCR is an interface/queue boundary only; first launch never starts bulk OCR.
- Mobile metadata and per-collection checkpoints persist in app-private SQLite and resume when PickLogic next runs. Android OS-scheduled WorkManager wakeups are not implemented.
- MediaStore deletion reconciliation and periodic full-snapshot generations are not implemented; v0.1 incrementally adds or updates visible records.
- Flutter/MSBuild currently corrupts the canonical Chinese repository path during a Windows custom build step. Local Windows builds use a separate ASCII-path detached worktree; hosted Windows CI remains green.
- Windows packages remain unsigned portable ZIPs and the Android user-test APK is debug-signed; production signing and store distribution are not part of this alpha.
