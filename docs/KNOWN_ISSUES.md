# Known Issues — v0.1.0-alpha Draft

- Windows artifacts are portable unsigned ZIPs, not MSI/MSIX installers. Final signing and installer format are maintainer gates.
- Android's installable artifact is debug-signed and arm64-only for the verified reference device. Upgrade identity is not guaranteed across CI builds.
- The arm64 unsigned release APK is a size-check artifact, not an installable release.
- Pro's accepted PDFium path supports local page rendering, thumbnails, search, selection/copy, and a packaged native smoke test. Advanced PDF editing and conversion remain out of scope.
- System Insight uses synthetic observations in the current vertical slice and performs no registry/service/task/startup inspection on the reference machine.
- No real Windows directory or Android media collection has been indexed or benchmarked.
- OCR is an interface/queue boundary only; first launch never starts bulk OCR.
- Mobile metadata and per-collection checkpoints persist in app-private SQLite and resume when PickLogic next runs. Android OS-scheduled WorkManager wakeups are not implemented.
- MediaStore deletion reconciliation and periodic full-snapshot generations are not implemented; v0.1 incrementally adds or updates visible records.
- Windows local compilation requires the user to enable Developer Mode and install Visual Studio Desktop C++ Build Tools. Hosted Windows CI is green.
- The final open-source license, copyright owner, package signing, Public conversion, and release publication are pending maintainer decisions.
