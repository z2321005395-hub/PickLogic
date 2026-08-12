# Known Issues — v0.1.0-alpha Draft

- Windows artifacts are portable unsigned ZIPs, not MSI/MSIX installers. Final signing and installer format are maintainer gates.
- Android's installable artifact is debug-signed and arm64-only for the verified reference device. Upgrade identity is not guaranteed across CI builds.
- The arm64 unsigned release APK is a size-check artifact, not an installable release.
- Pro renders an explicit PDF reader skeleton. Local page rendering, thumbnails, search, and selection remain blocked on the PDFium dependency-size experiment.
- System Insight uses synthetic observations in the current vertical slice and performs no registry/service/task/startup inspection on the reference machine.
- No real Windows directory or Android media collection has been indexed or benchmarked.
- OCR is an interface/queue boundary only; first launch never starts bulk OCR.
- Mobile incremental metadata state is process-local; durable WorkManager resume is not implemented.
- Windows local compilation requires the user to enable Developer Mode and install Visual Studio Desktop C++ Build Tools. Hosted Windows CI is green.
- The final open-source license, copyright owner, package signing, Public conversion, and release publication are pending maintainer decisions.
